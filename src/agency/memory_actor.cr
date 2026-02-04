require "../movie"
require "./protocol"
require "./graph_store_extension"
require "./context_store_extension"
require "./vector_store_extension"
require "./embedder_extension"
require "./memory_policy"
require "./token_estimator"
require "./summarizer"

module Agency
  enum MemoryScope
    Global
    Agent
    User
    Project
    Session
  end

  struct StoreEvent
    getter session_id : String
    getter message : Message
    getter embed : Bool
    getter reply_to : Movie::ActorRef(String)?

    def initialize(@session_id : String, @message : Message, @embed : Bool, @reply_to : Movie::ActorRef(String)? = nil)
    end
  end

  struct FetchEvents
    getter session_id : String
    getter limit : Int32
    getter reply_to : Movie::ActorRef(Array(Message))?

    def initialize(@session_id : String, @limit : Int32, @reply_to : Movie::ActorRef(Array(Message))? = nil)
    end
  end

  struct FetchEventsById
    getter ids : Array(String)
    getter reply_to : Movie::ActorRef(Array(Message))?

    def initialize(@ids : Array(String), @reply_to : Movie::ActorRef(Array(Message))? = nil)
    end
  end

  struct StoreSummary
    getter session_id : String
    getter summary : String
    getter reply_to : Movie::ActorRef(Bool)?

    def initialize(@session_id : String, @summary : String, @reply_to : Movie::ActorRef(Bool)? = nil)
    end
  end

  struct SessionMeta
    getter session_id : String
    getter agent_id : String
    getter model : String
    getter created_at : String
    getter updated_at : String

    def initialize(
      @session_id : String,
      @agent_id : String,
      @model : String,
      @created_at : String,
      @updated_at : String
    )
    end
  end

  struct StoreSessionMeta
    getter session_id : String
    getter agent_id : String
    getter model : String
    getter reply_to : Movie::ActorRef(Bool)?

    def initialize(@session_id : String, @agent_id : String, @model : String, @reply_to : Movie::ActorRef(Bool)? = nil)
    end
  end

  struct GetSessionMeta
    getter session_id : String
    getter reply_to : Movie::ActorRef(SessionMeta?)?

    def initialize(@session_id : String, @reply_to : Movie::ActorRef(SessionMeta?)? = nil)
    end
  end

  struct GetSummary
    getter session_id : String
    getter reply_to : Movie::ActorRef(String?)?

    def initialize(@session_id : String, @reply_to : Movie::ActorRef(String?)? = nil)
    end
  end

  struct UpsertEmbedding
    getter collection : String
    getter id : String
    getter vector : Array(Float32)
    getter metadata : Hash(String, VectorMetadataValue)?
    getter reply_to : Movie::ActorRef(Bool)?

    def initialize(
      @collection : String,
      @id : String,
      @vector : Array(Float32),
      @metadata : Hash(String, VectorMetadataValue)?,
      @reply_to : Movie::ActorRef(Bool)? = nil
    )
    end
  end

  struct QueryEmbedding
    getter collection : String
    getter vector : Array(Float32)
    getter k : Int32
    getter filter : Ametist::Filter?
    getter reply_to : Movie::ActorRef(Array(Ametist::QueryResult))?

    def initialize(
      @collection : String,
      @vector : Array(Float32),
      @k : Int32,
      @filter : Ametist::Filter?,
      @reply_to : Movie::ActorRef(Array(Ametist::QueryResult))? = nil
    )
    end
  end

  struct AddNode
    getter id : String
    getter type : String
    getter data : String?
    getter reply_to : Movie::ActorRef(Bool)?

    def initialize(@id : String, @type : String, @data : String?, @reply_to : Movie::ActorRef(Bool)? = nil)
    end
  end

  struct AddEdge
    getter id : String
    getter from_id : String
    getter to_id : String
    getter type : String
    getter data : String?
    getter reply_to : Movie::ActorRef(Bool)?

    def initialize(@id : String, @from_id : String, @to_id : String, @type : String, @data : String?, @reply_to : Movie::ActorRef(Bool)? = nil)
    end
  end

  struct GraphNeighbors
    getter node_id : String
    getter reply_to : Movie::ActorRef(Array(GraphNode))?

    def initialize(@node_id : String, @reply_to : Movie::ActorRef(Array(GraphNode))? = nil)
    end
  end

  alias MemoryMessage = StoreEvent | FetchEvents | FetchEventsById | StoreSummary | StoreSessionMeta | GetSessionMeta | GetSummary | UpsertEmbedding | QueryEmbedding | AddNode | AddEdge | GraphNeighbors
  alias ContextStoreMessage = StoreEvent | FetchEvents | FetchEventsById | StoreSummary | StoreSessionMeta | GetSessionMeta | GetSummary
  alias VectorStoreMessage = UpsertEmbedding | QueryEmbedding
  alias GraphStoreMessage = AddNode | AddEdge | GraphNeighbors

  class ContextStoreActor < Movie::AbstractBehavior(ContextStoreMessage)
    def initialize(@store : ContextStoreExtension)
    end

    def receive(message, ctx)
      case message
      when StoreEvent
        begin
          id = @store.store.append_event(
            message.session_id,
            message.message.role.to_s.downcase,
            message.message.content,
            message.message.name,
            message.message.tool_call_id
          ).to_s
          reply(ctx, message.reply_to, id, String)
        rescue
          reply_failure(ctx, message.reply_to, "", String)
        end
      when FetchEvents
        begin
          events = @store.store.fetch_events(message.session_id, message.limit).map do |event|
            Message.new(parse_role(event[:role]), event[:content], event[:name], event[:tool_call_id])
          end
          reply(ctx, message.reply_to, events)
        rescue
          reply_failure(ctx, message.reply_to, [] of Message)
        end
      when FetchEventsById
        begin
          events = message.ids.compact_map do |id|
            event = @store.store.get_event_by_id(id)
            next unless event
            Message.new(parse_role(event[:role]), event[:content], event[:name], event[:tool_call_id])
          end
          reply(ctx, message.reply_to, events)
        rescue
          reply_failure(ctx, message.reply_to, [] of Message)
        end
      when StoreSummary
        begin
          @store.store.store_summary(message.session_id, message.summary)
          reply(ctx, message.reply_to, true)
        rescue
          reply_failure(ctx, message.reply_to, false)
        end
      when StoreSessionMeta
        begin
          @store.store.upsert_session_meta(message.session_id, message.agent_id, message.model)
          reply(ctx, message.reply_to, true)
        rescue
          reply_failure(ctx, message.reply_to, false)
        end
      when GetSessionMeta
        begin
          meta = @store.store.get_session_meta(message.session_id)
          if meta
          reply(
            ctx,
            message.reply_to,
            SessionMeta.new(
              message.session_id,
              meta[:agent_id],
              meta[:model],
              meta[:created_at],
              meta[:updated_at]
            )
          )
        else
          reply(ctx, message.reply_to, nil.as(SessionMeta?))
        end
      rescue
          reply_failure(ctx, message.reply_to, nil.as(SessionMeta?))
      end
      when GetSummary
        begin
          reply(ctx, message.reply_to, @store.store.get_summary(message.session_id))
        rescue
          reply_failure(ctx, message.reply_to, nil.as(String?))
        end
      end
      Movie::Behaviors(ContextStoreMessage).same
    end

    private def parse_role(role : String) : Role
      case role
      when "system" then Role::System
      when "user" then Role::User
      when "assistant" then Role::Assistant
      when "tool" then Role::Tool
      else
        Role::Assistant
      end
    end

    private def reply(ctx, reply_to, value)
      if reply_to
        reply_to << value
      else
        Movie::Ask.reply_if_asked(ctx.sender, value)
      end
    end

    private def reply_failure(ctx, reply_to, fallback)
      if reply_to
        reply_to << fallback
      else
        Movie::Ask.reply_if_asked(ctx.sender, fallback)
      end
    end
  end

  class VectorStoreActor < Movie::AbstractBehavior(VectorStoreMessage)
    def initialize(@store : VectorStoreExtension)
    end

    def receive(message, ctx)
      case message
      when UpsertEmbedding
        future = @store.upsert_embedding(message.collection, message.id, message.vector, message.metadata)
        if message.reply_to
          reply_to_bool = message.reply_to.not_nil!.as(Movie::ActorRef(Bool))
          future.on_success { |value| reply_to_bool << value }
          future.on_failure { |_error| reply_to_bool << false }
        else
          future.on_success { |value| Movie::Ask.reply_if_asked(ctx.sender, value) }
          future.on_failure { |error| Movie::Ask.fail_if_asked(ctx.sender, error, Bool) }
        end
      when QueryEmbedding
        future = @store.query_top_k(message.collection, message.vector, message.k, message.filter)
        if message.reply_to
          reply_to_results = message.reply_to.not_nil!.as(Movie::ActorRef(Array(Ametist::QueryResult)))
          future.on_success { |results| reply_to_results << results }
          future.on_failure { |_error| reply_to_results << [] of Ametist::QueryResult }
        else
          future.on_success { |results| Movie::Ask.reply_if_asked(ctx.sender, results) }
          future.on_failure { |error| Movie::Ask.fail_if_asked(ctx.sender, error, Array(Ametist::QueryResult)) }
        end
      end
      Movie::Behaviors(VectorStoreMessage).same
    end
  end

  class NullVectorStoreActor < Movie::AbstractBehavior(VectorStoreMessage)
    def receive(message, ctx)
      case message
      when UpsertEmbedding
        if reply_to = message.reply_to
          reply_to << false
        else
          Movie::Ask.reply_if_asked(ctx.sender, false)
        end
      when QueryEmbedding
        if reply_to = message.reply_to
          reply_to << [] of Ametist::QueryResult
        else
          Movie::Ask.reply_if_asked(ctx.sender, [] of Ametist::QueryResult)
        end
      end
      Movie::Behaviors(VectorStoreMessage).same
    end
  end

  class GraphStoreActor < Movie::AbstractBehavior(GraphStoreMessage)
    def initialize(@store : GraphStoreExtension, @exec : Movie::ExecutorExtension)
    end

    def receive(message, ctx)
      case message
      when AddNode
        future = @exec.execute do
          @store.store.add_node(message.id, message.type, message.data)
          true
        end
        if message.reply_to
          reply_to_bool = message.reply_to.not_nil!.as(Movie::ActorRef(Bool))
          future.on_success { |value| reply_to_bool << value }
          future.on_failure { |_error| reply_to_bool << false }
        else
          future.on_success { |value| Movie::Ask.reply_if_asked(ctx.sender, value) }
          future.on_failure { |error| Movie::Ask.fail_if_asked(ctx.sender, error, Bool) }
        end
      when AddEdge
        future = @exec.execute do
          @store.store.add_edge(message.id, message.from_id, message.to_id, message.type, message.data)
          true
        end
        if message.reply_to
          reply_to_bool = message.reply_to.not_nil!.as(Movie::ActorRef(Bool))
          future.on_success { |value| reply_to_bool << value }
          future.on_failure { |_error| reply_to_bool << false }
        else
          future.on_success { |value| Movie::Ask.reply_if_asked(ctx.sender, value) }
          future.on_failure { |error| Movie::Ask.fail_if_asked(ctx.sender, error, Bool) }
        end
      when GraphNeighbors
        future = @exec.execute do
          @store.store.neighbors(message.node_id)
        end
        if message.reply_to
          reply_to_nodes = message.reply_to.not_nil!.as(Movie::ActorRef(Array(GraphNode)))
          future.on_success { |nodes| reply_to_nodes << nodes }
          future.on_failure { |_error| reply_to_nodes << [] of GraphNode }
        else
          future.on_success { |nodes| Movie::Ask.reply_if_asked(ctx.sender, nodes) }
          future.on_failure { |error| Movie::Ask.fail_if_asked(ctx.sender, error, Array(GraphNode)) }
        end
      end
      Movie::Behaviors(GraphStoreMessage).same
    end
  end

  class NullGraphStoreActor < Movie::AbstractBehavior(GraphStoreMessage)
    def receive(message, ctx)
      case message
      when AddNode, AddEdge
        if reply_to = message.reply_to
          reply_to << false
        else
          Movie::Ask.reply_if_asked(ctx.sender, false)
        end
      when GraphNeighbors
        if reply_to = message.reply_to
          reply_to << [] of GraphNode
        else
          Movie::Ask.reply_if_asked(ctx.sender, [] of GraphNode)
        end
      end
      Movie::Behaviors(GraphStoreMessage).same
    end
  end

  class MemoryActor < Movie::AbstractBehavior(MemoryMessage)
    def self.behavior(
      scope : MemoryScope,
      vector_collection : String = "agency_memory",
      supervision : Movie::SupervisionConfig = Movie::SupervisionConfig.default,
      context_store : ContextStoreExtension? = nil,
      graph_store : GraphStoreExtension? = nil,
      vector_store : VectorStoreExtension? = nil,
      embedder : EmbedderExtension? = nil,
      memory_policy : MemoryPolicy? = nil,
      summarizer : Movie::ActorRef(SummarizerMessage)? = nil
    ) : Movie::AbstractBehavior(MemoryMessage)
      Movie::Behaviors(MemoryMessage).setup do |ctx|
        begin
          exec = ctx.extension(Movie::Execution.instance)
          graph_ext = graph_store
          unless graph_ext
            begin
              graph_ext = GraphStoreExtensionId.get(ctx.system)
            rescue
              graph_ext = nil
            end
          end

          context_ext = context_store || ContextStoreExtensionId.get(ctx.system)

          vector_ext = vector_store
          unless vector_ext
            begin
              vector_ext = VectorStoreExtensionId.get(ctx.system)
            rescue
              vector_ext = nil
            end
          end

          graph_actor = if graph_ext
            ctx.spawn(GraphStoreActor.new(graph_ext, exec), Movie::RestartStrategy::RESTART, supervision, "graph-store")
          else
            ctx.spawn(NullGraphStoreActor.new, Movie::RestartStrategy::RESTART, supervision, "graph-store")
          end

          vector_actor = if vector_ext
            ctx.spawn(VectorStoreActor.new(vector_ext), Movie::RestartStrategy::RESTART, supervision, "vector-store")
          else
            ctx.spawn(NullVectorStoreActor.new, Movie::RestartStrategy::RESTART, supervision, "vector-store")
          end

          embedder ||= begin
            EmbedderExtensionId.get(ctx.system)
          rescue
            nil
          end

          policy = memory_policy || MemoryPolicy.from_config(ctx.system.config)
          summarizer_ref = summarizer || ctx.spawn(
            SummarizerActor.behavior(ctx.ref, nil),
            Movie::RestartStrategy::RESTART,
            supervision,
            "summarizer"
          )
          MemoryActor.new(scope, vector_collection, context_ext, vector_actor, graph_actor, embedder, exec, policy, summarizer_ref)
        rescue ex
          Log.for("Agency::MemoryActor").error(exception: ex) { "Failed to initialize MemoryActor" }
          raise ex
        end
      end
    end

    def initialize(
      @scope : MemoryScope,
      @vector_collection : String,
      @context_store : ContextStoreExtension,
      @vector_store : Movie::ActorRef(VectorStoreMessage),
      @graph_store : Movie::ActorRef(GraphStoreMessage),
      @embedder : EmbedderExtension?,
      @exec : Movie::ExecutorExtension,
      @policy : MemoryPolicy,
      @summarizer : Movie::ActorRef(SummarizerMessage)?
    )
      @token_estimator = TokenEstimator.new
      @summary_tokens = {} of String => Int32
      @summary_pending = {} of String => Bool
    end

    def receive(message, ctx)
      case message
      when StoreEvent
        store_event(message.session_id, message.message, message.reply_to, message.embed, ctx.sender)
      when FetchEvents
        fetch_events(message.session_id, message.limit, message.reply_to, ctx.sender)
      when FetchEventsById
        fetch_events_by_id(message.ids, message.reply_to, ctx.sender)
      when StoreSummary
        store_summary(message.session_id, message.summary, message.reply_to, ctx.sender)
      when StoreSessionMeta
        store_session_meta(message.session_id, message.agent_id, message.model, message.reply_to, ctx.sender)
      when GetSessionMeta
        get_session_meta(message.session_id, message.reply_to, ctx.sender)
      when GetSummary
        get_summary(message.session_id, message.reply_to, ctx.sender)
      when UpsertEmbedding, QueryEmbedding
        @vector_store << message
      when AddNode, AddEdge, GraphNeighbors
        @graph_store << message
      end

      Movie::Behaviors(MemoryMessage).same
    end

    private def store_event(session_id : String, message : Message, reply_to : Movie::ActorRef(String)?, embed : Bool, sender)
      add_tokens(session_id, message.content)
      maybe_request_summary(session_id)
      future = @exec.execute do
        @context_store.store.append_event(
          session_id,
          message.role.to_s.downcase,
          message.content,
          message.name,
          message.tool_call_id
        ).to_s
      end
      future.on_success do |id|
        if embed && @embedder
          embedder = @embedder.not_nil!
          embedder.embed(message.content).on_success do |vector|
            @vector_store << UpsertEmbedding.new(@vector_collection, id, vector, nil)
          end
        end
        reply_value(reply_to, sender, id)
      end
      future.on_failure do |error|
        reply_failure(reply_to, sender, "", error)
      end
    end

    private def fetch_events(session_id : String, limit : Int32, reply_to : Movie::ActorRef(Array(Message))?, sender)
      future = @exec.execute do
        @context_store.store.fetch_events(session_id, limit).map do |event|
          Message.new(parse_role(event[:role]), event[:content], event[:name], event[:tool_call_id])
        end
      end
      future.on_success { |events| reply_value(reply_to, sender, events) }
      future.on_failure { |error| reply_failure(reply_to, sender, [] of Message, error) }
    end

    private def fetch_events_by_id(ids : Array(String), reply_to : Movie::ActorRef(Array(Message))?, sender)
      future = @exec.execute do
        ids.compact_map do |id|
          event = @context_store.store.get_event_by_id(id)
          next unless event
          Message.new(parse_role(event[:role]), event[:content], event[:name], event[:tool_call_id])
        end
      end
      future.on_success { |events| reply_value(reply_to, sender, events) }
      future.on_failure { |error| reply_failure(reply_to, sender, [] of Message, error) }
    end

    private def store_summary(session_id : String, summary : String, reply_to : Movie::ActorRef(Bool)?, sender)
      future = @exec.execute do
        @context_store.store.store_summary(session_id, summary)
        true
      end
      future.on_success do |value|
        @summary_tokens[session_id] = 0
        @summary_pending.delete(session_id)
        reply_value(reply_to, sender, value)
      end
      future.on_failure do |error|
        @summary_pending.delete(session_id)
        reply_failure(reply_to, sender, false, error)
      end
    end

    private def store_session_meta(session_id : String, agent_id : String, model : String, reply_to : Movie::ActorRef(Bool)?, sender)
      future = @exec.execute do
        @context_store.store.upsert_session_meta(session_id, agent_id, model)
        true
      end
      future.on_success { |value| reply_value(reply_to, sender, value) }
      future.on_failure { |error| reply_failure(reply_to, sender, false, error) }
    end

    private def get_session_meta(session_id : String, reply_to : Movie::ActorRef(SessionMeta?)?, sender)
      future = @exec.execute do
        @context_store.store.get_session_meta(session_id)
      end
      future.on_success do |meta|
        if meta
          reply_value(
            reply_to,
            sender,
            SessionMeta.new(
              session_id,
              meta[:agent_id],
              meta[:model],
              meta[:created_at],
              meta[:updated_at]
            ).as(SessionMeta?)
          )
        else
          reply_value(reply_to, sender, nil.as(SessionMeta?))
        end
      end
      future.on_failure { |error| reply_failure(reply_to, sender, nil.as(SessionMeta?), error) }
    end

    private def get_summary(session_id : String, reply_to : Movie::ActorRef(String?)?, sender)
      future = @exec.execute do
        @context_store.store.get_summary(session_id)
      end
      future.on_success { |value| reply_value(reply_to, sender, value.as(String?)) }
      future.on_failure { |error| reply_failure(reply_to, sender, nil.as(String?), error) }
    end

    private def parse_role(role : String) : Role
      case role
      when "system" then Role::System
      when "user" then Role::User
      when "assistant" then Role::Assistant
      when "tool" then Role::Tool
      else
        Role::Assistant
      end
    end

    private def reply_value(reply_to, sender, value)
      if reply_to
        reply_to << value
      else
        Movie::Ask.reply_if_asked(sender, value)
      end
    end

    private def reply_failure(reply_to, sender, fallback, error)
      if reply_to
        reply_to << fallback
      else
        Movie::Ask.reply_if_asked(sender, fallback)
      end
    end

    private def add_tokens(session_id : String, content : String)
      tokens = @token_estimator.estimate(content)
      return if tokens == 0
      @summary_tokens[session_id] = (@summary_tokens[session_id]? || 0) + tokens
    end

    private def maybe_request_summary(session_id : String)
      return unless @summarizer
      return if @summary_pending[session_id]?
      threshold = @policy.summary_token_threshold
      return if threshold <= 0
      count = @summary_tokens[session_id]? || 0
      return if count < threshold
      @summary_pending[session_id] = true
      @summarizer.not_nil! << SummarizeSession.new(session_id)
    end
  end
end
