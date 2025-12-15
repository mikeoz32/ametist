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

  def self.cosine_similarity(vector1 : Slice(Float32), vector2 : Slice(Float32))
    # Cosine similarity between two vectors
    # calculated as dot product of normalized vectors
    raise "Vector size mismatch" unless vector1.size == vector2.size
    dot_product = vector1.zip(vector2).sum { |a, b| a * b }
    magnitude1 = Math.sqrt(vector1.sum { |x| x ** 2 })
    magnitude2 = Math.sqrt(vector2.sum { |x| x ** 2 })
    dot_product / (magnitude1 * magnitude2)
  end

  struct Caster(T)
    # Casts slice of bytes to slice of T
    def self.cast(bytes : Slice(UInt8))
      puts bytes.size
      ptr = bytes.to_unsafe.as(T*)
      ptr.value
    end
  end

  struct StringBuffer
    # Like vector buffer but for strings (and probably for orher types with variable length)
    # Append only
    # TODO: mark deleted strings, update operation will be delete + insert updated but for same index
    # eg index is [{0,5},{5,5},{10,5}]  after update of second string
    # index will be [{0,5},{15,5},{10,5}]
    #
    getter capacity : Int32
    getter size : Int32
    getter buffer : Slice(Int32)

    def initialize(capacity : Int32)
      # Size - amount of strings in the buffer
      # Capacity - maximum amount of integers that can be stored in the buffer
      # position - current position in the buffer
      @capacity = capacity
      @size = 0
      @position = 0
      @index = Array(Tuple(Int32, Int32)).new()
      @buffer = Slice(Int32).new(capacity)
    end

    def append(string : String)
      slice = Slice(Int32).new(string.chars.to_unsafe().as(Pointer(Int32)), string.size.as(Int))
      offset = @position
      @index << {offset, slice.size}
      dest = @buffer[offset, offset + slice.size]
      dest.copy_from(slice)
      @position += slice.size
      @size += 1
    end

    def slice_at(index : Int32)
      offset, size = @index[index]
      @buffer[offset, size]
    end

    def string_at(index : Int32)
      slice_at(index).map(&.chr).join
    end
  end

  struct VectorBuffer(T)
    # Append only buffer of floats grouped by sized size chunks
    # Dimension - Size of each vector in the buffer
    # size - Number of vectors in the buffer
    # capacity - Maximum number of vectors that can be stored in the buffer
    # buffer - Underlying buffer of floats (slice of memory in heap)
    getter dimension : Int32
    getter size : Int32
    getter capacity : Int32
    getter buffer : Slice(T)

   def initialize(dimension : Int32, capacity : Int32)
      @dimension = dimension
      @size = 0
      @capacity = capacity
      @buffer = Slice(T).new(capacity * dimension)
    end

    private def grow_if_needed
      return if @size < @capacity
      @capacity *= 2
      puts "Growing buffer #{@capacity}"
      buf = Slice(T).new(@capacity * @dimension)
      @buffer.copy_to(buf)
      @buffer = buf
    end

    def append(vector : Slice(T))
      raise "Vector size mismatch" unless vector.size == @dimension
      grow_if_needed

      @size += 1

      offset = (@size - 1) * @dimension
      dest = @buffer[offset, @dimension]
      dest.copy_from(vector)
    end

    def vector(index : Int32)
      raise "Index out of bounds" unless index >= 0 && index < @size
      @buffer[index * @dimension, @dimension]
    end

    def search(query_vector : Slice(Float32), k : Int32)
      # Todo make this one parallel using Parallel Execution context
      raise "Query vector size mismatch" unless query_vector.size == @dimension
      results = Array(Tuple(Float32, Int32)).new()
      each do |vector, index|
        similarity = Ametist.cosine_similarity(query_vector, vector)
        puts "Similarity: #{similarity}"
        results << {similarity, index}
      end
      results.sort_by { |r| -r[0] }[0...k]
    end

    def each(&)
      @size.times do |i|
        yield vector(i), i
      end
    end
  end

  abstract struct Column(T)
    # Column structure.
    # Column stores documents
    def initialize(@name : String)
      @buffer = VectorBuffer(UInt8).new(sizeof(T), 10)
    end
  end

  struct ColumnInt32 < Column(Int32)
  end

  struct ColumnInt64 < Column(Int64)
  end


  struct Collection
    # Collection structure.
    # Collection stores documents
    def initialize()
    end
  end
end

def main
  puts "Here will run cool vector database, i promice"
  vb = Ametist::VectorBuffer(Float32).new(5, 2)
  vb.append(Float32.slice(1.0, 2.0, 3.0, 4.0, 5.0))
  vb.append(Float32.slice(1.0, 2.0, 3.0, 4.0, 5.1))
  vb.append(Float32.slice(1.0, 2.0, 3.0, 4.0, 5.2))
  vb.append(Float32.slice(1.0, 2.0, 3.0, 4.0, 5.3))
  vb.append(Float32.slice(1.0, 2.0, 3.0, 4.0, 5.4))
  vb.append(Float32.slice(1.0, 2.0, 3.0, 4.0, 5.5))
  vb.append(Float32.slice(1.0, 2.0, 3.0, 4.0, 5.6))
  vb.append(Float32.slice(1.0, 2.0, 3.0, 4.0, 5.7))
  vb.append(Float32.slice(1.0, 2.0, 3.0, 4.0, 5.8))
  vb.append(Float32.slice(1.0, 2.0, 3.0, 4.0, 5.9))
  puts vb.inspect
  print(vb.search(Float32.slice(1.0, 2.0, 3.0, 4.0, 5.0), 10))

  int_buf = Ametist::VectorBuffer(UInt8).new(sizeof(UInt32), 10)
  int_buf.append(UInt32.slice(20200100).as_bytes())

  puts Ametist::Caster(UInt32).cast(int_buf.vector(0))

  str = "Some String"

  stb = Ametist::StringBuffer.new(100)
  stb.append(str)
  stb.append("Привіт")
  puts stb.inspect
  puts stb.string_at(0)
  puts stb.string_at(1)
end


main
