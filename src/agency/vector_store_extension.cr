require "../movie"
require "../ametist"

module Agency
  alias VectorMetadataValue = String | Int32 | Float32

  # Vector store wrapper around Ametist.
  class VectorStoreExtension < Movie::Extension
    getter store : Ametist::AmetistExtension

    def initialize(@system : Movie::AbstractActorSystem)
      @store = Ametist.get(@system)
    end

    def stop
      # Ametist extension managed by Movie registry.
    end

    def upsert_embedding(
      collection : String,
      id : String,
      vector : Array(Float32),
      metadata : Hash(String, VectorMetadataValue)? = nil,
      vector_field : String = "embedding"
    ) : Movie::Future(Bool)
      fields = [] of Ametist::DocumentField
      fields << Ametist::DocumentField.new(vector_field, vector)
      if metadata
        metadata.each do |name, value|
          fields << Ametist::DocumentField.new(name, value)
        end
      end
      document = Ametist::Document.new(id, fields)
      @store.upsert(collection, document)
    end

    def query_top_k(
      collection : String,
      vector : Array(Float32),
      k : Int32,
      filter : Ametist::Filter? = nil,
      vector_field : String = "embedding"
    ) : Movie::Future(Array(Ametist::QueryResult))
      @store.query(collection, vector_field, vector, k, filter)
    end
  end

  class VectorStoreExtensionId < Movie::ExtensionId(VectorStoreExtension)
    def create(system : Movie::AbstractActorSystem) : VectorStoreExtension
      VectorStoreExtension.new(system)
    end
  end
end
