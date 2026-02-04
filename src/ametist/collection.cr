require "json"
require "./databuffer"
require "./filter"

module Ametist
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
    property id : String
    property fields : Hash(String, DocumentField)

    def initialize(@id : String, fields : Array(DocumentField))
      @fields = Hash(String, DocumentField).new
      fields.each do |field|
        @fields[field.name] = field
      end
    end

    def [](name : String)
      @fields[name].value
    end
  end

  class Collection
    @data_buffers : Hash(String, BufferType) = Hash(String, BufferType).new
    @field_schema : Hash(String, FieldSchema) = Hash(String, FieldSchema).new
    @id_to_index : Hash(String, Int32) = {} of String => Int32
    @ids : Array(String?) = [] of String?
    @size : Int32 = 0

    getter size : Int32
    getter schema : CollectionSchema

    def initialize(@schema : CollectionSchema)
      @schema.fields.each do |field|
        @data_buffers[field.name] = CollectionSchema.create_buffer(field)
        @field_schema[field.name] = field
      end
    end

    def add(document : Document) : Bool
      raise ArgumentError.new("Document id already exists") if @id_to_index.has_key?(document.id)
      idx = append_document(document)
      @id_to_index[document.id] = idx
      @ids[idx] = document.id
      @size += 1
      true
    end

    def upsert(document : Document) : Bool
      if existing = @id_to_index[document.id]?
        delete_at(existing)
        @id_to_index.delete(document.id)
        @ids[existing] = nil
        @size -= 1
      end
      idx = append_document(document)
      @id_to_index[document.id] = idx
      @ids[idx] = document.id
      @size += 1
      true
    end

    def delete(id : String) : Bool
      if idx = @id_to_index.delete(id)
        delete_at(idx)
        @ids[idx] = nil
        @size -= 1
        return true
      end
      false
    end

    def get(index : Int32) : Document?
      id = @ids[index]?
      return nil unless id
      build_document(id, index)
    end

    def get_by_id(id : String) : Document?
      return nil unless idx = @id_to_index[id]?
      build_document(id, idx)
    end

    def query(field : String, vector : Array(Float32), k : Int32, filter : Filter? = nil) : Array(QueryResult)
      return [] of QueryResult if k <= 0
      buffer = @data_buffers[field]?
      return [] of QueryResult unless buffer && buffer.is_a?(VectorBuffer)
      return [] of QueryResult unless vector.size == buffer.as(VectorBuffer).dimension

      query = Slice(Float32).new(vector.to_unsafe.as(Pointer(Float32)), vector.size.as(Int))
      scored = [] of Tuple(Float32, String)
      buffer.as(VectorBuffer).each do |entry, idx|
        id = @ids[idx]?
        next unless id
        next unless filter.nil? || matches_filter?(idx, filter.not_nil!)
        score = Ametist.cosine_similarity(query, entry)
        scored << {score, id}
      end

      scored.sort_by { |(score, _)| -score }
        .first(k)
        .map { |(score, id)| QueryResult.new(id, score) }
    end

    def fields
      @data_buffers.keys
    end

    private def append_document(document : Document) : Int32
      index = @ids.size
      @schema.fields.each do |field|
        doc_field = document.fields[field.name]? || raise ArgumentError.new("Missing field #{field.name}")
        append_value(field, doc_field.value)
      end
      @ids << document.id
      index
    end

    private def append_value(field : FieldSchema, value : String | Float32 | Int32 | Array(Float32))
      buffer = @data_buffers[field.name]
      case field.type.name
      when "integer"
        raise ArgumentError.new("Invalid value type for #{field.name}") unless value.is_a?(Int32)
        buffer.as(DenseDataBuffer(Int32)) << Int32.slice(value.as(Int32))
      when "float"
        raise ArgumentError.new("Invalid value type for #{field.name}") unless value.is_a?(Float32)
        buffer.as(DenseDataBuffer(Float32)) << Float32.slice(value.as(Float32))
      when "string"
        raise ArgumentError.new("Invalid value type for #{field.name}") unless value.is_a?(String)
        buffer.as(StringBuffer) << value.as(String)
      when "vector"
        raise ArgumentError.new("Invalid value type for #{field.name}") unless value.is_a?(Array(Float32))
        if field.type.size && value.as(Array(Float32)).size != field.type.size
          raise ArgumentError.new("Vector size mismatch for #{field.name}")
        end
        buffer.as(VectorBuffer).append(value.as(Array(Float32)))
      else
        raise ArgumentError.new("Invalid field type #{field.type.name} #{field.name}")
      end
    end

    private def delete_at(index : Int32)
      @schema.fields.each do |field|
        @data_buffers[field.name].delete_at(index)
      end
    end

    private def build_document(id : String, index : Int32) : Document
      fields = [] of DocumentField
      @schema.fields.each do |field|
        buffer = @data_buffers[field.name]
        value = case field.type.name
                when "integer"
                  slice = buffer.as(DenseDataBuffer(Int32)).slice_at(index)
                  raise ArgumentError.new("Invalid value") if slice.nil?
                  slice.as(Slice(Int32))[0]
                when "float"
                  slice = buffer.as(DenseDataBuffer(Float32)).slice_at(index)
                  raise ArgumentError.new("Invalid value") if slice.nil?
                  slice.as(Slice(Float32))[0]
                when "string"
                  buffer.as(StringBuffer).string_at(index) || ""
                when "vector"
                  buffer.as(VectorBuffer).vector_at(index)
                else
                  raise ArgumentError.new("Invalid field type #{field.type.name} #{field.name}")
                end
        fields << DocumentField.new(field.name, value)
      end
      Document.new(id, fields)
    end

    private def matches_filter?(index : Int32, filter : Filter) : Bool
      case filter
      when FilterAnd
        return true if filter.items.empty?
        filter.items.all? { |item| matches_filter?(index, item) }
      when FilterOr
        return false if filter.items.empty?
        filter.items.any? { |item| matches_filter?(index, item) }
      when FilterNot
        !matches_filter?(index, filter.item)
      when FilterTerm
        match_term?(index, filter)
      else
        true
      end
    end

    private def match_term?(index : Int32, term : FilterTerm) : Bool
      value = field_value_at(term.field, index)
      case term.op
      when FilterOp::Exists
        !value.nil?
      else
        return false if value.nil? || term.value.nil?
        apply_operator(value, term.op, term.value.not_nil!)
      end
    end

    private def field_value_at(field : String, index : Int32) : String | Float32 | Int32 | Array(Float32) | Nil
      schema = @field_schema[field]?
      return nil unless schema
      buffer = @data_buffers[field]?
      return nil unless buffer
      case schema.type.name
      when "integer"
        slice = buffer.as(DenseDataBuffer(Int32)).slice_at(index)
        return nil if slice.nil?
        slice.as(Slice(Int32))[0]
      when "float"
        slice = buffer.as(DenseDataBuffer(Float32)).slice_at(index)
        return nil if slice.nil?
        slice.as(Slice(Float32))[0]
      when "string"
        buffer.as(StringBuffer).string_at(index)
      when "vector"
        buffer.as(VectorBuffer).vector_at(index)
      else
        nil
      end
    end

    private def apply_operator(
      actual : String | Float32 | Int32 | Array(Float32),
      op : FilterOp,
      expected : FilterValue
    ) : Bool
      case op
      when FilterOp::Eq
        value_eq?(actual, expected)
      when FilterOp::Ne
        !value_eq?(actual, expected)
      when FilterOp::Lt
        numeric_compare(actual, expected) { |a, b| a < b }
      when FilterOp::Lte
        numeric_compare(actual, expected) { |a, b| a <= b }
      when FilterOp::Gt
        numeric_compare(actual, expected) { |a, b| a > b }
      when FilterOp::Gte
        numeric_compare(actual, expected) { |a, b| a >= b }
      when FilterOp::In
        value_in?(actual, expected)
      when FilterOp::Contains
        actual.is_a?(String) && expected.is_a?(String) && actual.includes?(expected)
      when FilterOp::StartsWith
        actual.is_a?(String) && expected.is_a?(String) && actual.starts_with?(expected)
      when FilterOp::EndsWith
        actual.is_a?(String) && expected.is_a?(String) && actual.ends_with?(expected)
      when FilterOp::Exists
        !actual.nil?
      else
        false
      end
    end

    private def value_eq?(actual : String | Float32 | Int32 | Array(Float32), expected : FilterValue) : Bool
      case actual
      when String
        expected.is_a?(String) && actual == expected
      when Int32
        if expected.is_a?(Int32)
          actual == expected
        elsif expected.is_a?(Float32)
          actual.to_f64 == expected.to_f64
        else
          false
        end
      when Float32
        if expected.is_a?(Float32)
          actual == expected
        elsif expected.is_a?(Int32)
          actual.to_f64 == expected.to_f64
        else
          false
        end
      when Array(Float32)
        expected.is_a?(Array(Float32)) && actual == expected
      else
        false
      end
    end

    private def numeric_compare(actual, expected, &block : Float64, Float64 -> Bool) : Bool
      a = numeric_value(actual)
      b = numeric_value(expected)
      return false unless a && b
      yield a, b
    end

    private def numeric_value(value) : Float64?
      case value
      when Int32
        value.to_f64
      when Float32
        value.to_f64
      else
        nil
      end
    end

    private def value_in?(actual : String | Float32 | Int32 | Array(Float32), expected : FilterValue) : Bool
      case expected
      when Array(String)
        actual.is_a?(String) && expected.includes?(actual)
      when Array(Int32)
        numeric_in?(actual, expected)
      when Array(Float32)
        numeric_in?(actual, expected)
      else
        false
      end
    end

    private def numeric_in?(actual, values : Array(Int32) | Array(Float32)) : Bool
      actual_num = numeric_value(actual)
      return false unless actual_num
      values.any? { |value| actual_num == value.to_f64 }
    end
  end

  class Database
    def initialize
      @collections = {} of String => Collection
    end

    def create_collection(name : String, schema : CollectionSchema)
      raise ArgumentError.new("Collection name already exists") if @collections.key?(name)
      @collections[name] = Collection.new(schema)
    end

    def get_collection(name : String)
      @collections[name]
    end
  end
end
