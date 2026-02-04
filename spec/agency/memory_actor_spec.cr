require "../spec_helper"
require "../../src/agency/memory_actor"
require "../../src/ametist"

private class ReplyActor(T) < Movie::AbstractBehavior(T)
  def initialize(@promise : Movie::Promise(T))
  end

  def receive(message, ctx)
    @promise.try_success(message)
    ctx.stop
    Movie::Behaviors(T).same
  end
end

private class Dropper(T) < Movie::AbstractBehavior(T)
  def receive(message, ctx)
    Movie::Behaviors(T).same
  end
end

private class SlowContextStore < Agency::ContextStore
  getter summary : String?

  def initialize
    super(":memory:")
  end

  def fetch_events(session_id : String, limit : Int32 = 100) : Array(NamedTuple(role: String, content: String, name: String?, tool_call_id: String?))
    sleep 200.milliseconds
    [] of NamedTuple(role: String, content: String, name: String?, tool_call_id: String?)
  end

  def store_summary(session_id : String, summary : String)
    @summary = summary
  end
end

private class SlowContextStoreExtension < Agency::ContextStoreExtension
  def initialize(@system : Movie::AbstractActorSystem, store : SlowContextStore)
    @db_path = ""
    @store = store
  end
end

private class SlowGraphStore < Agency::GraphStore
  getter added : Bool

  def initialize
    super(":memory:")
    @added = false
  end

  def add_node(id : String, type : String, data : String? = nil)
    sleep 200.milliseconds
    @added = true
  end
end

private class SlowGraphStoreExtension < Agency::GraphStoreExtension
  def initialize(@system : Movie::AbstractActorSystem, store : SlowGraphStore)
    @db_path = ""
    @store = store
  end
end

