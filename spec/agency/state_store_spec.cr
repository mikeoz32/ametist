# spec/agency/state_store_spec.cr
require "../spec_helper"
require "../../src/agency/state_store"

describe Agency::StateStore do
  it "stores and retrieves a string value" do
    store = Agency::StateStore.new(":memory:")
    store.set("greeting", "hello")
    store.get("greeting").should eq "hello"
  end

  it "returns nil for non-existent keys" do
    store = Agency::StateStore.new(":memory:")
    store.get("non_existent").should be_nil
  end

  it "updates existing values" do
    store = Agency::StateStore.new(":memory:")
    store.set("greeting", "hello")
    store.set("greeting", "world")
    store.get("greeting").should eq "world"
  end
end
