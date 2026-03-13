# Reverse-Engineering Roadmap

## Immediate goals

1. Recover the project from the embedded Godot pack.
2. Confirm the exact engine version and import settings reported by GDRE.
3. Identify which gameplay systems live in `GDScript` versus the native `libgdblocks` module.

## First files and systems to inspect after recovery

- startup scene and autoload singletons
- main menu flow and save selection
- player controller and camera
- world seed and chunk generation
- block placement and block breaking
- inventory, item spawning, and item pickup
- enemy spawn, AI, and combat
- save format and serialization boundaries
- any firmament or online-share integration that should stay disabled for modded saves

## Co-op implementation order

1. Add a debug host/join path.
2. Spawn a remote player proxy.
3. Sync movement, facing, and animation state.
4. Sync block mutations.
5. Sync item pickup and inventory deltas.
6. Move enemy and combat authority to host.
7. Split co-op save data from vanilla save data.
8. Add reconnect handling and desync checks.

## Hard blockers to watch for

- chunk generation or save code implemented only in native code
- heavy use of preload-time scene wiring that makes late pack overrides ineffective
- physics or AI systems that assume exactly one local player exists
- Steam integration points tied directly into game flow
