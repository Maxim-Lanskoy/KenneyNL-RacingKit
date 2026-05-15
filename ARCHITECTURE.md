# Architecture

This kit separates the **vehicle rig** (physics + audio + camera target) from the **vehicle model** (visuals + animation + handling profile). Swapping vehicle types is a `PackedScene` change on a single export, not a scene rewrite.

## Scene tree

```
Vehicle (vehicle.gd) ......................... the rig
├── Ground (RayCast3D) ....................... ground detection
├── ModelHolder (Node3D) ..................... pivot the script positions/rotates
│   ├── ScreechSound (autoplay) .............. skid audio
│   ├── EngineSound .......................... stream wired from model at _ready
│   └── ImpactSound .......................... collision audio
├── LocalInputProvider (Node) ................ input source (swappable)
└── Sphere (RigidBody3D) ..................... physics body
    └── CollisionShape3D
```

At runtime, `Vehicle._ready` instantiates `model_scene` and adds it as a child of `ModelHolder`:

```
ModelHolder
├── (audio nodes)
└── CarModel | MotorcycleModel (the instantiated model)
    ├── Mesh (GLB instance)
    │   ├── body, wheels...                   GLB internals
    │   └── Antenna
    ├── TrailLeft / TrailRight ............... per-vehicle trail positions
```

## Scripts

| Script | Type | Role |
|---|---|---|
| `vehicle.gd` | `Vehicle extends Node3D` | The rig. Handles steering input → sphere physics → ground alignment → audio. Delegates per-frame visual updates and trail emission to its `_model`. |
| `vehicle-model.gd` | `VehicleModel extends Node3D` | Base class for vehicle adapters. Default `update_pose` tilts a leanable `body` subnode; default `on_landed` bounces it. Owns `trail_left/right` and exposes `set_trail_emit(bool)`. |
| `car-model.gd` | `CarModel extends VehicleModel` | Spins four wheels, rotates the front wheels for steering. |
| `motorcycle-model.gd` | `MotorcycleModel extends VehicleModel` | Leans the entire model around z; rotates the fork and the front wheel for steering; spins two wheels. |
| `vehicle-config.gd` | `VehicleConfig extends Resource` | Handling profile: steering response, acceleration rates, sphere coupling offset, engine audio range. Each model carries one. |
| `input-provider.gd` | `InputProvider extends Node` | Interface returning steering/throttle in `[-1.0, 1.0]`. |
| `local-input-provider.gd` | `LocalInputProvider extends InputProvider` | Polls `InputMap` actions with an optional `action_prefix` for per-player namespacing. |
| `spawn-point.gd` | `SpawnPoint extends Marker3D` | Instantiates a Vehicle at this transform. Auto-spawns on `_ready` by default (deferred via `call_deferred` so `add_child` doesn't race the parent's setup). Emits `spawned(vehicle)`. |
| `checkpoint.gd` | `Checkpoint extends Area3D` | Registers itself in the `"checkpoints"` group on `_ready` so `RaceManager` can auto-discover. Emits `passed(vehicle, index)` when a Vehicle's sphere enters. Carries an editor-only `VisualIndicator` mesh hidden at runtime. |
| `race-manager.gd` | `RaceManager extends Node` | Deferred-setup `Node` that auto-discovers `Checkpoint` group members (or uses an explicit `checkpoints` override), sorts by `index`, and tracks per-vehicle lap progress. Emits `race_started`, `lap_completed(vehicle, lap, time)`, `vehicle_finished(vehicle, total)`. `lap_completed` keeps firing as long as a vehicle laps; `vehicle_finished` fires exactly once. |
| `ai-spawner.gd` | `AISpawner extends Marker3D` | Deferred-spawn `Marker3D` that instantiates N vehicles evenly spaced along a shared `Path3D`, swaps each one's `LocalInputProvider` for an `AIInputProvider`, forwards its `AIProfile` to each, and adds them to the scene's root. `count = 0` is valid (no spawn, no errors). Exposes `get_spawned()`. |
| `ai-input-provider.gd` | `AIInputProvider extends InputProvider` | Pure-pursuit AI driver. Each physics frame samples a fixed-distance lookahead point on a shared `Path3D` and produces steering / throttle to aim at it. Throttle is reduced when the corner is sharp so the sphere doesn't drift through the wall. Connects to its vehicle's sphere `body_entered`: a hit from another vehicle cuts steering authority briefly and shoves the pursued line sideways (decaying back over time). Three forward feeler raycasts add reactive obstacle avoidance (walls and other vehicles). All tuning is read from an `AIProfile`. |
| `ai-profile.gd` | `AIProfile extends Resource` | Difficulty preset: the `AIInputProvider` tuning knobs (pure pursuit, throttle, corner braking, hit reaction, obstacle avoidance) bundled into a Resource. Kit ships `ai-easy/normal/hard.tres`. Mirrors how `VehicleConfig` carries vehicle handling. |
| `view.gd` | `View extends Node3D` | Camera follower. Reads `target.get_vehicle_position()` and `target.linear_speed` for zoom. Optional `spawn_point` export connects to `SpawnPoint.spawned` so the camera latches onto a runtime-spawned vehicle (otherwise wire `target` directly). |
| `main.gd` | `extends Node3D` | Demo glue on the `Main` scene root. Receives `RaceManager`'s `race_started`, `lap_completed`, `vehicle_finished` signals and prints them. Replace with HUD / game-state logic when forking. |