describe Agency::MemoryActor do
  it "stores events, summaries, and embeddings" do
    graph_path = "/tmp/agency_memory_actor_graph_#{UUID.random}.sqlite3"
    context_path = "/tmp/agency_memory_actor_context_#{UUID.random}.sqlite3"
    config = Movie::Config.builder
      .set("agency.graph.db_path", graph_path)
      .set("agency.context.db_path", context_path)
      .build
    system = Movie::ActorSystem(Agency::SystemMessage).new(Movie::Behaviors(Agency::SystemMessage).same, config)

    ametist = Ametist.get(system)
    schema = Ametist::CollectionSchema.new("memory_events", [
      Ametist::FieldSchema.new("embedding", Ametist::TypeSchema.new("vector", 2)),
    ])
    ametist.create_collection(schema).await(1.second).should be_true

    context_ext = Agency::ContextStoreExtension.new(system, context_path)
    graph_ext = Agency::GraphStoreExtension.new(system, graph_path)
    vector_ext = Agency::VectorStoreExtensionId.get(system)

    memory = system.spawn(
      Agency::MemoryActor.behavior(
        Agency::MemoryScope::Session,
        vector_collection: "memory_events",
        context_store: context_ext,
        graph_store: graph_ext,
        vector_store: vector_ext
      )
    )

    event_promise = Movie::Promise(String).new
    event_reply = system.spawn(ReplyActor(String).new(event_promise))
    memory << Agency::StoreEvent.new("s1", Agency::Message.new(Agency::Role::User, "hello"), false, event_reply)
    event_id = event_promise.future.await(1.second)
    event_id.should_not be_empty

    events = context_ext.store.fetch_events("s1", 10)
    events.size.should eq(1)
    events.first[:content].should eq("hello")

    summary_promise = Movie::Promise(Bool).new
    summary_reply = system.spawn(ReplyActor(Bool).new(summary_promise))
    memory << Agency::StoreSummary.new("s1", "sum", summary_reply)
    summary_promise.future.await(1.second).should be_true
    context_ext.store.get_summary("s1").should eq("sum")

    embed_promise = Movie::Promise(Bool).new
    embed_reply = system.spawn(ReplyActor(Bool).new(embed_promise))
    memory << Agency::UpsertEmbedding.new("memory_events", event_id, [1.0_f32, 0.0_f32], nil, embed_reply)
    embed_promise.future.await(1.second).should be_true

    results = Agency::VectorStoreExtensionId.get(system)
      .query_top_k("memory_events", [1.0_f32, 0.0_f32], 1)
      .await(1.second)
    results.size.should eq(1)
    results.first.id.should eq(event_id)
  end

  it "stores and fetches session metadata" do
    graph_path = "/tmp/agency_memory_actor_graph_#{UUID.random}.sqlite3"
    context_path = "/tmp/agency_memory_actor_context_#{UUID.random}.sqlite3"
    config = Movie::Config.builder
      .set("agency.graph.db_path", graph_path)
      .set("agency.context.db_path", context_path)
      .build
    system = Movie::ActorSystem(Agency::SystemMessage).new(Movie::Behaviors(Agency::SystemMessage).same, config)

    ametist = Ametist.get(system)
    schema = Ametist::CollectionSchema.new("memory_meta", [
      Ametist::FieldSchema.new("embedding", Ametist::TypeSchema.new("vector", 2)),
    ])
    ametist.create_collection(schema).await(1.second).should be_true

    context_ext = Agency::ContextStoreExtension.new(system, context_path)
    graph_ext = Agency::GraphStoreExtension.new(system, graph_path)
    vector_ext = Agency::VectorStoreExtensionId.get(system)

    memory = system.spawn(
      Agency::MemoryActor.behavior(
        Agency::MemoryScope::Session,
        vector_collection: "memory_meta",
        context_store: context_ext,
        graph_store: graph_ext,
        vector_store: vector_ext
      )
    )

    store_promise = Movie::Promise(Bool).new
    store_reply = system.spawn(ReplyActor(Bool).new(store_promise))
    memory << Agency::StoreSessionMeta.new("s1", "agent-a", "model-x", store_reply)
    store_promise.future.await(1.second).should be_true

    get_promise = Movie::Promise(Agency::SessionMeta?).new
    get_reply = system.spawn(ReplyActor(Agency::SessionMeta?).new(get_promise))
    memory << Agency::GetSessionMeta.new("s1", get_reply)
    meta = get_promise.future.await(1.second)
    meta.should_not be_nil
    meta.not_nil!.agent_id.should eq("agent-a")
    meta.not_nil!.model.should eq("model-x")
  end

  it "does not block mailbox on slow context fetches" do
    graph_path = "/tmp/agency_memory_actor_graph_#{UUID.random}.sqlite3"
    config = Movie::Config.builder
      .set("agency.graph.db_path", graph_path)
      .build
    system = Movie::ActorSystem(Agency::SystemMessage).new(Movie::Behaviors(Agency::SystemMessage).same, config)

    slow_store = SlowContextStore.new
    context_ext = SlowContextStoreExtension.new(system, slow_store)
    graph_ext = Agency::GraphStoreExtension.new(system, graph_path)
    vector_ext = Agency::VectorStoreExtensionId.get(system)

    memory = system.spawn(
      Agency::MemoryActor.behavior(
        Agency::MemoryScope::Session,
        context_store: context_ext,
        graph_store: graph_ext,
        vector_store: vector_ext
      )
    )

    fetch_promise = Movie::Promise(Array(Agency::Message)).new
    fetch_reply = system.spawn(ReplyActor(Array(Agency::Message)).new(fetch_promise))
    memory << Agency::FetchEvents.new("s1", 10, fetch_reply)

    summary_promise = Movie::Promise(Bool).new
    summary_reply = system.spawn(ReplyActor(Bool).new(summary_promise))
    memory << Agency::StoreSummary.new("s1", "sum", summary_reply)

    summary_promise.future.await(50.milliseconds).should be_true
    slow_store.summary.should eq("sum")
  end

  it "does not block mailbox on slow graph operations" do
    context_path = "/tmp/agency_memory_actor_context_#{UUID.random}.sqlite3"
    config = Movie::Config.builder
      .set("agency.context.db_path", context_path)
      .set("executor.pool-size", 2)
      .build
    system = Movie::ActorSystem(Agency::SystemMessage).new(Movie::Behaviors(Agency::SystemMessage).same, config)

    slow_store = SlowGraphStore.new
    context_ext = Agency::ContextStoreExtension.new(system, context_path)
    graph_ext = SlowGraphStoreExtension.new(system, slow_store)
    vector_ext = Agency::VectorStoreExtensionId.get(system)

    memory = system.spawn(
      Agency::MemoryActor.behavior(
        Agency::MemoryScope::Session,
        context_store: context_ext,
        graph_store: graph_ext,
        vector_store: vector_ext
      )
    )

    add_promise = Movie::Promise(Bool).new
    add_reply = system.spawn(ReplyActor(Bool).new(add_promise))
    memory << Agency::AddNode.new("n1", "entity", nil, add_reply)

    summary_promise = Movie::Promise(Bool).new
    summary_reply = system.spawn(ReplyActor(Bool).new(summary_promise))
    memory << Agency::StoreSummary.new("s1", "sum", summary_reply)

    summary_promise.future.await(1.second).should be_true
  end
end
