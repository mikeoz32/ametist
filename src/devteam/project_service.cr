require "../movie"
require "./project_entity"

module DevTeam
  struct AttachProjectRoles
    getter org_id : String
    getter project_id : String
    getter roles : Array(String)

    def initialize(@org_id : String, @project_id : String, @roles : Array(String))
    end
  end

  struct KickoffProject
    getter org_id : String
    getter project_id : String
    getter prompt : String
    getter session_id : String?

    def initialize(@org_id : String, @project_id : String, @prompt : String, @session_id : String? = nil)
    end
  end

  struct GetProjectStateRequest
    getter org_id : String
    getter project_id : String

    def initialize(@org_id : String, @project_id : String)
    end
  end

  alias ProjectServiceMessage = CreateProject | AttachProjectRoles | KickoffProject | GetProjectStateRequest

  class ProjectService < Movie::AbstractBehavior(ProjectServiceMessage)
    REQUEST_TIMEOUT = 10.seconds
    KICKOFF_TIMEOUT = 90.seconds

    def initialize(@durable : Movie::DurableStateExtension)
    end

    def receive(message, ctx)
      case message
      when CreateProject
        ref = project_ref(message.org_id, message.project_id)
        state = ctx.ask(ref, message, ProjectState, REQUEST_TIMEOUT).await(REQUEST_TIMEOUT)
        Movie::Ask.reply_if_asked(ctx.sender, state)
      when AttachProjectRoles
        ref = project_ref(message.org_id, message.project_id)
        state = ctx.ask(ref, AttachRoles.new(message.roles), ProjectState, REQUEST_TIMEOUT).await(REQUEST_TIMEOUT)
        Movie::Ask.reply_if_asked(ctx.sender, state)
      when KickoffProject
        ref = project_ref(message.org_id, message.project_id)
        result = ctx.ask(ref, StartKickoff.new(message.prompt, message.session_id), KickoffResult, KICKOFF_TIMEOUT).await(KICKOFF_TIMEOUT)
        Movie::Ask.reply_if_asked(ctx.sender, result)
      when GetProjectStateRequest
        ref = project_ref(message.org_id, message.project_id)
        state = ctx.ask(ref, GetProjectState.new, ProjectState, REQUEST_TIMEOUT).await(REQUEST_TIMEOUT)
        Movie::Ask.reply_if_asked(ctx.sender, state)
      end
      Movie::Behaviors(ProjectServiceMessage).same
    end

    private def project_ref(org_id : String, project_id : String) : Movie::ActorRef(ProjectCommand)
      @durable.get_entity_ref_as(ProjectCommand, DevTeam.project_id(org_id, project_id))
    end

    def self.behavior(durable : Movie::DurableStateExtension)
      Movie::Behaviors(ProjectServiceMessage).setup do |_ctx|
        ProjectService.new(durable)
      end
    end
  end
end
