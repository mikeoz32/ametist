require "../src/movie"
require "./spec_helper"

class Main < Movie::AbstractBehavior(MainMessage)
  @@count : Int32 = 0
  def self.create()
    new()
  end

  def self.count
    @@count
  end

  def self.reset
    @@count = 0
  end

  def receive(message, context)
    puts message.message + " " + @@count.to_s
    @@count += 1
  end
end

class Child < Movie::AbstractBehavior(String)
  @parent : Movie::ActorRef(MainMessage)

  @@count : Int32 = 0

  def self.count
    @@count
  end

  def self.reset
    @@count = 0
  end

  def self.create(parent)
    new(parent)
  end

  protected def initialize(parent)
    @parent = parent
  end

  def receive(message, context)
    @@count += 1
    @parent << MainMessage.new(message: message)
  end
end

class StopProbe < Movie::AbstractBehavior(Symbol)
  @@events = [] of String
  @@mutex = Mutex.new

  def self.reset
    @@mutex.synchronize { @@events.clear }
  end

  def self.events
    @@mutex.synchronize { @@events.dup }
  end

  def initialize(@name : String)
  end

  def receive(message, context)
    Movie::Behaviors(Symbol).same
  end

  def on_signal(signal)
    STDERR.puts "StopProbe #{@name} signal=#{signal.class}" if ENV["DEBUG_STOP"]?
    case signal
    when Movie::PreStop
      @@mutex.synchronize { @@events << "#{@name}:pre_stop" }
    when Movie::PostStop
      @@mutex.synchronize { @@events << "#{@name}:post_stop" }
    when Movie::Terminated
      @@mutex.synchronize { @@events << "#{@name}:terminated" }
    end
  end
end

class RestartProbe < Movie::AbstractBehavior(Int32)
  @@signals = [] of String
  @@mutex = Mutex.new

  def self.reset
    @@mutex.synchronize { @@signals.clear }
  end

  def self.signals
    @@mutex.synchronize { @@signals.dup }
  end

  def initialize(@name : String)
  end

  def receive(message, context)
    raise "fail" if message == 1
    @@mutex.synchronize { @@signals << "#{@name}:msg:#{message}" }
    Movie::Behaviors(Int32).same
  end

  def on_signal(signal)
    @@mutex.synchronize { @@signals << "#{@name}:signal:#{signal.class}" }
  end
end



def wait_until(timeout_ms : Int32 = 1000, interval_ms : Int32 = 5)
  deadline = Time.monotonic + timeout_ms.milliseconds
  until yield
    raise "Timeout waiting for condition" if Time.monotonic >= deadline
    sleep(interval_ms.milliseconds)
  end
end

