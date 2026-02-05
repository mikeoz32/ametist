require "../spec_helper"
require "../../src/movie"
require "../../src/agency/agents/manager"
require "../../src/agency/llm/client"

module Agency
  class FixedLLMClient < LLMClient
    def initialize(@response : String)
      super("dummy-key")
    end

    def chat(messages : Array(Agency::Message), tools : Array(Agency::ToolSpec), model : String = "gpt-3.5-turbo") : String
      @response
    end
  end

  class ResultActor < Movie::AbstractBehavior(String)
    def initialize(@promise : Movie::Promise(String))
    end

    def receive(message, ctx)
      @promise.try_success(message)
      Movie::Behaviors(Agency::SystemMessage).same
    end
  end
end

describe "Agency manager actor integration" do
  it "handles RunPrompt and returns a response" do
    system = Agency.spec_system
    Movie::Execution.get(system)
    client = Agency::FixedLLMClient.new({"type" => "final", "content" => "ok"}.to_json)
    manager = Agency::AgentManager.spawn(system, client, "gpt-3.5-turbo")

    promise = Movie::Promise(String).new
    receiver = system.spawn(Agency::ResultActor.new(promise))

    manager.ref << Agency::RunPrompt.new("simple test", "default", "gpt-3.5-turbo", receiver.as(Movie::ActorRef(String)))
    result = promise.future.await(3.seconds)
    result.should eq("ok")
  end
end
