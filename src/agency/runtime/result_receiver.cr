require "../../movie"

module Agency
  # Generic receiver that fulfills a promise when it gets a TaskResult.
  class ResultReceiver(T) < Movie::AbstractBehavior(Movie::ExecutorExtension::TaskResult(T))
    def initialize(@promise : Movie::Promise(T))
    end

    def receive(message, ctx)
      @promise.try_success(message.value)
      Movie::Behaviors(Movie::ExecutorExtension::TaskResult(T)).same
    end
  end
end
