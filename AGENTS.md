# AGENTS Instructions

These are project-specific instructions for future agent sessions.

## General
- Prefer actor-based design consistent with Movie.
- Use `Behaviors.setup` when the actor needs `ActorContext` (spawning children, adapters, timers).
- Spawn children via `ctx.spawn`, not `system.spawn`, unless creating a top-level root.
- Use Movie ExtensionIds for shared services (e.g., `Movie::Execution.get(system)`), never `new`.
- Keep mutable state inside actors; avoid shared mutable registries outside actors.

## Agency Runtime Design Rules
- `AgentManagerActor` is the **single supervisor/root** for the Agency runtime.
- All infra actors (ToolDispatcher, LLMGateway, Session actors, tool actors) are children of the manager via `ctx.spawn`.
- Tools are **actors**; register them via `AgentManager.register_tool(spec, behavior)` so the manager spawns them as children.
- Tool registry lives in `ToolDispatcher` actor (no external hash).
- Sessions must cap history and clean up helper actors on completion.
- Use explicit supervision for infra and sessions (backoff + restart limits).

## LLM / Executor
- Always access executor via `Movie::Execution.get(system)` or `ctx.extension(Movie::Execution.instance)`.
- LLM base URL and API key are resolved from config (`agency.llm.base_url`, `agency.llm.api_key`) or env.
- Local models can use OpenAI-compatible base URL with empty API key (non-OpenAI endpoints only).

## Tooling
- Default test/build flags: `-Dpreview_mt -Dexecution_context`.
- Common commands:
  - Build CLI: `crystal build -Dpreview_mt -Dexecution_context src/bin/agency.cr`
  - Run agency specs: `crystal spec spec/agency -Dpreview_mt -Dexecution_context`

## Repo Style
- Keep code in Crystal idioms (no unnecessary metaprogramming).
- Use ASCII unless file already has unicode.
- Keep file edits minimal and localized; prefer `apply_patch` for single-file edits.

## When in doubt
- Check `src/movie/context.cr`, `src/movie/behavior.cr`, `src/movie/system.cr` for canonical patterns.
- Prefer explicit supervision config where failures are expected (LLM calls, tool IO).
