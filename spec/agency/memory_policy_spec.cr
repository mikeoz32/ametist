require "../spec_helper"
require "../../src/agency/memory_policy"

describe Agency::MemoryPolicy do
  it "uses defaults and allows overrides" do
    config = Movie::Config.builder
      .set("agency.memory.summary_token_threshold", 8000)
      .set("agency.memory.max_history", 50)
      .set("agency.memory.semantic_k", 5)
      .set("agency.memory.graph_k", 10)
      .set("agency.memory.project.semantic_k", 4)
      .set("agency.memory.user.graph_k", 2)
      .build

    policy = Agency::MemoryPolicy.from_config(config)

    policy.summary_token_threshold.should eq 8000

    policy.session.max_history.should eq 50
    policy.session.semantic_k.should eq 5
    policy.session.graph_k.should eq 10

    policy.project.semantic_k.should eq 4
    policy.project.graph_k.should eq 5

    policy.user.semantic_k.should eq 2
    policy.user.graph_k.should eq 2
  end

  it "merges named policy overrides with defaults" do
    config = Movie::Config.builder
      .set("agency.memory.summary_token_threshold", 8000)
      .set("agency.memory.semantic_k", 5)
      .set("agency.memory.graph_k", 10)
      .set("agency.memory.policies.explorer.semantic_k", 1)
      .set("agency.memory.policies.explorer.graph_k", 2)
      .set("agency.memory.policies.explorer.summary_token_threshold", 1200)
      .build

    policy = Agency::MemoryPolicy.from_config(config, "explorer")

    policy.summary_token_threshold.should eq 1200
    policy.session.semantic_k.should eq 1
    policy.session.graph_k.should eq 2
    policy.session.max_history.should eq 50
  end
end
