require "../spec_helper"
require "../../src/agency/context/builder"
require "../../src/agency/memory/actor"
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
  it "merges session, project, and user summaries in order" do
    session_path = "/tmp/agency_multi_scope_session_#{UUID.random}.sqlite3"
    project_path = "/tmp/agency_multi_scope_project_#{UUID.random}.sqlite3"
    user_path = "/tmp/agency_multi_scope_user_#{UUID.random}.sqlite3"
    config = Movie::Config.builder
      .set("agency.context.db_path", session_path)
      .build
    system = Movie::ActorSystem(Agency::SystemMessage).new(Movie::Behaviors(Agency::SystemMessage).same, config)

    session_store = Agency::ContextStoreExtension.new(system, session_path)
    project_store = Agency::ContextStoreExtension.new(system, project_path)
    user_store = Agency::ContextStoreExtension.new(system, user_path)

    policy = Agency::MemoryPolicy.from_config(system.config)
    session_memory = system.spawn(
      Agency::MemoryActor.behavior(
        Agency::MemoryScope::Session,
        context_store: session_store,
        memory_policy: policy
      )
    )
    project_memory = system.spawn(
      Agency::MemoryActor.behavior(
        Agency::MemoryScope::Project,
        context_store: project_store,
        memory_policy: policy
      )
    )
    user_memory = system.spawn(
      Agency::MemoryActor.behavior(
        Agency::MemoryScope::User,
        context_store: user_store,
        memory_policy: policy
      )
    )

    summary_promise = Movie::Promise(Bool).new
    summary_reply = system.spawn(ReplyActor(Bool).new(summary_promise))
    session_memory << Agency::StoreSummary.new("session-1", "session summary", summary_reply)
    summary_promise.future.await(1.second)

    summary_promise = Movie::Promise(Bool).new
    summary_reply = system.spawn(ReplyActor(Bool).new(summary_promise))
    project_memory << Agency::StoreSummary.new("project-1", "project summary", summary_reply)
    summary_promise.future.await(1.second)

    summary_promise = Movie::Promise(Bool).new
    summary_reply = system.spawn(ReplyActor(Bool).new(summary_promise))
    user_memory << Agency::StoreSummary.new("user-1", "user summary", summary_reply)
    summary_promise.future.await(1.second)

    builder = system.spawn(
      Agency::ContextBuilder.behavior(
        session_memory,
        embedder: nil,
        vector_collection: "agency_memory",
        max_history: policy.session.max_history,
        semantic_k: policy.session.semantic_k,
        timeout: 2.seconds,
        project_memory: project_memory,
        user_memory: user_memory,
        memory_policy: policy
      )
    )

    promise = Movie::Promise(Agency::ContextBuilt).new
    reply = system.spawn(ReplyActor(Agency::ContextBuilt).new(promise))
    builder << Agency::BuildContext.new("session-1", "prompt", [] of Agency::Message, reply, "user-1", "project-1")

    built = promise.future.await(2.seconds)
    contents = built.messages.map(&.content)
    contents[0].should eq("Summary: session summary")
    contents[1].should eq("Project Summary: project summary")
    contents[2].should eq("User Summary: user summary")
  end
end
