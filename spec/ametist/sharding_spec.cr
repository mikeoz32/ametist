require "../spec_helper"

include Ametist

def shard_index(value, partitions : Int32) : Int32
  ((value.hash.to_u64) % partitions.to_u64).to_i32
end

def find_mismatch(ids : Array(T), keys : Array(U), partitions : Int32) forall T, U
  ids.each do |id|
    keys.each do |key|
      return {id, key} if shard_index(id, partitions) != shard_index(key, partitions)
    end
  end
  raise "Unable to find mismatch shard pair"
end

def find_split(values : Array(T), partitions : Int32) forall T
  values.each_with_index do |left, idx|
    (idx + 1).upto(values.size - 1) do |j|
      right = values[j]
      return {left, right} if shard_index(left, partitions) != shard_index(right, partitions)
    end
  end
  raise "Unable to find split shard pair"
end

describe "Ametist sharding" do
  it "routes by shard key and maps id to partition" do
    system = Movie::ActorSystem(Agency::SystemMessage).new(Movie::Behaviors(Agency::SystemMessage).same)
    ext = Ametist.get(system)

    schema = CollectionSchema.new("accounts", [
      FieldSchema.new("embedding", TypeSchema.new("vector", 2)),
      FieldSchema.new("user_id", TypeSchema.new("string", 0)),
    ])

    ext.create_collection(schema, 2, "user_id", ShardStrategy::Hash).await(1.second).should be_true

    pair = find_mismatch(
      ["id-a", "id-b", "id-c", "id-d"],
      ["user-a", "user-b", "user-c", "user-d"],
      2
    )

    id = pair[0]
    user = pair[1]

    doc = Document.new(id, [
      DocumentField.new("embedding", [1.0_f32, 0.0_f32] of Float32),
      DocumentField.new("user_id", user),
    ])

    ext.upsert("accounts", doc).await(1.second).should be_true

    fetched = ext.get("accounts", id).await(1.second)
    fetched.should_not be_nil
    fetched.not_nil!.id.should eq(id)
    fetched.not_nil!["user_id"].should eq(user)

    ext.delete("accounts", id).await(1.second).should be_true
    ext.get("accounts", id).await(1.second).should be_nil
  end

  it "merges query results across partitions" do
    system = Movie::ActorSystem(Agency::SystemMessage).new(Movie::Behaviors(Agency::SystemMessage).same)
    ext = Ametist.get(system)

    schema = CollectionSchema.new("vectors", [
      FieldSchema.new("embedding", TypeSchema.new("vector", 2)),
    ])

    ext.create_collection(schema, 2).await(1.second).should be_true

    split = find_split(["v1", "v2", "v3", "v4"], 2)
    id1 = split[0]
    id2 = split[1]

    shard_index(id1, 2).should_not eq(shard_index(id2, 2))

    ext.upsert("vectors", Document.new(id1, [
      DocumentField.new("embedding", [1.0_f32, 0.0_f32] of Float32),
    ])).await(1.second).should be_true

    ext.upsert("vectors", Document.new(id2, [
      DocumentField.new("embedding", [0.0_f32, 1.0_f32] of Float32),
    ])).await(1.second).should be_true

    results = ext.query("vectors", "embedding", [1.0_f32, 0.0_f32], 2).await(1.second)
    results.size.should eq(2)
    results.first.id.should eq(id1)
  end

  it "drops collections and rejects new writes" do
    system = Movie::ActorSystem(Agency::SystemMessage).new(Movie::Behaviors(Agency::SystemMessage).same)
    ext = Ametist.get(system)

    schema = CollectionSchema.new("drop-test", [
      FieldSchema.new("embedding", TypeSchema.new("vector", 2)),
    ])

    ext.create_collection(schema).await(1.second).should be_true
    ext.drop_collection("drop-test").await(1.second).should be_true

    doc = Document.new("v1", [
      DocumentField.new("embedding", [1.0_f32, 0.0_f32] of Float32),
    ])

    ext.upsert("drop-test", doc).await(1.second).should be_false
    ext.query("drop-test", "embedding", [1.0_f32, 0.0_f32], 1).await(1.second).should be_empty
  end

  it "supports integer shard keys" do
    system = Movie::ActorSystem(Agency::SystemMessage).new(Movie::Behaviors(Agency::SystemMessage).same)
    ext = Ametist.get(system)

    schema = CollectionSchema.new("accounts-int", [
      FieldSchema.new("embedding", TypeSchema.new("vector", 2)),
      FieldSchema.new("account_id", TypeSchema.new("integer", 0)),
    ])

    ext.create_collection(schema, 2, "account_id", ShardStrategy::Hash).await(1.second).should be_true

    pair = find_mismatch(
      ["id-a", "id-b", "id-c", "id-d"],
      [1, 2, 3, 4],
      2
    )

    id = pair[0]
    account_id = pair[1]

    doc = Document.new(id, [
      DocumentField.new("embedding", [1.0_f32, 0.0_f32] of Float32),
      DocumentField.new("account_id", account_id),
    ])

    ext.upsert("accounts-int", doc).await(1.second).should be_true

    fetched = ext.get("accounts-int", id).await(1.second)
    fetched.should_not be_nil
    fetched.not_nil!["account_id"].should eq(account_id)

    ext.delete("accounts-int", id).await(1.second).should be_true
  end

  it "supports float shard keys" do
    system = Movie::ActorSystem(Agency::SystemMessage).new(Movie::Behaviors(Agency::SystemMessage).same)
    ext = Ametist.get(system)

    schema = CollectionSchema.new("accounts-float", [
      FieldSchema.new("embedding", TypeSchema.new("vector", 2)),
      FieldSchema.new("score", TypeSchema.new("float", 0)),
    ])

    ext.create_collection(schema, 2, "score", ShardStrategy::Hash).await(1.second).should be_true

    pair = find_mismatch(
      ["id-a", "id-b", "id-c", "id-d"],
      [1.1_f32, 2.2_f32, 3.3_f32, 4.4_f32],
      2
    )

    id = pair[0]
    score = pair[1]

    doc = Document.new(id, [
      DocumentField.new("embedding", [1.0_f32, 0.0_f32] of Float32),
      DocumentField.new("score", score),
    ])

    ext.upsert("accounts-float", doc).await(1.second).should be_true

    fetched = ext.get("accounts-float", id).await(1.second)
    fetched.should_not be_nil
    fetched.not_nil!["score"].should eq(score)

    ext.delete("accounts-float", id).await(1.second).should be_true
  end
end
