require "../spec_helper"
require "file_utils"
require "../../src/agency/runtime/env_loader"

private def with_tmpdir(prefix : String, &block : String ->)
  root = File.join(Dir.tempdir, "#{prefix}-#{UUID.random}")
  FileUtils.mkdir_p(root)
  begin
    yield root
  ensure
    FileUtils.rm_r(root)
  end
end

describe Agency::EnvLoader do
  it "parses .env key/value pairs" do
    with_tmpdir("agency-env") do |root|
      path = File.join(root, ".env")
      File.write(path, <<-ENV)
# comment
OPENAI_API_KEY=abc123
OPENAI_BASE_URL="http://localhost:11434/v1"
EMPTY=
export COPILOT_TOKEN=xyz
ENV

      env = Agency::EnvLoader.load(path)
      env["OPENAI_API_KEY"].should eq("abc123")
      env["OPENAI_BASE_URL"].should eq("http://localhost:11434/v1")
      env["EMPTY"].should eq("")
      env["COPILOT_TOKEN"].should eq("xyz")

      ENV["OPENAI_API_KEY"]?.should eq("abc123")
      ENV["OPENAI_BASE_URL"]?.should eq("http://localhost:11434/v1")
      ENV["EMPTY"]?.should eq("")
      ENV["COPILOT_TOKEN"]?.should eq("xyz")
    end
  end

  it "returns empty hash when file missing" do
    with_tmpdir("agency-env") do |root|
      env = Agency::EnvLoader.load(File.join(root, ".env"))
      env.empty?.should be_true
    end
  end
end
