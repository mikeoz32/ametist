require "../spec_helper"
require "../../src/ametist"

describe "Ametist actor extension" do
  it "creates collection, upserts, and queries" do
    system = Movie::ActorSystem(Agency::SystemMessage).new(Movie::Behaviors(Agency::SystemMessage).same)
    ext = Ametist.get(system)

    schema = CollectionSchema.new("test", [
      FieldSchema.new("embedding", TypeSchema.new("vector", 2)),
      FieldSchema.new("label", TypeSchema.new("string", 0)),
    ])
    ext.create_collection(schema).await(1.second).should be_true

    doc1 = Document.new("v1", [
      DocumentField.new("embedding", [1.0_f32, 0.0_f32] of Float32),
      DocumentField.new("label", "one"),
    ])
    doc2 = Document.new("v2", [
      DocumentField.new("embedding", [0.0_f32, 1.0_f32] of Float32),
      DocumentField.new("label", "two"),
    ])
    ext.upsert("test", doc1).await(1.second).should be_true
    ext.upsert("test", doc2).await(1.second).should be_true

    filter = FilterTerm.new("label", FilterOp::Eq, "one")
    results = ext.query("test", "embedding", [1.0_f32, 0.0_f32], 1, filter).await(1.second)
    results.size.should eq(1)
    results.first.id.should eq("v1")
  end
end
