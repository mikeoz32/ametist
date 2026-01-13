# LFAPI Route Guards with DI (Spec)

## Goal
Define a minimal, fast guard pipeline for LFAPI routes using DI-resolved guard instances, serving as the basis for implementation tasks (OZW-44 router support, OZW-43 macro sugar).

## Design
- Interface: `module LF::Guard; abstract def can_activate(context : HTTP::Server::Context, params : Hash(String, String), di : LF::DI::AnnotationApplicationContext) : Bool`.
- Routing API (non-macro first): `router.get("/path", guards: ["basic_auth"]) { ... }`.
- Guard resolution: requires request-scope DI in `context.state`; lookup bean by name; failure => 500 InternalServerError.
- Execution flow: resolve guards -> run sequentially -> on allow -> run handler.
- Error handling:
  - `false` => 403 Forbidden (default).
  - `LF::HTTPException` => its status/message (guards can raise 401/403 explicitly).
  - Other exceptions => 500 InternalServerError.
- Performance: zero overhead when no guards configured (no array, no DI lookup).
- Macro sugar (later): `@[UseGuards(...)]` to collect guard names per class/method; class + method guards appended by default.

## Open Notes
- Append semantics for class + method guards unless a future override mode is added.
- If DI is missing but guards are configured, respond 500 (InternalServerError).

## Next Steps
- OZW-44: Implement guard support in router (manual guards via names + DI lookup, tests for 403/400/pass-through).
- OZW-43: Add macro sugar (`UseGuards`) to feed guard lists into the router consistently.
