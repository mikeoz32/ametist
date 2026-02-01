# Memory Design (Hybrid Pyramid)

## Goals
- Keep context small while preserving long-term usefulness.
- Make memory durable across sessions (user/project) without inflating prompt size.
- Separate automatic memory from agent-controlled graph facts.
- Keep failure modes safe: memory issues never break agent runs.

## Summary of the Approach
We use a **hybrid “Pyramid”** model:
1. **Raw events** (always stored)
2. **Rolling summary** (auto-updated at token threshold)
3. **Semantic memory** (automatic embeddings + recall)
4. **Graph memory** (explicit facts written by agent)

Context assembly order is fixed and deduped:
**summary → recent → semantic → graph**, repeated per scope (session → project → user) with tighter caps at broader scopes.

## Components
- **MemoryActor** (per scope): owns persistence + policy decisions.
- **ContextBuilder**: assembles final prompt context in a deterministic order.
- **Summarizer**: LLM-driven rolling summary engine.
- **Vector store**: Ametist collection for semantic recall.
- **Graph store**: SQLite-backed graph for explicit facts.

## Memory Scopes
- **Session scope**: default for all conversations.
- **Project scope**: optional; shared for sessions tied to a project.
- **User scope**: optional; shared across all user sessions.

Each scope stores:
- raw events
- summary
- vector embeddings
- graph nodes/edges

Sessions may opt into project/user layers; unscoped sessions use only session memory.

## Data Flow
1. **Message ingestion**
   - Session stores every user/assistant message via `StoreEvent(embed=true)`.
   - Embeddings are automatic when an embedder is configured.

2. **Summary update (automatic)**
   - MemoryActor tracks estimated token usage.
   - When a session exceeds **8k tokens**, Summarizer generates a new rolling summary.

3. **Graph writes (agent controlled)**
   - Agent uses tool calls (e.g., `memory.add_node`, `memory.add_edge`).
   - These become `AddNode` / `AddEdge` messages to MemoryActor.

4. **Context assembly**
   - Session summary + recent window
   - Semantic recall (prompt embedding → top-k → fetch events)
   - Graph recall (policy-based neighbors)
   - Then project and user layers with smaller caps

## Configuration Defaults
- `agency.memory.summary_token_threshold = 8000`
- `agency.memory.max_history = 50`
- `agency.memory.semantic_k = 5` (session)
- `agency.memory.project.semantic_k = 3`
- `agency.memory.user.semantic_k = 2`
- `agency.graph.enabled = true`
- `agency.vector.enabled = true`

## Error Handling
- Embedding failures do not block storing events.
- Graph failures do not block context building.
- Summary failures keep last summary and retry later.
- All memory calls use timeouts; failures degrade gracefully.

## Testing Plan
- MemoryActor: summary threshold triggers; embedder missing; vector/graph failures.
- ContextBuilder: ordering + dedupe; multi-scope merge.
- Graph store: add node/edge + neighbors.
- End-to-end: summary appears after token threshold; history prunes correctly.

## Notes
- Graph and vectors are currently independent; future work may link vector ids to graph nodes for hybrid recall.
- Session context remains the highest priority; broader scopes are always capped.
