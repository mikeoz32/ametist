require "./spec_helper"
require "../src/movie"

alias Stream = Movie::Streams::Typed
alias Elem = Nil | Int32 | Int64 | Float64 | String | Bool | Symbol | JSON::Any
alias Msg = Stream::MessageBase(Elem)

describe Stream do
  it "honors demand: emits only requested elements" do
    out_ch = Channel(Elem).new
    signals = Channel(Symbol).new(1)

    main = Movie::Behaviors(Msg).setup do |context|
      source = context.spawn(Stream::ManualSource(Elem).new)
      flow = context.spawn(Stream::PassThroughFlow(Elem).new)
      sink = context.spawn(Stream::CollectSink(Elem).new(out_ch, signals))

      # Wire downstream->upstream subscriptions
      flow << Stream::Subscribe(Elem).new(sink)
      source << Stream::Subscribe(Elem).new(flow)

      # Drive demand
      sink << Stream::Request(Elem).new(2u64)

      # Produce three elements; only two should flow.
      source << Stream::Produce(Elem).new(1)
      source << Stream::Produce(Elem).new(2)
      source << Stream::Produce(Elem).new(3)

      Movie::Behaviors(Msg).same
    end

    Movie::ActorSystem(Msg).new(main)

    v1 = receive_or_timeout(out_ch)
    v2 = receive_or_timeout(out_ch)
    receive_optional(out_ch, 50.milliseconds).should be_nil

    v1.should eq 1
    v2.should eq 2
  end

  it "propagates cancel downstream to upstream" do
    out_ch = Channel(Elem).new
    signals = Channel(Symbol).new(1)
    refs_ch = Channel(Tuple(Movie::ActorRef(Msg), Movie::ActorRef(Msg))).new(1)

    main = Movie::Behaviors(Msg).setup do |context|
      source = context.spawn(Stream::ManualSource(Elem).new)
      flow = context.spawn(Stream::PassThroughFlow(Elem).new)
      sink = context.spawn(Stream::CollectSink(Elem).new(out_ch, signals))

      flow << Stream::Subscribe(Elem).new(sink)
      source << Stream::Subscribe(Elem).new(flow)
      refs_ch.send({source, sink})

      Movie::Behaviors(Msg).same
    end

    Movie::ActorSystem(Msg).new(main)
    source, sink = receive_or_timeout(refs_ch)

    sink << Stream::Request(Elem).new(1u64)
    sleep 5.milliseconds
    source << Stream::Produce(Elem).new(10)

    first = receive_or_timeout(out_ch)
    first.should eq 10

    sink << Stream::Cancel(Elem).new
    source << Stream::Produce(Elem).new(20)

    receive_optional(out_ch, 50.milliseconds).should be_nil
    receive_optional(signals, 50.milliseconds).should eq :cancel
  end

  it "propagates completion" do
    out_ch = Channel(Elem).new
    signals = Channel(Symbol).new(1)

    main = Movie::Behaviors(Msg).setup do |context|
      source = context.spawn(Stream::ManualSource(Elem).new)
      flow = context.spawn(Stream::PassThroughFlow(Elem).new)
      sink = context.spawn(Stream::CollectSink(Elem).new(out_ch, signals))

      flow << Stream::Subscribe(Elem).new(sink)
      source << Stream::Subscribe(Elem).new(flow)

      sink << Stream::Request(Elem).new(1u64)
      source << Stream::Produce(Elem).new(42)
      source << Stream::OnComplete(Elem).new

      Movie::Behaviors(Msg).same
    end

    Movie::ActorSystem(Msg).new(main)

    receive_or_timeout(out_ch).should eq 42
    receive_optional(signals, 50.milliseconds).should eq :complete
  end

  it "propagates error and stops" do
    out_ch = Channel(Elem).new
    signals = Channel(Symbol).new(1)

    main = Movie::Behaviors(Msg).setup do |context|
      source = context.spawn(Stream::ManualSource(Elem).new)
      flow = context.spawn(Stream::PassThroughFlow(Elem).new)
      sink = context.spawn(Stream::CollectSink(Elem).new(out_ch, signals))

      flow << Stream::Subscribe(Elem).new(sink)
      source << Stream::Subscribe(Elem).new(flow)

      sink << Stream::Request(Elem).new(2u64)

      spawn do
        sleep 2.milliseconds
        source << Stream::Produce(Elem).new(1)
        source << Stream::OnError(Elem).new(Exception.new("boom"))
        source << Stream::Produce(Elem).new(2)
      end

      Movie::Behaviors(Msg).same
    end

    Movie::ActorSystem(Msg).new(main)

    receive_or_timeout(out_ch).should eq 1
    receive_optional(out_ch, 50.milliseconds).should be_nil
    receive_optional(signals, 50.milliseconds).should eq :error
  end

  it "maps elements" do
    out_ch = Channel(Elem).new

    main = Movie::Behaviors(Msg).setup do |context|
      source = context.spawn(Stream::ManualSource(Elem).new)
      map = context.spawn(Stream::MapFlow(Elem).new { |v| v.is_a?(Int32) ? v * 2 : v })
      sink = context.spawn(Stream::CollectSink(Elem).new(out_ch))

      map << Stream::Subscribe(Elem).new(sink)
      source << Stream::Subscribe(Elem).new(map)

      sink << Stream::Request(Elem).new(2u64)
      source << Stream::Produce(Elem).new(1)
      source << Stream::Produce(Elem).new(2)

      Movie::Behaviors(Msg).same
    end

    Movie::ActorSystem(Msg).new(main)

    receive_or_timeout(out_ch).should eq 2
    receive_or_timeout(out_ch).should eq 4
    receive_optional(out_ch, 20.milliseconds).should be_nil
  end

  it "filters elements" do
    out_ch = Channel(Elem).new

    main = Movie::Behaviors(Msg).setup do |context|
      source = context.spawn(Stream::ManualSource(Elem).new)
      filter = context.spawn(Stream::FilterFlow(Elem).new { |v| v.is_a?(Int32) && v.even? })
      sink = context.spawn(Stream::CollectSink(Elem).new(out_ch))

      filter << Stream::Subscribe(Elem).new(sink)
      source << Stream::Subscribe(Elem).new(filter)

      sink << Stream::Request(Elem).new(2u64)
      source << Stream::Produce(Elem).new(1)
      source << Stream::Produce(Elem).new(2)
      source << Stream::Produce(Elem).new(3)
      source << Stream::Produce(Elem).new(4)

      Movie::Behaviors(Msg).same
    end

    Movie::ActorSystem(Msg).new(main)

    receive_or_timeout(out_ch).should eq 2
    receive_or_timeout(out_ch).should eq 4
    receive_optional(out_ch, 20.milliseconds).should be_nil
  end

  it "takes N then completes" do
    out_ch = Channel(Elem).new
    signals = Channel(Symbol).new(1)

    main = Movie::Behaviors(Msg).setup do |context|
      source = context.spawn(Stream::ManualSource(Elem).new)
      take = context.spawn(Stream::TakeFlow(Elem).new(2u64))
      sink = context.spawn(Stream::CollectSink(Elem).new(out_ch, signals))

      take << Stream::Subscribe(Elem).new(sink)
      source << Stream::Subscribe(Elem).new(take)

      sink << Stream::Request(Elem).new(5u64)
      source << Stream::Produce(Elem).new(1)
      source << Stream::Produce(Elem).new(2)
      source << Stream::Produce(Elem).new(3)
      source << Stream::OnComplete(Elem).new

      Movie::Behaviors(Msg).same
    end

    Movie::ActorSystem(Msg).new(main)

    receive_or_timeout(out_ch).should eq 1
    receive_or_timeout(out_ch).should eq 2
    receive_optional(out_ch, 20.milliseconds).should be_nil
    receive_optional(signals, 50.milliseconds).should eq :complete
  end

  it "drops the first N elements" do
    out_ch = Channel(Elem).new

    main = Movie::Behaviors(Msg).setup do |context|
      source = context.spawn(Stream::ManualSource(Elem).new)
      drop = context.spawn(Stream::DropFlow(Elem).new(2u64))
      sink = context.spawn(Stream::CollectSink(Elem).new(out_ch))

      drop << Stream::Subscribe(Elem).new(sink)
      source << Stream::Subscribe(Elem).new(drop)

      sink << Stream::Request(Elem).new(2u64)
      source << Stream::Produce(Elem).new(1)
      source << Stream::Produce(Elem).new(2)
      source << Stream::Produce(Elem).new(3)
      source << Stream::Produce(Elem).new(4)

      Movie::Behaviors(Msg).same
    end

    Movie::ActorSystem(Msg).new(main)

    receive_or_timeout(out_ch).should eq 3
    receive_or_timeout(out_ch).should eq 4
    receive_optional(out_ch, 20.milliseconds).should be_nil
  end

  it "materializes via builder and completes future" do
    out_ch = Channel(Elem).new

    mat = Stream.build_pipeline(
      Elem,
      Stream::ManualSource(Elem).new,
      [Stream::MapFlow(Elem).new { |v| v.is_a?(Int32) ? v + 1 : v }],
      Stream::CollectSink(Elem).new(out_ch),
      initial_demand: 2u64
    )

    mat.source << Stream::Produce(Elem).new(5)
    mat.source << Stream::Produce(Elem).new(6)
    mat.source << Stream::OnComplete(Elem).new

    receive_or_timeout(out_ch).should eq 6
    receive_or_timeout(out_ch).should eq 7
    mat.completion.await(200.milliseconds).should be_nil
  end

  it "taps side effects without altering stream" do
    out_ch = Channel(Elem).new
    tap_ch = Channel(Elem).new

    main = Movie::Behaviors(Msg).setup do |context|
      source = context.spawn(Stream::ManualSource(Elem).new)
      tap = context.spawn(Stream::TapFlow(Elem).new { |v| tap_ch.send(v) })
      sink = context.spawn(Stream::CollectSink(Elem).new(out_ch))

      tap << Stream::Subscribe(Elem).new(sink)
      source << Stream::Subscribe(Elem).new(tap)

      sink << Stream::Request(Elem).new(2u64)
      source << Stream::Produce(Elem).new(10)
      source << Stream::Produce(Elem).new(20)

      Movie::Behaviors(Msg).same
    end

    Movie::ActorSystem(Msg).new(main)

    receive_or_timeout(out_ch).should eq 10
    receive_or_timeout(out_ch).should eq 20
    receive_or_timeout(tap_ch).should eq 10
    receive_or_timeout(tap_ch).should eq 20
  end

  it "folds via builder and returns accumulator" do
    mat = Stream.build_fold_pipeline(
      Elem,
      Int32,
      Stream::ManualSource(Elem).new,
      [Stream::MapFlow(Elem).new { |v| v.is_a?(Int32) ? v + 1 : 0 }],
      0,
      ->(acc : Int32, elem : Elem) { acc + elem.as(Int32) },
      initial_demand: 3u64
    )

    mat.source << Stream::Produce(Elem).new(1)
    mat.source << Stream::Produce(Elem).new(2)
    mat.source << Stream::Produce(Elem).new(3)
    mat.source << Stream::OnComplete(Elem).new

    mat.completion.await(200.milliseconds).should eq 9
  end

  it "collects to channel via helper" do
    pipeline = Stream.build_collecting_pipeline(
      Elem,
      Stream::ManualSource(Elem).new,
      [Stream::DropFlow(Elem).new(1u64)],
      initial_demand: 2u64,
      channel_capacity: 2
    )
    out_ch = pipeline.out_channel.not_nil!

    pipeline.source << Stream::Produce(Elem).new(5)
    pipeline.source << Stream::Produce(Elem).new(6)
    pipeline.source << Stream::Produce(Elem).new(7)
    pipeline.source << Stream::OnComplete(Elem).new

    receive_or_timeout(out_ch).should eq 6
    receive_or_timeout(out_ch).should eq 7
    receive_optional(out_ch, 20.milliseconds).should be_nil
    pipeline.completion.await(200.milliseconds).should be_nil
  end

  it "broadcasts elements to multiple subscribers with independent demand" do
    out_ch1 = Channel(Elem).new
    out_ch2 = Channel(Elem).new
    refs_ch = Channel(Tuple(Movie::ActorRef(Msg), Movie::ActorRef(Msg), Movie::ActorRef(Msg))).new(1)

    main = Movie::Behaviors(Msg).setup do |context|
      source = context.spawn(Stream::ManualSource(Elem).new)
      hub = context.spawn(Stream::BroadcastHub(Elem).new)
      sink1 = context.spawn(Stream::CollectSink(Elem).new(out_ch1))
      sink2 = context.spawn(Stream::CollectSink(Elem).new(out_ch2))

      hub << Stream::Subscribe(Elem).new(sink1)
      hub << Stream::Subscribe(Elem).new(sink2)
      source << Stream::Subscribe(Elem).new(hub)
      refs_ch.send({source, sink1, sink2})

      Movie::Behaviors(Msg).same
    end

    Movie::ActorSystem(Msg).new(main)
    source, sink1, sink2 = receive_or_timeout(refs_ch)

    sink1 << Stream::Request(Elem).new(2u64)
    sink2 << Stream::Request(Elem).new(1u64)
    sleep 5.milliseconds
    source << Stream::Produce(Elem).new(10)
    source << Stream::Produce(Elem).new(20)

    receive_or_timeout(out_ch1).should eq 10
    receive_or_timeout(out_ch1).should eq 20
    receive_or_timeout(out_ch2).should eq 10
    receive_optional(out_ch2, 20.milliseconds).should be_nil
  end

  it "cancels one broadcast subscriber without affecting others" do
    out_ch1 = Channel(Elem).new
    out_ch2 = Channel(Elem).new
    signals1 = Channel(Symbol).new(1)
    refs_ch = Channel(Tuple(Movie::ActorRef(Msg), Movie::ActorRef(Msg), Movie::ActorRef(Msg))).new(1)

    main = Movie::Behaviors(Msg).setup do |context|
      source = context.spawn(Stream::ManualSource(Elem).new)
      hub = context.spawn(Stream::BroadcastHub(Elem).new)
      sink1 = context.spawn(Stream::CollectSink(Elem).new(out_ch1, signals1))
      sink2 = context.spawn(Stream::CollectSink(Elem).new(out_ch2))

      hub << Stream::Subscribe(Elem).new(sink1)
      hub << Stream::Subscribe(Elem).new(sink2)
      source << Stream::Subscribe(Elem).new(hub)
      refs_ch.send({source, sink1, sink2})

      Movie::Behaviors(Msg).same
    end

    Movie::ActorSystem(Msg).new(main)
    source, sink1, sink2 = receive_or_timeout(refs_ch)

    sink1 << Stream::Request(Elem).new(1u64)
    sink2 << Stream::Request(Elem).new(2u64)
    sleep 5.milliseconds
    source << Stream::Produce(Elem).new(1)

    receive_or_timeout(out_ch1).should eq 1
    receive_or_timeout(out_ch2).should eq 1

    sink1 << Stream::Cancel(Elem).new
    source << Stream::Produce(Elem).new(2)

    receive_optional(out_ch1, 20.milliseconds).should be_nil
    receive_optional(signals1, 100.milliseconds).should eq :cancel

    receive_or_timeout(out_ch2).should eq 2
  end

  it "supports JSON payload elements" do
    out_ch = Channel(Elem).new
    payload = JSON.parse(%({"type":"event","content":"hello"}))
    flows = [] of Movie::AbstractBehavior(Msg)

    mat = Stream.build_pipeline(
      Elem,
      Stream::ManualSource(Elem).new,
      flows,
      Stream::CollectSink(Elem).new(out_ch),
      initial_demand: 1u64
    )

    mat.source << Stream::Produce(Elem).new(payload)
    mat.source << Stream::OnComplete(Elem).new

    value = receive_or_timeout(out_ch)
    value.should be_a(JSON::Any)
    value.as(JSON::Any)["type"].as_s.should eq("event")
    mat.completion.await(200.milliseconds).should be_nil
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
