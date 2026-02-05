require "../../movie"
require "../runtime/protocol"

module Agency
  alias ToolSetFactory = Proc(Movie::AbstractActorSystem, Movie::AbstractBehavior(ToolSetMessage))

  struct ToolSetDefinition
    getter id : String
    getter prefix : String
    getter tools : Array(ToolSpec)

    @ref : Movie::ActorRef(ToolSetMessage)?
    @factory : ToolSetFactory?

    def initialize(
      @id : String,
      @prefix : String,
      @tools : Array(ToolSpec),
      @ref : Movie::ActorRef(ToolSetMessage)
    )
      @factory = nil
    end

    def initialize(
      @id : String,
      @prefix : String,
      @tools : Array(ToolSpec),
      @factory : ToolSetFactory
    )
      @ref = nil
    end

    def static_ref? : Movie::ActorRef(ToolSetMessage)?
      @ref
    end

    def factory? : ToolSetFactory?
      @factory
    end

    def resolve(ctx : Movie::ActorContext(U)) : Movie::ActorRef(ToolSetMessage) forall U
      if ref = @ref
        return ref
      end
      factory = @factory || raise "ToolSetDefinition missing factory"
      ctx.spawn(factory.call(ctx.system), Movie::RestartStrategy::RESTART, Movie::SupervisionConfig.default)
    end
  end
end
