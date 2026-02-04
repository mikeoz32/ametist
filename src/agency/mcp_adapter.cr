require "../movie"
require "./protocol"

module Agency
  struct MCPToolRequest
    getter call : ToolCall
    getter reply_to : Movie::ActorRef(ToolResult)?
    getter sender : Movie::ActorRefBase?

    def initialize(@call : ToolCall, @reply_to : Movie::ActorRef(ToolResult)?, @sender : Movie::ActorRefBase? = nil)
    end
  end

  alias MCPMessage = MCPToolRequest

  # Stub adapter for MCP tool calls. Replace with real MCP wiring later.
  class MCPAdapter < Movie::AbstractBehavior(MCPMessage)
    def receive(message, ctx)
      result = ToolResult.new(message.call.id, message.call.name, "(MCP) not implemented")
      if reply_to = message.reply_to
        reply_to << result
      else
        Movie::Ask.reply_if_asked(message.sender, result)
      end
      Movie::Behaviors(MCPMessage).same
    end
  end
end
