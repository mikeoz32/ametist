require "../../movie"
require "../agents/messages"
require "../runtime/protocol"

module Agency
  # Routes tool calls to toolset actors based on a name prefix (prefix.tool).
  class ToolRouter < Movie::AbstractBehavior(ToolCall)
    def initialize(@toolsets : Hash(String, Movie::ActorRef(ToolSetMessage)))
    end

    def receive(message, ctx)
      prefix, tool_name = split_name(message.name)
      unless prefix && tool_name
        reply_error(message, ctx, "Toolset not found for #{message.name}")
        return Movie::Behaviors(ToolCall).same
      end

      toolset = @toolsets[prefix]?
      unless toolset
        reply_error(message, ctx, "Toolset not found for #{message.name}")
        return Movie::Behaviors(ToolCall).same
      end

      forwarded = ToolCall.new(tool_name, message.arguments, message.id)
      if reply_to = ctx.sender.as?(Movie::ActorRef(ToolResult))
        toolset.tell_from(reply_to, forwarded)
      else
        toolset.tell_from(ctx.sender, forwarded)
      end

      Movie::Behaviors(ToolCall).same
    end

    private def split_name(name : String) : Tuple(String?, String?)
      idx = name.index('.')
      return {nil, nil} unless idx
      prefix = name[0, idx]
      tool = name[idx + 1, name.size - idx - 1]
      return {nil, nil} if prefix.empty? || tool.empty?
      {prefix, tool}
    end

    private def reply_error(call : ToolCall, ctx, message : String)
      result = ToolResult.new(call.id, call.name, message)
      if reply_to = ctx.sender.as?(Movie::ActorRef(ToolResult))
        reply_to << result
      else
        Movie::Ask.reply_if_asked(ctx.sender, result)
      end
    end
  end
end
