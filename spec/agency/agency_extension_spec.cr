require "../spec_helper"
require "../../src/agency/agency_extension"
require "../../src/agency/skill_registry"

private class MutableSkillSource < Agency::SkillSource
  def initialize
    @skills = [] of Agency::Skill
  end

  def set(skills : Array(Agency::Skill))
    @skills = skills
  end

  def list_skills : Array(Agency::Skill)
    @skills
  end
end

private class ToolCaptureLLMClient < Agency::LLMClient
  def initialize(@channel : Channel(Array(String)), @response : String)
    super("dummy-key")
  end

  def chat(messages : Array(Agency::Message), tools : Array(Agency::ToolSpec), model : String = "gpt-3.5-turbo") : String
    @channel.send(tools.map(&.name))
    @response
  end
end

private class NoopTool < Movie::AbstractBehavior(Agency::ToolCall)
  def receive(message, ctx)
    if sender = ctx.sender.as?(Movie::ActorRef(Agency::ToolResult))
      sender << Agency::ToolResult.new(message.id, message.name, "ok")
    end
    Movie::Behaviors(Agency::ToolCall).same
  end
end

describe Agency::AgencyExtension do
  it "reloads skills via extension and manager" do
    system = Agency.spec_system
    client = Agency::LLMClient.new("dummy-key", "https://api.openai.com")
    source = MutableSkillSource.new
    source.set([Agency::Skill.new("s1", "first", "", [] of Agency::ToolSpec)])

    extension = Agency::AgencyExtension.new(system, client, "model", source)

    extension.list_skills.await(2.seconds).map(&.id).should eq(["s1"])

    source.set([Agency::Skill.new("s2", "second", "", [] of Agency::ToolSpec)])
    extension.rescan_skills_async.await(2.seconds).should be_true
    extension.list_skills.await(2.seconds).map(&.id).should eq(["s2"])

    source.set([Agency::Skill.new("s3", "third", "", [] of Agency::ToolSpec)])
    extension.manager.rescan_skills_async.await(2.seconds).should be_true
    extension.list_skills.await(2.seconds).map(&.id).should eq(["s3"])
  end

  it "updates allowlist for agents" do
    system = Agency.spec_system
    channel = Channel(Array(String)).new(2)
    client = ToolCaptureLLMClient.new(channel, {"type" => "final", "content" => "ok"}.to_json)
    source = MutableSkillSource.new
    extension = Agency::AgencyExtension.new(system, client, "gpt-3.5-turbo", source)

    tool_spec = Agency::ToolSpec.new(
      "echo",
      "echo tool",
      JSON.parse(%({"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}))
    )
    extension.register_tool(tool_spec, NoopTool.new, "echo")

    extension.run("first", "s1", "gpt-3.5-turbo", "agent-1").await(6.seconds)
    channel.receive.empty?.should be_true

    extension.update_allowed_tools("agent-1", ["echo"]).await(6.seconds)
    extension.run("second", "s1", "gpt-3.5-turbo", "agent-1").await(6.seconds)
    channel.receive.includes?("echo").should be_true
  end
end
