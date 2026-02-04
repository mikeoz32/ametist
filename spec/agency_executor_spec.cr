require "./spec_helper"
require "../src/movie"
require "../src/agency/result_receiver"

# Simple message used by the actor‑based Future example
struct ResultMsg
  getter value : Int32
  def initialize(@value : Int32)
  end
end

# Test actor that calls the executor inside its receive method and forwards the result as a ResultMsg.
class TestActor < Movie::AbstractBehavior(Symbol | ResultMsg)
  def initialize(@exec : Movie::ExecutorExtension, @promise : Movie::Promise(Int32))
  end

  def receive(message, ctx)
    case message
    when :run
      future = @exec.execute { 123 }
      future.on_success do |v|
        ctx.ref << ResultMsg.new(v)
      end
    when ResultMsg
      @promise.try_success(message.value)
    end
    Movie::Behaviors(Symbol | ResultMsg).same
  end
end
require "../src/agency"

# Helper to build a system with the executor registered
def build_system(pool_size = 2, queue_capacity = 8)
  system = Movie::ActorSystem(String).new(Movie::Behaviors(String).same)
  system.register_extension(Movie::ExecutorExtension.new(system, pool_size, queue_capacity))
  system
end

describe Movie::ExecutorExtension do
  it "executes a simple block and returns the result via Future" do
    system = build_system
    exec = system.extension!(Movie::ExecutorExtension)
    future = exec.execute { 42 }
    future.await.should eq 42
  end

  it "executes a block and sends result back as a message" do
    system = build_system
    exec = system.extension!(Movie::ExecutorExtension)
    # Create a temporary actor that will receive the TaskResult
      promise = Movie::Promise(Int32).new
      receiver = system.spawn(Agency::ResultReceiver(Int32).new(promise))
        exec.execute_with_reply(receiver.as(Movie::ActorRef(Movie::ExecutorExtension::TaskResult(Int32)))) { 42 }
      # Wait for the promise to be completed by the receiver actor
      promise.future.await.should eq 42
  end

  # Demonstrate using the executor inside an actor's receive method and awaiting the Future.
  it "actor can call executor.execute and handle result via Future" do
    system = build_system
    exec = system.extension!(Movie::ExecutorExtension)

    promise = Movie::Promise(Int32).new
    test_actor = system.spawn(TestActor.new(exec, promise))
    test_actor << :run
    # Await the promise fulfilled by the actor when it receives the ResultMsg
    promise.future.await.should eq 123
  end

  it "fails with FutureTimeout when the block exceeds the timeout" do
    system = build_system
    exec = system.extension!(Movie::ExecutorExtension)
    future = exec.execute(0.1.seconds) do
      sleep 0.5.seconds
      1
    end
    expect_raises(Movie::FutureTimeout) { future.await }
  end
end
