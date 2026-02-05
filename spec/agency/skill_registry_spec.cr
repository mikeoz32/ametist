require "../spec_helper"
require "../../src/agency/skills/registry"

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

private class ReplyActor(T) < Movie::AbstractBehavior(T)
  def initialize(@promise : Movie::Promise(T))
  end

  def receive(message, ctx)
    @promise.try_success(message)
    ctx.stop
    Movie::Behaviors(T).same
  end
end

describe Agency::SkillRegistry do
  it "reloads skills on demand" do
    system = Agency.spec_system
    source = MutableSkillSource.new
    source.set([Agency::Skill.new("s1", "first", "", [] of Agency::ToolSpec)])

    registry = system.spawn(Agency::SkillRegistry.behavior(source))

    reply = Movie::Promise(Array(Agency::Skill)).new
    reply_ref = system.spawn(ReplyActor(Array(Agency::Skill)).new(reply))
    registry << Agency::GetAllSkills.new(reply_ref)
    reply.future.await(2.seconds).map(&.id).should eq(["s1"])

    source.set([Agency::Skill.new("s2", "second", "", [] of Agency::ToolSpec)])
    reload = Movie::Promise(Bool).new
    reload_ref = system.spawn(ReplyActor(Bool).new(reload))
    registry << Agency::ReloadSkills.new(reload_ref)
    reload.future.await(2.seconds).should be_true

    reply = Movie::Promise(Array(Agency::Skill)).new
    reply_ref = system.spawn(ReplyActor(Array(Agency::Skill)).new(reply))
    registry << Agency::GetAllSkills.new(reply_ref)
    reply.future.await(2.seconds).map(&.id).should eq(["s2"])
  end
end
