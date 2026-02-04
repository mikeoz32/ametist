require "../movie"

module Ametist
  class ResultReceiver(T) < Movie::AbstractBehavior(T)
    def initialize(@promise : Movie::Promise(T))
    end

    def receive(message, ctx)
      @promise.try_success(message)
      Movie::Behaviors(T).same
    end
  end
end
