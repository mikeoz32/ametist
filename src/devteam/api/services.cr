require "../../movie"
require "./messages"

@[LF::DI::Service]
class OrgService
  REQUEST_TIMEOUT = 10.seconds
  KICKOFF_TIMEOUT = 90.seconds

  def initialize(
    @system : Movie::ActorSystem(Movie::SystemMessage),
    @org_actor : Movie::ActorRef(DevTeam::OrgServiceMessage)
  )
  end

  def create_org(request : DevTeam::Api::CreateOrgRequest) : DevTeam::Api::CreateOrgResponse
    org = @system.ask(@org_actor, DevTeam::CreateOrg.new(request.org_id, request.name), DevTeam::OrgState, REQUEST_TIMEOUT).await(REQUEST_TIMEOUT)
    DevTeam::Api::CreateOrgResponse.new(org.org_id)
  end

  def create_project(org_id : String, request : DevTeam::Api::CreateProjectRequest) : DevTeam::Api::CreateProjectResponse
    project = @system.ask(
      @org_actor,
      DevTeam::CreateProject.new(org_id, request.project_id, request.name),
      DevTeam::ProjectState,
      REQUEST_TIMEOUT
    ).await(REQUEST_TIMEOUT)
    DevTeam::Api::CreateProjectResponse.new(project.project_id)
  end

  def attach_roles(org_id : String, project_id : String, request : DevTeam::Api::AttachRolesRequest) : DevTeam::ProjectState
    @system.ask(
      @org_actor,
      DevTeam::AttachProjectRoles.new(org_id, project_id, request.roles),
      DevTeam::ProjectState,
      REQUEST_TIMEOUT
    ).await(REQUEST_TIMEOUT)
  end

  def kickoff(org_id : String, project_id : String, request : DevTeam::Api::KickoffRequest) : DevTeam::KickoffResult
    @system.ask(
      @org_actor,
      DevTeam::KickoffProject.new(org_id, project_id, request.prompt, request.session_id),
      DevTeam::KickoffResult,
      KICKOFF_TIMEOUT
    ).await(KICKOFF_TIMEOUT)
  end

  def get_org(org_id : String) : DevTeam::OrgState
    @system.ask(@org_actor, DevTeam::GetOrgState.new(org_id), DevTeam::OrgState, REQUEST_TIMEOUT).await(REQUEST_TIMEOUT)
  end
end
