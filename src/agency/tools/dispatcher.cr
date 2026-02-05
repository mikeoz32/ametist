require "../../movie"
require "../runtime/protocol"
require "./schema_validator"

module Agency
  struct ToolRoute
    getter call : ToolCall
    getter reply_to : Movie::ActorRef(ToolResult)

    def initialize(@call : ToolCall, @reply_to : Movie::ActorRef(ToolResult))
    end
  end

  struct RegisterTool
    getter spec : ToolSpec
    getter ref : Movie::ActorRef(ToolCall)

    def initialize(@spec : ToolSpec, @ref : Movie::ActorRef(ToolCall))
    end
  end

  struct UnregisterTool
    getter name : String

    def initialize(@name : String)
    end
  end

  alias ToolDispatcherMessage = ToolRoute | RegisterTool | UnregisterTool

  # Routes tool calls to registered tool actors and validates arguments.
  class ToolDispatcher < Movie::AbstractBehavior(ToolDispatcherMessage)
    def self.behavior : Movie::AbstractBehavior(ToolDispatcherMessage)
      Movie::Behaviors(ToolDispatcherMessage).setup do |_ctx|
        ToolDispatcher.new
      end
    end

    def initialize
      @tools = {} of String => NamedTuple(spec: ToolSpec, ref: Movie::ActorRef(ToolCall))
    end

    def receive(message, ctx)
      case message
      when RegisterTool
        @tools[message.spec.name] = {spec: message.spec, ref: message.ref}
      when UnregisterTool
        @tools.delete(message.name)
      when ToolRoute
        call = message.call
        reply_to = message.reply_to

        if entry = @tools[call.name]?
          spec = entry[:spec]
          errors = SchemaValidator.validate(spec.parameters, call.arguments)
          if errors.size > 0
            reply_to << ToolResult.new(call.id, call.name, "Schema validation failed: #{errors.join("; ")}")
            return Movie::Behaviors(ToolDispatcherMessage).same
          end
          entry[:ref].tell_from(reply_to, call)
        else
          reply_to << ToolResult.new(call.id, call.name, "Tool not found: #{call.name}")
        end
      end

      Movie::Behaviors(ToolDispatcherMessage).same
    end
  end
end
