require "../movie"
require "./protocol"
require "../movie"
require "./llm_client"

module Agency
  Log = ::Log.for(self)

  struct LLMRequest
    getter messages : Array(Message)
    getter tools : Array(ToolSpec)
    getter model : String
    getter timeout : Time::Span?
    getter reply_to : Movie::ActorRef(LLMResponse)?

    def initialize(@messages : Array(Message),
                   @tools : Array(ToolSpec),
                   @reply_to : Movie::ActorRef(LLMResponse)? = nil,
                   @model : String = "gpt-3.5-turbo",
                   @timeout : Time::Span? = 20.seconds)
    end
  end

  struct LLMResponse
    getter output : LLMOutput
    getter raw_text : String

    def initialize(@output : LLMOutput, @raw_text : String)
    end
  end

  # Actor that submits LLM requests to the Movie::ExecutorExtension.
  class LLMGateway < Movie::AbstractBehavior(LLMRequest)
    def self.format_messages(messages : Array(Message)) : String
      messages.map { |msg| "[#{msg.role.to_s.downcase}] #{msg.content}" }.join("\n")
    end

    def self.behavior(client : LLMClient) : Movie::AbstractBehavior(LLMRequest)
      Movie::Behaviors(LLMRequest).setup do |ctx|
        exec = ctx.extension(Movie::Execution.instance)
        LLMGateway.new(client, exec)
      end
    end

    def initialize(@client : LLMClient, @exec : Movie::ExecutorExtension)
    end

    def receive(message, ctx)
      Log.info { "LLM request model=#{message.model}\n#{self.class.format_messages(message.messages)}" }
      fut = @exec.execute(message.timeout) do
        @client.chat(message.messages, message.tools, message.model)
      end

      fut.on_success do |raw|
        output = Protocol.parse_output(raw)
        respond(ctx, message, LLMResponse.new(output, raw))
      end

      fut.on_failure do |ex|
        output = LLMOutput.new("(LLM) failed: #{ex.message}", [] of ToolCall)
        respond(ctx, message, LLMResponse.new(output, "(error) #{ex.message}"))
      end

      Movie::Behaviors(LLMRequest).same
    end

    private def respond(ctx, message, response : LLMResponse)
      if reply_to = message.reply_to
        reply_to << response
      else
        Movie::Ask.reply_if_asked(ctx.sender, response)
      end
    end
  end
end
