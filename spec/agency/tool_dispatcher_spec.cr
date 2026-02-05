require "../spec_helper"
require "../../src/movie"
require "../../src/agency/tools/dispatcher"

module Agency
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

describe Agency::ToolDispatcher do
  it "routes calls to registered tools" do
    system = Agency.spec_system
    dispatcher = system.spawn(Agency::ToolDispatcher.behavior)

    spec = Agency::ToolSpec.new(
      "echo",
      "echo back args",
      JSON.parse(%({"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}))
    )
    tool = system.spawn(Agency::ToolEcho.new)
    dispatcher << Agency::RegisterTool.new(spec, tool)

    promise = Movie::Promise(String).new
    receiver = system.spawn(Agency::ToolResultReceiver.new(promise))

    call = Agency::ToolCall.new("echo", JSON.parse(%({"text":"hi"})))
    dispatcher << Agency::ToolRoute.new(call, receiver)

    result = promise.future.await(1.second)
    result.includes?("\"text\":\"hi\"").should be_true
  end

  it "returns error when tool is missing" do
    system = Agency.spec_system
    dispatcher = system.spawn(Agency::ToolDispatcher.behavior)

    promise = Movie::Promise(String).new
    receiver = system.spawn(Agency::ToolResultReceiver.new(promise))

    call = Agency::ToolCall.new("missing", JSON::Any.new({} of String => JSON::Any))
    dispatcher << Agency::ToolRoute.new(call, receiver)

    result = promise.future.await(1.second)
    result.includes?("Tool not found").should be_true
  end
end
