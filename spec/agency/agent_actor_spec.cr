require "../spec_helper"
require "../../src/movie"
require "../../src/agency/agents/messages"
require "../../src/agency/agents/actor"
require "../../src/agency/agents/session"
require "../../src/agency/agents/run"
require "../../src/agency/llm/gateway"
require "../../src/agency/llm/client"
require "../../src/agency/agents/profile"

module Agency
  class ActorFixedLLMClient < LLMClient
    def initialize(@response : String)
      super("dummy-key")
    end

    def chat(messages : Array(Agency::Message), tools : Array(Agency::ToolSpec), model : String = "gpt-3.5-turbo") : String
      @response
    end
  end

  class ModelCaptureLLMClient < LLMClient
    def initialize(@channel : Channel(String), @response : String)
      super("dummy-key")
    end

    def chat(messages : Array(Agency::Message), tools : Array(Agency::ToolSpec), model : String = "gpt-3.5-turbo") : String
      @channel.send(model)
      @response
    end
  end

  class StringReceiver < Movie::AbstractBehavior(String)
    def initialize(@promise : Movie::Promise(String))
    end

    def receive(message, ctx)
      @promise.try_success(message)
      Movie::Behaviors(Agency::SystemMessage).same
    end
  end

  class AgentStateReceiver < Movie::AbstractBehavior(AgentState)
    def initialize(@promise : Movie::Promise(AgentState))
    end

    def receive(message, ctx)
      @promise.try_success(message)
      Movie::Behaviors(AgentState).same
    end
  end
end

describe Agency::AgentActor do
  it "routes prompts to sessions and returns a response" do
    context_path = "/tmp/agency_agent_actor_context_#{UUID.random}.sqlite3"
    graph_path = "/tmp/agency_agent_actor_graph_#{UUID.random}.sqlite3"
    config = Movie::Config.builder
      .set("agency.context.db_path", context_path)
      .set("agency.graph.db_path", graph_path)
      .build
    system = Movie::ActorSystem(Agency::SystemMessage).new(Movie::Behaviors(Agency::SystemMessage).same, config)
    client = Agency::ActorFixedLLMClient.new({"type" => "final", "content" => "ok"}.to_json)
    llm_gateway = system.spawn(Agency::LLMGateway.behavior(client))
    profile = Agency::AgentProfile.new("agent-1", "gpt-3.5-turbo", 4, 50)

    agent = system.spawn(
      Agency::AgentActor.behavior(
        profile,
        llm_gateway,
        [] of Agency::ToolSetDefinition,
        Movie::SupervisionConfig.default,
        Movie::SupervisionConfig.default
      )
    )

    promise = Movie::Promise(String).new
    receiver = system.spawn(Agency::StringReceiver.new(promise))

    agent << Agency::RunPrompt.new("hello", "session-1", "gpt-3.5-turbo", receiver, "agent-1")
    result = promise.future.await(5.seconds)
    result.should eq("ok")
  end

  it "reports and updates agent state for sessions" do
    context_path = "/tmp/agency_agent_actor_context_#{UUID.random}.sqlite3"
    graph_path = "/tmp/agency_agent_actor_graph_#{UUID.random}.sqlite3"
    config = Movie::Config.builder
      .set("agency.context.db_path", context_path)
      .set("agency.graph.db_path", graph_path)
      .build
    system = Movie::ActorSystem(Agency::SystemMessage).new(Movie::Behaviors(Agency::SystemMessage).same, config)
    client = Agency::ActorFixedLLMClient.new({"type" => "final", "content" => "ok"}.to_json)
    llm_gateway = system.spawn(Agency::LLMGateway.behavior(client))
    profile = Agency::AgentProfile.new("agent-1", "gpt-3.5-turbo", 4, 50)

    agent = system.spawn(
      Agency::AgentActor.behavior(
        profile,
        llm_gateway,
        [] of Agency::ToolSetDefinition,
        Movie::SupervisionConfig.default,
        Movie::SupervisionConfig.default
      )
    )

    agent << Agency::StartSession.new("s1")
    agent << Agency::StartSession.new("s2")

    state_promise = Movie::Promise(Agency::AgentState).new
    state_receiver = system.spawn(Agency::AgentStateReceiver.new(state_promise))
    agent << Agency::GetAgentState.new(state_receiver)

    state = state_promise.future.await(5.seconds)
    state.agent_id.should eq("agent-1")
    state.sessions.includes?("s1").should be_true
    state.sessions.includes?("s2").should be_true

    agent << Agency::StopSession.new("s1")
    state_promise2 = Movie::Promise(Agency::AgentState).new
    state_receiver2 = system.spawn(Agency::AgentStateReceiver.new(state_promise2))
    agent << Agency::GetAgentState.new(state_receiver2)

    state2 = state_promise2.future.await(5.seconds)
    state2.sessions.includes?("s1").should be_false
  end

  it "uses profile model when prompt model is empty" do
    context_path = "/tmp/agency_agent_actor_context_#{UUID.random}.sqlite3"
    graph_path = "/tmp/agency_agent_actor_graph_#{UUID.random}.sqlite3"
    config = Movie::Config.builder
      .set("agency.context.db_path", context_path)
      .set("agency.graph.db_path", graph_path)
      .build
    system = Movie::ActorSystem(Agency::SystemMessage).new(Movie::Behaviors(Agency::SystemMessage).same, config)
    channel = Channel(String).new(2)
    client = Agency::ModelCaptureLLMClient.new(channel, {"type" => "final", "content" => "ok"}.to_json)
    llm_gateway = system.spawn(Agency::LLMGateway.behavior(client))
    profile = Agency::AgentProfile.new("agent-1", "model-x", 4, 50)

    agent = system.spawn(
      Agency::AgentActor.behavior(
        profile,
        llm_gateway,
        [] of Agency::ToolSetDefinition,
        Movie::SupervisionConfig.default,
        Movie::SupervisionConfig.default
      )
    )

    promise = Movie::Promise(String).new
    receiver = system.spawn(Agency::StringReceiver.new(promise))

    agent << Agency::RunPrompt.new("hello", "session-1", "", receiver, "agent-1")

    model = channel.receive
    model.should eq("model-x")
    promise.future.await(5.seconds).should eq("ok")
  end
end
