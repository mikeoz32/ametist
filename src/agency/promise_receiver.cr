require "../movie"

module Agency
  class PromiseReceiver(T) < Movie::AbstractBehavior(T)
    def initialize(@promise : Movie::Promise(T))
    end

    def receive(message, ctx)
      @promise.try_success(message)
      ctx.stop
      Movie::Behaviors(T).same
    end
  end
end
