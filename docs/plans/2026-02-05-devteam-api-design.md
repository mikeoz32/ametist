# Dev Team API (Org/Project/Agents) Design

Date: 2026-02-05

## Goals
- API-first service for dev teams with role-based agents.
- MVP workflow: create org -> create project -> attach PM/BA -> kickoff -> persist results.
- Persistence modeled after Akka: Event Sourcing and Durable State behaviors.
- Storage via SQLite using Crystal DB shard; data stored as JSON.
- Tenancy at Organization level; projects belong to orgs.

## Non-Goals
- Human-in-the-loop approvals.
- Full tool marketplace.
- Vector memory integration (Ametist) in MVP.
- Multi-region deployment.

## Architecture
### High-level
- API server owns Movie ActorSystem and Agency runtime.
- CLI/TUI becomes a thin client to the API.
- Org is tenant; projects belong to org; agents are org-scoped.

### Service Actors
- **OrgService** (org registry + config)
  - Creates ProjectService children per org.
  - Owns AgentService for the org.
- **ProjectService** (project metadata + kickoff orchestration)
  - Links projects to agent roles (PM, BA).
  - Triggers kickoff by calling AgentService.
  - Persists kickoff results + events.
- **AgentService** (org-scoped)
  - Owns AgentManager for the org.
  - Manages agent profiles, allowed toolsets, and sessions.

## API (MVP)
- `POST /orgs` -> `{org_id}`
- `POST /orgs/{org_id}/projects` -> `{project_id}`
- `POST /orgs/{org_id}/projects/{project_id}/agents` -> attach roles `{roles:["pm","ba"]}`
- `POST /orgs/{org_id}/projects/{project_id}/kickoff` -> kickoff `{prompt, session_id?}` -> `{pm_summary, ba_requirements, risks, next_steps}`

Auth: static API key (header or query parameter).

## Kickoff Flow
1) API validates API key and org/project.
2) OrgService routes to ProjectService.
3) ProjectService calls AgentService to run PM and BA kickoff sessions.
4) AgentService uses Agency runtime to execute sessions.
5) ProjectService aggregates and persists:
   - Durable state: latest kickoff result.
   - Event stream: kickoff requested + responses.

## Persistence (Akka-inspired)
### Behaviors
**EventSourcedBehavior(TCommand, TEvent, TState)**
- `TEvent` and `TState` must include `JSON::Serializable`.
- `empty_state`, `apply_event`, `handle_command`.
- On start: replay events for `persistence_id`.
- On command: persist events, apply, reply.

**DurableStateBehavior(TCommand, TState)**
- `TState` includes `JSON::Serializable`.
- `empty_state`, `handle_command`.
- On start: load state for `persistence_id`.
- On command: persist state, reply.

### Extensions
- `Persistence::Id` combines `entity_type` and `entity_id` (`"Type:Id"`).
- Extensions register entity factories up front:
  - `EventSourcing.register_entity("Type") { |id, store| ... }`
  - `DurableState.register_entity(TypeClass) { |id, store| ... }`
- Lookup is Akka-style: `get_entity_ref(Persistence::Id)`
  - Typed helper: `get_entity_ref_as(MessageType, Persistence::Id)`
- Registry actor caches entity refs per `Persistence::Id` and owns children (supervision).

### Storage
- SQLite via DB shard.
- JSON stored as TEXT.
- Application-level keys encode org/project:
  - `org/<org_id>/project/<project_id>/meta`
  - `org/<org_id>/project/<project_id>/events`

## Error Handling
- API returns structured errors: `invalid_auth`, `not_found`, `validation_failed`, `internal_error`.
- ProjectService handles partial failures (one agent fails) and persists partial results.
- Recovery errors fail actor startup; surfaced as 500 errors.

## Testing
- Unit: EventSourcedBehavior replay order; DurableStateBehavior load/save.
- Integration: OrgService/ProjectService/AgentService with SQLite.
- API: full flow test (org -> project -> agents -> kickoff).

## Open Questions (Deferred)
- Human approvals for tool calls.
- Toolset marketplace and dynamic discovery.
- Vector memory and graph integration.
