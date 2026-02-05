require "../../movie"
require "../agents/messages"
require "./schema_validator"

module Agency
  # Base ToolSet provides common error handling and a unified ToolResult response.
  abstract class ToolSet < Movie::AbstractBehavior(ToolSetMessage)
    def receive(message, ctx)
      case message
      when ToolCall
        reply_to = ctx.sender.as?(Movie::ActorRef(ToolResult))
        sender = ctx.sender
        return Movie::Behaviors(ToolSetMessage).same unless reply_to || sender

        begin
          handle(message, reply_to, sender)
        rescue ex : Exception
          reply(message, reply_to, sender, ToolResult.new(message.id, message.name, "(ToolSet) error: #{ex.message}"))
        end
      when ToolSetRegisterExec
        register_exec_tool(message.spec, message.handler)
      when ToolSetRegisterActor
        register_actor_tool(message.spec, message.ref)
      when ToolSetUnregister
        unregister_tool(message.name)
      end

      Movie::Behaviors(ToolSetMessage).same
    end

    protected abstract def handle(call : ToolCall, reply_to : Movie::ActorRef(ToolResult)?, sender : Movie::ActorRefBase?)

    protected def reply(call : ToolCall, reply_to : Movie::ActorRef(ToolResult)?, sender : Movie::ActorRefBase?, result : ToolResult)
      if reply_to
        reply_to << result
      else
        Movie::Ask.reply_if_asked(sender, result)
      end
    end

    protected def register_exec_tool(spec : ToolSpec, handler : ExecTool)
    end

    protected def register_actor_tool(spec : ToolSpec, ref : Movie::ActorRef(ToolCall))
    end

    protected def unregister_tool(name : String)
    end
  end

  # Default ToolSet routes calls to executor-backed or actor-backed tools.
  class DefaultToolSet < ToolSet
    def initialize(
      @executor : Movie::ExecutorExtension,
      exec_tools : Hash(String, ExecTool) = {} of String => ExecTool,
      actor_tools : Hash(String, Movie::ActorRef(ToolCall)) = {} of String => Movie::ActorRef(ToolCall),
      specs : Hash(String, ToolSpec) = {} of String => ToolSpec
    )
      @exec_tools = exec_tools
      @actor_tools = actor_tools
      @tool_specs = specs
    end

    protected def handle(call : ToolCall, reply_to : Movie::ActorRef(ToolResult)?, sender : Movie::ActorRefBase?)
      if spec = @tool_specs[call.name]?
        errors = SchemaValidator.validate(spec.parameters, call.arguments)
        if errors.size > 0
          reply(call, reply_to, sender, ToolResult.new(call.id, call.name, "Schema validation failed: #{errors.join("; ")}"))
          return
        end
      end

      if handler = @exec_tools[call.name]?
        future = @executor.execute do
          handler.call(call)
        end
        future.on_success do |content|
          reply(call, reply_to, sender, ToolResult.new(call.id, call.name, content))
        end
        future.on_failure do |ex|
          reply(call, reply_to, sender, ToolResult.new(call.id, call.name, "(Tool) error: #{ex.message}"))
        end
        return
      end

      if ref = @actor_tools[call.name]?
        if reply_to
          ref.tell_from(reply_to, call)
        else
          ref.tell_from(sender, call)
        end
        return
      end

      reply(call, reply_to, sender, ToolResult.new(call.id, call.name, "Tool not found: #{call.name}"))
    end

    protected def register_exec_tool(spec : ToolSpec, handler : ExecTool)
      @exec_tools[spec.name] = handler
      @tool_specs[spec.name] = spec
    end

    protected def register_actor_tool(spec : ToolSpec, ref : Movie::ActorRef(ToolCall))
      @actor_tools[spec.name] = ref
      @tool_specs[spec.name] = spec
    end

    protected def unregister_tool(name : String)
      @exec_tools.delete(name)
      @actor_tools.delete(name)
      @tool_specs.delete(name)
    end
  end
end
