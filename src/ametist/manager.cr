require "../movie"
require "../agency/system_message"
require "./collection"
require "./actor_protocol"
require "./manager_actor"
require "./result_receiver"

module Ametist
  class AmetistManager
    getter ref : Movie::ActorRef(ManagerMessage)

    def self.spawn(
      system : Movie::ActorSystem(Agency::SystemMessage),
      partitions : Int32 = 1,
      supervision : Movie::SupervisionConfig = Movie::SupervisionConfig.default
    ) : AmetistManager
      ref = system.spawn(AmetistManagerActor.behavior(partitions, supervision))
      new(system, ref)
    end

    def initialize(@system : Movie::ActorSystem(Agency::SystemMessage), @ref : Movie::ActorRef(ManagerMessage))
    end

    def create_collection(name : String, dimension : Int32) : Movie::Future(Bool)
      schema = CollectionSchema.new(name, [
        FieldSchema.new("vector", TypeSchema.new("vector", dimension)),
      ])
      create_collection(schema)
    end

    def create_collection(
      schema : CollectionSchema,
      partitions : Int32? = nil,
      shard_key : String? = nil,
      shard_strategy : ShardStrategy? = nil
    ) : Movie::Future(Bool)
      promise = Movie::Promise(Bool).new
      receiver = @system.spawn(ResultReceiver(Bool).new(promise))
      @ref << CreateCollection.new(schema.name, schema, receiver, partitions, shard_key, shard_strategy)
      promise.future
    end

    def drop_collection(name : String) : Movie::Future(Bool)
      promise = Movie::Promise(Bool).new
      receiver = @system.spawn(ResultReceiver(Bool).new(promise))
      @ref << DropCollection.new(name, receiver)
      promise.future
    end

    def upsert(collection : String, document : Document) : Movie::Future(Bool)
      promise = Movie::Promise(Bool).new
      receiver = @system.spawn(ResultReceiver(Bool).new(promise))
      @ref << UpsertDocument.new(collection, document, receiver)
      promise.future
    end

    def delete(collection : String, id : String) : Movie::Future(Bool)
      promise = Movie::Promise(Bool).new
      receiver = @system.spawn(ResultReceiver(Bool).new(promise))
      @ref << DeleteDocument.new(collection, id, receiver)
      promise.future
    end

    def get(collection : String, id : String) : Movie::Future(Document?)
      promise = Movie::Promise(Document?).new
      receiver = @system.spawn(ResultReceiver(Document?).new(promise))
      @ref << GetDocument.new(collection, id, receiver)
      promise.future
    end

    def query(
      collection : String,
      field : String,
      vector : Array(Float32),
      k : Int32,
      filter : Filter? = nil
    ) : Movie::Future(Array(QueryResult))
      promise = Movie::Promise(Array(QueryResult)).new
      receiver = @system.spawn(ResultReceiver(Array(QueryResult)).new(promise))
      @ref << QueryVector.new(collection, field, vector, k, receiver, filter)
      promise.future
    end

    def stop
      @ref.send_system(Movie::STOP)
    end
  end
end
