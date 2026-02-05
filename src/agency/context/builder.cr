require "../../movie"
require "../../ametist"
require "../runtime/protocol"
require "../memory/actor"
require "../stores/embedder_extension"
require "../memory/policy"

module Agency
  def self.safe_tell(ref : Movie::ActorRef(T), message : T) forall T
    ref << message
  rescue ex
    # Receiver likely stopped; ignore.
  end

  struct BuildContext
    getter session_id : String
    getter prompt : String
    getter history : Array(Message)
    getter reply_to : Movie::ActorRef(ContextBuilt)?
    getter user_id : String?
    getter project_id : String?

    def initialize(
      @session_id : String,
      @prompt : String,
      @history : Array(Message),
      @reply_to : Movie::ActorRef(ContextBuilt)? = nil,
      @user_id : String? = nil,
      @project_id : String? = nil
    )
    end
  end

  struct ContextBuilt
    getter messages : Array(Message)

    def initialize(@messages : Array(Message))
    end
  end

  struct RecentEvents
    getter events : Array(Message)

    def initialize(@events : Array(Message))
    end
  end

  struct SummaryResult
    getter summary : String?

    def initialize(@summary : String?)
    end
  end

  struct SemanticEvents
    getter events : Array(Message)

    def initialize(@events : Array(Message))
    end
  end

  struct CollectorTimeout
  end

  alias ContextMessage = BuildContext
  struct GraphEvents
    getter events : Array(Message)

    def initialize(@events : Array(Message))
    end
  end

  alias CollectorMessage = RecentEvents | SummaryResult | SemanticEvents | GraphEvents | CollectorTimeout

  struct ScopeContextBuilt
    getter scope : MemoryScope
    getter messages : Array(Message)

    def initialize(@scope : MemoryScope, @messages : Array(Message))
    end
  end

  alias MultiScopeMessage = ScopeContextBuilt | CollectorTimeout

  # forwarder actors removed in favor of ctx.pipe mappings

  class ContextCollector < Movie::AbstractBehavior(CollectorMessage)
    def initialize(
      @reply_to : Movie::ActorRef(ContextBuilt)?,
      @sender : Movie::ActorRefBase?,
      @history : Array(Message),
      @max_history : Int32,
      @semantic_k : Int32,
      @summary_prefix : String = "Summary"
    )
      @recent = nil.as(Array(Message)?)
      @summary = nil.as(String?)
      @semantic = nil.as(Array(Message)?)
      @graph = nil.as(Array(Message)?)
      @received = 0
    end

    def receive(message, ctx)
      case message
      when RecentEvents
        @recent = message.events
        @received += 1
      when SummaryResult
        @summary = message.summary
        @received += 1
      when SemanticEvents
        @semantic = message.events
        @received += 1
      when GraphEvents
        @graph = message.events
        @received += 1
      when CollectorTimeout
        finish
        return Movie::Behaviors(CollectorMessage).stopped
      end

      if @received >= 4
        finish
        return Movie::Behaviors(CollectorMessage).stopped
      end
      Movie::Behaviors(CollectorMessage).same
    end

    private def finish
      if @received < 4
        @received = 4
      end
      base = @recent || @history
      base = base.last(@max_history) if base.size > @max_history

      messages = base.dup
      @history.each do |msg|
        unless messages.any? { |existing| same_message?(existing, msg) }
          messages << msg
        end
      end
      if @summary
        messages.unshift(Message.new(Role::System, "#{@summary_prefix}: #{@summary}"))
      end

      if semantic = @semantic
        semantic.each do |msg|
          unless messages.any? { |existing| same_message?(existing, msg) }
            messages << msg
          end
        end
      end

      if graph = @graph
        graph.each do |msg|
          unless messages.any? { |existing| same_message?(existing, msg) }
            messages << msg
          end
        end
      end

      if @reply_to
        @reply_to.not_nil! << ContextBuilt.new(messages)
      else
        Movie::Ask.reply_if_asked(@sender, ContextBuilt.new(messages))
      end
    end

    private def same_message?(left : Message, right : Message) : Bool
      left.role == right.role &&
        left.content == right.content &&
        left.name == right.name &&
        left.tool_call_id == right.tool_call_id
    end
  end

  class GraphCollector < Movie::AbstractBehavior(Array(GraphNode))
    def initialize(
      @reply_to : Movie::ActorRef(CollectorMessage),
      @summary_prefix : String
    )
    end

    def receive(message, ctx)
      events = message.map do |node|
        Message.new(Role::System, "#{@summary_prefix}: #{node.type}=#{node.data || node.id}")
      end
      @reply_to << GraphEvents.new(events)
      ctx.stop
      Movie::Behaviors(Array(GraphNode)).same
    end
  end

  class MultiScopeCollector < Movie::AbstractBehavior(MultiScopeMessage)
    def initialize(
      @reply_to : Movie::ActorRef(ContextBuilt)?,
      @sender : Movie::ActorRefBase?,
      scopes : Array(MemoryScope)
    )
      @scopes = scopes
      @received = {} of MemoryScope => Array(Message)
    end

    def receive(message, ctx)
      case message
      when ScopeContextBuilt
        @received[message.scope] = message.messages
      when CollectorTimeout
        finish
        return Movie::Behaviors(MultiScopeMessage).stopped
      end

      if @received.size >= @scopes.size
        finish
        return Movie::Behaviors(MultiScopeMessage).stopped
      end

      Movie::Behaviors(MultiScopeMessage).same
    end

    private def finish
      merged = [] of Message
      ordered_scopes = @scopes
      ordered_scopes.each do |scope|
        messages = @received[scope]?
        next unless messages
        messages.each do |msg|
          unless merged.any? { |existing| same_message?(existing, msg) }
            merged << msg
          end
        end
      end

      if @reply_to
        @reply_to.not_nil! << ContextBuilt.new(merged)
      else
        Movie::Ask.reply_if_asked(@sender, ContextBuilt.new(merged))
      end
    end

    private def same_message?(left : Message, right : Message) : Bool
      left.role == right.role &&
        left.content == right.content &&
        left.name == right.name &&
        left.tool_call_id == right.tool_call_id
    end
  end

  class ScopeForwarder < Movie::AbstractBehavior(ContextBuilt)
    def initialize(@scope : MemoryScope, @target : Movie::ActorRef(MultiScopeMessage))
    end

    def receive(message, ctx)
      @target << ScopeContextBuilt.new(@scope, message.messages)
      ctx.stop
      Movie::Behaviors(ContextBuilt).same
    end
  end

  # Builds context from memory stores + recent history.
  class ContextBuilder < Movie::AbstractBehavior(ContextMessage)
    def self.behavior(
      memory : Movie::ActorRef(MemoryMessage),
      embedder : EmbedderExtension? = nil,
      vector_collection : String = "agency_memory",
      max_history : Int32 = 50,
      semantic_k : Int32 = 5,
      timeout : Time::Span = 2.seconds,
      project_memory : Movie::ActorRef(MemoryMessage)? = nil,
      user_memory : Movie::ActorRef(MemoryMessage)? = nil,
      memory_policy : MemoryPolicy? = nil
    ) : Movie::AbstractBehavior(ContextMessage)
      Movie::Behaviors(ContextMessage).setup do |_ctx|
        policy = memory_policy || MemoryPolicy.from_config(_ctx.system.config)
        ContextBuilder.new(memory, embedder, vector_collection, max_history, semantic_k, timeout, project_memory, user_memory, policy)
      end
    end

    def initialize(
      @memory : Movie::ActorRef(MemoryMessage)? = nil,
      @embedder : EmbedderExtension? = nil,
      @vector_collection : String = "agency_memory",
      @max_history : Int32 = 50,
      @semantic_k : Int32 = 5,
      @timeout : Time::Span = 1.second,
      @project_memory : Movie::ActorRef(MemoryMessage)? = nil,
      @user_memory : Movie::ActorRef(MemoryMessage)? = nil,
      @policy : MemoryPolicy = MemoryPolicy.new(8000, ScopePolicy.new(50, 5, 10), ScopePolicy.new(50, 3, 5), ScopePolicy.new(50, 2, 3))
    )
    end

    def receive(message, ctx)
      case message
      when BuildContext
        handle_build(message, ctx)
      end
      Movie::Behaviors(ContextMessage).same
    end

    private def handle_build(message : BuildContext, ctx)
      memory = @memory
      unless memory
        if reply_to = message.reply_to
          reply_to << ContextBuilt.new(message.history)
        else
          Movie::Ask.reply_if_asked(ctx.sender, ContextBuilt.new(message.history))
        end
        return
      end
      scopes = [] of MemoryScope
      scopes << MemoryScope::Session
      if @project_memory && message.project_id
        scopes << MemoryScope::Project
      end
      if @user_memory && message.user_id
        scopes << MemoryScope::User
      end

      multi = ctx.spawn(
        MultiScopeCollector.new(message.reply_to, ctx.sender, scopes),
        Movie::RestartStrategy::STOP,
        Movie::SupervisionConfig.default
      )

      request_scope_context(
        ctx,
        memory,
        message.session_id,
        message.history,
        @policy.session.max_history,
        @policy.session.semantic_k,
        "Summary",
        MemoryScope::Session,
        multi,
        message.prompt
      )

      if project_memory = @project_memory
        if project_id = message.project_id
          request_scope_context(
            ctx,
            project_memory,
            project_id,
            [] of Message,
            @policy.project.max_history,
            @policy.project.semantic_k,
            "Project Summary",
            MemoryScope::Project,
            multi,
            message.prompt
          )
        end
      end

      if user_memory = @user_memory
        if user_id = message.user_id
          request_scope_context(
            ctx,
            user_memory,
            user_id,
            [] of Message,
            @policy.user.max_history,
            @policy.user.semantic_k,
            "User Summary",
            MemoryScope::User,
            multi,
            message.prompt
          )
        end
      end

      ctx.system.scheduler.schedule_once(@timeout * 2) do
        Agency.safe_tell(multi, CollectorTimeout.new)
      end
    end

    private def request_scope_context(
      ctx,
      memory : Movie::ActorRef(MemoryMessage),
      scope_id : String,
      history : Array(Message),
      max_history : Int32,
      semantic_k : Int32,
      summary_prefix : String,
      scope : MemoryScope,
      reply_to : Movie::ActorRef(MultiScopeMessage),
      prompt : String
    )
      forwarder = ctx.spawn(
        ScopeForwarder.new(scope, reply_to),
        Movie::RestartStrategy::STOP,
        Movie::SupervisionConfig.default
      )

      collector = ctx.spawn(
        ContextCollector.new(forwarder, ctx.sender, history, max_history, semantic_k, summary_prefix),
        Movie::RestartStrategy::STOP,
        Movie::SupervisionConfig.default
      )

      events_future = ctx.ask(memory, FetchEvents.new(scope_id, max_history), Array(Message), @timeout)
      ctx.pipe(
        events_future,
        collector,
        ->(events : Array(Message)) { RecentEvents.new(events) },
        ->(_ex : Exception) { RecentEvents.new([] of Message) }
      )

      summary_future = ctx.ask(memory, GetSummary.new(scope_id), String?, @timeout)
      ctx.pipe(
        summary_future,
        collector,
        ->(summary : String?) { SummaryResult.new(summary) },
        ->(_ex : Exception) { SummaryResult.new(nil) }
      )

      if @embedder
        future = @embedder.not_nil!.embed(prompt, timeout: @timeout)
        future.on_success do |vector|
          query_future = ctx.ask(
            memory,
            QueryEmbedding.new(@vector_collection, vector, semantic_k, nil),
            Array(Ametist::QueryResult),
            @timeout
          )
          query_future.on_success do |results|
            if results.empty?
              Agency.safe_tell(collector, SemanticEvents.new([] of Message))
            else
              ids = results.map(&.id)
              events_by_id = ctx.ask(
                memory,
                FetchEventsById.new(ids),
                Array(Message),
                @timeout
              )
              ctx.pipe(
                events_by_id,
                collector,
                ->(events : Array(Message)) { SemanticEvents.new(events) },
                ->(_ex : Exception) { SemanticEvents.new([] of Message) }
              )
            end
          end
          query_future.on_failure { |_error| Agency.safe_tell(collector, SemanticEvents.new([] of Message)) }
        end
        future.on_failure { |_error| Agency.safe_tell(collector, SemanticEvents.new([] of Message)) }
      else
        Agency.safe_tell(collector, SemanticEvents.new([] of Message))
      end

      request_graph(ctx, memory, scope_id, summary_prefix, collector)

      ctx.system.scheduler.schedule_once(@timeout * 2) do
        Agency.safe_tell(collector, CollectorTimeout.new)
      end
    end

    private def request_graph(
      ctx,
      memory : Movie::ActorRef(MemoryMessage),
      scope_id : String,
      summary_prefix : String,
      collector : Movie::ActorRef(CollectorMessage)
    )
      graph_reply = ctx.spawn(
        GraphCollector.new(collector, summary_prefix),
        Movie::RestartStrategy::STOP,
        Movie::SupervisionConfig.default
      )
      memory << GraphNeighbors.new(scope_id, graph_reply)
    end
  end
end
