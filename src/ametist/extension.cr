require "../movie"
require "../agency/system_message"
require "./collection"
require "./manager"

module Ametist
  class AmetistExtension < Movie::Extension
    getter manager : AmetistManager

    def initialize(@system : Movie::ActorSystem(Agency::SystemMessage), @partitions : Int32 = 1)
      @manager = AmetistManager.spawn(@system, @partitions)
    end

    def stop
      @manager.stop
    end

    def create_collection(
      schema : CollectionSchema,
      partitions : Int32? = nil,
      shard_key : String? = nil,
      shard_strategy : ShardStrategy? = nil
    ) : Movie::Future(Bool)
      @manager.create_collection(schema, partitions, shard_key, shard_strategy)
    end

    def create_collection(name : String, dimension : Int32) : Movie::Future(Bool)
      @manager.create_collection(name, dimension)
    end

    def upsert(collection : String, document : Document) : Movie::Future(Bool)
      @manager.upsert(collection, document)
    end

    def get(collection : String, id : String) : Movie::Future(Document?)
      @manager.get(collection, id)
    end

    def delete(collection : String, id : String) : Movie::Future(Bool)
      @manager.delete(collection, id)
    end

    def drop_collection(name : String) : Movie::Future(Bool)
      @manager.drop_collection(name)
    end

    def query(
      collection : String,
      field : String,
      vector : Array(Float32),
      k : Int32,
      filter : Filter? = nil
    ) : Movie::Future(Array(QueryResult))
      @manager.query(collection, field, vector, k, filter)
    end
  end

  class ExtensionId < Movie::ExtensionId(AmetistExtension)
    def create(system : Movie::AbstractActorSystem) : AmetistExtension
      actor_system = system.as?(Movie::ActorSystem(Agency::SystemMessage))
      raise "Ametist requires ActorSystem(Agency::SystemMessage)" unless actor_system
      partitions = actor_system.config.get_int("ametist.partitions", 1)
      AmetistExtension.new(actor_system, partitions)
    end
  end

  def self.get(system : Movie::AbstractActorSystem) : AmetistExtension
    ExtensionId.get(system)
  end
end
