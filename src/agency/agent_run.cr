require "../movie"
require "./protocol"
require "./agent_messages"
require "./context_builder"
require "./llm_gateway"
require "./tool_set"

module Agency
  struct RunStart
    getter prompt : String

    def initialize(@prompt : String)
    end
  end

  struct RunStep
    getter step : Int32

    def initialize(@step : Int32)
    end
  end

  struct RunOutput
    getter content : String

    def initialize(@content : String)
    end
  end

  struct RunError
    getter error : String

    def initialize(@error : String)
    end
  end

  alias RunMessage = RunStart | LLMResponse | ToolResult | ContextBuilt | RunStep | RunOutput | RunError

  class LLMForwarder < Movie::AbstractBehavior(LLMResponse)
    def initialize(@target : Movie::ActorRef(RunMessage))
    end

    def receive(message, ctx)
      @target << message
      Movie::Behaviors(LLMResponse).same
    end
  end

  class ContextForwarder < Movie::AbstractBehavior(ContextBuilt)
    def initialize(@target : Movie::ActorRef(RunMessage))
    end

    def receive(message, ctx)
      @target << message
      Movie::Behaviors(ContextBuilt).same
    end
  end

  class ToolForwarder < Movie::AbstractBehavior(ToolResult)
    def initialize(@target : Movie::ActorRef(RunMessage))
    end

    def receive(message, ctx)
      @target << message
      Movie::Behaviors(ToolResult).same
    end
  end

  # forwarder actors removed in favor of ctx.pipe where possible (LLM/context still use forwarders)

  # Executes a single ReAct loop for a prompt and then stops.
  class AgentRun < Movie::AbstractBehavior(RunMessage)
    def self.behavior(
      session_ref : Movie::ActorRef(SessionMessage),
      session_id : String,
      prompt : String,
      llm_gateway : Movie::ActorRef(LLMRequest),
      tool_set : Movie::ActorRef(ToolSetMessage),
      tools : Array(ToolSpec),
      context_builder : Movie::ActorRef(ContextMessage)? = nil,
      model : String = "gpt-3.5-turbo",
      max_steps : Int32 = 8,
      history : Array(Message) = [] of Message,
      user_id : String? = nil,
      project_id : String? = nil
    ) : Movie::AbstractBehavior(RunMessage)
      Movie::Behaviors(RunMessage).setup do |ctx|
        run = AgentRun.new(session_ref, session_id, llm_gateway, tool_set, tools, context_builder, model, max_steps, history, user_id, project_id)
        ctx.ref << RunStart.new(prompt)
        run
      end
    end

    def initialize(
      @session_ref : Movie::ActorRef(SessionMessage),
      @session_id : String,
      @llm_gateway : Movie::ActorRef(LLMRequest),
      @tool_set : Movie::ActorRef(ToolSetMessage),
      @tools : Array(ToolSpec),
      @context_builder : Movie::ActorRef(ContextMessage)?,
      @model : String,
      @max_steps : Int32,
      history : Array(Message),
      @user_id : String?,
      @project_id : String?
    )
      @messages = history.dup
      @delta = [] of Message
      @pending_tool_calls = {} of String => ToolCall
      @step = 0
      @llm_reply_ref = nil.as(Movie::ActorRef(LLMResponse)?)
      @context_reply_ref = nil.as(Movie::ActorRef(ContextBuilt)?)
      @tool_reply_ref = nil.as(Movie::ActorRef(ToolResult)?)
    end

    def receive(message, ctx)
      case message
      when RunStart
        handle_start(message, ctx)
      when ContextBuilt
        handle_context(message, ctx)
      when LLMResponse
        handle_llm_response(message, ctx)
      when ToolResult
        handle_tool_result(message, ctx)
      when RunStep
        # no-op: reserved for future use
      when RunOutput
        # no-op: reserved for future use
      when RunError
        fail_run(message.error, ctx)
      end
      Movie::Behaviors(RunMessage).same
    end

    private def handle_start(message : RunStart, ctx)
      add_message(Message.new(Role::User, message.prompt))
      request_context(ctx, message.prompt)
    end

    private def handle_context(message : ContextBuilt, ctx)
      @messages = message.messages.dup
      request_llm(ctx)
    end

    private def handle_llm_response(message : LLMResponse, ctx)
      output = message.output
      content = output.content || message.raw_text
      add_message(Message.new(Role::Assistant, content))

      if output.tool_calls.empty?
        complete_run(output.content || "", ctx)
        return
      end

      if @step >= @max_steps
        fail_run("(Agent) reached max steps", ctx)
        return
      end

      @pending_tool_calls.clear
      output.tool_calls.each do |call|
        @pending_tool_calls[call.id] = call
        reply_ref = tool_reply_ref(ctx)
        @tool_set.tell_from(reply_ref, call)
      end
      @step += 1
    end

    private def handle_tool_result(message : ToolResult, ctx)
      return unless @pending_tool_calls.has_key?(message.id)
      @pending_tool_calls.delete(message.id)
      add_message(Message.new(Role::Tool, message.content, message.name, message.id))

      if @pending_tool_calls.empty?
        request_llm(ctx)
      end
    end

    private def request_llm(ctx)
      reply_ref = llm_reply_ref(ctx)
      @llm_gateway << LLMRequest.new(@messages, @tools, reply_ref, @model)
    end

    private def request_context(ctx, prompt : String)
      if builder = @context_builder
        builder << BuildContext.new(@session_id, prompt, @messages, context_reply_ref(ctx), @user_id, @project_id)
      else
        request_llm(ctx)
      end
    end

    private def complete_run(content : String, ctx)
      @session_ref << RunCompleted.new(content, @delta)
      stop_forwarders
      ctx.stop
    end

    private def fail_run(error : String, ctx)
      @session_ref << RunFailed.new(error, @delta)
      stop_forwarders
      ctx.stop
    end

    private def add_message(message : Message)
      @messages << message
      @delta << message
    end

    private def tool_reply_ref(ctx) : Movie::ActorRef(ToolResult)
      @tool_reply_ref ||= ctx.spawn(ToolForwarder.new(ctx.ref))
      @tool_reply_ref.not_nil!
    end

    private def stop_forwarders
      @llm_reply_ref.try &.send_system(Movie::STOP)
      @context_reply_ref.try &.send_system(Movie::STOP)
      @tool_reply_ref.try &.send_system(Movie::STOP)
    end

    private def llm_reply_ref(ctx) : Movie::ActorRef(LLMResponse)
      @llm_reply_ref ||= ctx.spawn(LLMForwarder.new(ctx.ref))
      @llm_reply_ref.not_nil!
    end

    private def context_reply_ref(ctx) : Movie::ActorRef(ContextBuilt)
      @context_reply_ref ||= ctx.spawn(ContextForwarder.new(ctx.ref))
      @context_reply_ref.not_nil!
    end

  end
end