## Data flow per frame

```
InputProvider.get_steering/get_throttle()
            │
            ▼
Vehicle._handle_input → input.x, input.z (only when grounded)
            │
            ▼
Vehicle._physics_process
  ├─ climb suppression         (cap upward velocity vs. horizontal speed)
  ├─ ModelHolder.rotate_y      (steering)
  ├─ ground alignment          (lerp toward raycast normal)
  ├─ linear_speed lerp         (target ± brake/forward/reverse, from VehicleConfig)
  ├─ sphere.angular_velocity   (drives the physics ball forward)
  ├─ ModelHolder.position      (= sphere.position − config.sphere_offset_y)
  └─ delegate visuals:
       ├─ _effect_engine        (engine_sound pitch + volume from config range)
       ├─ _model.update_pose    (wheel spin, body lean, fork rotation — per model)
       └─ _effect_trails        (drift detection → _model.set_trail_emit + screech)
```

`_on_sphere_body_entered` is the only thing outside `_physics_process` — it fires impact_sound proportional to `linear_velocity · body.global_basis.z`.

## Extension points

- **New vehicle type** → new model script (extends `VehicleModel`) + new model scene + new config `.tres`. The rig doesn't change.
- **AI driver** → the kit ships `AIInputProvider` (pure pursuit + corner braking) and `AISpawner` (populates N AI cars along a shared `Path3D`). For different behaviors — context steering, racing-line learning, inter-AI separation — subclass `InputProvider` and either swap it manually into individual vehicles or fork `AISpawner` to construct your provider type.
- **AI difficulty** → new `AIProfile` `.tres` (duplicate `ai-easy/normal/hard.tres` and retune the five knobs). Wire it into `AISpawner.profile`; use multiple spawners with different profiles for a mixed-skill field.
- **Network player** → another `InputProvider` subclass whose `get_steering`/`get_throttle` read replicated values. For state replication, add a `MultiplayerSynchronizer` watching `Vehicle.sphere` and `Vehicle.model_holder.transform` (set authority per spawned vehicle).
- **New handling profile** → new `*-config.tres`; wire it into a model's `config` export.
- **More checkpoints** → just drop another `checkpoint.tscn` instance into the scene tree and set its `index`. `RaceManager` auto-discovers via the `"checkpoints"` group at startup — no manual wiring. Use the `RaceManager.checkpoints` Inspector override only for filtered/multi-track setups.
- **Race logic** → drop `SpawnPoint`s and `Checkpoint`s into the track scene, add a `RaceManager` node, connect its signals to your HUD/game state. `main.gd` is the demo glue example.

## Invariants & assumptions

