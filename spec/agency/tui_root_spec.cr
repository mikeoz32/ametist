require "../spec_helper"
require "file_utils"
require "../../src/agency/tui_root"

private def with_tmpdir(prefix : String, &block : String ->)
  root = File.join(Dir.tempdir, "#{prefix}-#{UUID.random}")
  FileUtils.mkdir_p(root)
  begin
    yield root
  ensure
    FileUtils.rm_r(root)
  end
end

describe Agency::TuiRoot do

  it "routes prompts through the system root" do
    config = Movie::Config.builder
      .set("agency.llm.api_key", "dummy-key")
      .build
    system = Movie::ActorSystem(Agency::SystemMessage).new(Agency::TuiRoot.behavior, config)
    Movie::Execution.get(system)

    result = system.ask(Agency::TuiInput.new("hello"), String).await(3.seconds)
    result.includes?("Simulated response").should be_true
  end

  it "lists skills via the root" do
    with_tmpdir("agency-skill") do |root|
      skill_dir = File.join(root, ".claude", "skills", "demo")
      FileUtils.mkdir_p(skill_dir)
      File.write(File.join(skill_dir, "SKILL.md"), <<-MD)
---
name: demo-skill
description: Demo skill
---
# Demo
MD

      config = Movie::Config.builder
        .set("agency.llm.api_key", "dummy-key")
        .set("agency.skills.paths", [File.join(root, ".claude", "skills")])
        .build
      system = Movie::ActorSystem(Agency::SystemMessage).new(Agency::TuiRoot.behavior, config)
      Movie::Execution.get(system)

      response = system.ask(Agency::TuiListSkills.new, String).await(3.seconds)
      response.includes?("demo-skill").should be_true
    end
  end

  it "reloads skills via the root" do
    config = Movie::Config.builder
      .set("agency.llm.api_key", "dummy-key")
      .build
    system = Movie::ActorSystem(Agency::SystemMessage).new(Agency::TuiRoot.behavior, config)
    Movie::Execution.get(system)

    result = system.ask(Agency::TuiReloadSkills.new, String).await(3.seconds)
    result.should eq("skills reloaded")
  end
end
