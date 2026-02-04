require "../movie"
require "./actor_protocol"
require "./collection"
require "./partition_actor"

module Ametist
  class CollectionActor < Movie::AbstractBehavior(CollectionMessage)
    class MappingReply < Movie::AbstractBehavior(Bool)
      def initialize(
        @reply_to : Movie::ActorRef(Bool),
        @collection : Movie::ActorRef(CollectionMessage),
        @id : String,
        @partition : Int32,
        @record : Bool
      )
      end

      def receive(message, ctx)
        if message
          if @record
            @collection << RecordLocation.new(@id, @partition)
          else
            @collection << RemoveLocation.new(@id)
          end
        end
        @reply_to << message
        ctx.stop
        Movie::Behaviors(Bool).same
      end
    end

    class QueryCollector < Movie::AbstractBehavior(Array(QueryResult))
      def initialize(@expected : Int32, @reply_to : Movie::ActorRef(Array(QueryResult)), @k : Int32)
        @results = [] of QueryResult
        @received = 0
      end

      def receive(message, ctx)
        @results.concat(message)
        @received += 1
        if @received >= @expected
          merged = @results.sort_by { |item| -item.score }.first(@k)
          @reply_to << merged
          ctx.stop
        end
        Movie::Behaviors(Array(QueryResult)).same
      end
    end

    def self.behavior(
      name : String,
      schema : CollectionSchema,
      partitions : Int32,
      shard_key : String?,
      shard_strategy : ShardStrategy?,
      supervision : Movie::SupervisionConfig = Movie::SupervisionConfig.default
    ) : Movie::AbstractBehavior(CollectionMessage)
      Movie::Behaviors(CollectionMessage).setup do |ctx|
        count = partitions < 1 ? 1 : partitions
        refs = Array(Movie::ActorRef(PartitionMessage)).new
        count.times do |idx|
          collection = Collection.new(schema)
          refs << ctx.spawn(
            PartitionActor.new(idx, collection),
            Movie::RestartStrategy::RESTART,
            supervision,
            "partition-#{idx}"
          )
        end
        CollectionActor.new(name, schema, refs, shard_key, shard_strategy)
      end
    end

    def initialize(
      @name : String,
      @schema : CollectionSchema,
      @partitions : Array(Movie::ActorRef(PartitionMessage)),
      @shard_key : String?,
      @shard_strategy : ShardStrategy?
    )
      @id_to_partition = {} of String => Int32
    end

    def receive(message, ctx)
      case message
      when CollectionUpsert
        partition_idx = partition_for_document(message.document)
        proxy = ctx.spawn(
          MappingReply.new(message.reply_to, ctx.ref.as(Movie::ActorRef(CollectionMessage)), message.document.id, partition_idx, true),
          Movie::RestartStrategy::STOP,
          Movie::SupervisionConfig.default
        )
        @partitions[partition_idx] << CollectionUpsert.new(message.document, proxy)
      when CollectionDelete
        partition_idx = partition_for_id(message.id)
        proxy = ctx.spawn(
          MappingReply.new(message.reply_to, ctx.ref.as(Movie::ActorRef(CollectionMessage)), message.id, partition_idx, false),
          Movie::RestartStrategy::STOP,
          Movie::SupervisionConfig.default
        )
        @partitions[partition_idx] << CollectionDelete.new(message.id, proxy)
      when CollectionGet
        partition_idx = partition_for_id(message.id)
        @partitions[partition_idx] << message
      when CollectionQuery
        collector = ctx.spawn(
          QueryCollector.new(@partitions.size, message.reply_to, message.k),
          Movie::RestartStrategy::STOP,
          Movie::SupervisionConfig.default
        )
        @partitions.each do |partition|
          partition << CollectionQuery.new(message.field, message.vector, message.k, collector, message.filter)
        end
      when RecordLocation
        @id_to_partition[message.id] = message.partition
      when RemoveLocation
        @id_to_partition.delete(message.id)
      end

      Movie::Behaviors(CollectionMessage).same
    end

    private def partition_for_id(id : String) : Int32
      if idx = @id_to_partition[id]?
        return idx
      end
      hash_index(id)
    end

    private def partition_for_document(document : Document) : Int32
      key = @shard_key
      return partition_for_id(document.id) if key.nil? || key == "id"
      if field = document.fields[key]?
        value = field.value
        case value
        when String, Int32, Float32
          return partition_for_scalar(value)
        else
          return partition_for_id(document.id)
        end
      end
      partition_for_id(document.id)
    end

    private def partition_for_scalar(value : String | Float32 | Int32) : Int32
      hash_index(value)
    end

    private def hash_index(value) : Int32
      ((value.hash.to_u64) % @partitions.size.to_u64).to_i32
    end
  end
end
