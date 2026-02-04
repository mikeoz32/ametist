require "../movie"
require "./llm_message"

module Agency
  # Simple receiver that fulfills a promise when an LLMResult arrives.
  class LLMResultReceiver < Movie::AbstractBehavior(LLMResult)
    def initialize(@promise : Movie::Promise(String))
    end

    def receive(message, ctx)
      @promise.try_success(message.content)
      Movie::Behaviors(LLMResult).same
    end
  end
end
