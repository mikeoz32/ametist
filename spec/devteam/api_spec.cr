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

describe DevTeam::Api::App do
  it "serves org/project endpoints with API key" do
    db_path = "/tmp/devteam_api_#{UUID.random}.sqlite3"
    config = Movie::Config.builder.set("movie.persistence.db_path", db_path).build
    system = Movie::ActorSystem(Movie::SystemMessage).new(Movie::Behaviors(Movie::SystemMessage).same, config)

    event = Movie::EventSourcing.get(system)
    durable = Movie::DurableState.get(system)
    executor = Movie::Execution.get(system)
    gateway = DevTeam::FakeGateway.new({"pm" => "pm-summary", "ba" => "ba-req"})
    DevTeam.register_entities(system, durable, event, gateway, executor)

    org_service = system.spawn(DevTeam::OrgService.behavior(durable, event, gateway, executor))
    app = DevTeam::Api::App.new(system, org_service, "test-key")

    server = HTTP::Server.new([app])
    address = server.bind_tcp("127.0.0.1", 0)
    done = Channel(Nil).new
    spawn do
      server.listen
      done.send(nil)
    end

    client = HTTP::Client.new(address.address, address.port)
    headers_with_key = HTTP::Headers{"X-API-Key" => "test-key", "Content-Type" => "application/json"}
    headers = HTTP::Headers{"Content-Type" => "application/json"}

    begin
      resp = client.post("/orgs", headers_with_key, %({"org_id":"org-1","name":"Acme"}))
      resp.status_code.should eq(200)
      JSON.parse(resp.body)["org_id"].as_s.should eq("org-1")

      resp = client.post("/orgs/org-1/projects?api_key=test-key", headers, %({"project_id":"proj-1","name":"Test"}))
      resp.status_code.should eq(200)
      JSON.parse(resp.body)["project_id"].as_s.should eq("proj-1")

      resp = client.post("/orgs/org-1/projects/proj-1/agents", headers_with_key, %({"roles":["pm","ba"]}))
      resp.status_code.should eq(200)
      JSON.parse(resp.body)["roles"].as_a.map(&.as_s).should eq(["pm", "ba"])

      resp = client.post("/orgs/org-1/projects/proj-1/kickoff", headers_with_key, %({"prompt":"Build API"}))
      resp.status_code.should eq(200)
      JSON.parse(resp.body)["pm_summary"].as_s.should eq("pm-summary")
    ensure
      client.close
      server.close
      begin
        done.receive
      rescue
      end
    end
  end

  it "rejects missing api key" do
    system = Movie::ActorSystem(Movie::SystemMessage).new(Movie::Behaviors(Movie::SystemMessage).same)
    durable = Movie::DurableState.get(system)
    event = Movie::EventSourcing.get(system)
    executor = Movie::Execution.get(system)
    gateway = DevTeam::FakeGateway.new({} of String => String)
    DevTeam.register_entities(system, durable, event, gateway, executor)
    org_service = system.spawn(DevTeam::OrgService.behavior(durable, event, gateway, executor))
    app = DevTeam::Api::App.new(system, org_service, "test-key")

    server = HTTP::Server.new([app])
    address = server.bind_tcp("127.0.0.1", 0)
    done = Channel(Nil).new
    spawn do
      server.listen
      done.send(nil)
    end

    client = HTTP::Client.new(address.address, address.port)
    begin
      resp = client.post("/orgs", HTTP::Headers.new, %({"org_id":"org-1","name":"Acme"}))
      resp.status_code.should eq(401)
    ensure
      client.close
      server.close
      begin
        done.receive
      rescue
      end
    end
  end

  it "returns bad request for invalid json" do
    system = Movie::ActorSystem(Movie::SystemMessage).new(Movie::Behaviors(Movie::SystemMessage).same)
    durable = Movie::DurableState.get(system)
    event = Movie::EventSourcing.get(system)
    executor = Movie::Execution.get(system)
    gateway = DevTeam::FakeGateway.new({} of String => String)
    DevTeam.register_entities(system, durable, event, gateway, executor)
    org_service = system.spawn(DevTeam::OrgService.behavior(durable, event, gateway, executor))
    app = DevTeam::Api::App.new(system, org_service, "test-key")

    server = HTTP::Server.new([app])
    address = server.bind_tcp("127.0.0.1", 0)
    done = Channel(Nil).new
    spawn do
      server.listen
      done.send(nil)
    end

    client = HTTP::Client.new(address.address, address.port)
    headers = HTTP::Headers{"X-API-Key" => "test-key", "Content-Type" => "application/json"}
    begin
      resp = client.post("/orgs", headers, "{bad-json")
      resp.status_code.should eq(400)
      JSON.parse(resp.body)["error"].as_s.should_not be_empty
    ensure
      client.close
      server.close
      begin
        done.receive
      rescue
      end
    end
  end
end
