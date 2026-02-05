# Agency Implementation Plan (What / DoD)

This plan covers **all features defined in `doc/agency_design.md` that are not yet implemented**.
Each feature lists tasks and subtasks with **What** and **DoD (Definition of Done)**.

---

## Feature 1 — Naming + Extension Alignment (AgencyExtension / Agency < ExtensionId)

### Task 1.1 — Rename runtime extension to AgencyExtension
- What: Rename `RuntimeExtension` -> `AgencyExtension`, expose `Agency.get(system)` via ExtensionId.
- DoD: Code compiles; references updated across `src/agency`, `src/bin`, specs, and docs; `Agency.get(system)` is the entry point.
Status: DONE

#### Subtasks
- Subtask 1.1.1 — Rename files and classes
  - What: Rename files/classes and adjust module names.
  - DoD: New names exist; old names removed.
  - Status: DONE
- Subtask 1.1.2 — Update references in code
  - What: Update all call sites in `src/` and `spec/`.
  - DoD: `rg` finds no old class names.
  - Status: DONE
- Subtask 1.1.3 — Update runtime wiring
  - What: Ensure CLI and extension usage reference `Agency.get(system)`.
  - DoD: CLI runs and builds.
  - Status: DONE

### Task 1.2 — Update docs + API references
- What: Ensure public API, examples, and docs reference AgencyExtension + Agency ExtensionId consistently.
- DoD: `doc/agency_design.md` and `doc/implementation.md` reflect the new names.
Status: DONE

#### Subtasks
- Subtask 1.2.1 — Update design doc naming
  - What: Align terms/sections with new naming.
  - DoD: No legacy naming remains in design doc.
  - Status: DONE
- Subtask 1.2.2 — Update examples
  - What: Update any code snippets/examples in docs.
  - DoD: All snippets match codebase.
  - Status: DONE

---

## Feature 2 — Agent Hierarchy (AgentActor + AgentSession + AgentRun)

### Task 2.1 — Define protocols
- What: Define typed messages for AgentActor, AgentSession, AgentRun (e.g., `StartSession`, `RunPrompt`, `RunResult`, `RunFailed`, `ToolCall`, `ToolResult`).
- DoD: Protocol types exist in `src/agency/runtime/protocol.cr` or dedicated files; all actors use those types.
Status: DONE

#### Subtasks
- Subtask 2.1.1 — AgentActor protocol
  - What: Define `StartSession`, `StopSession`, `RunPrompt`, `GetState` messages.
  - DoD: Protocol types compiled and used by AgentActor.
  - Status: DONE
- Subtask 2.1.2 — AgentSession protocol
  - What: Define `UserPrompt`, `RunCompleted`, `RunFailed`, `SessionState` messages.
  - DoD: Session actor uses the types exclusively.
  - Status: DONE
- Subtask 2.1.3 — AgentRun protocol
  - What: Define `RunStart`, `RunStep`, `RunOutput`, `RunError`.
  - DoD: Run actor only accepts these messages.
  - Status: DONE

### Task 2.2 — Implement AgentActor (long-lived identity)
- What: Implement AgentActor that owns agent profile, policy, ToolSet, MemoryActor, Session registry.
- DoD: AgentActor spawns ToolSet + MemoryActor as children via `ctx.spawn` and handles session creation.
Status: DONE

#### Subtasks
- Subtask 2.2.1 — Agent profile model
  - What: Add `AgentProfile` struct (model, tools, memory policy, hooks).
  - DoD: Profile is passed into AgentActor at spawn.
  - Status: DONE
- Subtask 2.2.2 — Session registry
  - What: Maintain session map and create on demand.
  - DoD: Sessions are reused by id; stop cleans them up.
  - Status: DONE
- Subtask 2.2.3 — Child spawning + supervision
  - What: Spawn ToolSet + MemoryActor with explicit supervision.
  - DoD: All infra are children of AgentActor.
  - Status: DONE

### Task 2.3 — Implement AgentSession (long-lived session state)
- What: AgentSession stores session state, history pointer, session config; spawns AgentRun per prompt.
- DoD: Sessions can accept repeated prompts; history is capped; session survives run failures.
Status: DONE

#### Subtasks
- Subtask 2.3.1 — Session state model
  - What: Define `SessionState` (history ids, last run id, tool history).
  - DoD: State object used in Session actor.
  - Status: DONE
