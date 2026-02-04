# Ametist Vector Database - Actor-Based Architecture

This document outlines the actor-based architecture for Ametist vector database, leveraging the Movie actor framework for concurrency, distribution, and fault tolerance.

## Overview

Building Ametist fully with actors provides natural concurrency boundaries, built-in fault tolerance via supervision, and a clear path to distributed search across nodes using Movie's remoting capabilities.

## Core Actor Types

### 1. PartitionActor

Owns a subset of vectors (a partition/shard) and handles local search operations.

```crystal
record SearchRequest, query_vector : Array(Float32), k : Int32, request_id : String do
  include JSON::Serializable
end

record SearchResult, request_id : String, results : Array(ScoredDoc) do
  include JSON::Serializable
end

record InsertVector, id : String, vector : Array(Float32), metadata : Hash(String, String)? do
  include JSON::Serializable
end

class PartitionActor < Movie::AbstractBehavior(PartitionMessage)
  @vectors : Hash(String, Array(Float32))
  @index : HNSWIndex?  # Optional ANN index

  def receive(message : SearchRequest, context)
    results = search_local(message.query_vector, message.k)
    # Reply to sender with results
    context.sender.try &.<< SearchResult.new(message.request_id, results)
    Movie::Behaviors(PartitionMessage).same
  end

  def receive(message : InsertVector, context)
    @vectors[message.id] = message.vector
    @index.try &.add(message.id, message.vector)
    Movie::Behaviors(PartitionMessage).same
  end

  private def search_local(query : Array(Float32), k : Int32) : Array(ScoredDoc)
    # Brute-force or use index
    if index = @index
      index.search(query, k)
    else
      brute_force_search(query, k)
    end
  end
end
```

### 2. CollectionActor

Routes requests to partitions and coordinates scatter-gather operations.

```crystal
class CollectionActor < Movie::AbstractBehavior(CollectionMessage)
  @partitions : Array(Movie::ActorRef(PartitionMessage))
  @pending_searches : Hash(String, PendingSearch)

  def receive(message : SearchRequest, context)
    # Scatter to all partitions
    search_id = UUID.random.to_s
    @pending_searches[search_id] = PendingSearch.new(
      original_request: message,
      requester: context.sender,
      expected_responses: @partitions.size,
      received: [] of SearchResult
    )

    @partitions.each do |partition|
      partition << SearchRequest.new(message.query_vector, message.k, search_id)
    end

    Movie::Behaviors(CollectionMessage).same
  end

  def receive(message : SearchResult, context)
    # Gather results from partition
    if pending = @pending_searches[message.request_id]?
      pending.received << message

      if pending.received.size == pending.expected_responses
        # All responses received - merge and reply
        merged = merge_results(pending.received, pending.original_request.k)
        pending.requester.try &.<< merged
        @pending_searches.delete(message.request_id)
      end
    end

    Movie::Behaviors(CollectionMessage).same
  end

  private def merge_results(results : Array(SearchResult), k : Int32) : SearchResult
    # Merge and sort by score, take top-k
    all_docs = results.flat_map(&.results)
    sorted = all_docs.sort_by(&.score).reverse.first(k)
    SearchResult.new(results.first.request_id, sorted)
  end
end
```

### 3. SearchMerger (Optional Pattern)

For complex merging logic or when results need post-processing:

```crystal
class SearchMerger < Movie::AbstractBehavior(MergerMessage)
  def receive(message : MergeRequest, context)
    merged = weighted_merge(message.results, message.weights)
    context.sender.try &.<< MergeComplete.new(message.request_id, merged)
    Movie::Behaviors(MergerMessage).same
  end
end
```

## Architecture Diagram

