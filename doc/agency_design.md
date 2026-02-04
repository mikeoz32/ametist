# Agency Runtime Design (Movie-based)

## 1) Goals
- Provide a state-of-the-art agentic runtime on top of Movie's typed actor model.
- Support single-agent and multi-agent flows with clear supervision boundaries.
- Make configuration explicit (system-level, agent profile, session-level).
- Integrate tools safely (schema validation, supervision, throttling).
- Support multiple protocols (embedded TUI, ACP, AG-UI, HTTP/WebSocket, etc.).

## 2) Core Principles (from Movie + Akka/OTP patterns)
- Parent spawns children via `ctx.spawn` to ensure supervision, paths, and lifecycle.
- Behaviors that need a context are created via `Behaviors.setup`.
- Supervision is explicit at spawn sites; default should not be implicit.
- State lives in actors; avoid shared mutable registries outside actors.
- Use `ExtensionId.get(system)` for shared services (Executor, Remoting, IO, etc.).

## 3) Terms (used consistently in this document)
- **AgencyExtension**: the Movie extension that wires the Agency runtime. Accessed via **Agency < ExtensionId**.
- **Agency (ExtensionId)**: ExtensionId entry point for AgencyExtension (`Agency.get(system)` semantics).
- **AgentManager**: the single root actor for the Agency runtime (supervisor). Implemented by `AgentManagerActor`.
- **AgentManager facade**: small API wrapper that holds `ActorRef(ManagerMessage)` for the supervisor.
- **Agent Session**: per-session actor (`AgentSession`) that runs the ReAct loop.
- **ToolSet**: concrete tool routing actor; subclasses implement tool families and execution policy.
- **LLM Gateway**: `LLMGateway` actor that performs LLM calls via the Executor extension.
- **Protocol Adapter**: actor that maps external protocol messages to `RunPrompt` and subscribes to events.
- **Tool Actor**: actor implementing a tool (stateful or rate-limited).

## 4) Actor Topology

ActorSystem
└── AgentManager (AgentManagerActor)
    ├── ToolSet (per agent, routing + policy)
    ├── LLMGateway (LLM calls via Executor extension)
    ├── Session Actors (per session / agent instance)
    ├── Optional: SessionEventBus (publish/subscribe events)
    ├── Optional: MemoryActor (per session or shared)
    └── Optional: GraphOrchestrator (multi-agent flows)

Notes:
- AgentManager is the single root for Agency runtime.
- All children are spawned by the AgentManager using ctx.spawn.

## 5) Responsibilities

### AgentManager (AgentManagerActor)
- Owns all Agency infrastructure.
- Spawns ToolSet, LLMGateway, Session actors.
- Tracks sessions by id (session_id -> ActorRef).
- Holds tool specs and registration state.
- Implements RunPrompt, RegisterTool, UnregisterTool.

### ToolSet
- Encapsulates tool routing + policy for a family of tools.
- Decides per-call execution strategy (actor tool vs executor task).
- Enforces allowlist, rate limits, and timeouts per agent.

### LLMGateway
- Calls LLM via Executor extension (bounded work queue).
- Parses JSON output via Protocol.
- Returns LLMResponse to session.

### AgentSession
- Maintains message history (capped).
- Implements ReAct loop: LLM -> tool calls -> tool results -> LLM -> final.
- Tracks pending tool calls and step count.
- Sends final response to reply_to.

### SessionEventBus (optional)
- Publish/subscribe for progress events, tool calls, tokens, etc.
- Multiple protocols can subscribe to the same session.

### GraphOrchestrator (optional)
- Runs a DAG of session actors (multi-agent workflows).
- Combines results and applies policies (review, voting, critique).

## 6) Supervision Strategy

Default recommendations:
- Infrastructure (ToolSet, LLMGateway):
  - RESTART, one-for-one, higher restart limit, exponential backoff.
- Sessions:
  - RESTART, one-for-one, lower restart limit, tighter backoff.

AgentManager is responsible for choosing these when spawning children.

## 7) Configuration Model

### System-level (Config or env)
- agency.llm.base_url
- agency.llm.api_key
- agency.llm.model
- executor.pool-size
- executor.queue-capacity
- supervision defaults (infra + session)

### Agent Profile (static)
- model
- temperature/top_p
- max_steps
- max_history
- tool policy (allowlist/denylist)
- memory policy (none/window/summary)
- tool timeouts
- LLM timeout

### Session (dynamic)
- session_id
- profile_id
- per-request model override
- tool overrides
- memory TTL
- protocol adapter options

## 8) Agent State Machine

IDLE -> RUNNING -> (WAITING_TOOL <-> RUNNING)* -> COMPLETED
      -> FAILED | CANCELLED

State transitions are inside AgentSession. Failures propagate to AgentManager.

## 9) Agent / Session / Run Model (chosen)

We will use **Option C**: Agent + Session + Run actors.

