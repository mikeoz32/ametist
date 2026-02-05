require "../spec_helper"
require "../../src/agency/context/builder"
require "../../src/agency/memory/actor"
require "../../src/agency/stores/embedder_extension"
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

private class FakeResponse
  getter status_code : Int32
  getter body : String

  def initialize(@status_code : Int32, @body : String)
  end
end

private class FakeHttpClient
  include OpenAI::HttpClient

  def request(method : String, url : String, headers : Hash(String, String) = {} of String => String, body : String | IO | Nil = nil)
    response_body = {
      "object" => "list",
      "model" => "test",
      "data" => [
        {"index" => 0, "object" => "embedding", "embedding" => [1.0, 0.0]},
      ],
    }.to_json
    FakeResponse.new(200, response_body)
  end
end

private class SlowContextStore < Agency::ContextStore
  def fetch_events(session_id : String, limit : Int32 = 100) : Array(NamedTuple(role: String, content: String, name: String?, tool_call_id: String?))
    sleep 300.milliseconds
    super
  end
end

private class SlowContextStoreExtension < Agency::ContextStoreExtension
  def initialize(@system : Movie::AbstractActorSystem, store : SlowContextStore)
    @db_path = ""
    @store = store
  end
end

describe Agency::ContextBuilder do
  it "builds context with summary and semantic matches" do
    graph_path = "/tmp/agency_context_builder_graph_#{UUID.random}.sqlite3"
    context_path = "/tmp/agency_context_builder_context_#{UUID.random}.sqlite3"
    config = Movie::Config.builder
      .set("agency.graph.db_path", graph_path)
      .set("agency.context.db_path", context_path)
      .build
    system = Movie::ActorSystem(Agency::SystemMessage).new(Movie::Behaviors(Agency::SystemMessage).same, config)

    ametist = Ametist.get(system)
    schema = Ametist::CollectionSchema.new("session_memory", [
      Ametist::FieldSchema.new("embedding", Ametist::TypeSchema.new("vector", 2)),
    ])
    ametist.create_collection(schema).await(2.seconds).should be_true

    context_ext = Agency::ContextStoreExtension.new(system, context_path)
    graph_ext = Agency::GraphStoreExtension.new(system, graph_path)
    vector_ext = Agency::VectorStoreExtensionId.get(system)

    memory = system.spawn(
      Agency::MemoryActor.behavior(
        Agency::MemoryScope::Session,
        vector_collection: "session_memory",
        context_store: context_ext,
        graph_store: graph_ext,
        vector_store: vector_ext
      )
    )

    event_promise = Movie::Promise(String).new
    event_reply = system.spawn(ReplyActor(String).new(event_promise))
    memory << Agency::StoreEvent.new("s1", Agency::Message.new(Agency::Role::User, "hello world"), false, event_reply)
    event_id = event_promise.future.await(2.seconds)

    embed_promise = Movie::Promise(Bool).new
    embed_reply = system.spawn(ReplyActor(Bool).new(embed_promise))
    memory << Agency::UpsertEmbedding.new("session_memory", event_id, [1.0_f32, 0.0_f32], nil, embed_reply)
    embed_promise.future.await(2.seconds).should be_true

    summary_promise = Movie::Promise(Bool).new
    summary_reply = system.spawn(ReplyActor(Bool).new(summary_promise))
    memory << Agency::StoreSummary.new("s1", "summary text", summary_reply)
    summary_promise.future.await(2.seconds).should be_true

    client = OpenAI::Client.new("dummy-key", "http://example.test", FakeHttpClient.new)
    embedder = Agency::EmbedderExtension.new(system, client, "test-model")

    builder = system.spawn(Agency::ContextBuilder.behavior(memory, embedder, "session_memory", timeout: 10.seconds))

    reply_promise = Movie::Promise(Agency::ContextBuilt).new
    reply = system.spawn(ReplyActor(Agency::ContextBuilt).new(reply_promise))
    builder << Agency::BuildContext.new("s1", "hello", [] of Agency::Message, reply)

    context = reply_promise.future.await(12.seconds)
    context.messages.size.should be > 0
    context.messages.first.role.should eq(Agency::Role::System)
  end

  it "keeps current prompt when recent history comes from memory" do
    graph_path = "/tmp/agency_context_builder_graph_#{UUID.random}.sqlite3"
    context_path = "/tmp/agency_context_builder_context_#{UUID.random}.sqlite3"
    config = Movie::Config.builder
      .set("agency.graph.db_path", graph_path)
      .set("agency.context.db_path", context_path)
      .build
    system = Movie::ActorSystem(Agency::SystemMessage).new(Movie::Behaviors(Agency::SystemMessage).same, config)

    context_ext = Agency::ContextStoreExtension.new(system, context_path)
    graph_ext = Agency::GraphStoreExtension.new(system, graph_path)
    vector_ext = Agency::VectorStoreExtensionId.get(system)

    memory = system.spawn(
      Agency::MemoryActor.behavior(
        Agency::MemoryScope::Session,
        vector_collection: "session_memory",
        context_store: context_ext,
        graph_store: graph_ext,
        vector_store: vector_ext
      )
    )

    event_promise = Movie::Promise(String).new
    event_reply = system.spawn(ReplyActor(String).new(event_promise))
    memory << Agency::StoreEvent.new("s2", Agency::Message.new(Agency::Role::User, "hi there"), false, event_reply)
    event_promise.future.await(2.seconds).should_not eq("")

    builder = system.spawn(Agency::ContextBuilder.behavior(memory, nil, "session_memory", timeout: 3.seconds))

    reply_promise = Movie::Promise(Agency::ContextBuilt).new
    reply = system.spawn(ReplyActor(Agency::ContextBuilt).new(reply_promise))
    history = [Agency::Message.new(Agency::Role::User, "remember my name is Mike")]
    builder << Agency::BuildContext.new("s2", "remember my name is Mike", history, reply)

    context = reply_promise.future.await(2.seconds)
    context.messages.any? { |msg| msg.content == "remember my name is Mike" }.should be_true
  end

  it "waits long enough to include slow recent history by default" do
    graph_path = "/tmp/agency_context_builder_graph_#{UUID.random}.sqlite3"
    context_path = "/tmp/agency_context_builder_context_#{UUID.random}.sqlite3"
    config = Movie::Config.builder
      .set("agency.graph.db_path", graph_path)
      .set("agency.context.db_path", context_path)
      .build
    system = Movie::ActorSystem(Agency::SystemMessage).new(Movie::Behaviors(Agency::SystemMessage).same, config)

    slow_store = SlowContextStore.new(context_path)
    context_ext = SlowContextStoreExtension.new(system, slow_store)
    graph_ext = Agency::GraphStoreExtension.new(system, graph_path)
    vector_ext = Agency::VectorStoreExtensionId.get(system)

    memory = system.spawn(
      Agency::MemoryActor.behavior(
        Agency::MemoryScope::Session,
        vector_collection: "session_memory",
        context_store: context_ext,
        graph_store: graph_ext,
        vector_store: vector_ext
      )
    )

    context_ext.store.append_event("slow-session", "user", "from store", nil, nil)

    builder = system.spawn(Agency::ContextBuilder.behavior(memory, nil, "session_memory", timeout: 3.seconds))

    reply_promise = Movie::Promise(Agency::ContextBuilt).new
    reply = system.spawn(ReplyActor(Agency::ContextBuilt).new(reply_promise))
    history = [Agency::Message.new(Agency::Role::User, "current prompt")]
    builder << Agency::BuildContext.new("slow-session", "current prompt", history, reply)

    context = reply_promise.future.await(3.seconds)
    context.messages.any? { |msg| msg.content == "from store" }.should be_true
  end
end
