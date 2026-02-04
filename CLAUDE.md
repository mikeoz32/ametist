# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Working Guidelines

**Always check documentation before giving suggestions.** Use Context7 or web search to look up Crystal stdlib APIs, library documentation, and best practices before proposing implementations. This ensures suggestions align with established patterns and current API specifications.

## Build and Test Commands

```bash
# Build all targets
shards build

# Build specific target
crystal build src/bin/ametist.cr -Dpreview_mt -Dexecution_context

# Run tests
crystal spec

# Run single test file
crystal spec spec/movie_spec.cr

# Run tests with multithreading flags (required for actor/stream tests)
crystal spec -Dpreview_mt -Dexecution_context

# Run examples
crystal run examples/remoting_example.cr -Dpreview_mt -Dexecution_context
crystal run examples/config_example.cr -Dpreview_mt -Dexecution_context
```

**Required compiler flags**: `-Dpreview_mt -Dexecution_context` for experimental multithreading support.

## Architecture Overview

Ametist is a Crystal toolkit with three interconnected modules:

### 1. Ametist - Columnar Vector Database (`src/ametist/`)

Stores documents in typed columnar buffers for efficient vector operations.

- `Collection` - Document storage with typed columns
- `CollectionSchema` - Schema definitions with field types
- `DenseDataBuffer(T)` - Generic typed column storage
- `VectorBuffer`, `StringBuffer` - Specialized columns

**Future architecture**: Actor-based design with `PartitionActor` for sharded search. See [doc/ametist.md](doc/ametist.md).

### 2. LFApi - HTTP Router with DI (`src/lfapi/`)

Trie-based HTTP router with O(k) path matching and dependency injection.

**Routing**: Use `@[LF::APIRoute::Get("/path/:param")]` annotations for automatic parameter injection from path, query string, or JSON body.

**DI System**:
- `@[LF::DI::Service]` - Register services
- `@[LF::DI::Bean]` - Factory methods
- `LF::DI::AnnotationApplicationContext` - Container

**Exceptions**: `LF::BadRequest`, `LF::NotFound`, `LF::InternalServerError` automatically set HTTP status codes.

### 3. Movie - Actor Framework (`src/movie/`)

Fiber-based actor system with typed message passing.

**Core Types**:
- `ActorRef(T)` - Type-safe actor reference; send via `actor << message`
- `AbstractBehavior(T)` - Define message handlers in `receive(message, context)`
- `ActorContext(T)` - Runtime context with mailbox
- `ActorSystem(T)` - Root system managing actor lifecycle

**Lifecycle**: `CREATED -> STARTING -> RUNNING -> STOPPING -> STOPPED -> TERMINATED`

**Supervision**: Configure via `SupervisionConfig` with strategies: `RESTART`, `ESCALATE`, `STOP`

**Ask Pattern**: `actor.ask(message)` returns `Future(T)` for request-reply.

**Path Hierarchy**: Actors are organized under guardians:
- `/` - Root guardian
- `/system` - System actors (internal)
- `/user` - User-spawned actors

**Actor Lookup** (unified for local and remote):
```crystal
# Full URI
system.actor_for("movie://system-name/user/actor", MessageType)
# Absolute path (local)
system.actor_for("/user/actor", MessageType)
# Relative path (local)
system.actor_for("user/actor", MessageType)
# Convenience method
system.user_actor("actor", MessageType)
```

#### Configuration System (`src/movie/config.cr`)

Typesafe configuration with path-based access, inspired by Typesafe Config.

```crystal
# Programmatic
config = Movie::Config.builder
  .set("name", "my-system")
  .set("remoting.port", 9000)
  .set_duration("timeout", 5.seconds)
  .build

# From YAML
config = Movie::Config.from_yaml(File.read("config.yaml"))

# With defaults and env overrides
config = Movie::Config.from_yaml(yaml_string)
  .with_fallback(Movie::ActorSystemConfig.default)
  .with_env_overrides  # MOVIE_NAME, MOVIE_REMOTING_PORT, etc.

# Access values
config.get_string("name")
config.get_int("remoting.port")
config.get_bool("remoting.enabled", false)  # with default
config.get_duration("supervision.within")   # parses "5s", "100ms", etc.
config.get_config("remoting")               # subsection as Config
```

