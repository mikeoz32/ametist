require "./movie"
require "./ametist/databuffer"
require "./ametist/filter"
require "./ametist/collection"
require "./ametist/actor_protocol"
require "./ametist/collection_actor"
require "./ametist/partition_actor"
require "./ametist/manager_actor"
require "./ametist/result_receiver"
require "./ametist/manager"
require "./ametist/extension"
require "http/server"
require "json"
require "./lfapi"

# Ametist is a vector database implementation in Crystal.
struct Slice(T)
  def as_bytes() forall T
    bytes_per_element = sizeof(T)
    ptr = to_unsafe.as(UInt8*)
    Slice.new(ptr, size * bytes_per_element)
  end
end

module Ametist
  VERSION = "0.1.0"
end
