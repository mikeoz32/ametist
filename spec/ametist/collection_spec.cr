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
    collection.add(Document.new(1, [
      DocumentField.new("embeddings", [1.0, 2.0] of Float32),
      DocumentField.new("int", 3),
      DocumentField.new("string", "hello"),
      DocumentField.new("float", 3.14)
    ]))
    collection.size.should eq(1)

    collection.get(0).should_not be_nil
    puts collection.get(0)["embeddings"]
    collection.get(0)["embeddings"].should eq([1.0, 2.0])
    collection.get(0)["int"].should eq(3)
    collection.get(0)["string"].should eq("hello")
    collection.get(0)["float"].should eq(Float32.new(3.14))
  end
end
