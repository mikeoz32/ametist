require "../spec_helper"
require "../../src/movie"
require "../../src/movie/persistence"
require "../../src/devteam"

module DevTeam
  class FakeGateway < AgentGateway
    def initialize(@responses : Hash(String, String))
    end

    def run(role : String, prompt : String, session_id : String, org_id : String, project_id : String) : Movie::Future(String)
      promise = Movie::Promise(String).new
      promise.try_success(@responses[role]? || "ok")
      promise.future
    end
  end
end

describe DevTeam::OrgService do
  it "creates org and project, then runs kickoff" do
    db_path = "/tmp/devteam_org_#{UUID.random}.sqlite3"
    config = Movie::Config.builder.set("movie.persistence.db_path", db_path).build
    system = Movie::ActorSystem(Movie::SystemMessage).new(Movie::Behaviors(Movie::SystemMessage).same, config)

    event = Movie::EventSourcing.get(system)
    durable = Movie::DurableState.get(system)
    executor = Movie::Execution.get(system)
    gateway = DevTeam::FakeGateway.new({"pm" => "pm-summary", "ba" => "ba-req"})

    DevTeam.register_entities(system, durable, event, gateway, executor)

    service = system.spawn(DevTeam::OrgService.behavior(durable, event, gateway, executor))

    org = system.ask(service, DevTeam::CreateOrg.new("org-1", "Acme"), DevTeam::OrgState, 5.seconds).await(5.seconds)
    org.org_id.should eq("org-1")

    project = system.ask(service, DevTeam::CreateProject.new("org-1", "proj-1", "Test Project"), DevTeam::ProjectState, 5.seconds).await(5.seconds)
    project.project_id.should eq("proj-1")

    system.ask(service, DevTeam::AttachProjectRoles.new("org-1", "proj-1", ["pm", "ba"]), DevTeam::ProjectState, 5.seconds).await(5.seconds)

    kickoff = system.ask(service, DevTeam::KickoffProject.new("org-1", "proj-1", "Build an API"), DevTeam::KickoffResult, 10.seconds).await(10.seconds)
    kickoff.pm_summary.should eq("pm-summary")

    org_state = system.ask(service, DevTeam::GetOrgState.new("org-1"), DevTeam::OrgState, 5.seconds).await(5.seconds)
    org_state.projects.should eq(["proj-1"])
  end
end
