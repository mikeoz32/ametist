require "../spec_helper"
require "../../src/movie"
require "../../src/agency/runtime/protocol"
require "../../src/agency/tools/tool_router"

module Agency
  class RouterEchoToolSet < Movie::AbstractBehavior(ToolSetMessage)
    def receive(message, ctx)
      case message
      when ToolCall
        if reply_to = ctx.sender.as?(Movie::ActorRef(ToolResult))
          reply_to << ToolResult.new(message.id, message.name, "name=#{message.name}")
        end
      end
      Movie::Behaviors(ToolSetMessage).same
    end
  end

  class RouterResultReceiver < Movie::AbstractBehavior(ToolResult)
    def initialize(@promise : Movie::Promise(ToolResult))
    end

    def receive(message, ctx)
      @promise.try_success(message)
      Movie::Behaviors(ToolResult).same
    end
  end
end

describe Agency::ToolRouter do
  it "routes calls by prefix and strips the prefix before forwarding" do
    system = Agency.spec_system
    tool_set = system.spawn(Agency::RouterEchoToolSet.new)
    router = system.spawn(Agency::ToolRouter.new({"fs" => tool_set}))

    promise = Movie::Promise(Agency::ToolResult).new
    receiver = system.spawn(Agency::RouterResultReceiver.new(promise))

    call = Agency::ToolCall.new("fs.echo", JSON.parse(%({"text":"hi"})))
    router.tell_from(receiver, call)

    result = promise.future.await(1.second)
    result.content.should eq("name=echo")
  end

  it "returns an error when the prefix is unknown" do
    system = Agency.spec_system
    tool_set = system.spawn(Agency::RouterEchoToolSet.new)
    router = system.spawn(Agency::ToolRouter.new({"fs" => tool_set}))

    promise = Movie::Promise(Agency::ToolResult).new
    receiver = system.spawn(Agency::RouterResultReceiver.new(promise))

    call = Agency::ToolCall.new("git.status", JSON.parse(%({})))
    router.tell_from(receiver, call)

    result = promise.future.await(1.second)
    result.content.includes?("Toolset not found").should be_true
  end
end
