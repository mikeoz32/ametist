require "./spec_helper"
require "../src/movie"

alias AckMsg = Symbol

def run_actor_system(behavior)
  Movie::ActorSystem(AckMsg).new(behavior)
end

class AckTarget < Movie::AbstractBehavior(AckMsg)
  def receive(message : AckMsg, context : Movie::ActorContext(AckMsg))
    case message
    when :ping
      Movie::Ask.success(context.sender, true)
    when :fail
      Movie::Ask.failure(context.sender, Exception.new("boom"), Bool)
    when :silent
      # no response
    when :die
      context.stop
    end
    Movie::Behaviors(AckMsg).same
  end

  def on_signal(signal : Movie::SystemMessage)
  end
end

describe Movie::Ask do
  it "resolves future on success" do
    result_ch = Channel(Bool).new(1)

    driver = Movie::Behaviors(AckMsg).setup do |context|
      target = context.spawn(AckTarget.new)
      future = context.ask(target, :ping, Bool)
      spawn do
        result_ch.send(future.await(200.milliseconds))
      end
      Movie::Behaviors(AckMsg).stopped
    end

    run_actor_system(driver)
    result_ch.receive.should be_true
  end

  it "propagates failure" do
    err_ch = Channel(Exception).new(1)

    driver = Movie::Behaviors(AckMsg).setup do |context|
      target = context.spawn(AckTarget.new)
      future = context.ask(target, :fail, Bool)
      spawn do
        begin
          future.await(200.milliseconds)
        rescue ex
          err_ch.send(ex)
        end
      end
      Movie::Behaviors(AckMsg).stopped
    end

    run_actor_system(driver)
    err = err_ch.receive
    err.message.should eq "boom"
  end

  it "fails when target terminates before replying" do
    err_ch = Channel(Exception).new(1)

    driver = Movie::Behaviors(AckMsg).setup do |context|
      target = context.spawn(AckTarget.new)
      future = context.ask(target, :die, Bool)
      spawn do
        begin
          future.await(500.milliseconds)
        rescue ex
          err_ch.send(ex)
        end
      end
      Movie::Behaviors(AckMsg).stopped
    end

    run_actor_system(driver)
    err = err_ch.receive
    err.should be_a(Movie::Ask::TargetTerminated)
  end
end
