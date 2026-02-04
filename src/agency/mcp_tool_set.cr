require "../movie"
require "./tool_set"
require "./mcp_adapter"

module Agency
  # ToolSet implementation that forwards tool calls to an MCP adapter actor.
  class McpToolSet < ToolSet
    def initialize(@adapter : Movie::ActorRef(MCPMessage))
    end

    protected def handle(call : ToolCall, reply_to : Movie::ActorRef(ToolResult)?, sender : Movie::ActorRefBase?)
      @adapter << MCPToolRequest.new(call, reply_to, sender)
    end
  end
end
