require "./ametist/databuffer"
require "http/server"
require "json"
# Ametist is a vector database implementation in Crystal
#
struct Slice(T)
  def as_bytes() forall T
    bytes_per_element = sizeof(T)
    ptr = to_unsafe.as(UInt8*)
    Slice.new(ptr, size * bytes_per_element)
  end
end

module Ametist
  VERSION = "0.1.0"

  struct Caster(T)
    # Casts slice of bytes to slice of T
    def self.cast(bytes : Slice(UInt8) | Nil)
      return nil if bytes.nil?
      puts bytes.size
      ptr = bytes.to_unsafe.as(T*)
      ptr.value
    end
  end

  class TypeSchema
    include JSON::Serializable

    property name : String
    property size : Int32?

    def initialize(@name : String, @size : Int32?)
    end

  end

  class FieldSchema
    include JSON::Serializable

    property name : String
    property type : TypeSchema

    def initialize(@name : String, @type : TypeSchema)
    end
  end

  alias IntegerDataBuffer = DenseDataBuffer(Int32)
  alias FloatDataBuffer = DenseDataBuffer(Float32)

  alias BufferType = StringBuffer | IntegerDataBuffer | FloatDataBuffer | VectorBuffer

  abstract class BufferFactory
    abstract def create_buffer(field : FieldSchema) : BufferType
  end

  class StringBufferFactory < BufferFactory
    def create_buffer(field : FieldSchema) : StringBuffer
      StringBuffer.new(10)
    end
  end

  class IntegerBufferFactory < BufferFactory
    def create_buffer(field : FieldSchema) : IntegerDataBuffer
      IntegerDataBuffer.new(10)
    end
  end

  class FloatBufferFactory < BufferFactory
    def create_buffer(field : FieldSchema) : FloatDataBuffer
      FloatDataBuffer.new(10)
    end
  end

  class VectorBufferFactory < BufferFactory
    def create_buffer(field : FieldSchema) : VectorBuffer
      VectorBuffer.new(10, field.type.size || 64)
    end
  end

  class CollectionSchema
    include JSON::Serializable

    property name : String
    property fields : Array(FieldSchema)

    @@type_map : Hash(String, BufferFactory) = {
      "string" => StringBufferFactory.new,
      "vector" => VectorBufferFactory.new,
      "integer" => IntegerBufferFactory.new,
      "float" => FloatBufferFactory.new,
    } of String => BufferFactory

    def self.create_buffer(field : FieldSchema) : BufferType
      @@type_map[field.type.name].create_buffer(field)
    end

    def initialize(@name : String, @fields : Array(FieldSchema))
    end

  end

  class DocumentField
    getter name : String
    getter value : String | Float32 | Int32 | Array(Float32)

    def initialize(@name : String, @value : String | Float32 | Int32 | Array(Float32))
    end
  end

  class Document
    property id : Int32
    property fields : Array(DocumentField)

    def initialize(@id : Int32, @fields : Array(DocumentField))
    end
  end

  class Collection
    # Collection structure.
    # Collection stores documents by given shema in DataBuffers for columnar storage

    @data_buffers : Hash(String, BufferType) = Hash(String, BufferType).new
    @size : Int32 = 0

    getter size : Int32

    def initialize(@schema : CollectionSchema)
      @schema.fields.each do |field|
        @data_buffers[field.name] = CollectionSchema.create_buffer(field)
      end
    end

    def add(document : Document)
      document.fields.each do |field|
        schema = @schema.fields.find { |f| f.name == field.name }
        raise ArgumentError, "Field #{field.name} not found in schema" unless schema
        @data_buffers[field.name] << field.value.to_slice
      end
      @size += 1
    end

    def fields
      @data_buffers.keys
    end
  end
end

module FastAPI
  class Route
  end

  class FastAPI
    include HTTP::Handler

    def call(context)
      schema = Ametist::CollectionSchema.new("test", [] of Ametist::FieldSchema)
      context.response.content_type = "application/json"
      context.response.print schema.to_json
    end
  end
end

def main
  puts "Here will run cool vector database, i promice"

  server = HTTP::Server.new ([FastAPI::FastAPI.new])

  address = server.bind_tcp 9999
  puts "Listening on #{address}"
  server.listen
end


# main
