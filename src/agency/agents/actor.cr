require "../../movie"
require "./messages"
require "./profile"
require "./session"
require "../context/builder"
require "../memory/actor"
require "../memory/policy"
require "../llm/gateway"
require "../skills/registry"

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
      session_supervision : Movie::SupervisionConfig = DEFAULT_SESSION_SUPERVISION,
      skill_registry : Movie::ActorRef(SkillRegistryMessage)? = nil
    ) : Movie::AbstractBehavior(AgentMessage)
      Movie::Behaviors(AgentMessage).setup do |ctx|
        AgentActor.new(profile, llm_gateway, toolsets, nil, session_supervision, skill_registry)
      end
    end

    def initialize(
      @profile : AgentProfile,
      @llm_gateway : Movie::ActorRef(LLMRequest),
      toolsets : Array(ToolSetDefinition),
      @context_builder : Movie::ActorRef(ContextMessage)?,
      @session_supervision : Movie::SupervisionConfig,
      @skill_registry : Movie::ActorRef(SkillRegistryMessage)?
    )
      @allowed_toolsets = @profile.allowed_toolsets
      @attached_skill_ids = @profile.skill_ids.uniq
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
      when AttachSkills
        @attached_skill_ids = (@attached_skill_ids + message.skill_ids).uniq
        reply_bool(message.reply_to, ctx, true)
      when DetachSkills
        remove = message.skill_ids
        @attached_skill_ids.reject! { |id| remove.includes?(id) }
        reply_bool(message.reply_to, ctx, true)
      when GetAttachedSkills
        reply_skill_ids(message.reply_to, ctx, @attached_skill_ids.dup)
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
      skills = snapshot_skills(ctx)
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
          skills: skills,
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

    private def snapshot_skills(ctx) : Array(Skill)
      registry = @skill_registry
      return [] of Skill if registry.nil? || @attached_skill_ids.empty?
      loaded = begin
        ctx.ask(registry, GetAllSkills.new, Array(Skill), 3.seconds).await(3.seconds)
      rescue
        [] of Skill
      end
      by_id = {} of String => Skill
      loaded.each { |skill| by_id[skill.id] = skill }
      @attached_skill_ids.compact_map { |id| by_id[id]? }
    end

    private def reply_bool(reply_to, ctx, value : Bool)
      if reply_to
        reply_to << value
      else
        Movie::Ask.reply_if_asked(ctx.sender, value)
      end
    end

    private def reply_skill_ids(reply_to, ctx, value : Array(String))
      if reply_to
        reply_to << value
      else
        Movie::Ask.reply_if_asked(ctx.sender, value)
      end
    end

    def stop
      @sessions.each_value(&.send_system(Movie::STOP))
      @sessions.clear
    end
  end
end