- `Vehicle.model_scene` must be set (assert in `_ready`). The instantiated scene's root must extend `VehicleModel`.
- `Vehicle.input_provider` must be set (assert in `_ready`).
- `VehicleModel.body`, if non-null, must be a sub-node of the model — not the model adapter root. The base `update_pose` lerps `body.position`, which the rig is *not* setting; if `body == self` the visual would drift relative to `ModelHolder`. Vehicles without a separable body should leave `body = null` and override `update_pose` entirely (motorcycle does the latter).
- All trail material/process visual config is shared via `scenes/trail-smoke-material.tres` and `scenes/trail-process-material.tres`. Each model scene references them and contributes only its own per-position trail nodes.
- A fast-spinning `Vehicle.sphere` pressed against a wall or another sphere converts its spin into a vertical climb via contact friction — pronounced here because the kit pumps `angular_velocity` every frame and the physics material's `friction = 5.0` is high. `Vehicle._physics_process` counters it by capping upward velocity to `MAX_CLIMB_RATIO ×` horizontal speed while grounded, so slopes still work but a stuck car can't ride up a wall.
- The `Vehicle.sphere` `RigidBody3D` has `contact_monitor = true` and `max_contacts_reported >= 1` for the impact signal to fire. It's on `collision_layer = 8` (layer 4); `Checkpoint`'s `collision_mask` must include this bit. Jolt Physics requires `Checkpoint.collision_layer != 0` and `monitorable = true` for body detection — the kit's default `checkpoint.tscn` complies. `AIInputProvider` also listens to `sphere.body_entered` for its hit reaction; `max_contacts_reported = 4` (raised from the kit's original 2) leaves room for ground + wall + multiple cars so vehicle-vs-vehicle hits aren't dropped in pile-ups.
- `AIInputProvider` obstacle avoidance casts three feeler rays each physics frame via the direct space state, with `collision_mask = 9` (ground/walls layer 1 + vehicles layer 4) and the host's own sphere excluded. The rays are oriented along the local ground plane (forward/side axes projected with `_vehicle.normal`) so they follow the track up and down slopes. A hit on a dynamic body (another vehicle — the only `RigidBody3D` on these layers) always counts; a hit on static geometry counts only if its surface normal is wall-like (`normal.dot(UP) < 0.5`), so the road, ramps and banking read as drivable. Remaining caveat: the rays only know the slope at the car's position, not at the ray's far tip, so a very abrupt grade change can still produce a brief (usually normal-filtered) false hit. The steering bias is added *after* the recovery-stun multiplier, so avoidance still works while a car is stunned.
- `RaceManager._ready` defers its setup by one frame so every `Checkpoint._ready` has had a chance to `add_to_group(Checkpoint.GROUP)`. Same pattern in `SpawnPoint`: `spawn.call_deferred()` to avoid `add_child` racing with the parent's `_ready` propagation.
- The first `body_entered` event for a vehicle spawned *inside* a checkpoint area is silently ignored by `RaceManager` (out-of-order: `index != next_index`). This makes it safe to place the start/finish checkpoint at the spawn position.
- AI cars use the same `vehicle.tscn` rig as the player; the rig's `Sphere.collision_mask = 9` (layer 1 = ground, layer 4 = vehicles), so AI ↔ player ↔ AI physical collisions all resolve. Changing the layer/mask values is the contract for "vehicles collide with each other"; keep them symmetric across the player and any AI spawners.
- `AIInputProvider.path` must be a `Path3D` whose `curve.closed = true`, otherwise lookahead wrapping at the loop seam (`fmod(progress, baked_length)`) produces a discontinuous racing line and the AI snaps when the offset wraps. The path is logically separate from `Checkpoint` placement — Path3D defines the racing line, Checkpoints define lap detection. AI cars do trigger Checkpoints though, so their `lap_completed` events fire alongside the player's.
- AI travels in the curve's drawing direction — `current_offset + lookahead` advances along the order the user added the points. Reversing the lap direction means reordering the curve's points (or swapping start/end), not flipping a flag in code.
- `AISpawner` adds spawned vehicles to `get_tree().current_scene`, not to itself. This prevents the spawner's transform from propagating into vehicle physics and makes the AI vehicles siblings of the player in the scene tree (so `view.gd` and other player-targeted glue is unaffected).
- `AIInputProvider` hit-reaction state (`_recovery_timer`, `_lateral_offset`, `_last_path_normal`) lives on the provider instance — never on the `AIProfile`. The profile is read-only tuning shared by reference across every car a spawner produces; per-car runtime state must stay off it. The provider connects to `Vehicle.sphere.body_entered` alongside the kit's own `_on_sphere_body_entered` (multiple connections to one signal are fine) and filters to collision layer 4 so only vehicle-vs-vehicle hits trigger a reaction.
