require "../spec_helper"
require "../../src/agency/context/builder"
require "../../src/agency/memory/actor"
require "../../src/agency/stores/graph_store_extension"
require "../../src/agency/context/store_extension"
require "../../src/agency/memory/policy"

private class ReplyActor(T) < Movie::AbstractBehavior(T)
  def initialize(@promise : Movie::Promise(T))
  end

  def receive(message, ctx)
    @promise.try_success(message)
    ctx.stop
    Movie::Behaviors(T).same
  end
end

describe Agency::ContextBuilder do
  it "includes graph neighbor data in context" do
    graph_path = "/tmp/agency_graph_recall_#{UUID.random}.sqlite3"
    context_path = "/tmp/agency_graph_recall_context_#{UUID.random}.sqlite3"
    config = Movie::Config.builder
      .set("agency.graph.db_path", graph_path)
      .set("agency.context.db_path", context_path)
      .build
    system = Movie::ActorSystem(Agency::SystemMessage).new(Movie::Behaviors(Agency::SystemMessage).same, config)

    graph_ext = Agency::GraphStoreExtension.new(system, graph_path)
    context_ext = Agency::ContextStoreExtension.new(system, context_path)
    policy = Agency::MemoryPolicy.from_config(system.config)

    memory = system.spawn(
      Agency::MemoryActor.behavior(
        Agency::MemoryScope::Session,
        context_store: context_ext,
        graph_store: graph_ext,
        memory_policy: policy
      )
    )

    promise = Movie::Promise(Bool).new
    reply = system.spawn(ReplyActor(Bool).new(promise))
    memory << Agency::AddNode.new("session-1", "session", "session-root", reply)
    promise.future.await(1.second)

    promise = Movie::Promise(Bool).new
    reply = system.spawn(ReplyActor(Bool).new(promise))
    memory << Agency::AddNode.new("n1", "fact", "Mike likes Crystal", reply)
    promise.future.await(1.second)

    promise = Movie::Promise(Bool).new
    reply = system.spawn(ReplyActor(Bool).new(promise))
    memory << Agency::AddEdge.new("e1", "session-1", "n1", "has_fact", nil, reply)
    promise.future.await(1.second)

    builder = system.spawn(
      Agency::ContextBuilder.behavior(
        memory,
        embedder: nil,
        vector_collection: "agency_memory",
        max_history: policy.session.max_history,
        semantic_k: policy.session.semantic_k,
        timeout: 2.seconds,
        memory_policy: policy
      )
    )

    reply_promise = Movie::Promise(Agency::ContextBuilt).new
    reply = system.spawn(ReplyActor(Agency::ContextBuilt).new(reply_promise))
    builder << Agency::BuildContext.new("session-1", "hello", [] of Agency::Message, reply)

    context = reply_promise.future.await(3.seconds)
    context.messages.any? { |msg| msg.content.includes?("Mike likes Crystal") }.should be_true
  end
end
