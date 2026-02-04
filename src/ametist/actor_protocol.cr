require "../movie"
require "./collection"
require "./filter"

module Ametist
  enum ShardStrategy
    Hash
  end

  struct QueryResult
    getter id : String
    getter score : Float32

    def initialize(@id : String, @score : Float32)
    end
  end

  struct CreateCollection
    getter name : String
    getter schema : CollectionSchema
    getter partitions : Int32?
    getter shard_key : String?
    getter shard_strategy : ShardStrategy?
    getter reply_to : Movie::ActorRef(Bool)

    def initialize(
      @name : String,
      @schema : CollectionSchema,
      @reply_to : Movie::ActorRef(Bool),
      @partitions : Int32? = nil,
      @shard_key : String? = nil,
      @shard_strategy : ShardStrategy? = nil
    )
    end
  end

  struct DropCollection
    getter name : String
    getter reply_to : Movie::ActorRef(Bool)

    def initialize(@name : String, @reply_to : Movie::ActorRef(Bool))
    end
  end

  struct UpsertDocument
    getter collection : String
    getter document : Document
    getter reply_to : Movie::ActorRef(Bool)

    def initialize(@collection : String, @document : Document, @reply_to : Movie::ActorRef(Bool))
    end
  end

  struct DeleteDocument
    getter collection : String
    getter id : String
    getter reply_to : Movie::ActorRef(Bool)

    def initialize(@collection : String, @id : String, @reply_to : Movie::ActorRef(Bool))
    end
  end

  struct GetDocument
    getter collection : String
    getter id : String
    getter reply_to : Movie::ActorRef(Document?)

    def initialize(@collection : String, @id : String, @reply_to : Movie::ActorRef(Document?))
    end
  end

  struct QueryVector
    getter collection : String
    getter field : String
    getter vector : Array(Float32)
    getter k : Int32
    getter reply_to : Movie::ActorRef(Array(QueryResult))
    getter filter : Filter?

    def initialize(
      @collection : String,
      @field : String,
      @vector : Array(Float32),
      @k : Int32,
      @reply_to : Movie::ActorRef(Array(QueryResult)),
      @filter : Filter? = nil
    )
    end
  end

  struct CollectionUpsert
    getter document : Document
    getter reply_to : Movie::ActorRef(Bool)

    def initialize(@document : Document, @reply_to : Movie::ActorRef(Bool))
    end
  end

  struct CollectionDelete
    getter id : String
    getter reply_to : Movie::ActorRef(Bool)

    def initialize(@id : String, @reply_to : Movie::ActorRef(Bool))
    end
  end

  struct CollectionGet
    getter id : String
    getter reply_to : Movie::ActorRef(Document?)

    def initialize(@id : String, @reply_to : Movie::ActorRef(Document?))
    end
  end

  struct CollectionQuery
    getter field : String
    getter vector : Array(Float32)
    getter k : Int32
    getter reply_to : Movie::ActorRef(Array(QueryResult))
    getter filter : Filter?

    def initialize(
      @field : String,
      @vector : Array(Float32),
      @k : Int32,
      @reply_to : Movie::ActorRef(Array(QueryResult)),
      @filter : Filter? = nil
    )
    end
  end

  struct RecordLocation
    getter id : String
    getter partition : Int32

    def initialize(@id : String, @partition : Int32)
    end
  end

  struct RemoveLocation
    getter id : String

    def initialize(@id : String)
    end
  end

  alias ManagerMessage = CreateCollection | DropCollection | UpsertDocument | DeleteDocument | GetDocument | QueryVector
  alias CollectionMessage = CollectionUpsert | CollectionDelete | CollectionGet | CollectionQuery | RecordLocation | RemoveLocation
  alias PartitionMessage = CollectionUpsert | CollectionDelete | CollectionGet | CollectionQuery
end
