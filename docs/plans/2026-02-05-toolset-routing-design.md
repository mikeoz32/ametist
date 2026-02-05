# ToolSet Routing and Registration Design

Date: 2026-02-05

## Goals
- Support multiple ToolSets per agent with prefix routing.
- Keep API code-driven (no new config required).
- Default per-agent allowlist is empty (no toolsets by default).
- Allow ToolSets to be per-session or shared (static ActorRef), including remote refs.
- Keep MCP as a ToolSet without special casing in session routing.

## Non-Goals
- Human-in-the-loop approval flow for tools.
- Tool sandboxing or permissions beyond allowlists.
- Dynamic tool discovery beyond MCP list_tools.

## Architecture

### Core Concepts
- **ToolSetDefinition**: registry entry holding toolset id, prefix, tools list, and a factory or a static ref.
- **ToolSetBinding**: resolved toolset for a session. Either:
  - **Factory**: session spawns a new toolset actor (per-session scope).
  - **Static Ref**: session reuses a shared or remote actor ref.
- **ToolRouter**: per-session actor that routes tool calls by prefix and exposes prefixed tool names to the LLM.

### Routing
- Tool names are published to the LLM as `<prefix>.<tool>`.
- The ToolRouter splits the tool name on the first `.` and routes to the ToolSet bound for that prefix.
- The ToolRouter strips the prefix before forwarding to the toolset actor.
- Errors:
  - Unknown prefix -> ToolResult error ("Toolset not found").
  - ToolSet error -> ToolResult error returned by toolset.

## API Surface

### Registration (code-driven)
Overloads on `AgencyExtension` (or `AgentManager`):
- `register_toolset(id : String, prefix : String, tools : Array(ToolSpec), &factory)`
- `register_toolset(id : String, prefix : String, tools : Array(ToolSpec), ref : Movie::ActorRef(ToolSetMessage))`

### Agent Allowlist
- `update_allowed_toolsets(agent_id : String, toolset_ids : Array(String))`
- Default allowlist is **empty** (agents have no toolsets unless allowed).

### MCP Convenience
- `register_mcp_toolset(id, prefix, command, args, env, cwd, roots)`:
  - Initialize JSON-RPC client
  - `list_tools` to build ToolSpec list
  - Register ToolSetDefinition
  - (optional) update agent allowlist to include the toolset id

## Data Flow
1) App registers ToolSets with `AgencyExtension`.
2) Agent allowlist is updated (explicitly).
3) Session starts:
   - AgentSession asks manager for ToolSetDefinitions by id.
   - Session spawns ToolRouter.
   - For each ToolSetDefinition:
     - If factory: spawn ToolSet actor for the session.
     - If static ref: reuse the ref.
     - Register prefix -> ref in router.
   - Build LLM tool list by prefixing tool names.
4) Tool call:
   - LLM sends call with `<prefix>.<tool>`.
   - ToolRouter routes to correct ToolSet and forwards stripped tool name.
   - ToolSet replies with ToolResult.

## Error Handling
- ToolRouter validates prefix and fails fast when missing.
- ToolSet owns execution errors and returns ToolResult with error content.
- Session stops only the ToolSets it spawned (factory-based). Static refs are not stopped.

## Testing
- Unit:
  - ToolRouter routes by prefix and strips names.
  - Unknown prefix returns ToolResult error.
  - Factory toolsets are spawned per session and stopped on session stop.
  - Static toolset refs are not stopped on session stop.
- Integration:
  - Multiple toolsets advertised with prefixed names.
  - MCP toolset registers and executes with prefixed names.
  - Agent allowlist (default none) blocks toolsets until enabled.

## Open Questions (Deferred)
- Human approval flow for tool calls.
- Toolset-level throttling or rate limits.
- Toolset discovery from config or external registry.
