require "../../movie"
require "../tools/tool_set"
require "./adapter"

module Agency
  # ToolSet implementation that forwards tool calls to an MCP adapter actor.
  class McpToolSet < ToolSet
    def initialize(@adapter : Movie::ActorRef(ToolSetMessage))
    end

    protected def handle(call : ToolCall, reply_to : Movie::ActorRef(ToolResult)?, sender : Movie::ActorRefBase?)
      if reply_to
        @adapter.tell_from(reply_to, call)
      else
        @adapter.tell_from(sender, call)
      end
    end
  end
end
