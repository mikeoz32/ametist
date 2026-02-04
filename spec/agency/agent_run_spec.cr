require "../spec_helper"
require "../../src/movie"
require "../../src/agency/agent_messages"
require "../../src/agency/agent_run"
require "../../src/agency/llm_gateway"
require "../../src/agency/llm_client"
require "../../src/agency/tool_set"
require "../../src/agency/context_builder"
require "../../src/agency/memory_actor"

module Agency
  class SequenceLLMClient < LLMClient
    def initialize(@responses : Array(String))
      super("dummy-key")
      @index = 0
    end

    def chat(messages : Array(Agency::Message), tools : Array(Agency::ToolSpec), model : String = "gpt-3.5-turbo") : String
      idx = @index
      @index += 1
      @responses[idx]? || @responses.last
    end
  end

  class RunResultReceiver < Movie::AbstractBehavior(SessionMessage)
    def initialize(@promise : Movie::Promise(Tuple(Bool, String)))
    end

    def receive(message, ctx)
      case message
      when RunCompleted
        @promise.try_success({true, message.content})
      when RunFailed
        @promise.try_success({false, message.error})
      end
      Movie::Behaviors(SessionMessage).same
    end
  end

  class RunDeltaReceiver < Movie::AbstractBehavior(SessionMessage)
    def initialize(@promise : Movie::Promise(Array(Agency::Message)))
    end

    def receive(message, ctx)
      case message
      when RunCompleted
        @promise.try_success(message.delta)
      when RunFailed
        @promise.try_success(message.delta)
      end
      Movie::Behaviors(SessionMessage).same
    end
  end

  class RecordingTool < Movie::AbstractBehavior(ToolCall)
    def initialize(@promise : Movie::Promise(String))
    end

    def receive(message, ctx)
      @promise.try_success(message.arguments.to_json)
      if sender = ctx.sender
        result = ToolResult.new(message.id, message.name, "ok")
        if ref = sender.as?(Movie::ActorRef(ToolResult))
          ref << result
        else
          Movie::Ask.success(sender, result)
        end
      end
      Movie::Behaviors(ToolCall).same
    end
  end
end

describe Agency::AgentRun do
  it "executes a tool call and completes" do
    tool_call = {"type" => "tool_call", "tool_calls" => [{"id" => "call-1", "name" => "echo", "arguments" => {"text" => "hi"}}]}.to_json
    final = {"type" => "final", "content" => "done"}.to_json

    system = Agency.spec_system
    executor = Movie::Execution.get(system)
    client = Agency::SequenceLLMClient.new([tool_call, final])
    llm_gateway = system.spawn(Agency::LLMGateway.behavior(client))
    tool_set = system.spawn(Agency::DefaultToolSet.new(executor))
    context_builder = system.spawn(Agency::ContextBuilder.new)

    tool_spec = Agency::ToolSpec.new(
      "echo",
      "echo tool",
      JSON.parse(%({"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}))
    )

    tool_promise = Movie::Promise(String).new
    tool_ref = system.spawn(Agency::RecordingTool.new(tool_promise))
    tool_set << Agency::ToolSetRegisterActor.new(tool_spec, tool_ref)

    result_promise = Movie::Promise(Tuple(Bool, String)).new
    receiver = system.spawn(Agency::RunResultReceiver.new(result_promise))

    system.spawn(
      Agency::AgentRun.behavior(
        receiver,
        "s1",
        "hello",
        llm_gateway,
        tool_set,
        [tool_spec],
        context_builder,
        "gpt-3.5-turbo",
        2,
        [] of Agency::Message
      )
    )

    tool_args = tool_promise.future.await(1.second)
    tool_args.includes?("\"text\":\"hi\"").should be_true

    result = result_promise.future.await(1.second)
    result[0].should be_true
    result[1].should eq("done")
  end

  it "fails when max steps is reached" do
    tool_call = {"type" => "tool_call", "tool_calls" => [{"id" => "call-1", "name" => "echo", "arguments" => {"text" => "hi"}}]}.to_json

    system = Agency.spec_system
    executor = Movie::Execution.get(system)
    client = Agency::SequenceLLMClient.new([tool_call, tool_call])
    llm_gateway = system.spawn(Agency::LLMGateway.behavior(client))
    tool_set = system.spawn(Agency::DefaultToolSet.new(executor))
    context_builder = system.spawn(Agency::ContextBuilder.new)

    tool_spec = Agency::ToolSpec.new(
      "echo",
      "echo tool",
      JSON.parse(%({"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}))
    )

    tool_promise = Movie::Promise(String).new
    tool_ref = system.spawn(Agency::RecordingTool.new(tool_promise))
    tool_set << Agency::ToolSetRegisterActor.new(tool_spec, tool_ref)

    result_promise = Movie::Promise(Tuple(Bool, String)).new
    receiver = system.spawn(Agency::RunResultReceiver.new(result_promise))

    system.spawn(
      Agency::AgentRun.behavior(
        receiver,
        "s1",
        "hello",
        llm_gateway,
        tool_set,
        [tool_spec],
        context_builder,
        "gpt-3.5-turbo",
        1,
        [] of Agency::Message
      )
    )

    tool_promise.future.await(1.second)
    result = result_promise.future.await(1.second)
    result[0].should be_false
    result[1].includes?("max steps").should be_true
  end

  it "stores assistant content instead of raw response payload" do
    final = {"type" => "final", "content" => "done"}.to_json

    system = Agency.spec_system
    executor = Movie::Execution.get(system)
    client = Agency::SequenceLLMClient.new([final])
    llm_gateway = system.spawn(Agency::LLMGateway.behavior(client))
    tool_set = system.spawn(Agency::DefaultToolSet.new(executor))
    context_builder = system.spawn(Agency::ContextBuilder.new)

    delta_promise = Movie::Promise(Array(Agency::Message)).new
    receiver = system.spawn(Agency::RunDeltaReceiver.new(delta_promise))

    system.spawn(
      Agency::AgentRun.behavior(
        receiver,
        "s1",
        "hello",
        llm_gateway,
        tool_set,
        [] of Agency::ToolSpec,
        context_builder,
        "gpt-3.5-turbo",
        2,
        [] of Agency::Message
      )
    )

    delta = delta_promise.future.await(1.second)
    assistant = delta.find { |msg| msg.role == Agency::Role::Assistant }
    assistant.should_not be_nil
    assistant.not_nil!.content.should eq("done")
  end
end
