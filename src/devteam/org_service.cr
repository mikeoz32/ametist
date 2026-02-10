require "../movie"
require "./org_entity"
require "./project_service"

module DevTeam
  alias OrgServiceMessage = CreateOrg | CreateProject | AttachProjectRoles | KickoffProject | GetOrgState | GetProjectStateRequest

  class OrgService < Movie::AbstractBehavior(OrgServiceMessage)
    REQUEST_TIMEOUT = 10.seconds
    KICKOFF_TIMEOUT = 90.seconds

    def initialize(
      @durable : Movie::DurableStateExtension,
      @event : Movie::EventSourcingExtension,
      @gateway : AgentGateway,
      @executor : Movie::ExecutorExtension
    )
      @projects = {} of String => Movie::ActorRef(ProjectServiceMessage)
    end

    def receive(message, ctx)
      case message
      when CreateOrg
        org = org_ref(message.org_id)
        state = ctx.ask(org, message, OrgState, REQUEST_TIMEOUT).await(REQUEST_TIMEOUT)
        Movie::Ask.reply_if_asked(ctx.sender, state)
      when CreateProject
        service = ensure_project_service(message.org_id, ctx)
        state = ctx.ask(service, message, ProjectState, REQUEST_TIMEOUT).await(REQUEST_TIMEOUT)
        register_project(message.org_id, message.project_id, ctx)
        Movie::Ask.reply_if_asked(ctx.sender, state)
      when AttachProjectRoles
        service = ensure_project_service(message.org_id, ctx)
        state = ctx.ask(service, message, ProjectState, REQUEST_TIMEOUT).await(REQUEST_TIMEOUT)
        Movie::Ask.reply_if_asked(ctx.sender, state)
      when KickoffProject
        service = ensure_project_service(message.org_id, ctx)
        result = ctx.ask(service, message, KickoffResult, KICKOFF_TIMEOUT).await(KICKOFF_TIMEOUT)
        Movie::Ask.reply_if_asked(ctx.sender, result)
      when GetOrgState
        org = org_ref(message.org_id)
        state = ctx.ask(org, message, OrgState, REQUEST_TIMEOUT).await(REQUEST_TIMEOUT)
        Movie::Ask.reply_if_asked(ctx.sender, state)
      when GetProjectStateRequest
        service = ensure_project_service(message.org_id, ctx)
        state = ctx.ask(service, message, ProjectState, REQUEST_TIMEOUT).await(REQUEST_TIMEOUT)
        Movie::Ask.reply_if_asked(ctx.sender, state)
      end
      Movie::Behaviors(OrgServiceMessage).same
    end

    private def org_ref(org_id : String) : Movie::ActorRef(OrgCommand)
      @durable.get_entity_ref_as(OrgCommand, DevTeam.org_id(org_id))
    end

    private def register_project(org_id : String, project_id : String, ctx : Movie::ActorContext(OrgServiceMessage))
      org = org_ref(org_id)
      ctx.ask(org, RegisterProject.new(project_id), OrgState, REQUEST_TIMEOUT).await(REQUEST_TIMEOUT)
    end

    private def ensure_project_service(org_id : String, ctx : Movie::ActorContext(OrgServiceMessage)) : Movie::ActorRef(ProjectServiceMessage)
      if existing = @projects[org_id]?
        return existing
      end
      ref = ctx.spawn(ProjectService.behavior(@durable), Movie::RestartStrategy::RESTART, Movie::SupervisionConfig.default, "project-service-#{org_id}")
      @projects[org_id] = ref
      ref
    end

    def self.behavior(
      durable : Movie::DurableStateExtension,
      event : Movie::EventSourcingExtension,
      gateway : AgentGateway,
      executor : Movie::ExecutorExtension
    )
      Movie::Behaviors(OrgServiceMessage).setup do |_ctx|
        OrgService.new(durable, event, gateway, executor)
      end
    end
  end
end
