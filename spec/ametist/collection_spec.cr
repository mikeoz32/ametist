require "../spec_helper"
require "../../src/ametist"

include Ametist

test_schema= CollectionSchema.new("test", [
  FieldSchema.new("embeddings", TypeSchema.new("vector", 2)),
  FieldSchema.new("int", TypeSchema.new("integer", 0)),
  FieldSchema.new("string", TypeSchema.new("string", 0)),
  FieldSchema.new("float", TypeSchema.new("float", 0))
])

describe Collection do
  it "should create a new collection" do
    collection = Collection.new(test_schema)
    collection.should_not be_nil
    collection.fields.size.should eq(4)
    collection.fields.should contain("embeddings")
    collection.size.should eq(0)
  end
  it "Should add documents" do
    collection = Collection.new(test_schema)
    collection.add(Document.new("1", [
      DocumentField.new("embeddings", [1.0, 2.0] of Float32),
      DocumentField.new("int", 3),
      DocumentField.new("string", "hello"),
      DocumentField.new("float", 3.14)
    ]))
    collection.size.should eq(1)

    doc = collection.get(0)
    doc.should_not be_nil
    doc.not_nil!["embeddings"].should eq([1.0, 2.0])
    doc.not_nil!["int"].should eq(3)
    doc.not_nil!["string"].should eq("hello")
    doc.not_nil!["float"].should eq(Float32.new(3.14))
  end

  it "filters query results" do
    collection = Collection.new(test_schema)
    collection.add(Document.new("1", [
      DocumentField.new("embeddings", [1.0, 0.0] of Float32),
      DocumentField.new("int", 1),
      DocumentField.new("string", "alpha"),
      DocumentField.new("float", 1.0)
    ]))
    collection.add(Document.new("2", [
      DocumentField.new("embeddings", [0.0, 1.0] of Float32),
      DocumentField.new("int", 2),
      DocumentField.new("string", "beta"),
      DocumentField.new("float", 2.0)
    ]))

    filter = FilterAnd.new([
      FilterTerm.new("int", FilterOp::Gt, 1),
      FilterTerm.new("string", FilterOp::Contains, "et")
    ] of Filter)

    results = collection.query("embeddings", [0.0, 1.0] of Float32, 5, filter)
    results.size.should eq(1)
    results.first.id.should eq("2")
  end
end
