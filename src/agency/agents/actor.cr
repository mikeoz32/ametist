require "../../movie"
require "./messages"
require "./profile"
require "./session"
require "../context/builder"
require "../memory/actor"
require "../memory/policy"
require "../llm/gateway"

module Agency
  # Long-lived agent identity that owns sessions for a given agent_id.
  class AgentActor < Movie::AbstractBehavior(AgentMessage)
    @toolsets : Hash(String, ToolSetDefinition)
    @allowed_toolsets : Array(String)
    def self.behavior(
      profile : AgentProfile,
      llm_gateway : Movie::ActorRef(LLMRequest),
      toolsets : Array(ToolSetDefinition),
      supervision : Movie::SupervisionConfig = DEFAULT_INFRA_SUPERVISION,
      session_supervision : Movie::SupervisionConfig = DEFAULT_SESSION_SUPERVISION
    ) : Movie::AbstractBehavior(AgentMessage)
      Movie::Behaviors(AgentMessage).setup do |ctx|
        AgentActor.new(profile, llm_gateway, toolsets, nil, session_supervision)
      end
    end

    def initialize(
      @profile : AgentProfile,
      @llm_gateway : Movie::ActorRef(LLMRequest),
      toolsets : Array(ToolSetDefinition),
      @context_builder : Movie::ActorRef(ContextMessage)?,
      @session_supervision : Movie::SupervisionConfig
    )
      @allowed_toolsets = @profile.allowed_toolsets
      @toolsets = {} of String => ToolSetDefinition
      toolsets.each do |toolset|
        @toolsets[toolset.id] = toolset
      end
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
      when RegisterToolSetDefinition
        @toolsets[message.definition.id] = message.definition
      when UpdateAllowedToolSets
        update_allowed_toolsets(message.allowed_toolsets)
      end
      Movie::Behaviors(AgentMessage).same
    end

    private def handle_prompt(message : RunPrompt, ctx)
      return unless message.agent_id == @profile.id
      model = message.model.empty? ? @profile.model : message.model
      session = ensure_session(message.session_id, ctx)
      session << SessionPrompt.new(message.agent_id, message.prompt, model, message.reply_to, message.user_id, message.project_id)
    end

    private def ensure_session(id : String, ctx) : Movie::ActorRef(SessionMessage)
      if existing = @sessions[id]?
        return existing
      end
      toolsets = allowed_toolset_definitions
      policy = MemoryPolicy.from_config(ctx.system.config, @profile.memory_policy_name)
      session = ctx.spawn(
        AgentSession.behavior(
          id,
          @llm_gateway,
          toolsets,
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

    private def update_allowed_toolsets(allowed_toolsets : Array(String))
      @allowed_toolsets = allowed_toolsets
    end

    private def allowed_toolset_definitions : Array(ToolSetDefinition)
      return [] of ToolSetDefinition if @allowed_toolsets.empty?
      @allowed_toolsets.compact_map { |id| @toolsets[id]? }
    end

    def stop
      @sessions.each_value(&.send_system(Movie::STOP))
      @sessions.clear
    end
  end
end
