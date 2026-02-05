require "../../movie"
require "../runtime/protocol"
require "./actor"
require "../../openai/client"
require "./policy"

module Agency
  struct SummarizeSession
    getter session_id : String

    def initialize(@session_id : String)
    end
  end

  alias SummarizerMessage = SummarizeSession

  abstract class SummarizerClient
    abstract def summarize(summary : String?, events : Array(Message), model : String) : String
  end

  class LLMSummarizerClient < SummarizerClient
    def initialize(@api_key : String, @base_url : String, @http_client : OpenAI::HttpClient? = nil)
      @client = OpenAI::Client.new(@api_key, @base_url, @http_client)
    end

    def summarize(summary : String?, events : Array(Message), model : String) : String
      payload_messages = [] of OpenAI::ChatCompletionRequest::ChatMessagePayload
      system_prompt = "You are a summarizer. Produce a concise summary for future context."
      payload_messages << OpenAI::ChatCompletionRequest::ChatMessagePayload.new("system", system_prompt)

      if summary
        payload_messages << OpenAI::ChatCompletionRequest::ChatMessagePayload.new("system", "Existing summary: #{summary}")
      end

      events.each do |msg|
        role = case msg.role
               when Role::System then "system"
               when Role::User then "user"
               when Role::Assistant then "assistant"
               when Role::Tool then "user"
               else "assistant"
               end
        payload_messages << OpenAI::ChatCompletionRequest::ChatMessagePayload.new(role, msg.content)
      end

      payload = OpenAI::ChatCompletionRequest.new(model, payload_messages)
      begin
        response = @client.chat_completions(payload)
        if response.choices.empty?
          summary || ""
        else
          response.choices.first.message.content.to_s
        end
      rescue
        summary || ""
      end
    end
  end

  struct SummaryFetched
    getter summary : String?

    def initialize(@summary : String?)
    end
  end

  struct EventsFetched
    getter events : Array(Message)

    def initialize(@events : Array(Message))
    end
  end

  struct MetaFetched
    getter meta : SessionMeta?

    def initialize(@meta : SessionMeta?)
    end
  end

  struct SummarizeTimeout
  end

  alias SummarizeJobMessage = SummaryFetched | EventsFetched | MetaFetched | SummarizeTimeout

  class SummarizeJob < Movie::AbstractBehavior(SummarizeJobMessage)
    def initialize(
      @session_id : String,
      @memory : Movie::ActorRef(MemoryMessage),
      @client : SummarizerClient,
      @exec : Movie::ExecutorExtension,
      @summary_model : String,
      @default_model : String,
      @max_history : Int32,
      @timeout : Time::Span
    )
      @summary = nil.as(String?)
      @events = nil.as(Array(Message)?)
      @meta = nil.as(SessionMeta?)
      @received = 0
      @completed = false
    end

    def receive(message, ctx)
      return Movie::Behaviors(SummarizeJobMessage).stopped if @completed
      case message
      when SummaryFetched
        @summary = message.summary
        @received += 1
      when EventsFetched
        @events = message.events
        @received += 1
      when MetaFetched
        @meta = message.meta
        @received += 1
      when SummarizeTimeout
        finish
        return Movie::Behaviors(SummarizeJobMessage).stopped
      end

      if @received >= 3
        finish
        return Movie::Behaviors(SummarizeJobMessage).stopped
      end

      Movie::Behaviors(SummarizeJobMessage).same
    end

    private def finish
      return if @completed
      @completed = true
      summary = @summary
      events = @events || [] of Message
      model = resolve_model
      future = @exec.execute(@timeout) do
        @client.summarize(summary, events, model)
      end
      future.on_success do |text|
        @memory << StoreSummary.new(@session_id, text)
      end
    end

    private def resolve_model : String
      if @meta && !@meta.not_nil!.model.empty?
        return @meta.not_nil!.model
      end
      return @summary_model unless @summary_model.empty?
      @default_model
    end
  end

  class SummarizerActor < Movie::AbstractBehavior(SummarizerMessage)
    def self.behavior(
      memory : Movie::ActorRef(MemoryMessage),
      client : SummarizerClient? = nil,
      timeout : Time::Span = 10.seconds
    ) : Movie::AbstractBehavior(SummarizerMessage)
      Movie::Behaviors(SummarizerMessage).setup do |ctx|
        exec = ctx.extension(Movie::Execution.instance)
        cfg = ctx.system.config
        api_key = cfg.get_string("agency.llm.api_key", "")
        base_url = cfg.get_string("agency.llm.base_url", "https://api.openai.com")
        summary_model = cfg.get_string("agency.memory.summary_model", "")
        default_model = cfg.get_string("agency.llm.model", "gpt-3.5-turbo")
        policy = MemoryPolicy.from_config(cfg)
        client = client || LLMSummarizerClient.new(api_key, base_url)
        SummarizerActor.new(memory, client.as(SummarizerClient), exec, summary_model, default_model, policy.session.max_history, timeout)
      end
    end

    def initialize(
      @memory : Movie::ActorRef(MemoryMessage),
      @client : SummarizerClient,
      @exec : Movie::ExecutorExtension,
      @summary_model : String,
      @default_model : String,
      @max_history : Int32,
      @timeout : Time::Span
    )
    end

    def receive(message, ctx)
      case message
      when SummarizeSession
        handle_session(message, ctx)
      end
      Movie::Behaviors(SummarizerMessage).same
    end

    private def handle_session(message : SummarizeSession, ctx)
      job = ctx.spawn(
        SummarizeJob.new(
          message.session_id,
          @memory,
          @client,
          @exec,
          @summary_model,
          @default_model,
          @max_history,
          @timeout
        ),
        Movie::RestartStrategy::STOP,
        Movie::SupervisionConfig.default
      )

      summary_future = ctx.ask(@memory, GetSummary.new(message.session_id), String?, @timeout)
      ctx.pipe(
        summary_future,
        job,
        ->(summary : String?) { SummaryFetched.new(summary) },
        ->(_ex : Exception) { SummaryFetched.new(nil) }
      )

      events_future = ctx.ask(@memory, FetchEvents.new(message.session_id, @max_history), Array(Message), @timeout)
      ctx.pipe(
        events_future,
        job,
        ->(events : Array(Message)) { EventsFetched.new(events) },
        ->(_ex : Exception) { EventsFetched.new([] of Message) }
      )

      meta_future = ctx.ask(@memory, GetSessionMeta.new(message.session_id), SessionMeta?, @timeout)
      ctx.pipe(
        meta_future,
        job,
        ->(meta : SessionMeta?) { MetaFetched.new(meta) },
        ->(_ex : Exception) { MetaFetched.new(nil) }
      )

      ctx.system.scheduler.schedule_once(@timeout) do
        begin
          job << SummarizeTimeout.new
        rescue
        end
      end
    end
  end
end
