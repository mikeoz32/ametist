require "../spec_helper"
require "file_utils"
require "../../src/agency/filesystem_skill_source"

private def write_skill(path : String, body : String)
  FileUtils.mkdir_p(path)
  File.write(File.join(path, "SKILL.md"), body)
end

private def with_tmpdir(prefix : String, &block : String ->)
  root = File.join(Dir.tempdir, "#{prefix}-#{UUID.random}")
  FileUtils.mkdir_p(root)
  begin
    yield root
  ensure
    FileUtils.rm_r(root)
  end
end

describe Agency::FilesystemSkillSource do
  it "loads skills from configured roots with front matter" do
    with_tmpdir("agency-skill") do |root|
      skill_dir = File.join(root, "project", ".claude", "skills", "demo")
      write_skill(skill_dir, <<-MD)
---
name: demo-skill
description: Demo skill
metadata:
  short-description: short
---
# Demo
Do the thing.
MD

      source = Agency::FilesystemSkillSource.new([File.join(root, "project", ".claude", "skills")])
      skills = source.list_skills
      skills.size.should eq(1)
      skill = skills.first
      skill.id.should eq("demo-skill")
      skill.description.should eq("Demo skill")
      skill.system_prompt.includes?("Do the thing").should be_true
    end
  end

  it "falls back to directory name when front matter missing" do
    with_tmpdir("agency-skill") do |root|
      skill_dir = File.join(root, "project", ".claude", "skills", "plain")
      write_skill(skill_dir, "Just text\n")

      source = Agency::FilesystemSkillSource.new([File.join(root, "project", ".claude", "skills")])
      skills = source.list_skills
      skills.size.should eq(1)
      skill = skills.first
      skill.id.should eq("plain")
      skill.description.should eq("")
      skill.system_prompt.includes?("Just text").should be_true
    end
  end

  it "uses short description when description missing" do
    with_tmpdir("agency-skill") do |root|
      skill_dir = File.join(root, "project", ".claude", "skills", "meta")
      write_skill(skill_dir, <<-MD)
---
name: meta-skill
metadata:
  short-description: Meta desc
---
# Meta
MD

      source = Agency::FilesystemSkillSource.new([File.join(root, "project", ".claude", "skills")])
      skills = source.list_skills
      skills.size.should eq(1)
      skills.first.description.should eq("Meta desc")
    end
  end

  it "prefers later roots when ids collide" do
    with_tmpdir("agency-skill") do |root|
      global_dir = File.join(root, "global", ".claude", "skills", "same")
      project_dir = File.join(root, "project", ".claude", "skills", "same")
      write_skill(global_dir, "---\nname: same\ndescription: global\n---\nGlobal\n")
      write_skill(project_dir, "---\nname: same\ndescription: project\n---\nProject\n")

      source = Agency::FilesystemSkillSource.new([
        File.join(root, "global", ".claude", "skills"),
        File.join(root, "project", ".claude", "skills"),
      ])
      skills = source.list_skills
      skills.size.should eq(1)
      skills.first.description.should eq("project")
    end
  end
end
