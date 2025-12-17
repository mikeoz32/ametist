require "./ametist/databuffer"
require "http/server"
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

  struct Collection
    # Collection structure.
    # Collection stores documents
    def initialize()
    end
  end
end

module FastAPI
  class FastAPI
    include HTTP::Handler

    def call(context)
      context.response.content_type = "text/plain"
      context.response.print "FastAPI"
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
