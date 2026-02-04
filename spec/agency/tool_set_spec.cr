require "../spec_helper"
require "../../src/movie"
require "../../src/agency/tool_set"
require "../../src/agency/protocol"

module Agency
  class ErrorToolSet < ToolSet
    protected def handle(call : ToolCall, reply_to : Movie::ActorRef(ToolResult)?, sender : Movie::ActorRefBase?)
      raise "boom"
    end
  end

  class ToolEcho < Movie::AbstractBehavior(ToolCall)
    def receive(message, ctx)
      if reply_to = ctx.sender.as?(Movie::ActorRef(ToolResult))
        reply_to << ToolResult.new(message.id, message.name, "echo: #{message.arguments.to_json}")
      end
      Movie::Behaviors(ToolCall).same
    end
  end

  class ToolResultReceiver < Movie::AbstractBehavior(ToolResult)
    def initialize(@promise : Movie::Promise(String))
    end

    def receive(message, ctx)
      @promise.try_success(message.content)
      Movie::Behaviors(ToolResult).same
    end
  end
end

describe Agency::DefaultToolSet do
  it "routes tool calls to actor-backed tools" do
    system = Agency.spec_system
    executor = Movie::Execution.get(system)
    tool_set = system.spawn(Agency::DefaultToolSet.new(executor))

    spec = Agency::ToolSpec.new(
      "echo",
      "echo tool",
      JSON.parse(%({"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}))
    )
    tool = system.spawn(Agency::ToolEcho.new)
    tool_set << Agency::ToolSetRegisterActor.new(spec, tool)

    promise = Movie::Promise(String).new
    receiver = system.spawn(Agency::ToolResultReceiver.new(promise))

    call = Agency::ToolCall.new("echo", JSON.parse(%({"text":"hi"})))
    tool_set.tell_from(receiver, call)

    result = promise.future.await(1.second)
    result.includes?("\"text\":\"hi\"").should be_true
  end
end

describe Agency::DefaultToolSet do
  it "executes stateless tools via executor" do
    system = Agency.spec_system
    executor = Movie::Execution.get(system)
    tool_set = system.spawn(Agency::DefaultToolSet.new(executor))

    promise = Movie::Promise(String).new
    receiver = system.spawn(Agency::ToolResultReceiver.new(promise))

    spec = Agency::ToolSpec.new(
      "upper",
      "upper tool",
      JSON.parse(%({"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}))
    )
    tool_set << Agency::ToolSetRegisterExec.new(spec, Agency::ExecTool.new { |call| call.arguments["text"].as_s.upcase })

    call = Agency::ToolCall.new("upper", JSON.parse(%({"text":"hi"})))
    tool_set.tell_from(receiver, call)

    result = promise.future.await(1.second)
    result.should eq("HI")
  end
end

describe Agency::ToolSet do
  it "returns a ToolResult error when handle raises" do
    system = Agency.spec_system
    tool_set = system.spawn(Agency::ErrorToolSet.new)

    promise = Movie::Promise(String).new
    receiver = system.spawn(Agency::ToolResultReceiver.new(promise))

    call = Agency::ToolCall.new("boom", JSON::Any.new({} of String => JSON::Any))
    tool_set.tell_from(receiver, call)

    result = promise.future.await(1.second)
    result.includes?("ToolSet").should be_true
  end
end