### Roles
- **AgentActor** (long-lived): agent identity, profile, memory policy, tool policy.
- **AgentSession** (long-lived per session): conversation state + history.
- **AgentRun** (short-lived): executes one ReAct loop for a single prompt; stops itself on completion.

### Why this choice
- Strong isolation: a failed run does not corrupt session state.
- Natural concurrency: multiple runs per session (or per agent) can be scheduled or pooled.
- Good fit for multi-agent graphs (each edge can spawn a run).

### Run lifecycle
1. Session receives user prompt.
2. Session spawns AgentRun (or borrows one from a pool).
3. AgentRun executes ReAct loop (LLM -> tools -> LLM) using the Session snapshot.
4. AgentRun sends final result + tool events to Session, then stops.

### Pooling (optional)
If throughput is high, use a **RunPool** actor under AgentManager to manage a bounded pool of AgentRun workers.

## 9) ToolSets (default: per agent)

ToolSet is a **concrete actor type**, not a registry. The base `ToolSet` is an abstract actor
(`AbstractBehavior(ToolCall)`), and concrete toolsets are subclasses that implement routing,
policy, and execution for specific tool families.

### Default scope
- **Per agent** (default): each AgentActor owns one ToolSet, shared across its sessions.
- Per session: Session spawns its own ToolSet for maximum isolation.
- Shared: a single ToolSet for all agents (only if resources must be shared globally).

### Execution strategies
- **Actor tools**: stateful or rate-limited services (service actors).
- **Executor tasks**: stateless IO or computation using `ExecutorExtension`.
ToolSet decides which strategy to use per tool.

### Example concrete ToolSets
- `DefaultToolSet` (built-ins: echo/time/fs)
- `McpToolSet` (routes to MCP server actor)
- `CodeToolSet` (code execution, repo tools)
- `ResearchToolSet` (web/doc/citation tools)

### Integration
- AgentManager/AgentActor spawns the ToolSet (per agent by default).
- AgentRun sends ToolCall directly to the ToolSet.

## 10) Protocol Adapters

Each protocol is implemented as an adapter actor:
- Embedded TUI -> Adapter actor converts UI events to RunPrompt and subscribes to SessionEventBus.
- ACP / AG-UI -> Adapter translates protocol messages to RunPrompt and streams events back.
- HTTP/WebSocket -> Adapter per connection/session.

Adapters are children of the AgentManager (or a dedicated Protocol Supervisor if needed).

## 11) Memory + Context (Graph + Semantic)

### Storage extensions (recommended)
- **GraphStoreExtension**: SQLite-backed graph store (nodes/edges + metadata).
- **VectorStoreExtension**: Ametist-backed semantic retrieval (embeddings).
- **ContextStoreExtension**: session logs, summaries, KV caches.
- **EmbedderExtension**: external embedding service adapter (OpenAI, local, etc.).

### Context Builder pipeline
1. Session window (recency).
2. Semantic search (VectorStore).
3. Graph expansion (GraphStore).
4. Rank + trim to budget.
5. Optional summary for overflow.

### Actor integration
- MemoryActor owns GraphStore + ContextStore.
- EmbedderActor owns embedding client.
- ContextBuilderActor orchestrates semantic + graph retrieval for AgentRun.

## 12) Extensions to Movie (if needed)

Recommended optional extensions:
- IOExtension: shared HTTP client pool, retry/circuit breaker.
- TelemetryExtension: tracing, metrics, structured logs.
- PersistenceExtension: event store / state snapshots.
- RateLimiterExtension: global LLM/tool quotas.
- VectorExtension: embeddings + semantic memory.
- GraphStoreExtension: SQLite-backed graph store (nodes/edges + metadata).
- ContextStoreExtension: session/context logs and summaries.
- EmbedderExtension: external embedding service adapter.

Use ExtensionId to access these from any actor context.

## 13) Implementation Outline

1. Create AgentManager (AgentManagerActor) via Behaviors.setup.
2. Spawn ToolSet and LLMGateway as children with supervision config.
3. Spawn sessions via ctx.spawn (supervised).
4. Use ExtensionId for Executor and optional extensions.
5. Add SessionEventBus and GraphOrchestrator when multi-agent workflows needed.
6. Add protocol adapters as separate actors.

## 14) Public API (consistent names)

Entry point:
- `agency = Agency.get(system)`  (AgencyExtension via ExtensionId)

Primary interactions:
- `agency.manager.register_tool(spec, behavior, name)`  (AgentManager spawns tool actor)
- `agency.manager.run(prompt, session_id, model)`  (returns Future(String))
- `agency.manager.ref << RunPrompt.new(...)` (typed message entry point)

## 15) Testing Strategy

- Unit: ToolSet routing + policy.
- Integration: RunPrompt -> LLM -> tool -> final response.
- Supervision: force failures and verify restart/backoff.
- Protocol: adapter contract tests (ACP/AG-UI/TUI).
