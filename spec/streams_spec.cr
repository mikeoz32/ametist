require "./spec_helper"
require "../src/movie"

alias Msg = Movie::Streams::MessageBase
alias Elem = Movie::Streams::Element

describe Movie::Streams do
  it "honors demand: emits only requested elements" do
    out_ch = Channel(Nil | Int32 | Float64 | String | Bool | Symbol).new
    signals = Channel(Symbol).new(1)

    main = Movie::Behaviors(Msg).setup do |context|
      source = context.spawn(Movie::Streams::ManualSource.new)
      flow = context.spawn(Movie::Streams::PassThroughFlow.new)
      sink = context.spawn(Movie::Streams::CollectSink.new(out_ch, signals))

      # Wire downstream->upstream subscriptions
      flow << Movie::Streams::Subscribe.new(sink)
      source << Movie::Streams::Subscribe.new(flow)

      # Drive demand
      sink << Movie::Streams::Request.new(2u64)

      # Produce three elements; only two should flow.
      source << Movie::Streams::Produce.new(1)
      source << Movie::Streams::Produce.new(2)
      source << Movie::Streams::Produce.new(3)

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
    out_ch = Channel(Nil | Int32 | Float64 | String | Bool | Symbol).new
    signals = Channel(Symbol).new(1)

    main = Movie::Behaviors(Msg).setup do |context|
      source = context.spawn(Movie::Streams::ManualSource.new)
      flow = context.spawn(Movie::Streams::PassThroughFlow.new)
      sink = context.spawn(Movie::Streams::CollectSink.new(out_ch, signals))

      flow << Movie::Streams::Subscribe.new(sink)
      source << Movie::Streams::Subscribe.new(flow)

      sink << Movie::Streams::Request.new(1u64)
      source << Movie::Streams::Produce.new(10)

      sink << Movie::Streams::Cancel.new
      source << Movie::Streams::Produce.new(20)

      Movie::Behaviors(Msg).same
    end

    Movie::ActorSystem(Msg).new(main)

    first = receive_or_timeout(out_ch)
    first.should eq 10
    receive_optional(out_ch, 50.milliseconds).should be_nil
    receive_optional(signals, 50.milliseconds).should eq :cancel
  end

  it "propagates completion" do
    out_ch = Channel(Nil | Int32 | Float64 | String | Bool | Symbol).new
    signals = Channel(Symbol).new(1)

    main = Movie::Behaviors(Msg).setup do |context|
      source = context.spawn(Movie::Streams::ManualSource.new)
      flow = context.spawn(Movie::Streams::PassThroughFlow.new)
      sink = context.spawn(Movie::Streams::CollectSink.new(out_ch, signals))

      flow << Movie::Streams::Subscribe.new(sink)
      source << Movie::Streams::Subscribe.new(flow)

      sink << Movie::Streams::Request.new(1u64)
      source << Movie::Streams::Produce.new(42)
      source << Movie::Streams::OnComplete.new

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
      source = context.spawn(Movie::Streams::ManualSource.new)
      flow = context.spawn(Movie::Streams::PassThroughFlow.new)
      sink = context.spawn(Movie::Streams::CollectSink.new(out_ch, signals))

      flow << Movie::Streams::Subscribe.new(sink)
      source << Movie::Streams::Subscribe.new(flow)

      sink << Movie::Streams::Request.new(2u64)

      spawn do
        sleep 2.milliseconds
        source << Movie::Streams::Produce.new(1)
        source << Movie::Streams::OnError.new(Exception.new("boom"))
        source << Movie::Streams::Produce.new(2)
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
      source = context.spawn(Movie::Streams::ManualSource.new)
      map = context.spawn(Movie::Streams::MapFlow.new { |v| v.is_a?(Int32) ? v * 2 : v })
      sink = context.spawn(Movie::Streams::CollectSink.new(out_ch))

      map << Movie::Streams::Subscribe.new(sink)
      source << Movie::Streams::Subscribe.new(map)

      sink << Movie::Streams::Request.new(2u64)
      source << Movie::Streams::Produce.new(1)
      source << Movie::Streams::Produce.new(2)

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
      source = context.spawn(Movie::Streams::ManualSource.new)
      filter = context.spawn(Movie::Streams::FilterFlow.new { |v| v.is_a?(Int32) && v.even? })
      sink = context.spawn(Movie::Streams::CollectSink.new(out_ch))

      filter << Movie::Streams::Subscribe.new(sink)
      source << Movie::Streams::Subscribe.new(filter)

      sink << Movie::Streams::Request.new(2u64)
      source << Movie::Streams::Produce.new(1)
      source << Movie::Streams::Produce.new(2)
      source << Movie::Streams::Produce.new(3)
      source << Movie::Streams::Produce.new(4)

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
      source = context.spawn(Movie::Streams::ManualSource.new)
      take = context.spawn(Movie::Streams::TakeFlow.new(2u64))
      sink = context.spawn(Movie::Streams::CollectSink.new(out_ch, signals))

      take << Movie::Streams::Subscribe.new(sink)
      source << Movie::Streams::Subscribe.new(take)

      sink << Movie::Streams::Request.new(5u64)
      source << Movie::Streams::Produce.new(1)
      source << Movie::Streams::Produce.new(2)
      source << Movie::Streams::Produce.new(3)
      source << Movie::Streams::OnComplete.new

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
      source = context.spawn(Movie::Streams::ManualSource.new)
      drop = context.spawn(Movie::Streams::DropFlow.new(2u64))
      sink = context.spawn(Movie::Streams::CollectSink.new(out_ch))

      drop << Movie::Streams::Subscribe.new(sink)
      source << Movie::Streams::Subscribe.new(drop)

      sink << Movie::Streams::Request.new(2u64)
      source << Movie::Streams::Produce.new(1)
      source << Movie::Streams::Produce.new(2)
      source << Movie::Streams::Produce.new(3)
      source << Movie::Streams::Produce.new(4)

      Movie::Behaviors(Msg).same
    end

    Movie::ActorSystem(Msg).new(main)

    receive_or_timeout(out_ch).should eq 3
    receive_or_timeout(out_ch).should eq 4
    receive_optional(out_ch, 20.milliseconds).should be_nil
  end

  it "materializes via builder and completes future" do
    out_ch = Channel(Elem).new

    mat = Movie::Streams.build_pipeline(
      Movie::Streams::ManualSource.new,
      [Movie::Streams::MapFlow.new { |v| v.is_a?(Int32) ? v + 1 : v }],
      Movie::Streams::CollectSink.new(out_ch),
      initial_demand: 2u64
    )

    mat.source << Movie::Streams::Produce.new(5)
    mat.source << Movie::Streams::Produce.new(6)
    mat.source << Movie::Streams::OnComplete.new

    receive_or_timeout(out_ch).should eq 6
    receive_or_timeout(out_ch).should eq 7
    mat.completion.await(200.milliseconds).should be_nil
  end

  it "taps side effects without altering stream" do
    out_ch = Channel(Elem).new
    tap_ch = Channel(Elem).new

    main = Movie::Behaviors(Msg).setup do |context|
      source = context.spawn(Movie::Streams::ManualSource.new)
      tap = context.spawn(Movie::Streams::TapFlow.new { |v| tap_ch.send(v) })
      sink = context.spawn(Movie::Streams::CollectSink.new(out_ch))

      tap << Movie::Streams::Subscribe.new(sink)
      source << Movie::Streams::Subscribe.new(tap)

      sink << Movie::Streams::Request.new(2u64)
      source << Movie::Streams::Produce.new(10)
      source << Movie::Streams::Produce.new(20)

      Movie::Behaviors(Msg).same
    end

    Movie::ActorSystem(Msg).new(main)

    receive_or_timeout(out_ch).should eq 10
    receive_or_timeout(out_ch).should eq 20
    receive_or_timeout(tap_ch).should eq 10
    receive_or_timeout(tap_ch).should eq 20
  end

  it "folds via builder and returns accumulator" do
    mat = Movie::Streams.build_fold_pipeline(Movie::Streams::ManualSource.new, [Movie::Streams::MapFlow.new { |v| v.is_a?(Int32) ? v + 1 : 0 }], 0, ->(acc : Int32, elem : Movie::Streams::Element) { acc + (elem.as(Int32)) }, initial_demand: 3u64)

    mat.source << Movie::Streams::Produce.new(1)
    mat.source << Movie::Streams::Produce.new(2)
    mat.source << Movie::Streams::Produce.new(3)
    mat.source << Movie::Streams::OnComplete.new

    mat.completion.await(200.milliseconds).should eq 9
  end

  it "collects to channel via helper" do
    pipeline = Movie::Streams.build_collecting_pipeline(Movie::Streams::ManualSource.new, [Movie::Streams::DropFlow.new(1u64)], initial_demand: 2u64, channel_capacity: 2)
    out_ch = pipeline.out_channel.not_nil!

    pipeline.source << Movie::Streams::Produce.new(5)
    pipeline.source << Movie::Streams::Produce.new(6)
    pipeline.source << Movie::Streams::Produce.new(7)
    pipeline.source << Movie::Streams::OnComplete.new

    receive_or_timeout(out_ch).should eq 6
    receive_or_timeout(out_ch).should eq 7
    receive_optional(out_ch, 20.milliseconds).should be_nil
    pipeline.completion.await(200.milliseconds).should be_nil
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
