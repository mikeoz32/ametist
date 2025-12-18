class String
  def to_vector
    Slice(Int32).new(chars.to_unsafe().as(Pointer(Int32)), size.as(Int))
  end
end

module Ametist

  def self.cosine_similarity(vector1 : Slice(Float32), vector2 : Slice(Float32))
    # Cosine similarity between two vectors
    # calculated as dot product of normalized vectors
    raise "Vector size mismatch" unless vector1.size == vector2.size
    dot_product = vector1.zip(vector2).sum { |a, b| a * b }
    magnitude1 = Math.sqrt(vector1.sum { |x| x ** 2 })
    magnitude2 = Math.sqrt(vector2.sum { |x| x ** 2 })
    dot_product / (magnitude1 * magnitude2)
  end

  alias BufferIndex = NamedTuple(offset: Int32, size: Int32, deleted: Bool)

  enum UpdateStrategy
    Append # Append new data to the end of the buffer and mark previous data as deleted
    Replace # Replace existing data at a specific index
  end

  class DataBuffer(T)
    # Data buffer, store data with dense or sparse types, eg Int32 or String
    # Append only
    # TODO: mark deleted strings, update operation will be delete + insert updated but for same index
    # eg index is [{0,5},{5,5},{10,5}]  after update of second string
    # index will be [{0,5},{15,5},{10,5}]
    #
    # TODO: DataBuffer should be able to save and load data from IO instances (for saving on disk or streaming to network)
    #
    # capacity - maximum amount of type T that can be stored in the buffer
    # size - amount of slices of type T stored in the buffer
    # position - amount items of type T stored in the buffer
    getter capacity : Int32
    getter size : Int32
    getter buffer : Slice(T)

    def initialize(capacity : Int32)
      @capacity = capacity
      @size = 0
      @position = 0
      @index = Array(BufferIndex).new() # offset, size, deleted
      @buffer = Slice(T).new(capacity)
      @update_strategy = UpdateStrategy::Append
    end

    private def grow_if_needed
      return unless should_grow?
      grow new_size
    end

    protected def new_size
      @capacity *= 2
      @capacity * bytes_size
    end

    def bytes_size
      @index.sum { |tuple| tuple[:size] }
    end

    protected def should_grow?
      @position >= @capacity - 2
    end

    protected def grow(size : Int32)
      buf = Slice(T).new(size)
      @buffer.copy_to(buf)
      @buffer = buf
    end

    def slice_valid?(value : Slice(T))
      true
    end

    protected def do_append(value : Slice(T))
      unless slice_valid?(value)
        raise ArgumentError.new("Invalid Value")
      end

      grow_if_needed

      offset = @position
      dest = @buffer[offset...offset + value.size]
      dest.copy_from(value)
      @position += value.size
      @size += 1
      {offset: offset, size: value.size, deleted: false}
    end

    def append(value : Slice(T))
      @index << do_append(value)
    end

    def update_at_replace(idx : Int32, value : Slice(T))
      raise ArgumentError.new("Wrong Behavior") if @update_strategy == UpdateStrategy::Append
      index = @index[idx]
      dest = @buffer[index[:offset]...index[:offset] + index[:size]]
      dest.copy_from(value)
    end

    def update_at_append(idx : Int32, value : Slice(T))
      raise ArgumentError.new("Wrong Behavior") if @update_strategy == UpdateStrategy::Replace
      delete_at(idx)
      @index[idx] = do_append(value)
    end

    def <<(value : Slice(T))
      append(value)
    end

    def delete_at(idx : Int32)
      index = @index[idx]
      @index[idx] = {offset: index[:offset], size: index[:size], deleted: true}
      # Do not decrease size due to size is size of items existing in buffer
      # Amounts of items that are available to clients should be calculated from index
    end

    def slice_at(index : Int32)
      index = @index[index]
      return nil if index[:deleted]
      @buffer[index[:offset], index[:size]]
    end

    def [](index : Int32)
      slice_at(index)
    end

    def deleted?(index : Int32)
      index = @index[index]
      index[:deleted]
    end
  end

  class DenseDataBuffer(T) < DataBuffer(T)

    def initialize(capacity : Int32, @dimension : Int32 = 1)
      super(capacity * @dimension)
      @update_strategy = UpdateStrategy::Replace
    end

    def slice_valid?(value : Slice(T))
      value.size == @dimension
    end

  end

  class StringBuffer < DataBuffer(Int32)
    def append(value : String)
      append value.to_vector()
    end


    def update_at_append(idx : Int32, value : String)
      update_at_append idx, value.to_vector()
    end

    def string_at(index : Int32)
      slice = slice_at(index)
      if slice.nil?
        nil
      else
        slice.map(&.chr).join
      end
    end
  end

  class VectorBuffer < DenseDataBuffer(Float32)
    def each(&)
      @size.times do |i|
        slice = slice_at(i)
        next if slice.nil?
        yield slice, i
      end
    end

    def search(query_vector : Slice(Float32), k : Int32)
      # Todo make this one parallel using Parallel Execution context
      raise "Query vector size mismatch" unless query_vector.size == @dimension
      results = Array(Tuple(Float32, Int32)).new()
      each do |vector, index|
        similarity = Ametist.cosine_similarity(query_vector, vector)
        results << {similarity, index}
      end
      results.sort_by { |result| -result[0] }[0...k]
    end
  end

end
