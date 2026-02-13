require "./spec_helper"
require "../src/movie"

record TestEvent, id : Int32, content : String

describe Movie::Streams::Typed do
  it "collects typed elements without casts" do
    pipeline = Movie::Streams::Typed.build_collecting_pipeline(
      TestEvent,
      Movie::Streams::Typed::ManualSource(TestEvent).new,
      [] of Movie::AbstractBehavior(Movie::Streams::Typed::MessageBase(TestEvent)),
      initial_demand: 2u64
    )
    out_ch = pipeline.out_channel.not_nil!

    pipeline.source << Movie::Streams::Typed::Produce(TestEvent).new(TestEvent.new(1, "a"))
    pipeline.source << Movie::Streams::Typed::Produce(TestEvent).new(TestEvent.new(2, "b"))
    pipeline.source << Movie::Streams::Typed::OnComplete(TestEvent).new

    receive_or_timeout(out_ch).should eq(TestEvent.new(1, "a"))
    receive_or_timeout(out_ch).should eq(TestEvent.new(2, "b"))
    pipeline.completion.await(200.milliseconds).should be_nil
  end

  it "broadcasts typed elements to multiple subscribers" do
    out_a = Channel(TestEvent).new
    out_b = Channel(TestEvent).new
    refs = Channel(Tuple(
      Movie::ActorRef(Movie::Streams::Typed::MessageBase(TestEvent)),
      Movie::ActorRef(Movie::Streams::Typed::MessageBase(TestEvent)),
      Movie::ActorRef(Movie::Streams::Typed::MessageBase(TestEvent))
    )).new(1)

    main = Movie::Behaviors(Movie::Streams::Typed::MessageBase(TestEvent)).setup do |ctx|
      source = ctx.spawn(Movie::Streams::Typed::ManualSource(TestEvent).new)
      hub = ctx.spawn(Movie::Streams::Typed::BroadcastHub(TestEvent).new)
      sink_a = ctx.spawn(Movie::Streams::Typed::CollectSink(TestEvent).new(out_a))
      sink_b = ctx.spawn(Movie::Streams::Typed::CollectSink(TestEvent).new(out_b))

      hub << Movie::Streams::Typed::Subscribe(TestEvent).new(sink_a)
      hub << Movie::Streams::Typed::Subscribe(TestEvent).new(sink_b)
      source << Movie::Streams::Typed::Subscribe(TestEvent).new(hub)
      refs.send({source, sink_a, sink_b})
      Movie::Behaviors(Movie::Streams::Typed::MessageBase(TestEvent)).same
    end

    Movie::ActorSystem(Movie::Streams::Typed::MessageBase(TestEvent)).new(main)
    source, sink_a, sink_b = receive_or_timeout(refs)

    sink_a << Movie::Streams::Typed::Request(TestEvent).new(2u64)
    sink_b << Movie::Streams::Typed::Request(TestEvent).new(1u64)
    sleep 5.milliseconds

    source << Movie::Streams::Typed::Produce(TestEvent).new(TestEvent.new(1, "one"))
    source << Movie::Streams::Typed::Produce(TestEvent).new(TestEvent.new(2, "two"))

    receive_or_timeout(out_a).should eq(TestEvent.new(1, "one"))
    receive_or_timeout(out_a).should eq(TestEvent.new(2, "two"))
    receive_or_timeout(out_b).should eq(TestEvent.new(1, "one"))
    receive_optional(out_b, 20.milliseconds).should be_nil
  end

  it "folds typed elements without element casts" do
    pipeline = Movie::Streams::Typed.build_fold_pipeline(
      Int32,
      Int32,
      Movie::Streams::Typed::ManualSource(Int32).new,
      [] of Movie::AbstractBehavior(Movie::Streams::Typed::MessageBase(Int32)),
      0,
      ->(acc : Int32, elem : Int32) { acc + elem },
      initial_demand: 3u64
    )

    pipeline.source << Movie::Streams::Typed::Produce(Int32).new(1)
    pipeline.source << Movie::Streams::Typed::Produce(Int32).new(2)
    pipeline.source << Movie::Streams::Typed::Produce(Int32).new(3)
    pipeline.source << Movie::Streams::Typed::OnComplete(Int32).new

    pipeline.completion.await(200.milliseconds).should eq(6)
  end
end

private def receive_or_timeout(ch, timeout_ms : Int32 = 1500)
  select
  when value = ch.receive
    value
  when timeout(timeout_ms.milliseconds)
    raise "Timeout waiting for channel"
  end
end

private def receive_optional(ch, duration)
  select
  when value = ch.receive
    value
  when timeout(duration)
    nil
  end
end
