require "../spec_helper"
require "../../src/agency/memory/token_estimator"

describe Agency::TokenEstimator do
  it "estimates tokens by character count" do
    estimator = Agency::TokenEstimator.new
    estimator.estimate("hello").should eq 2
    estimator.estimate("hello world").should eq 3
    estimator.estimate("").should eq 0
  end
end
