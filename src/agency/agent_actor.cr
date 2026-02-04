require "../movie"
require "./agent_messages"
require "./agent_profile"
require "./agent_session"
require "./context_builder"
require "./memory_actor"
require "./memory_policy"
require "./llm_gateway"
require "./tool_set"

module Agency
  # Long-lived agent identity that owns sessions for a given agent_id.
  class AgentActor < Movie::AbstractBehavior(AgentMessage)
    @tools : Array(ToolSpec)
    @allowed_tools : Array(String)
    def self.behavior(
      profile : AgentProfile,
      llm_gateway : Movie::ActorRef(LLMRequest),
      tools : Array(ToolSpec),
      supervision : Movie::SupervisionConfig = DEFAULT_INFRA_SUPERVISION,
      session_supervision : Movie::SupervisionConfig = DEFAULT_SESSION_SUPERVISION
    ) : Movie::AbstractBehavior(AgentMessage)
      Movie::Behaviors(AgentMessage).setup do |ctx|
        executor = ctx.extension(Movie::Execution.instance)
        tool_set = ctx.spawn(DefaultToolSet.new(executor), Movie::RestartStrategy::RESTART, supervision, "tool-set")
        AgentActor.new(profile, llm_gateway, tool_set, nil, tools, session_supervision)
      end
    end

    def initialize(
      @profile : AgentProfile,
      @llm_gateway : Movie::ActorRef(LLMRequest),
      @tool_set : Movie::ActorRef(ToolSetMessage),
      @context_builder : Movie::ActorRef(ContextMessage)?,
      tools : Array(ToolSpec),
      @session_supervision : Movie::SupervisionConfig
    )
      @allowed_tools = @profile.allowed_tools
      @tools = tools.select { |spec| tool_allowed?(spec.name) }
      @sessions = {} of String => Movie::ActorRef(SessionMessage)
    end

    def receive(message, ctx)
      case message
      when RunPrompt
        handle_prompt(message, ctx)
      when StartSession
        ensure_session(message.session_id, ctx)
      when StopSession
        stop_session(message.session_id)
      when GetAgentState
        message.reply_to << AgentState.new(@profile.id, @sessions.keys)
      when ToolSetRegisterExec
        if tool_allowed?(message.spec.name)
          register_tool_spec(message.spec)
          @tool_set << message
        end
      when ToolSetRegisterActor
        if tool_allowed?(message.spec.name)
          register_tool_spec(message.spec)
          @tool_set << message
        end
      when ToolSetUnregister
        @tools.reject! { |spec| spec.name == message.name }
        @tool_set << message
      when UpdateAllowedTools
        update_allowed_tools(message.allowed_tools)
      end
      Movie::Behaviors(AgentMessage).same
    end

    private def handle_prompt(message : RunPrompt, ctx)
      return unless message.agent_id == @profile.id
      model = message.model.empty? ? @profile.model : message.model
      session = ensure_session(message.session_id, ctx)
      session << SessionPrompt.new(message.agent_id, message.prompt, model, @tools, message.reply_to, message.user_id, message.project_id)
    end

    private def ensure_session(id : String, ctx) : Movie::ActorRef(SessionMessage)
      if existing = @sessions[id]?
        return existing
      end
      policy = MemoryPolicy.from_config(ctx.system.config, @profile.memory_policy_name)
      session = ctx.spawn(
        AgentSession.behavior(
          id,
          @llm_gateway,
          @tool_set,
          @context_builder,
          nil,
          @profile.max_steps,
          @profile.max_history,
          memory_policy: policy
        ),
        Movie::RestartStrategy::RESTART,
        @session_supervision
      )
      @sessions[id] = session
      session
    end

    private def stop_session(id : String)
      if session = @sessions.delete(id)
        session.send_system(Movie::STOP)
      end
    end

    private def register_tool_spec(spec : ToolSpec)
      @tools.reject! { |existing| existing.name == spec.name }
      @tools << spec
    end

    private def tool_allowed?(name : String) : Bool
      return false if @allowed_tools.empty?
      @allowed_tools.includes?(name)
    end

    private def update_allowed_tools(allowed_tools : Array(String))
      previous = @tools
      @allowed_tools = allowed_tools
      kept = [] of ToolSpec
      removed = [] of ToolSpec
      previous.each do |spec|
        if tool_allowed?(spec.name)
          kept << spec
        else
          removed << spec
        end
      end
      @tools = kept
      removed.each do |spec|
        @tool_set << ToolSetUnregister.new(spec.name)
      end
    end

    def stop
      @sessions.each_value(&.send_system(Movie::STOP))
      @sessions.clear
    end
  end
end
