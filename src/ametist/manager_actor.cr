require "../movie"
require "./actor_protocol"
require "./collection_actor"

module Ametist
  class AmetistManagerActor < Movie::AbstractBehavior(ManagerMessage)
    def self.behavior(
      partitions : Int32 = 1,
      supervision : Movie::SupervisionConfig = Movie::SupervisionConfig.default
    ) : Movie::AbstractBehavior(ManagerMessage)
      Movie::Behaviors(ManagerMessage).setup do |ctx|
        AmetistManagerActor.new(partitions < 1 ? 1 : partitions, supervision)
      end
    end

    def initialize(@default_partitions : Int32, @supervision : Movie::SupervisionConfig)
      @collections = {} of String => Movie::ActorRef(CollectionMessage)
    end

    def receive(message, ctx)
      case message
      when CreateCollection
        if @collections.has_key?(message.name)
          message.reply_to << false
        else
          count = message.partitions || @default_partitions
          shard_key = message.shard_key
          shard_strategy = message.shard_strategy || ShardStrategy::Hash
          ref = ctx.spawn(
            CollectionActor.behavior(message.name, message.schema, count, shard_key, shard_strategy, @supervision),
            Movie::RestartStrategy::RESTART,
            @supervision,
            "collection-#{message.name}"
          )
          @collections[message.name] = ref
          message.reply_to << true
        end
      when DropCollection
        if ref = @collections.delete(message.name)
          ref.send_system(Movie::STOP)
          message.reply_to << true
        else
          message.reply_to << false
        end
      when UpsertDocument
        if ref = @collections[message.collection]?
          ref << CollectionUpsert.new(message.document, message.reply_to)
        else
          message.reply_to << false
        end
      when DeleteDocument
        if ref = @collections[message.collection]?
          ref << CollectionDelete.new(message.id, message.reply_to)
        else
          message.reply_to << false
        end
      when GetDocument
        if ref = @collections[message.collection]?
          ref << CollectionGet.new(message.id, message.reply_to)
        else
          message.reply_to << nil
        end
      when QueryVector
        if ref = @collections[message.collection]?
          ref << CollectionQuery.new(message.field, message.vector, message.k, message.reply_to, message.filter)
        else
          message.reply_to << [] of QueryResult
        end
      end
      Movie::Behaviors(ManagerMessage).same
    end
  end
end
