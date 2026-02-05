require "../spec_helper"
require "../../src/agency/llm/gateway"
require "../../src/agency/runtime/protocol"

describe Agency::LLMGateway do
  it "formats messages for logging" do
    messages = [
      Agency::Message.new(Agency::Role::System, "sys"),
      Agency::Message.new(Agency::Role::User, "hi"),
      Agency::Message.new(Agency::Role::Assistant, "yo"),
    ]

    formatted = Agency::LLMGateway.format_messages(messages)
    formatted.includes?("[system] sys").should be_true
    formatted.includes?("[user] hi").should be_true
    formatted.includes?("[assistant] yo").should be_true
  end
end
