require "../spec_helper"
require "../../src/agency/graph_store"

describe Agency::GraphStore do
  it "adds and retrieves nodes and neighbors" do
    path = "/tmp/agency_graph_store_spec_#{UUID.random}.sqlite3"
    store = Agency::GraphStore.new(path)

    store.add_node("n1", "user", "Alice")
    store.add_node("n2", "doc", "Doc1")
    store.add_edge("e1", "n1", "n2", "owns", "meta")

    node = store.get_node("n1")
    node.should_not be_nil
    node.not_nil!.type.should eq("user")

    neighbors = store.neighbors("n1")
    neighbors.size.should eq(1)
    neighbors.first.id.should eq("n2")
  end
end