describe Movie do
  before_each do
    Main.reset
    Child.reset
    StopProbe.reset
    RestartProbe.reset
  end

  it "should be able to spawn actors" do
    system = Movie::ActorSystem(MainMessage).new(Main.create(), Movie::RestartStrategy::STOP)

    system << MainMessage.new(message: "hello")
    wait_until { Main.count == 1 }
    Main.count.should eq(1)

    main = system.spawn(Main.create())

    child = system.spawn(Child.create(main))
    child << "message "
    wait_until { Child.count == 1 && Main.count == 2 }
    Child.count.should eq(1)
    Main.count.should eq(2)
  end

  it "invokes Behaviors.receive handler and returns behavior" do
    handler_called = false
    returned_behavior : Movie::AbstractBehavior(String)? = nil

    receive_behavior = Movie::Behaviors(String).receive do |message, context|
      handler_called = true
      behavior = Movie::Behaviors(String).stopped
      returned_behavior = behavior
      behavior
    end

    system = Movie::ActorSystem(String).new(Movie::Behaviors(String).same)
    actor = system.spawn(receive_behavior)

    actor << "ping"
    wait_until { handler_called }

    handler_called.should be_true
    returned_behavior.should_not be_nil
    returned_behavior.not_nil!.should be_a(Movie::AbstractBehavior(String))
  end

  it "exposes context log" do
    logger : Log? = nil

    behavior = Movie::Behaviors(String).receive do |message, context|
      logger = context.log
      Movie::Behaviors(String).same
    end

    system = Movie::ActorSystem(String).new(Movie::Behaviors(String).same)
    actor = system.spawn(behavior)

    actor << "ping"
    wait_until { !logger.nil? }

    logger.should_not be_nil
    logger.not_nil!.responds_to?(:debug).should be_true
  end

  it "Should handle exception" do
    system = Movie::ActorSystem(MainMessage).new(Main.create(), Movie::RestartStrategy::STOP)
    ref = system.spawn (Movie::Behaviors(String).setup do |context|
      Movie::Behaviors(String).receive do |message, context|
        raise "Should be handled"
        Movie::Behaviors(String).same
      end
    end)
    ref << "message "

    wait_until(timeout_ms: 500) do
      if ctx = system.context(ref.id).as?(Movie::ActorContext(String))
        ctx.state != Movie::ActorContext::State::RUNNING
      else
        true
      end
    end
  end

  it "applies restart strategy RESTART" do
    system = Movie::ActorSystem(Int32).new(Movie::Behaviors(Int32).same, Movie::RestartStrategy::RESTART)

    actor = system.spawn(RestartProbe.new("r"), Movie::RestartStrategy::RESTART)

    actor << 1

    wait_until(timeout_ms: 500) do
      RestartProbe.signals.any? { |s| s.ends_with?("PreRestart") }
    end

    actor << 2

    wait_until(timeout_ms: 500) do
      RestartProbe.signals.includes?("r:msg:2")
    end
  end

  it "applies restart strategy STOP" do
    system = Movie::ActorSystem(Int32).new(Movie::Behaviors(Int32).same, Movie::RestartStrategy::STOP)

    behavior = Movie::Behaviors(Int32).receive do |message, context|
      raise "boom"
    end

    actor = system.spawn(behavior, Movie::RestartStrategy::STOP)

    actor << 1

    wait_until(timeout_ms: 500) do
      if ctx = system.context(actor.id).as?(Movie::ActorContext(Int32))
        ctx.state.stopped?
      else
        false
      end
    end
  end

  it "waits for children to terminate before finishing parent stop" do
    system = Movie::ActorSystem(Symbol).new(Movie::Behaviors(Symbol).same)

    parent_behavior = Movie::Behaviors(Symbol).setup do |context|
      context.spawn(StopProbe.new("child-1"))
      context.spawn(StopProbe.new("child-2"))
      StopProbe.new("parent")
    end

    parent = system.spawn(parent_behavior)

    STDERR.puts "Parent actor id: #{parent.id}" if ENV["DEBUG_STOP"]?

    parent.send_system(Movie::STOP)

    wait_until(timeout_ms: 1000) do
      ev = StopProbe.events
      ev.includes?("parent:post_stop") && ev.includes?("child-1:post_stop") && ev.includes?("child-2:post_stop")
    end

    events = StopProbe.events
    parent_idx = events.index("parent:post_stop").not_nil!
    child1_idx = events.index("child-1:post_stop").not_nil!
    child2_idx = events.index("child-2:post_stop").not_nil!

    parent_idx.should be > child1_idx
    parent_idx.should be > child2_idx

    ctx = system.context(parent.id).as?(Movie::ActorContext(Symbol))
    ctx.not_nil!.state.stopped?.should be_true
  end

  it "stops immediately when there are no children" do
    system = Movie::ActorSystem(Symbol).new(Movie::Behaviors(Symbol).same)
    actor = system.spawn(StopProbe.new("solo"))

    actor.send_system(Movie::STOP)

    wait_until(timeout_ms: 200) { StopProbe.events.includes?("solo:post_stop") }

    events = StopProbe.events
    events.includes?("solo:post_stop").should be_true

    ctx = system.context(actor.id).as?(Movie::ActorContext(Symbol))
    ctx.not_nil!.state.stopped?.should be_true
  end

  it "drops user messages while stopping" do
    count = 0
    mutex = Mutex.new

    behavior = Movie::Behaviors(Int32).receive do |message, context|
      mutex.synchronize { count += 1 }
      Movie::Behaviors(Int32).same
    end

    system = Movie::ActorSystem(Int32).new(Movie::Behaviors(Int32).same)
    actor = system.spawn(behavior)

    actor << 1
    wait_until { mutex.synchronize { count == 1 } }

    actor.send_system(Movie::STOP)

    actor << 2
    actor << 3

    wait_until(timeout_ms: 200) do
      if ctx = system.context(actor.id).as?(Movie::ActorContext(Int32))
        ctx.state.stopped?
      else
        false
      end
    end

    mutex.synchronize { count.should eq(1) }
  end

  it "notifies watchers when actor stops" do
    system = Movie::ActorSystem(Symbol).new(Movie::Behaviors(Symbol).same)

    parent_behavior = Movie::Behaviors(Symbol).setup do |context|
      context.spawn(StopProbe.new("child"))
      StopProbe.new("parent")
    end

    parent = system.spawn(parent_behavior)
    watcher = system.spawn(StopProbe.new("watcher"))

    parent.send_system(Movie::Watch.new(watcher).as(Movie::SystemMessage))

    parent.send_system(Movie::STOP)

    sleep(1.seconds)

    events = StopProbe.events
    events.includes?("watcher:terminated").should be_true
  end


end
