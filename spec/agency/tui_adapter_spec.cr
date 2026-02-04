require "../spec_helper"
require "../../src/agency/tui_adapter"
require "../../src/agency/agent_manager"
require "../../src/agency/llm_client"

describe Agency::TuiAdapter do
  it "runs a prompt and returns the response" do
    context_path = "/tmp/agency_tui_adapter_context_#{UUID.random}.sqlite3"
    graph_path = "/tmp/agency_tui_adapter_graph_#{UUID.random}.sqlite3"
    config = Movie::Config.builder
      .set("agency.context.db_path", context_path)
      .set("agency.graph.db_path", graph_path)
      .build
    system = Movie::ActorSystem(Agency::SystemMessage).new(Movie::Behaviors(Agency::SystemMessage).same, config)
    Movie::Execution.get(system)

    client = Agency::LLMClient.new("dummy-key")
    manager = Agency::AgentManager.spawn(system, client, "gpt-3.5-turbo")
    adapter = system.spawn(Agency::TuiAdapter.behavior(manager, "gpt-3.5-turbo"))

    promise = Movie::Promise(String).new
    receiver = system.spawn(ReplyActor.new(promise))
    helper = system.spawn(AskHelper.new(adapter, receiver))
    helper << Agency::TuiRun.new("hello", "s1", "gpt-3.5-turbo", "agent-1")

    promise.future.await(10.seconds).includes?("Simulated response").should be_true
  end
end

private class ReplyActor < Movie::AbstractBehavior(String)
  def initialize(@promise : Movie::Promise(String))
  end

  def receive(message, ctx)
    @promise.try_success(message)
    Movie::Behaviors(Agency::SystemMessage).stopped
  end
end

private class AskHelper < Movie::AbstractBehavior(Agency::TuiRun)
  def initialize(@adapter : Movie::ActorRef(Agency::TuiMessage), @reply_to : Movie::ActorRef(String))
  end

  def receive(message, ctx)
    future = ctx.ask(@adapter, message, String)
    future.on_success { |value| @reply_to << value }
    future.on_failure { |ex| @reply_to << "(error) #{ex.message}" }
    Movie::Behaviors(Agency::TuiRun).same
  end
end
