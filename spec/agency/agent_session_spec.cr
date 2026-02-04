require "../spec_helper"
require "../../src/movie"
require "../../src/agency/agent_messages"
require "../../src/agency/agent_session"
require "../../src/agency/agent_run"
require "../../src/agency/llm_gateway"
require "../../src/agency/llm_client"
require "../../src/agency/tool_set"
require "../../src/agency/context_builder"

module Agency
  class SessionFixedLLMClient < LLMClient
    def initialize(@response : String)
      super("dummy-key")
    end

    def chat(messages : Array(Agency::Message), tools : Array(Agency::ToolSpec), model : String = "gpt-3.5-turbo") : String
      @response
    end
  end

  class BlockingLLMClient < LLMClient
    def initialize(@gate : Channel(Nil))
      super("dummy-key")
    end

    def chat(messages : Array(Agency::Message), tools : Array(Agency::ToolSpec), model : String = "gpt-3.5-turbo") : String
      @gate.receive
      {"type" => "final", "content" => "done"}.to_json
    end
  end

  class RecordingLLMClient < LLMClient
    getter last_messages : Array(Agency::Message)

    def initialize(@response : String)
      super("dummy-key")
      @last_messages = [] of Agency::Message
    end

    def chat(messages : Array(Agency::Message), tools : Array(Agency::ToolSpec), model : String = "gpt-3.5-turbo") : String
      @last_messages = messages
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

  class SessionStateReceiver < Movie::AbstractBehavior(SessionState)
    def initialize(@promise : Movie::Promise(SessionState))
    end

    def receive(message, ctx)
      @promise.try_success(message)
      Movie::Behaviors(SessionState).same
    end
  end
end

describe Agency::AgentSession do
  it "spawns a run per prompt and returns the result" do
    system = Agency.spec_system
    executor = Movie::Execution.get(system)
    client = Agency::SessionFixedLLMClient.new({"type" => "final", "content" => "ok"}.to_json)
    llm_gateway = system.spawn(Agency::LLMGateway.behavior(client))
    tool_set = system.spawn(Agency::DefaultToolSet.new(executor))
    context_builder = system.spawn(Agency::ContextBuilder.new)

    session = system.spawn(Agency::AgentSession.behavior("session-1", llm_gateway, tool_set, context_builder, nil, 4, 50))

    promise = Movie::Promise(String).new
    receiver = system.spawn(Agency::StringReceiver.new(promise))

    session << Agency::SessionPrompt.new("default", "hello", "gpt-3.5-turbo", [] of Agency::ToolSpec, receiver)
    result = promise.future.await(5.seconds)
    result.should eq("ok")
  end

  it "rejects concurrent prompts while a run is active" do
    system = Agency.spec_system
    executor = Movie::Execution.get(system)
    gate = Channel(Nil).new
    client = Agency::BlockingLLMClient.new(gate)
    llm_gateway = system.spawn(Agency::LLMGateway.behavior(client))
    tool_set = system.spawn(Agency::DefaultToolSet.new(executor))
    context_builder = system.spawn(Agency::ContextBuilder.new)

    session = system.spawn(Agency::AgentSession.behavior("session-1", llm_gateway, tool_set, context_builder, nil, 4, 50))

    first_promise = Movie::Promise(String).new
    first_receiver = system.spawn(Agency::StringReceiver.new(first_promise))
    session << Agency::SessionPrompt.new("default", "first", "gpt-3.5-turbo", [] of Agency::ToolSpec, first_receiver)

    second_promise = Movie::Promise(String).new
    second_receiver = system.spawn(Agency::StringReceiver.new(second_promise))
    session << Agency::SessionPrompt.new("default", "second", "gpt-3.5-turbo", [] of Agency::ToolSpec, second_receiver)

    busy = second_promise.future.await(5.seconds)
    busy.includes?("session already running").should be_true

    gate.send(nil)
    result = first_promise.future.await(5.seconds)
    result.should eq("done")
  end

  it "reports session state while a run is active" do
    system = Agency.spec_system
    executor = Movie::Execution.get(system)
    gate = Channel(Nil).new
    client = Agency::BlockingLLMClient.new(gate)
    llm_gateway = system.spawn(Agency::LLMGateway.behavior(client))
    tool_set = system.spawn(Agency::DefaultToolSet.new(executor))
    context_builder = system.spawn(Agency::ContextBuilder.new)

    session = system.spawn(Agency::AgentSession.behavior("session-42", llm_gateway, tool_set, context_builder, nil, 4, 50))

    run_promise = Movie::Promise(String).new
    run_receiver = system.spawn(Agency::StringReceiver.new(run_promise))
    session << Agency::SessionPrompt.new("default", "state", "gpt-3.5-turbo", [] of Agency::ToolSpec, run_receiver)

    state_promise = Movie::Promise(Agency::SessionState).new
    state_receiver = system.spawn(Agency::SessionStateReceiver.new(state_promise))
    session << Agency::GetSessionState.new(state_receiver)

    state = state_promise.future.await(5.seconds)
    state.session_id.should eq("session-42")
    state.active_run.should be_true
    state.history_size.should eq(0)

    gate.send(nil)
    run_promise.future.await(5.seconds).should eq("done")
  end

  it "loads stored history before the first prompt" do
    graph_path = "/tmp/agency_agent_session_graph_#{UUID.random}.sqlite3"
    context_path = "/tmp/agency_agent_session_context_#{UUID.random}.sqlite3"
    config = Movie::Config.builder
      .set("agency.graph.db_path", graph_path)
      .set("agency.context.db_path", context_path)
      .build
    system = Movie::ActorSystem(Agency::SystemMessage).new(Movie::Behaviors(Agency::SystemMessage).same, config)
    executor = Movie::Execution.get(system)

    context_ext = Agency::ContextStoreExtension.new(system, context_path)
    context_ext.store.append_event("session-1", "user", "from store", nil, nil)

    client = Agency::RecordingLLMClient.new({"type" => "final", "content" => "ok"}.to_json)
    llm_gateway = system.spawn(Agency::LLMGateway.behavior(client))
    tool_set = system.spawn(Agency::DefaultToolSet.new(executor))
    context_builder = system.spawn(Agency::ContextBuilder.new)

    session = system.spawn(Agency::AgentSession.behavior("session-1", llm_gateway, tool_set, context_builder, nil, 4, 50))

    promise = Movie::Promise(String).new
    receiver = system.spawn(Agency::StringReceiver.new(promise))
    session << Agency::SessionPrompt.new("default", "current", "gpt-3.5-turbo", [] of Agency::ToolSpec, receiver)
    promise.future.await(5.seconds).should eq("ok")

    client.last_messages.any? { |msg| msg.content == "from store" }.should be_true
  end
end
