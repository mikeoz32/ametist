require "../spec_helper"
require "../../src/agency/vector_store_extension"
require "../../src/ametist"

describe Agency::VectorStoreExtension do
  it "upserts embeddings and queries top k with filters" do
    system = Agency.spec_system
    ametist = Ametist.get(system)

    schema = Ametist::CollectionSchema.new("memories", [
      Ametist::FieldSchema.new("embedding", Ametist::TypeSchema.new("vector", 2)),
      Ametist::FieldSchema.new("tag", Ametist::TypeSchema.new("string", 0)),
    ])
    ametist.create_collection(schema).await(1.second).should be_true

    store = Agency::VectorStoreExtensionId.get(system)

    store.upsert_embedding("memories", "a", [1.0_f32, 0.0_f32], {"tag" => "alpha"}).await(1.second).should be_true
    store.upsert_embedding("memories", "b", [0.0_f32, 1.0_f32], {"tag" => "beta"}).await(1.second).should be_true

    filter = Ametist::FilterTerm.new("tag", Ametist::FilterOp::Eq, "alpha")
    results = store.query_top_k("memories", [1.0_f32, 0.0_f32], 1, filter).await(1.second)
    results.size.should eq(1)
    results.first.id.should eq("a")
  end
end