**Environment Variables**: `MOVIE_*` prefix, underscores become dots: `MOVIE_REMOTING_PORT` -> `remoting.port`

#### Extensions System

Register extensions with the actor system:

```crystal
class MyExtension < Movie::Extension
  def start; end
  def stop; end
end

system.extensions.register(MyExtension.new)
extension = system.extension(MyExtension)
```

#### Remoting (`src/movie/remote/`)

TCP-based actor communication across network boundaries.

```crystal
# Enable remoting
system.enable_remoting("127.0.0.1", 9000)

# Or via config
config = Movie::Config.from_yaml(<<-YAML)
  remoting:
    enabled: true
    host: 0.0.0.0
    port: 9000
YAML
system = Movie::ActorSystem(String).new(behavior, config)

# Get remote actor reference
remote_ref = system.actor_for(
  "movie.tcp://remote-system@192.168.1.10:9000/user/actor",
  MessageType
)
remote_ref << message  # Transparent - same API as local
```

**Message Registration**: Remote messages must be registered:
```crystal
record MyMessage, data : String do
  include JSON::Serializable
end
Movie::Remote::MessageRegistry.register(MyMessage)
```

**Wire Protocol**: Length-prefixed JSON with `WireEnvelope` containing message type, payload, sender/target paths.

**Connection Pools**: Striped connections for parallel message delivery to same remote system.

### 4. Streams - Reactive Pipelines (`src/movie/streams/`)

Backpressure-aware reactive streams built on actors.

```crystal
# Pipeline: Source -> Flow operators -> Sink
build_pipeline(
  source: Streams::Source.from_array([1, 2, 3]),
  flows: [Streams::Flow.map { |x| x * 2 }],
  sink: Streams::Sink.foreach { |x| puts x }
)
```

Operators: `map`, `filter`, `take`, `drop`

### 5. OpenAI Client (`src/openai/`)

Typed wrapper for OpenAI API: chat completions (with SSE streaming), embeddings, images, audio, files, fine-tuning.

## Key Patterns

**Message Protocol** (Streams): `Subscribe -> OnSubscribe -> Request(n) -> OnNext(elem)* -> OnComplete/OnError`

**Parameter Types** (LFApi): Supports `Int32`, `Int64`, `Float32`, `Float64`, `Bool`, `UUID`, `String` with automatic coercion.

**Dispatchers** (Movie): `PinnedDispatcher` (isolated thread), `ParallelDispatcher` (thread pool), `ConcurrentDispatcher` (single thread, concurrent fibers).

**Scatter-Gather** (Actors): Send to multiple actors, collect responses, merge results. Used for distributed search.

## File Structure

```
src/
├── ametist/           # Vector database
├── lfapi/             # HTTP router + DI
├── movie/
│   ├── streams/       # Reactive streams
│   ├── remote/        # Remoting layer
│   │   ├── address.cr
│   │   ├── connection.cr
│   │   ├── connection_pool.cr
│   │   ├── extension.cr
│   │   ├── frame_codec.cr
│   │   ├── message_registry.cr
│   │   ├── path_registry.cr
│   │   ├── remote_actor_ref.cr
│   │   ├── server.cr
│   │   └── wire_envelope.cr
│   ├── config.cr      # Configuration system
│   ├── context.cr     # Actor context
│   ├── mailbox.cr     # Actor mailbox
│   ├── path.cr        # Address and ActorPath
│   └── ...
├── movie.cr           # Main actor module
└── openai/            # OpenAI client
doc/
└── ametist.md         # Actor-based vector DB architecture
examples/
├── config_example.cr  # Configuration demo
├── remoting_example.cr # Remoting demo
└── ...
```

## Common Issues

**Tests fail without MT flags**: Actor and stream tests require `-Dpreview_mt -Dexecution_context`. Run `crystal spec -Dpreview_mt -Dexecution_context`.

**Remote messages not delivered**: Ensure message type is registered with `Movie::Remote::MessageRegistry.register(MessageType)`.

**Config path not found**: Use `has_path?` to check existence, or provide defaults: `config.get_string("key", "default")`.
