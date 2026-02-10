require "../movie/persistence"
require "./agent_gateway"
require "./project_event_entity"

module DevTeam
  struct KickoffResult
    include JSON::Serializable

    getter pm_summary : String?
    getter ba_requirements : String?
    getter risks : String?
    getter next_steps : String?

    def initialize(
      @pm_summary : String? = nil,
      @ba_requirements : String? = nil,
      @risks : String? = nil,
      @next_steps : String? = nil
    )
    end

    def self.from_roles(outputs : Hash(String, String)) : KickoffResult
      KickoffResult.new(
        pm_summary: outputs["pm"]?,
        ba_requirements: outputs["ba"]?,
        risks: outputs["risks"]?,
        next_steps: outputs["next_steps"]?
      )
    end
  end

  struct ProjectState
    include JSON::Serializable

    getter org_id : String
    getter project_id : String
    getter name : String
    getter roles : Array(String)
    getter kickoff : KickoffResult?

    def initialize(
      @org_id : String = "",
      @project_id : String = "",
      @name : String = "",
      @roles : Array(String) = [] of String,
      @kickoff : KickoffResult? = nil
    )
    end

    def with_name(name : String) : ProjectState
      ProjectState.new(@org_id, @project_id, name, @roles, @kickoff)
    end

    def with_ids(org_id : String, project_id : String) : ProjectState
      ProjectState.new(org_id, project_id, @name, @roles, @kickoff)
    end

    def with_roles(roles : Array(String)) : ProjectState
      ProjectState.new(@org_id, @project_id, @name, roles, @kickoff)
    end

    def with_kickoff(result : KickoffResult) : ProjectState
      ProjectState.new(@org_id, @project_id, @name, @roles, result)
    end
  end

  struct CreateProject
    getter org_id : String
    getter project_id : String
    getter name : String

    def initialize(@org_id : String, @project_id : String, @name : String)
    end
  end

  struct AttachRoles
    getter roles : Array(String)

    def initialize(@roles : Array(String))
    end
  end

  struct StartKickoff
    getter prompt : String
    getter session_id : String?

    def initialize(@prompt : String, @session_id : String? = nil)
    end
  end

  struct KickoffCompleted
    getter result : KickoffResult

    def initialize(@result : KickoffResult)
    end
  end

  struct KickoffFailed
    getter reason : String

    def initialize(@reason : String)
    end
  end

  struct GetProjectState
  end

  alias ProjectCommand = CreateProject | AttachRoles | StartKickoff | KickoffCompleted | KickoffFailed | GetProjectState

  class ProjectEntity < Movie::DurableStateBehavior(ProjectCommand, ProjectState)
    @gateway : AgentGateway
    @executor : Movie::ExecutorExtension
    @event_log : Movie::ActorRef(ProjectEventCommand)
    @kickoff_pending : Bool = false
    @kickoff_sender : Movie::ActorRefBase? = nil

    def initialize(
      @id : Movie::Persistence::Id,
      store : Movie::Persistence::StateStoreClient,
      @gateway : AgentGateway,
      @executor : Movie::ExecutorExtension,
      @event_log : Movie::ActorRef(ProjectEventCommand)
    )
      super(@id.persistence_id, store)
    end

    protected def empty_state : ProjectState
      ProjectState.new
    end

    protected def handle_command(state : ProjectState, command : ProjectCommand, ctx : Movie::ActorContext(ProjectCommand)) : ProjectState?
      case command
      when CreateProject
        next_state = state.with_ids(command.org_id, command.project_id).with_name(command.name)
        Movie::Ask.reply_if_asked(ctx.sender, next_state)
        record_event("project_created", {org_id: command.org_id, project_id: command.project_id, name: command.name}.to_json)
        next_state
      when AttachRoles
        merged = (state.roles + command.roles).uniq
        next_state = state.with_roles(merged)
        Movie::Ask.reply_if_asked(ctx.sender, next_state)
        record_event("roles_attached", {roles: merged}.to_json)
        next_state
      when StartKickoff
        if @kickoff_pending
          Movie::Ask.fail_if_asked(ctx.sender, RuntimeError.new("kickoff already running"), KickoffResult)
          return nil
        end
        if state.roles.empty?
          Movie::Ask.fail_if_asked(ctx.sender, RuntimeError.new("no roles attached"), KickoffResult)
          return nil
        end
        @kickoff_pending = true
        @kickoff_sender = ctx.sender
        record_event("kickoff_requested", {prompt: command.prompt}.to_json)
        start_kickoff(state, command, ctx)
        nil
      when KickoffCompleted
        @kickoff_pending = false
        if sender = @kickoff_sender
          Movie::Ask.reply_if_asked(sender, command.result)
        end
        @kickoff_sender = nil
        record_event("kickoff_completed", command.result.to_json)
        state.with_kickoff(command.result)
      when KickoffFailed
        @kickoff_pending = false
        if sender = @kickoff_sender
          Movie::Ask.fail_if_asked(sender, RuntimeError.new(command.reason), KickoffResult)
        end
        @kickoff_sender = nil
        record_event("kickoff_failed", {reason: command.reason}.to_json)
        nil
      when GetProjectState
        Movie::Ask.reply_if_asked(ctx.sender, state)
        nil
      end
    end

    private def start_kickoff(state : ProjectState, command : StartKickoff, ctx : Movie::ActorContext(ProjectCommand))
      session_id = command.session_id || "#{state.org_id}/#{state.project_id}"
      roles = state.roles
      prompt = command.prompt
      org_id = state.org_id
      project_id = state.project_id
      gateway = @gateway

      future = @executor.execute do
        outputs = {} of String => String
        roles.each do |role|
          outputs[role] = gateway.run(role, prompt, session_id, org_id, project_id).await(60.seconds)
        end
        outputs
      end

      ctx.pipe(
        future,
        ctx.ref,
        success: ->(outputs : Hash(String, String)) { KickoffCompleted.new(KickoffResult.from_roles(outputs)) },
        failure: ->(ex : Exception) { KickoffFailed.new(ex.message || "kickoff failed") }
      )
    end

    private def record_event(kind : String, payload : String)
      @event_log << RecordProjectEvent.new(ProjectEvent.new(kind, payload))
    end
  end
end