- Subtask 2.3.2 — Spawn run per prompt
  - What: Spawn AgentRun via `ctx.spawn` on each user prompt.
  - DoD: Run stops itself; session handles completion.
  - Status: DONE
- Subtask 2.3.3 — History cap
  - What: Cap history size and keep summaries pointer.
  - DoD: History never exceeds configured limit.
  - Status: DONE

### Task 2.4 — Implement AgentRun (short-lived ReAct loop)
- What: AgentRun executes a single ReAct loop: build context -> LLM -> tool calls -> LLM -> result.
- DoD: Run stops itself after completion; failures are reported back to Session/AgentActor.
Status: DONE

#### Subtasks
- Subtask 2.4.1 — Context request
  - What: Request context from ContextBuilderActor.
  - DoD: Run gets bounded context for prompt.
  - Status: DONE
- Subtask 2.4.2 — LLM invocation
  - What: Use LLMGateway and parse structured output.
  - DoD: Tool calls or final answer returned.
  - Status: DONE
- Subtask 2.4.3 — Tool execution
  - What: Send ToolCall to ToolSet and await ToolResult(s).
  - DoD: Tool results appended and loop continues.
  - Status: DONE
- Subtask 2.4.4 — Completion
  - What: Send final response to Session; emit RunCompleted event.
  - DoD: Run actor stops (POST_STOP observed).
  - Status: DONE

### Task 2.5 — Update AgentManager
- What: AgentManager spawns AgentActor(s) and forwards RunPrompt to the correct AgentActor.
- DoD: Manager is single root; no system-level spawns except manager root.
Status: DONE

#### Subtasks
- Subtask 2.5.1 — Agent registry
  - What: Maintain map of agent_id -> AgentActor ref.
  - DoD: AgentActor reused per id.
  - Status: DONE
- Subtask 2.5.2 — Prompt routing
  - What: Route `RunPrompt` to correct AgentActor.
  - DoD: Prompts reach the right agent and session.
  - Status: DONE

---

## Feature 3 — ToolSet (per-agent default)

### Task 3.1 — ToolSet base actor
- What: Create abstract `ToolSet < AbstractBehavior(ToolCall)` with a unified ToolResult response protocol.
- DoD: Concrete ToolSets can be spawned and receive ToolCall messages.
Status: DONE

#### Subtasks
- Subtask 3.1.1 — ToolResult protocol
  - What: Define standard ToolResult envelope (id/name/content/errors).
  - DoD: All tool paths produce ToolResult.
  - Status: DONE
- Subtask 3.1.2 — Base ToolSet API
  - What: Define `handle(call, reply_to)` and default error handling.
  - DoD: Subclasses override minimal hooks.
  - Status: DONE

### Task 3.2 — DefaultToolSet implementation
- What: Implement DefaultToolSet that uses Executor tasks for stateless tools and actor calls for stateful tools.
- DoD: At least one executor-backed tool and one actor-backed tool are working end-to-end.
Status: DONE

#### Subtasks
- Subtask 3.2.1 — Executor tool wrapper
  - What: Map tool name -> Proc executed in ExecutorExtension.
  - DoD: Tool returns ToolResult via async completion.
  - Status: DONE
- Subtask 3.2.2 — Actor tool wrapper
  - What: Route tool calls to service actors.
  - DoD: Responses flow back to ToolSet.
  - Status: DONE

### Task 3.3 — MCP ToolSet stub
- What: Create `McpToolSet` that routes ToolCall to an MCP adapter actor.
- DoD: MCP adapter stub exists and is invoked; responses flow back to AgentRun.
Status: DONE

#### Subtasks
- Subtask 3.3.1 — MCP adapter protocol
  - What: Define request/response messages to MCP server.
  - DoD: Adapter compiles and can be mocked.
  - Status: DONE
- Subtask 3.3.2 — MCP tool routing
  - What: ToolSet forwards calls to MCP adapter.
  - DoD: ToolResult returned to run.
  - Status: DONE

### Task 3.4 — Integrate ToolSet into AgentActor/Run
- What: AgentRun sends ToolCall to ToolSet directly; ToolSet returns ToolResult.
- DoD: No ToolDispatcher registry used; per-agent ToolSet is default.
Status: DONE

