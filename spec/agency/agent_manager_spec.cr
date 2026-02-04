require "../spec_helper"
require "../../src/movie"
require "../../src/agency/agent_manager"
require "../../src/agency/llm_client"

module Agency
  class FixedLLMClient < LLMClient
    def initialize(@response : String)
      super("dummy-key")
    end

    def chat(messages : Array(Agency::Message), tools : Array(Agency::ToolSpec), model : String = "gpt-3.5-turbo") : String
      @response
    end
  end

  class ToolCaptureLLMClient < LLMClient
    def initialize(@channel : Channel(Array(String)), @response : String)
      super("dummy-key")
    end

    def chat(messages : Array(Agency::Message), tools : Array(Agency::ToolSpec), model : String = "gpt-3.5-turbo") : String
      @channel.send(tools.map(&.name))
      @response
    end
  end

  class NoopTool < Movie::AbstractBehavior(ToolCall)
    def receive(message, ctx)
      if sender = ctx.sender.as?(Movie::ActorRef(ToolResult))
        sender << ToolResult.new(message.id, message.name, "ok")
      end
      Movie::Behaviors(ToolCall).same
    end
  end
end

describe Agency::AgentManager do
  it "runs a prompt and returns a future" do
    graph_path = "/tmp/agency_agent_manager_graph_#{UUID.random}.sqlite3"
    context_path = "/tmp/agency_agent_manager_context_#{UUID.random}.sqlite3"
    config = Movie::Config.builder
      .set("agency.graph.db_path", graph_path)
      .set("agency.context.db_path", context_path)
      .build
    system = Movie::ActorSystem(Agency::SystemMessage).new(Movie::Behaviors(Agency::SystemMessage).same, config)
    Movie::Execution.get(system)
    client = Agency::FixedLLMClient.new({"type" => "final", "content" => "ok"}.to_json)
    manager = Agency::AgentManager.spawn(system, client, "gpt-3.5-turbo")
    future = manager.run("test prompt", "spec-session", "gpt-3.5-turbo")
    result = future.await(6.seconds)
    result.should eq("ok")
  end

  it "broadcasts tool updates to existing agents" do
    graph_path = "/tmp/agency_agent_manager_graph_#{UUID.random}.sqlite3"
    context_path = "/tmp/agency_agent_manager_context_#{UUID.random}.sqlite3"
    config = Movie::Config.builder
      .set("agency.graph.db_path", graph_path)
      .set("agency.context.db_path", context_path)
      .set("agency.agents.agent-1.allowed_tools", ["echo"])
      .build
    system = Movie::ActorSystem(Agency::SystemMessage).new(Movie::Behaviors(Agency::SystemMessage).same, config)
    Movie::Execution.get(system)
    channel = Channel(Array(String)).new(4)
    client = Agency::ToolCaptureLLMClient.new(channel, {"type" => "final", "content" => "ok"}.to_json)
    manager = Agency::AgentManager.spawn(system, client, "gpt-3.5-turbo")

    manager.run("first", "s1", "gpt-3.5-turbo", "agent-1").await(6.seconds)
    names1 = channel.receive
    names1.empty?.should be_true

    tool_spec = Agency::ToolSpec.new(
      "echo",
      "echo tool",
      JSON.parse(%({"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}))
    )
    manager.register_tool(tool_spec, Agency::NoopTool.new, "echo")

    manager.run("second", "s1", "gpt-3.5-turbo", "agent-1").await(6.seconds)
    names2 = channel.receive
    names2.includes?("echo").should be_true
  end

  it "does not expose tools without allowlist" do
    graph_path = "/tmp/agency_agent_manager_graph_#{UUID.random}.sqlite3"
    context_path = "/tmp/agency_agent_manager_context_#{UUID.random}.sqlite3"
    config = Movie::Config.builder
      .set("agency.graph.db_path", graph_path)
      .set("agency.context.db_path", context_path)
      .build
    system = Movie::ActorSystem(Agency::SystemMessage).new(Movie::Behaviors(Agency::SystemMessage).same, config)
    Movie::Execution.get(system)
    channel = Channel(Array(String)).new(2)
    client = Agency::ToolCaptureLLMClient.new(channel, {"type" => "final", "content" => "ok"}.to_json)
    manager = Agency::AgentManager.spawn(system, client, "gpt-3.5-turbo")

    tool_spec = Agency::ToolSpec.new(
      "echo",
      "echo tool",
      JSON.parse(%({"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}))
    )
    manager.register_tool(tool_spec, Agency::NoopTool.new, "echo")

    manager.run("third", "s1", "gpt-3.5-turbo", "agent-1").await(6.seconds)
    names = channel.receive
    names.empty?.should be_true
  end

  it "updates allowlist for existing agents" do
    graph_path = "/tmp/agency_agent_manager_graph_#{UUID.random}.sqlite3"
    context_path = "/tmp/agency_agent_manager_context_#{UUID.random}.sqlite3"
    config = Movie::Config.builder
      .set("agency.graph.db_path", graph_path)
      .set("agency.context.db_path", context_path)
      .build
    system = Movie::ActorSystem(Agency::SystemMessage).new(Movie::Behaviors(Agency::SystemMessage).same, config)
    Movie::Execution.get(system)
    channel = Channel(Array(String)).new(2)
    client = Agency::ToolCaptureLLMClient.new(channel, {"type" => "final", "content" => "ok"}.to_json)
    manager = Agency::AgentManager.spawn(system, client, "gpt-3.5-turbo")

    tool_spec = Agency::ToolSpec.new(
      "echo",
      "echo tool",
      JSON.parse(%({"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}))
    )
    manager.register_tool(tool_spec, Agency::NoopTool.new, "echo")

    manager.run("first", "s1", "gpt-3.5-turbo", "agent-1").await(6.seconds)
    names1 = channel.receive
    names1.empty?.should be_true

    manager.update_allowed_tools("agent-1", ["echo"]).await(6.seconds)
    manager.run("second", "s1", "gpt-3.5-turbo", "agent-1").await(6.seconds)
    names2 = channel.receive
    names2.includes?("echo").should be_true
  end
end
