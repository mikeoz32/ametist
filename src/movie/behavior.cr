module Movie
  enum BehaviorTag
    DEFERRED
    SAME
    STOPPED
    EXTENSIBLE
  end

  abstract class AbstractBehavior(T)
    @tag : BehaviorTag = BehaviorTag::EXTENSIBLE
    def initialize(@tag : BehaviorTag = BehaviorTag::EXTENSIBLE)
    end

    def receive(message : T, context : ActorContext(T))
    end

    def on_signal(signal : SystemMessage)
    end

    def tag : BehaviorTag
      @tag
    end
  end

  class SameBehavior(T) < AbstractBehavior(T)
    def initialize(@tag : BehaviorTag = BehaviorTag::SAME)
      super @tag
    end
  end

  class StoppedBehavior(T) < AbstractBehavior(T)
    def initialize(@tag : BehaviorTag = BehaviorTag::STOPPED)
      super @tag
    end
  end

  class DeferredBehavior(T) < AbstractBehavior(T)
    def initialize(@factory : ActorContext(T) -> AbstractBehavior(T))
      super BehaviorTag::DEFERRED
    end

    def defer(context : ActorContext(T)) : AbstractBehavior(T) forall T
      @factory.call context
    end
  end

  class ReceiveMessageBehavior(T) < AbstractBehavior(T)
    def initialize(@handler : Proc(T, ActorContext(T), AbstractBehavior(T)))
      super BehaviorTag::EXTENSIBLE
    end

    def receive(message : T, context : ActorContext(T))
      @handler.call message, context
    end
  end

  module Behaviors(T)
    def self.same : SameBehavior(T)
      SameBehavior(T).new
    end

    def self.stopped : StoppedBehavior(T)
      StoppedBehavior(T).new
    end

    def self.setup(&block : Proc(ActorContext(T), AbstractBehavior(T))) : DeferredBehavior(T)
      DeferredBehavior.new block
    end

    def self.receive(&block : Proc(T, ActorContext(T), AbstractBehavior(T))) : ReceiveMessageBehavior(T)
      ReceiveMessageBehavior.new(block)
    end

  end
end