#### Subtasks
- Subtask 3.4.1 — Wiring in AgentActor
  - What: Spawn ToolSet and expose ref to sessions/runs.
  - DoD: Runs can access ToolSet ref.
  - Status: DONE
- Subtask 3.4.2 — Run execution
  - What: Replace ToolDispatcher usage with ToolSet calls.
  - DoD: All tests updated and pass.
  - Status: DONE
- Subtask 3.4.3 — Per-agent tool allowlist
  - What: Allow agents to expose only allowed tool names from config and update at runtime.
  - DoD: Agents ignore non-allowed tools; allowlist update propagates to existing agents.
  - Status: DONE

---

## Feature 4 — Memory + Context (Graph + Semantic)

### Task 4.1 — GraphStoreExtension (SQLite)
- What: Implement GraphStoreExtension with node/edge schema and query APIs.
- DoD: SQLite schema + queries for `add_node`, `add_edge`, `neighbors`, `get_node`.
Status: DONE

#### Subtasks
- Subtask 4.1.1 — Schema definition
  - What: Define `nodes`/`edges` tables and indexes.
  - DoD: Schema migrates on startup.
  - Status: DONE
- Subtask 4.1.2 — CRUD APIs
  - What: Implement add/get for nodes and edges.
  - DoD: Unit tests pass.
  - Status: DONE

### Task 4.2 — ContextStoreExtension (SQLite/KV)
- What: Implement ContextStoreExtension to store session logs, summaries, and caches.
- DoD: Read/write APIs for session logs and summaries; basic unit tests.
Status: DONE

#### Subtasks
- Subtask 4.2.1 — Session log storage
  - What: Write/read session message events.
  - DoD: Test covers insert + fetch.
  - Status: DONE
- Subtask 4.2.2 — Summary storage
  - What: Store and retrieve summaries by session id.
  - DoD: Summary used in context building.
  - Status: DONE

### Task 4.3 — VectorStoreExtension (Ametist)
- What: Wrap Ametist vector DB in a Movie extension with `upsert_embedding`, `query_top_k`.
- DoD: Embedding insert + query flow demonstrated in a spec.
Status: DONE

#### Subtasks
- Subtask 4.3.1 — Extension wiring
  - What: ExtensionId that creates Ametist client/store.
  - DoD: Extension available via `ctx.extension`.
  - Status: DONE
- Subtask 4.3.2 — Query API
  - What: Provide `query_top_k` with filters.
  - DoD: Tests return expected ids.
  - Status: DONE

### Task 4.4 — EmbedderExtension
- What: External embedding adapter (OpenAI/local), with pluggable base URL and model.
- DoD: Embedder returns embeddings and is used by VectorStoreExtension.
Status: DONE

#### Subtasks
- Subtask 4.4.1 — Client abstraction
  - What: Define embedder interface and concrete OpenAI/local implementations.
  - DoD: Embeddings returned for test inputs.
  - Status: DONE
- Subtask 4.4.2 — Error handling
  - What: Normalize errors/timeouts.
  - DoD: Failures surfaced to ContextBuilderActor.
  - Status: DONE

### Task 4.5 — MemoryActor + ContextBuilderActor
- What: MemoryActor owns Graph/Context stores; ContextBuilderActor performs recency + semantic + graph expansion and budgets the context.
- DoD: AgentRun requests context; receives bounded context with expected sources.
Status: DONE

#### Subtasks
- Subtask 4.5.1 — MemoryActor storage API
  - What: Add methods for storing events, summaries, embeddings.
  - DoD: Writes appear in stores.
  - Status: DONE
- Subtask 4.5.2 — ContextBuilder scoring
  - What: Assemble summary + recent + semantic context with dedupe and max history.
  - DoD: Context builder returns expected ordering and bounds.
  - Status: DONE

### Task 4.6 — Hybrid Memory (Summary + Multi-scope + Graph Recall)
- What: Implement hybrid memory policy: automatic summaries by token threshold, multi-scope memory (session/project/user), and graph recall into context.
- DoD: ContextBuilder merges session + optional project/user scope; summary updates trigger at 8k tokens; graph recall contributes to context.
Status: PENDING

#### Subtasks
- Subtask 4.6.1 — Memory policy config
  - What: Add config keys for summary token threshold, per-scope caps (max_history, semantic_k, graph_k).
  - DoD: Defaults wired; can override via config.
  - Status: DONE
