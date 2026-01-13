# Changelog

## 2026-01-13

### Added
- Auto-spawn of main behavior and root delivery wiring in the actor system to ensure `system <<` reaches the main actor.

### Fixed
- `ReceiveMessageBehavior` constructor/`Behaviors.receive` now use the correct handler signature and return behavior transitions are applied.
- `ActorContext#log` accessor fixed; lifecycle logging now uses the logger instead of thread-unsafe `puts`.
- DispatcherRegistry deduplicated and cached default/internal dispatchers to avoid duplicate definitions.
- Specs updated to cover receive handler invocation, logger access, dispatcher registry usage, and root message delivery.

### Known
- Deprecated `sleep` warnings remain in specs; tracked via Linear OZW-36.
