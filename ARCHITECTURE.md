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
| `race-manager.gd` | `RaceManager extends Node` | Deferred-setup `Node` that auto-discovers `Checkpoint` group members (or uses an explicit `checkpoints` override), sorts by `index`, and tracks per-vehicle lap progress. Emits `race_started`, `lap_completed(vehicle, lap, time)`, `vehicle_finished(vehicle, total)`. |
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
- **AI driver** → new `InputProvider` subclass that computes steering/throttle from desired path, swapped into `Vehicle.input_provider`.
- **Network player** → another `InputProvider` subclass whose `get_steering`/`get_throttle` read replicated values. For state replication, add a `MultiplayerSynchronizer` watching `Vehicle.sphere` and `Vehicle.model_holder.transform` (set authority per spawned vehicle).
- **New handling profile** → new `*-config.tres`; wire it into a model's `config` export.
- **More checkpoints** → just drop another `checkpoint.tscn` instance into the scene tree and set its `index`. `RaceManager` auto-discovers via the `"checkpoints"` group at startup — no manual wiring. Use the `RaceManager.checkpoints` Inspector override only for filtered/multi-track setups.
- **Race logic** → drop `SpawnPoint`s and `Checkpoint`s into the track scene, add a `RaceManager` node, connect its signals to your HUD/game state. `main.gd` is the demo glue example.

## Invariants & assumptions

- `Vehicle.model_scene` must be set (assert in `_ready`). The instantiated scene's root must extend `VehicleModel`.
- `Vehicle.input_provider` must be set (assert in `_ready`).
- `VehicleModel.body`, if non-null, must be a sub-node of the model — not the model adapter root. The base `update_pose` lerps `body.position`, which the rig is *not* setting; if `body == self` the visual would drift relative to `ModelHolder`. Vehicles without a separable body should leave `body = null` and override `update_pose` entirely (motorcycle does the latter).
- All trail material/process visual config is shared via `scenes/trail-smoke-material.tres` and `scenes/trail-process-material.tres`. Each model scene references them and contributes only its own per-position trail nodes.
- The `Vehicle.sphere` `RigidBody3D` has `contact_monitor = true` and `max_contacts_reported >= 1` for the impact signal to fire. It's on `collision_layer = 8` (layer 4); `Checkpoint`'s `collision_mask` must include this bit. Jolt Physics requires `Checkpoint.collision_layer != 0` and `monitorable = true` for body detection — the kit's default `checkpoint.tscn` complies.
- `RaceManager._ready` defers its setup by one frame so every `Checkpoint._ready` has had a chance to `add_to_group(Checkpoint.GROUP)`. Same pattern in `SpawnPoint`: `spawn.call_deferred()` to avoid `add_child` racing with the parent's `_ready` propagation.
- The first `body_entered` event for a vehicle spawned *inside* a checkpoint area is silently ignored by `RaceManager` (out-of-order: `index != next_index`). This makes it safe to place the start/finish checkpoint at the spawn position.
