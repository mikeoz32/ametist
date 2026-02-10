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

describe DevTeam::ProjectEntity do
  it "persists roles and kickoff result" do
    db_path = "/tmp/devteam_project_#{UUID.random}.sqlite3"
    config = Movie::Config.builder.set("movie.persistence.db_path", db_path).build
    system = Movie::ActorSystem(Movie::SystemMessage).new(Movie::Behaviors(Movie::SystemMessage).same, config)

    event = Movie::EventSourcing.get(system)
    durable = Movie::DurableState.get(system)
    executor = Movie::Execution.get(system)

    gateway = DevTeam::FakeGateway.new({"pm" => "pm-summary", "ba" => "ba-req"})

    DevTeam.register_entities(system, durable, event, gateway, executor)

    pid = DevTeam.project_id("org-1", "proj-1")
    project = durable.get_entity_ref_as(DevTeam::ProjectCommand, pid)

    system.ask(project, DevTeam::CreateProject.new("org-1", "proj-1", "Test Project"), DevTeam::ProjectState, 5.seconds).await(5.seconds)
    system.ask(project, DevTeam::AttachRoles.new(["pm", "ba"]), DevTeam::ProjectState, 5.seconds).await(5.seconds)

    result = system.ask(project, DevTeam::StartKickoff.new("Build an API"), DevTeam::KickoffResult, 10.seconds).await(10.seconds)
    result.pm_summary.should eq("pm-summary")
    result.ba_requirements.should eq("ba-req")

    state = system.ask(project, DevTeam::GetProjectState.new, DevTeam::ProjectState, 5.seconds).await(5.seconds)
    state.roles.should eq(["pm", "ba"])
    state.kickoff.not_nil!.pm_summary.should eq("pm-summary")
  end
end
