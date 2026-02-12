require "../../movie"
require "../runtime/protocol"
require "./messages"
require "../llm/gateway"
require "../tools/tool_set"
require "../tools/tool_router"
require "../tools/toolset_definition"
require "../context/builder"
require "./run"
require "../memory/policy"
require "../skills/registry"

module Agency
  # Session actor that owns conversational history and spawns runs per prompt.
  class AgentSession < Movie::AbstractBehavior(SessionMessage)
    @skill_system_messages : Array(Message)

    def self.behavior(
      session_id : String,
      llm_gateway : Movie::ActorRef(LLMRequest),
      toolsets : Array(ToolSetDefinition),
      context_builder : Movie::ActorRef(ContextMessage)? = nil,
      memory : Movie::ActorRef(MemoryMessage)? = nil,
      max_steps : Int32 = 8,
      max_history : Int32 = 50,
      skills : Array(Skill) = [] of Skill,
      memory_policy : MemoryPolicy? = nil
    ) : Movie::AbstractBehavior(SessionMessage)
      Movie::Behaviors(SessionMessage).setup do |ctx|
        vector_collection = if ctx.system.responds_to?(:config) && !ctx.system.config.empty?
          ctx.system.config.get_string("agency.memory.vector_collection", "agency_memory")
        else
          "agency_memory"
        end

        embedder = begin
          EmbedderExtensionId.get(ctx.system)
        rescue
          nil
        end

        mem_ref = memory || ctx.spawn(
          MemoryActor.behavior(
            MemoryScope::Session,
            vector_collection,
            memory_policy: (memory_policy || MemoryPolicy.from_config(ctx.system.config))
          ),
          Movie::RestartStrategy::RESTART,
          Movie::SupervisionConfig.default,
          "memory"
        )

        builder_ref = context_builder || ctx.spawn(
          ContextBuilder.behavior(
            mem_ref,
            embedder,
            vector_collection,
            max_history,
            memory_policy: (memory_policy || MemoryPolicy.from_config(ctx.system.config))
          ),
          Movie::RestartStrategy::RESTART,
          Movie::SupervisionConfig.default,
          "context-builder"
        )

        toolset_refs = {} of String => Movie::ActorRef(ToolSetMessage)
        tool_list = [] of ToolSpec
        known_tools = {} of String => Bool
        toolsets.each do |definition|
          ref = definition.resolve(ctx)
          toolset_refs[definition.prefix] = ref
          definition.tools.each do |spec|
            name = "#{definition.prefix}.#{spec.name}"
            next if known_tools.has_key?(name)
            known_tools[name] = true
            tool_list << ToolSpec.new(name, spec.description, spec.parameters)
          end
        end
        skill_prompts = [] of String
        skills.each do |skill|
          prompt = skill.system_prompt.strip
          skill_prompts << prompt unless prompt.empty?
          skill.tools.each do |spec|
            next if known_tools.has_key?(spec.name)
            known_tools[spec.name] = true
            tool_list << spec
          end
        end
        tool_router = ctx.spawn(
          ToolRouter.new(toolset_refs),
          Movie::RestartStrategy::RESTART,
          Movie::SupervisionConfig.default,
          "tool-router"
        )

        AgentSession.new(session_id, llm_gateway, tool_router, tool_list, builder_ref, mem_ref, max_steps, max_history, skill_prompts)
      end
    end

    def initialize(
      @session_id : String,
      @llm_gateway : Movie::ActorRef(LLMRequest),
      @tool_router : Movie::ActorRef(ToolCall),
      @tools : Array(ToolSpec),
      @context_builder : Movie::ActorRef(ContextMessage)?,
      @memory : Movie::ActorRef(MemoryMessage)?,
      @max_steps : Int32 = 8,
      @max_history : Int32 = 50,
      skill_prompts : Array(String) = [] of String
    )
      @history = [] of Message
      @skill_system_messages = skill_prompts.map { |prompt| Message.new(Role::System, prompt) }
      @pending_reply = nil.as(Movie::ActorRef(String)?)
      @active_run = nil.as(Movie::ActorRef(RunMessage)?)
      @history_loaded = false
      @loading_history = false
      @pending_prompt = nil.as(SessionPrompt?)
      @history_load_timeout = 2.seconds
      @user_id = nil.as(String?)
      @project_id = nil.as(String?)
    end

    def receive(message, ctx)
      case message
      when SessionPrompt
        handle_prompt(message, ctx)
      when HistoryLoaded
        handle_history_loaded(message, ctx)
      when RunCompleted
        handle_completed(message)
      when RunFailed
        handle_failed(message)
      when GetSessionState
        handle_state(message)
      end
      Movie::Behaviors(SessionMessage).same
    end

    private def handle_prompt(message : SessionPrompt, ctx)
      if @active_run
        message.reply_to << "(Agent) session already running"
        return
      end

      unless @history_loaded
        if @loading_history
          message.reply_to << "(Agent) session already running"
          return
        end
        @loading_history = true
        @pending_prompt = message
        request_history(ctx)
        return
      end

      prune_history
      @user_id = message.user_id
      @project_id = message.project_id
      store_session_meta(message.agent_id, message.model)
      store_message(Message.new(Role::User, message.prompt))
      @pending_reply = message.reply_to
      run = ctx.spawn(
        AgentRun.behavior(
          ctx.ref,
          @session_id,
          message.prompt,
          @llm_gateway,
          @tool_router,
          @tools,
          @context_builder,
          message.model,
          @max_steps,
          run_history,
          @user_id,
          @project_id
        ),
        Movie::RestartStrategy::STOP
      )
      @active_run = run
    end

    private def handle_completed(message : RunCompleted)
      append_delta(message.delta)
      store_messages(message.delta)
      if reply_to = @pending_reply
        reply_to << message.content
      end
      @pending_reply = nil
      @active_run = nil
    end

    private def handle_failed(message : RunFailed)
      append_delta(message.delta)
      store_messages(message.delta)
      if reply_to = @pending_reply
        reply_to << "(Agent) failed: #{message.error}"
      end
      @pending_reply = nil
      @active_run = nil
    end

    private def handle_state(message : GetSessionState)
      message.reply_to << SessionState.new(@session_id, @history.size, !@active_run.nil? || @loading_history)
    end

    private def handle_history_loaded(message : HistoryLoaded, ctx)
      return if @history_loaded
      @history = message.events
      prune_history
      @history_loaded = true
      @loading_history = false
      if pending = @pending_prompt
        @pending_prompt = nil
        handle_prompt(pending, ctx)
      end
    end

    private def append_delta(delta : Array(Message))
      return if delta.empty?
      @history.concat(delta)
      prune_history
    end

    private def prune_history
      excess = @history.size - @max_history
      if excess > 0
        @history.shift(excess)
      end
    end

    private def run_history : Array(Message)
      return @history.dup if @skill_system_messages.empty?
      @skill_system_messages + @history
    end

    private def store_messages(delta : Array(Message))
      delta.each { |msg| store_message(msg) }
    end

    private def store_message(msg : Message)
      return unless memory = @memory
      embed = msg.role == Role::User || msg.role == Role::Assistant
      memory << StoreEvent.new(@session_id, msg, embed)
    end

    private def request_history(ctx)
      unless memory = @memory
        @history_loaded = true
        @loading_history = false
        if pending = @pending_prompt
          @pending_prompt = nil
          handle_prompt(pending, ctx)
        end
        return
      end
      future = ctx.ask(memory, FetchEvents.new(@session_id, @max_history), Array(Message), @history_load_timeout)
      ctx.pipe(
        future,
        ctx.ref,
        ->(events : Array(Message)) { HistoryLoaded.new(events) },
        ->(_ex : Exception) { HistoryLoaded.new([] of Message) }
      )
    end

    private def store_session_meta(agent_id : String, model : String)
      return unless memory = @memory
      memory << StoreSessionMeta.new(@session_id, agent_id, model)
    end
  end
end
