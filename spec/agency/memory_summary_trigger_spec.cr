require "../spec_helper"
require "../../src/agency/memory/actor"
require "../../src/agency/memory/policy"
require "../../src/agency/memory/summarizer"

private class SummaryProbe < Movie::AbstractBehavior(Agency::SummarizerMessage)
  def initialize(@promise : Movie::Promise(Agency::SummarizerMessage))
  end

  def receive(message, ctx)
    @promise.try_success(message)
    ctx.stop
    Movie::Behaviors(Agency::SummarizerMessage).same
  end
end

describe Agency::MemoryActor do
  it "triggers summarization when token threshold is exceeded" do
    graph_path = "/tmp/agency_memory_summary_graph_#{UUID.random}.sqlite3"
    context_path = "/tmp/agency_memory_summary_context_#{UUID.random}.sqlite3"
    config = Movie::Config.builder
      .set("agency.context.db_path", context_path)
      .set("agency.graph.db_path", graph_path)
      .set("agency.memory.summary_token_threshold", 1)
      .build

    system = Movie::ActorSystem(Agency::SystemMessage).new(Movie::Behaviors(Agency::SystemMessage).same, config)
    context_ext = Agency::ContextStoreExtension.new(system, context_path)
    graph_ext = Agency::GraphStoreExtension.new(system, graph_path)

    promise = Movie::Promise(Agency::SummarizerMessage).new
    probe = system.spawn(SummaryProbe.new(promise))

    policy = Agency::MemoryPolicy.from_config(config)
    memory = system.spawn(
      Agency::MemoryActor.behavior(
        Agency::MemoryScope::Session,
        context_store: context_ext,
        graph_store: graph_ext,
        memory_policy: policy,
        summarizer: probe
      )
    )

    memory << Agency::StoreEvent.new("session", Agency::Message.new(Agency::Role::User, "hello world from memory"), false)
    memory << Agency::StoreEvent.new("session", Agency::Message.new(Agency::Role::User, "hello world from memory"), false)

    message = promise.future.await(5.seconds)
    message.session_id.should eq "session"
  end
end
