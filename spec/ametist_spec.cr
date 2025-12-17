require "./spec_helper"
require "../src/ametist"

include Ametist

describe Ametist do
  describe "DataBuffer" do
    it "Should grow buffer when needed" do
      buffer = DataBuffer(Int32).new(4)
      buffer.capacity.should eq(4)
      buffer.append(Int32.slice(1))
      buffer.append(Int32.slice(2))
      buffer.append(Int32.slice(3))
      buffer.append(Int32.slice(4))
      buffer.capacity.should eq(8)

      buffer.slice_at(2).should eq Int32.slice(3)
    end
    it "Floats also should work" do
      buffer = DataBuffer(Float32).new(4)
      buffer.capacity.should eq(4)
      buffer.append(Float32.slice(1.0))
      buffer.append(Float32.slice(2.0))
      buffer.append(Float32.slice(3.0))
      buffer.append(Float32.slice(4.0))
      buffer.capacity.should eq(8)

      buffer.slice_at(2).should eq Float32.slice(3.0)
    end
    it "And dynamic lists of floats also" do
      buffer = DataBuffer(Float32).new(4)
      buffer.capacity.should eq(4)
      buffer.append(Float32.slice(1.0, 2.0))
      buffer.append(Float32.slice(3.0))
      buffer.append(Float32.slice(4.0, 5.0, 6.0))
      buffer.capacity.should eq(8)

      buffer.slice_at(1).should eq Float32.slice(3.0)
      buffer.slice_at(2).should eq Float32.slice(4.0, 5.0, 6.0)
    end
    it "Should delete data" do
      buffer = DataBuffer(Float32).new(4)
      buffer.append(Float32.slice(1.0, 2.0))
      buffer.append(Float32.slice(3.0))
      buffer.append(Float32.slice(4.0, 5.0, 6.0))
      buffer.slice_at(1).should eq Float32.slice(3.0)
      buffer.delete_at(1)

      buffer.deleted?(1).should be_true
      buffer.slice_at(1).should be_nil
      buffer.slice_at(2).should eq Float32.slice(4.0, 5.0, 6.0)
    end
    it "And also even could do like this" do
      int_buf = DenseDataBuffer(UInt8).new(10, sizeof(UInt32))
      int_buf.append(UInt32.slice(20200100).as_bytes())

      Ametist::Caster(UInt32).cast(int_buf.slice_at(0)).should eq (20200100)
    end
  end
  describe "StringBuffer" do
    it "Should store strings" do
      str = "Some String"
      stb = Ametist::StringBuffer.new(100)
      stb.append(str)
      stb.append("Привіт")
      stb.string_at(0).should eq str
      stb.string_at(1).should eq "Привіт"
    end

    it "Should update" do
      str = "Some String"
      stb = Ametist::StringBuffer.new(100)
      stb.append(str)
      stb.append("Привіт")
      stb.update_at_append(1, "Hi!")
      stb.string_at(1).should eq "Hi!"
    end
  end
  describe "VectorBuffer" do
    it "Should store and search" do
      vb = Ametist::VectorBuffer.new(30, 5)
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
      vb.search(Float32.slice(1.0, 2.0, 3.0, 4.0, 5.0), 10).size.should eq(10)
    end
    it "Should update" do
      vb = Ametist::VectorBuffer.new(30, 5)
      vb.append(Float32.slice(1.0, 2.0, 3.0, 4.0, 5.0))
      vb.append(Float32.slice(1.0, 2.0, 3.0, 4.0, 5.1))
      vb.update_at_replace(0, Float32.slice(1.0, 2.0, 3.0, 4.0, 6.0))
      vb.slice_at(0).should eq Float32.slice(1.0, 2.0, 3.0, 4.0, 6.0)
    end
  end
  it "Should extend string" do
    slice ="Test".to_vector
  end
end
