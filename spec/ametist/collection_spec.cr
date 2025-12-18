require "../spec_helper"
require "../../src/ametist"

include Ametist

test_schema= CollectionSchema.new("test", [FieldSchema.new("embeddings", TypeSchema.new("vector", 2))])

describe Collection do
  it "should create a new collection" do
    collection = Collection.new(test_schema)
    collection.should_not be_nil
    collection.fields.size.should eq(1)
    collection.fields.should contain("embeddings")
    collection.size.should eq(0)
  end
  it "Should add documents" do
    collection = Collection.new(test_schema)
    collection.add(Document.new(1, [DocumentField.new("embeddings", [1.0, 2.0] of Float32)]))
    collection.size.should eq(1)
  end
end
