require "../spec_helper"
require "../../src/movie"
require "../../src/agency/mcp/tool_set"
require "../../src/agency/mcp/adapter"

module Agency
  class MCPTestAdapter < Movie::AbstractBehavior(ToolSetMessage)
    def initialize(@promise : Movie::Promise(String))
    end

    def receive(message, ctx)
      case message
      when ToolCall
        @promise.try_success(message.name)
        if reply_to = ctx.sender.as?(Movie::ActorRef(ToolResult))
          reply_to << ToolResult.new(message.id, message.name, "ok")
        end
      end
      Movie::Behaviors(ToolSetMessage).same
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

describe Agency::McpToolSet do
  it "forwards calls to MCP adapter and returns results" do
    system = Agency.spec_system
    call_promise = Movie::Promise(String).new
    adapter = system.spawn(Agency::MCPTestAdapter.new(call_promise))
    tool_set = system.spawn(Agency::McpToolSet.new(adapter))

    result_promise = Movie::Promise(String).new
    receiver = system.spawn(Agency::ToolResultReceiver.new(result_promise))

    call = Agency::ToolCall.new("mcp-tool", JSON::Any.new({} of String => JSON::Any))
    tool_set.tell_from(receiver, call)

    call_name = call_promise.future.await(1.second)
    call_name.should eq("mcp-tool")

    result = result_promise.future.await(1.second)
    result.should eq("ok")
  end
end