- Subtask 4.6.2 — Token estimator + summary trigger
  - What: Track estimated token count per scope; trigger summarizer at 8k tokens.
  - DoD: Summary updates stored and visible in context.
  - Status: DONE
- Subtask 4.6.3 — Summarizer service
  - What: Add LLM summarizer flow that updates rolling summary using previous summary + recent delta.
  - DoD: Summary stored; failures fall back to last summary.
  - Status: DONE
- Subtask 4.6.4 — Multi-scope MemoryActor wiring
  - What: Add user/project scopes and route queries per scope; session attaches to optional user/project ids.
  - DoD: Session can include project/user context layers when configured.
  - Status: DONE
- Subtask 4.6.5 — Graph recall in ContextBuilder
  - What: Add graph neighbor lookup to context build; merge with dedupe.
  - DoD: Graph results appear in built context under tests.
  - Status: DONE

---

## Feature 5 — Skills + Hooks

### Task 5.1 — Skill definition
- What: Define `Skill` with toolset selection, prompt fragments, context policy, and hooks.
- DoD: Skill registry available on AgentActor; skills can be attached to sessions.
Status: IN PROGRESS

#### Subtasks
- Subtask 5.1.1 — Skill schema
  - What: Define skill fields and validation.
  - DoD: Skill loading errors are explicit.
  - Status: DONE
- Subtask 5.1.2 — AgentActor registry
  - What: Add skill registry + attach/detach.
  - DoD: Sessions inherit agent skills.
  - Status: PENDING
- Subtask 5.1.3 — Filesystem skill source
  - What: Load `SKILL.md` from default project/global paths (Claude/OpenCode/Codex/Copilot) and allow rescan.
  - DoD: Skills load on startup; `/skills` lists; `/skills reload` refreshes.
  - Status: DONE

### Task 5.2 — Hook pipeline
- What: Implement ordered hooks (pre-run, pre-llm, post-llm, post-tool, post-run).
- DoD: Hooks can inject context and are executed in order; hook errors handled gracefully.
Status: PENDING

#### Subtasks
- Subtask 5.2.1 — Hook protocol
  - What: Define Hook interface and hook result types.
  - DoD: Hook errors handled with policy (stop/continue).
  - Status: PENDING
- Subtask 5.2.2 — Hook execution in AgentRun
  - What: Apply hooks in correct order.
  - DoD: Hooks can modify context/tool set.
  - Status: PENDING

---

## Feature 6 — SessionEventBus

### Task 6.1 — Event protocol
- What: Define session event messages (RunStarted, ToolCall, ToolResult, RunCompleted, RunFailed).
- DoD: Events are published from AgentRun and can be subscribed to.

#### Subtasks
- Subtask 6.1.1 — Event types
  - What: Define event classes with required fields.
  - DoD: All actors compile and use events.
- Subtask 6.1.2 — Event emission
  - What: Emit events from AgentRun and Session.
  - DoD: Events observable in tests.

### Task 6.2 — EventBus actor
- What: Implement pub/sub with session filters.
- DoD: Multiple subscribers receive events without blocking AgentRun.

#### Subtasks
- Subtask 6.2.1 — Subscription lifecycle
  - What: Subscribe/unsubscribe; cleanup on Terminated.
  - DoD: No leaks after subscriber stops.
- Subtask 6.2.2 — Filtering
  - What: Filter by session_id and event type.
  - DoD: Only matching events delivered.

---

## Feature 7 — GraphOrchestrator (multi-agent workflows)

### Task 7.1 — DAG execution protocol
- What: Define `WorkflowGraph`, `NodeSpec`, `EdgeSpec`, and execution commands.
- DoD: GraphOrchestrator can execute a simple 2-node pipeline.

#### Subtasks
- Subtask 7.1.1 — Graph model
  - What: Define DAG schema and validation.
  - DoD: Invalid graphs rejected.
- Subtask 7.1.2 — Execution engine
  - What: Execute nodes in topological order.
  - DoD: Node outputs propagate to downstream nodes.

### Task 7.2 — Result aggregation
- What: Add join/merge strategies (first-success, majority vote, synthesis).
- DoD: Aggregation works on sample multi-agent run.

