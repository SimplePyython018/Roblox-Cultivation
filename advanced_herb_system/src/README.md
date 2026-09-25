# Advanced Mobile Herb Detection & Auto-Farm UI

Roblox/Luau-oriented modular starter architecture for a **game you control or are authorized to automate**.

## Modules

- `Main.client.lua` — bootstrap and wiring
- `Config.lua` — tunables and safe adapters
- `StateManager.lua` — centralized feature/runtime state
- `UIController.lua` — mobile-first landscape utility UI, drag/clamp/minimize/exit
- `HerbDetector.lua` — recursive herb discovery, debounced rescans, validated registry
- `TargetManager.lua` — MANUAL/ALL modes, target locking, dedupe, queue, priorities
- `MovementController.lua` — validated movement abstraction with cancellation/timeouts
- `PromptController.lua` — prompt validation and collection adapter boundary
- `FarmController.lua` — explicit auto-farm state machine
- `ShutdownManager.lua` — centralized clean shutdown

## Important integration boundary

`PromptController` intentionally does **not** use exploit-only prompt firing or bypass APIs. Connect `Config.InteractionHandler` to the normal collection logic for your own Roblox experience (for example, your server-authoritative collection service / RemoteEvent).

The UI/detection/target-management layers are independent of that game-specific implementation.

## Expected hierarchy

`workspace.Game.spawn.Herbs` is the default path, but every segment is configurable. Detection is recursive and does not depend on a fixed depth or a fixed `Part` name.
