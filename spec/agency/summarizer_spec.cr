require "../spec_helper"
require "../../src/agency/summarizer"
require "../../src/agency/memory_actor"
require "../../src/agency/context_store_extension"

private class FakeSummarizerClient < Agency::SummarizerClient
  def summarize(summary : String?, events : Array(Agency::Message), model : String) : String
    "summary(#{model}):#{events.size}"
  end
end

private class ReplyActor(T) < Movie::AbstractBehavior(T)
  def initialize(@promise : Movie::Promise(T))
  end

  def receive(message, ctx)
    @promise.try_success(message)
    ctx.stop
    Movie::Behaviors(T).same
  end
end

describe Agency::SummarizerActor do
  it "stores summary using the summarizer client" do
    context_path = "/tmp/agency_summarizer_context_#{UUID.random}.sqlite3"
    config = Movie::Config.builder
      .set("agency.context.db_path", context_path)
      .set("agency.llm.model", "test-model")
      .build

    system = Movie::ActorSystem(Agency::SystemMessage).new(Movie::Behaviors(Agency::SystemMessage).same, config)
    context_ext = Agency::ContextStoreExtension.new(system, context_path)

    memory = system.spawn(
      Agency::MemoryActor.behavior(
        Agency::MemoryScope::Session,
        context_store: context_ext
      )
    )

    meta_promise = Movie::Promise(Bool).new
    meta_reply = system.spawn(ReplyActor(Bool).new(meta_promise))
    memory << Agency::StoreSessionMeta.new("session", "agent", "session-model", meta_reply)
    meta_promise.future.await(1.second)

    meta_fetch = Movie::Promise(Agency::SessionMeta?).new
    meta_fetch_reply = system.spawn(ReplyActor(Agency::SessionMeta?).new(meta_fetch))
    memory << Agency::GetSessionMeta.new("session", meta_fetch_reply)
    meta = meta_fetch.future.await(1.second)
    meta.should_not be_nil
    meta.not_nil!.model.should eq "session-model"

    event_promise = Movie::Promise(String).new
    event_reply = system.spawn(ReplyActor(String).new(event_promise))
    memory << Agency::StoreEvent.new("session", Agency::Message.new(Agency::Role::User, "hello"), false, event_reply)
    event_promise.future.await(1.second)

    event_promise = Movie::Promise(String).new
    event_reply = system.spawn(ReplyActor(String).new(event_promise))
    memory << Agency::StoreEvent.new("session", Agency::Message.new(Agency::Role::Assistant, "world"), false, event_reply)
    event_promise.future.await(1.second)

    summarizer = system.spawn(
      Agency::SummarizerActor.behavior(memory, FakeSummarizerClient.new, 2.seconds)
    )
    summarizer << Agency::SummarizeSession.new("session")

    deadline = Time.monotonic + 5.seconds
    summary = nil.as(String?)
    loop do
      promise = Movie::Promise(String?).new
      reply = system.spawn(ReplyActor(String?).new(promise))
      memory << Agency::GetSummary.new("session", reply)
      summary = promise.future.await(1.second)
      break if summary
      break if Time.monotonic >= deadline
      sleep 25.milliseconds
    end

    summary.should_not be_nil
    summary.not_nil!.should contain("summary(session-model):2")
  end
end
