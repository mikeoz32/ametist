require "../../movie"
require "../runtime/protocol"
require "./client"

module Agency
  # Adapter that proxies tool calls to an MCP server over JSON-RPC.
  class MCPAdapter < Movie::AbstractBehavior(ToolSetMessage)
    def self.behavior(client : MCP::Client) : Movie::AbstractBehavior(ToolSetMessage)
      Movie::Behaviors(ToolSetMessage).setup do |_ctx|
        MCPAdapter.new(client)
      end
    end

    def initialize(@client : MCP::Client)
      @ready = Movie::Promise(Bool).new
      @init_started = false
      @client.start
    end

    def receive(message, ctx)
      case message
      when ToolCall
        handle_call(message, ctx)
      end
      Movie::Behaviors(ToolSetMessage).same
    end

    private def ensure_ready(ctx)
      return if @init_started
      @init_started = true

      executor = ctx.extension(Movie::Execution.instance)
      init_future = executor.execute do
        @client.initialize_connection
      end
      init_future.on_success do
        @ready.try_success(true)
      end
      init_future.on_failure do |ex|
        @ready.try_failure(ex)
      end
    end

    private def handle_call(message : ToolCall, ctx)
      sender = ctx.sender
      ensure_ready(ctx)

      @ready.future.on_success do
        executor = ctx.extension(Movie::Execution.instance)
        call_future = executor.execute do
          @client.call_tool(message.name, message.arguments)
        end
        call_future.on_success do |result|
          content = result.to_json
          respond(sender, ToolResult.new(message.id, message.name, content))
        end
        call_future.on_failure do |ex|
          respond(sender, ToolResult.new(message.id, message.name, "(MCP) error: #{ex.message}"))
        end
      end

      @ready.future.on_failure do |ex|
        respond(sender, ToolResult.new(message.id, message.name, "(MCP) init failed: #{ex.message}"))
      end
    end

    private def respond(sender : Movie::ActorRefBase?, result : ToolResult)
      if reply_to = sender.as?(Movie::ActorRef(ToolResult))
        reply_to << result
      else
        Movie::Ask.reply_if_asked(sender, result)
      end
    end
  end
end