```
                    ┌─────────────────┐
                    │  Client Request │
                    └────────┬────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │ CollectionActor │
                    │  (Coordinator)  │
                    └────────┬────────┘
                             │
           ┌─────────────────┼─────────────────┐
           │                 │                 │
           ▼                 ▼                 ▼
    ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
    │ PartitionActor│ │PartitionActor│ │PartitionActor│
    │  (Shard 0)   │ │  (Shard 1)   │ │  (Shard 2)   │
    └──────────────┘ └──────────────┘ └──────────────┘
           │                 │                 │
           ▼                 ▼                 ▼
    ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
    │ VectorBuffer │ │ VectorBuffer │ │ VectorBuffer │
    │ + HNSWIndex  │ │ + HNSWIndex  │ │ + HNSWIndex  │
    └──────────────┘ └──────────────┘ └──────────────┘
```

## Distributed Search with Remoting

Using Movie's remoting, partitions can live on different nodes:

```crystal
# Node 1: Collection coordinator
system1 = Movie::ActorSystem(String).new(
  Movie::Behaviors(String).same,
  name: "coordinator"
)
system1.enable_remoting("192.168.1.10", 9000)

# Get remote partition refs
partition1 = system1.actor_for(
  "movie.tcp://partition-node-1@192.168.1.11:9000/user/partition",
  PartitionMessage
)
partition2 = system1.actor_for(
  "movie.tcp://partition-node-2@192.168.1.12:9000/user/partition",
  PartitionMessage
)

# CollectionActor treats local and remote partitions identically
collection = system1.spawn(
  CollectionActor.new([partition1, partition2]),
  name: "collection"
)
```

## Benefits of Actor-First Design

| Aspect | Benefit |
|--------|---------|
| **Concurrency** | Each partition searches in parallel naturally |
| **Fault Tolerance** | Supervision restarts failed partitions; searches can timeout gracefully |
| **Backpressure** | Mailbox acts as natural buffer; can implement load shedding |
| **Distribution** | Same code works local or remote via Movie remoting |
| **Isolation** | Partition state is fully encapsulated; no shared mutable state |
| **Scalability** | Add partitions/nodes without changing search logic |

## Implementation Roadmap

### Phase 1: Local Actor-Based Search
- [ ] Define message types with `JSON::Serializable`
- [ ] Implement `PartitionActor` with brute-force search
- [ ] Implement `CollectionActor` with scatter-gather
- [ ] Add supervision for partition failures

### Phase 2: Indexing
- [ ] Implement HNSW index in Crystal
- [ ] Integrate index into `PartitionActor`
- [ ] Add index building/rebuilding messages
- [ ] Benchmark vs brute-force

### Phase 3: Persistence
- [ ] Add snapshot/restore messages to `PartitionActor`
- [ ] Implement write-ahead log for durability
- [ ] Recovery on actor restart

### Phase 4: Distributed Search
- [ ] Register message types with `MessageRegistry`
- [ ] Deploy partitions across nodes
- [ ] Add partition discovery/registration
- [ ] Implement timeout handling for remote partitions

### Phase 5: Advanced Features
- [ ] Filtering (metadata-based pre/post filtering)
- [ ] Hybrid search (vector + keyword)
- [ ] Replication for fault tolerance
- [ ] Dynamic rebalancing

## Configuration Example

```yaml
# ametist.yaml
name: ametist-cluster
partitions:
  count: 8
  index:
    type: hnsw
    m: 16
    ef_construction: 200
    ef_search: 50
remoting:
  enabled: true
  host: 0.0.0.0
  port: 9000
supervision:
  strategy: restart
  max-restarts: 3
  within: 1m
```

## Message Types Reference

```crystal
# Search operations
record SearchRequest, query_vector : Array(Float32), k : Int32, request_id : String
record SearchResult, request_id : String, results : Array(ScoredDoc)
record ScoredDoc, id : String, score : Float32

# CRUD operations
record InsertVector, id : String, vector : Array(Float32), metadata : Hash(String, String)?
record DeleteVector, id : String
record UpdateVector, id : String, vector : Array(Float32)

# Index operations
record RebuildIndex
record IndexStats, doc_count : Int32, index_size : Int64

# Partition management
record PartitionSnapshot, path : String
record PartitionRestore, path : String
```

## See Also

- [Movie Actor Framework](../src/movie/) - Core actor implementation
- [Movie Remoting](../src/movie/remote/) - Network transport for actors
- [Movie Config](../src/movie/config.cr) - Configuration system
