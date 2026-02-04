require "../spec_helper"
require "../../src/agency/context_store"

describe Agency::ContextStore do
  it "stores and fetches session events" do
    path = "/tmp/agency_context_store_spec_#{UUID.random}.sqlite3"
    store = Agency::ContextStore.new(path)

    store.append_event("s1", "user", "hello")
    store.append_event("s1", "assistant", "hi there")
    store.append_event("s1", "tool", "ok", "echo", "tool-1")

    events = store.fetch_events("s1", 10)
    events.size.should eq(3)
    events.first[:role].should eq("user")
    events.last[:name].should eq("echo")
  end

  it "stores and retrieves summaries" do
    path = "/tmp/agency_context_store_summary_spec_#{UUID.random}.sqlite3"
    store = Agency::ContextStore.new(path)

    store.store_summary("s1", "summary")
    store.get_summary("s1").should eq("summary")
  end
end