#### Subtasks
- Subtask 7.2.1 — Aggregator interface
  - What: Define aggregation policy interface.
  - DoD: Policies selectable per workflow.
- Subtask 7.2.2 — Sample policies
  - What: Implement at least two policies (first-success, majority).
  - DoD: Tests demonstrate outputs.

---

## Feature 8 — Protocol Adapters

### Task 8.1 — TUI adapter
- What: Translate TUI input -> RunPrompt, stream events back.
- DoD: CLI/TUI interactive mode receives live run events.
Status: IN PROGRESS

#### Subtasks
- Subtask 8.1.1 — Adapter actor
  - What: Implement actor mapping input to RunPrompt.
  - DoD: TUI sends prompt and receives response.
  - Status: DONE
- Subtask 8.1.2 — Event streaming
  - What: Subscribe to SessionEventBus.
  - DoD: Events show in TUI output.
  - Status: PENDING

### Task 8.2 — ACP adapter
- What: Map ACP messages to agent commands; return structured responses.
- DoD: ACP adapter spec tests pass.

#### Subtasks
- Subtask 8.2.1 — Protocol mapping
  - What: Map ACP message types to RunPrompt/GraphOrchestrator.
  - DoD: Round-trip mapping works.
- Subtask 8.2.2 — ACP tests
  - What: Add protocol tests.
  - DoD: Tests pass in CI.

### Task 8.3 — AG-UI adapter
- What: Provide AG-UI protocol translation layer.
- DoD: Adapter handles a round-trip message + event stream.

#### Subtasks
- Subtask 8.3.1 — Protocol mapping
  - What: Define AG-UI message mapping.
  - DoD: Example handshake works.
- Subtask 8.3.2 — Event bridging
  - What: Stream events to AG-UI.
  - DoD: Events are delivered in spec.

---

## Feature 9 — Tool policies (rate limits, concurrency)

### Task 9.1 — Per-tool concurrency controls
- What: Add optional semaphores/queueing in ToolSet.
- DoD: ToolSet enforces per-tool concurrency limit.

#### Subtasks
- Subtask 9.1.1 — Concurrency config
  - What: Add per-tool config (max_concurrency).
  - DoD: Config is applied by ToolSet.
- Subtask 9.1.2 — Enforcement
  - What: Implement semaphore + queue.
  - DoD: Limits observed under load test.

### Task 9.2 — Per-tool timeouts
- What: Enforce tool timeout at ToolSet level.
- DoD: Timeouts return ToolResult error and do not hang runs.

#### Subtasks
- Subtask 9.2.1 — Timeout config
  - What: Add per-tool timeout settings.
  - DoD: Config applied and logged.
- Subtask 9.2.2 — Timeout execution
  - What: Timer cancels or fails tool call.
  - DoD: ToolResult error returned on timeout.

---

## Feature 10 — Testing + Observability

### Task 10.1 — Spec coverage for new actors
- What: Add specs for AgentActor/Session/Run, ToolSet, Memory pipeline, EventBus.
- DoD: Specs cover success + failure paths and pass with `-Dpreview_mt -Dexecution_context`.

#### Subtasks
- Subtask 10.1.1 — Actor tests
  - What: Add specs for each actor protocol.
  - DoD: All actors tested in isolation.
- Subtask 10.1.2 — Integration tests
  - What: End-to-end run with tools + memory.
  - DoD: Integration spec passes.

### Task 10.2 — Telemetry extension hooks
- What: Trace runs and tool calls; record timings and failures.
- DoD: TelemetryExtension produces structured logs and metrics.

#### Subtasks
- Subtask 10.2.1 — Telemetry interface
  - What: Define spans/events for run lifecycle.
  - DoD: Logs include run id, timings, errors.
- Subtask 10.2.2 — Metrics wiring
  - What: Add counters/timers (runs, tools, failures).
  - DoD: Metrics exposed or logged.

---

## Implementation Order (recommended)
1) Feature 1 (naming alignment)
2) Feature 2 (AgentActor/Session/Run)
3) Feature 3 (ToolSet)
4) Feature 4 (Memory + Context)
5) Feature 5 (Skills + Hooks)
6) Feature 6 (EventBus)
7) Feature 7 (GraphOrchestrator)
8) Feature 8 (Protocol adapters)
9) Feature 9 (Tool policies)
10) Feature 10 (Testing + Observability)
