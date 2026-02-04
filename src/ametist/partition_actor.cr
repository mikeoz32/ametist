require "../movie"
require "./actor_protocol"
require "./collection"

module Ametist
  class PartitionActor < Movie::AbstractBehavior(PartitionMessage)
    def initialize(@partition_id : Int32, @collection : Collection)
    end

    def receive(message, ctx)
      case message
      when CollectionUpsert
        message.reply_to << @collection.upsert(message.document)
      when CollectionDelete
        message.reply_to << @collection.delete(message.id)
      when CollectionGet
        message.reply_to << @collection.get_by_id(message.id)
      when CollectionQuery
        message.reply_to << @collection.query(message.field, message.vector, message.k, message.filter)
      end

      Movie::Behaviors(PartitionMessage).same
    end
  end
end
