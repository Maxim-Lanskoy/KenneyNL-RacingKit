<p align="center"><img src="icon.png"/></p>

# Starter Kit Racing

This package includes a basic template for a racing game in Godot 4.6. Includes features like;

- Arcade-like vehicle controls
- Smoke effect
- GridMap based track creation
- 3D Models & sounds _(CC0 licensed)_
- Composable vehicle architecture: rig + swappable model adapter + tunable handling config
- Pluggable input source (local / AI / network-ready)
- Race scaffold: spawn points, checkpoints, race manager

### Screenshot

<p align="center"><img src="screenshots/screenshot.png"/></p>

### Controls

| Key | Command |
| --- | --- |
| <kbd>W</kbd> | Accelerate/brake |
| <kbd>S</kbd> | Brake/reverse |
| <kbd>A</kbd> <kbd>D</kbd> | Steering |

### Project Architecture

The vehicle is composed of three pieces. See [`ARCHITECTURE.md`](ARCHITECTURE.md) for a full breakdown.

- **`scenes/vehicle.tscn`** — the rig: physics sphere, ground raycast, audio, and a `ModelHolder` where the active model is instanced at runtime.
- **`scenes/car-model.tscn`** / **`scenes/motorcycle-model.tscn`** — model adapters, each carrying their own GLB visual, antenna, trails, engine sound, and `VehicleConfig`.
- **`scripts/vehicle-config.gd`** — a `Resource` describing per-vehicle handling (steering, accel, brake, engine pitch/volume range).

### Instructions

#### 1. How to adjust the track?

Select the 'GridMap' node and place pre-made tiles in the world.

#### 2. How to swap between car and motorcycle?

Open `vehicle.tscn`, select the `Vehicle` root node, and change the `Model Scene` property to `car-model.tscn` or `motorcycle-model.tscn`. Save and run.

#### 3. How to add a new vehicle?

For most vehicles you only need four files (two scripts, one model scene, one config resource).

1. Add your GLB under `models/` (or reuse one of the included ones).
2. Create a model script extending `VehicleModel` in `scripts/`. Override `update_pose` for any per-vehicle visual animation (e.g. wheel spin, fork rotation, leaning). See `car-model.gd` and `motorcycle-model.gd` for examples.
3. Create a model scene packaging the GLB, antenna, trails, and your script. Wire the script's exports (`body`, `engine_stream`, `trail_left/right`, etc.) to the appropriate inner nodes via the scene's `node_paths`. Use `[editable path="Mesh"]` to expose the GLB's children.
4. Create a `VehicleConfig` resource in `scenes/yourvehicle-config.tres` and wire it into your model scene's `config` export.
5. Point `Vehicle.model_scene` at your new model scene.

#### 4. How to customize handling per vehicle?

Edit the matching `*-config.tres` resource in `scenes/` (e.g. `car-config.tres`, `motorcycle-config.tres`). Each resource exposes steering, acceleration, sphere coupling, and engine audio parameters that the rig reads every frame. Different configs per vehicle let a truck feel heavy and a motorcycle agile without forking scripts.

#### 5. How to use a different input source (AI, networking)?

`Vehicle.input_provider` accepts any node that extends `InputProvider`. The default `LocalInputProvider` reads `InputMap` actions (`left`/`right`/`back`/`forward` by default). For AI or networked players, write a subclass overriding `get_steering()` and `get_throttle()` and swap it in via the editor:

- **AI** — see the bundled `AIInputProvider` + `AISpawner` (section 7 below) for the kit's pure-pursuit implementation, or subclass `InputProvider` for your own.
- **Networked player** — return values replicated from the network layer (e.g. via `MultiplayerSynchronizer` on a state node).

`LocalInputProvider` also exposes an optional `action_prefix` (defaults to empty) for namespacing — e.g. setting it to `"my_"` would read `my_left`/`my_right`/etc. — but you'd need to define those actions in `InputMap` yourself.

#### 6. Race scaffold

The kit ships with three building blocks for racing logic:

- **`scenes/spawn-point.tscn`** — a `Marker3D` that instantiates a Vehicle scene at its transform. Set `vehicle_scene` in the editor. Auto-spawns on `_ready` (deferred to avoid `add_child` racing with parent setup); disable `auto_spawn` if you want a `RaceManager` or game state to trigger the spawn.
- **`scenes/checkpoint.tscn`** — an `Area3D` trigger with a translucent yellow `VisualIndicator` box (visible only in the editor — hidden at runtime) so you can position and rotate trigger zones on the track at a glance. Set `index` to order checkpoints around the lap. Emits `passed(vehicle, index)`.
- **`scripts/race-manager.gd`** — a `Node` that watches checkpoints, tracks per-vehicle lap progress, and emits `race_started`, `lap_completed(vehicle, lap, time)`, and `vehicle_finished(vehicle, total_time)`. **Auto-discovers** every `Checkpoint` in the scene by group lookup (`"checkpoints"`) and sorts them by `index` — drop a new Checkpoint anywhere, set its index, and it joins the race. The `checkpoints` `@export` array remains as an optional explicit override for multi-track scenes.

`main.tscn` ships with a working demo: a `SpawnPoint` at the start line (the `View` camera latches onto the spawned vehicle via the `spawned` signal), three `Checkpoint` triggers around the GridMap track, and a `RaceManager` whose lap signals connect to print handlers in `scripts/main.gd` (`[Race] Started`, `[Race] <vehicle_name> lap N in N.NNs`, `[Race] <vehicle_name> finished in N.NNs`). Replace `main.gd` with your HUD / results-screen logic when forking. Spawning inside a checkpoint at race start is fine — `RaceManager`'s out-of-order check silently ignores the initial entry until the vehicle crosses checkpoint 0 in order.

#### 7. Adding AI opponents

The kit ships with a `Path3D` + `AISpawner` pair that drops N AI-driven cars onto a racing line of your choosing. Each AI is a regular `vehicle.tscn` instance — same sphere physics, same model adapter (wheels spin, trails emit when drifting, engine plays, sphere collides with the player) — with its `LocalInputProvider` swapped for an `AIInputProvider`.

- **`scripts/ai-input-provider.gd`** — Pure-pursuit driver. Each physics frame projects the host vehicle onto the path, samples a lookahead point farther along the curve, and produces steering / throttle to aim at it. Throttle is reduced through tight corners so the sphere doesn't drift through the wall.
- **`scenes/ai-spawner.tscn` + `scripts/ai-spawner.gd`** — `Marker3D` that instantiates `count` vehicles evenly spaced along the path and swaps in the AI provider. Deferred spawn (one frame) so `add_child` doesn't race the parent scene's setup. `count = 0` is valid — nothing spawns, no errors.

To add AI to a track:

1. Drop a `Path3D` into the scene and draw a **closed** racing line (set `curve.closed = true` so AI laps endlessly). AI travels in the curve's drawing direction (increasing baked offset) — if the AI runs the wrong way around your track, reverse the curve point order in the editor.
2. Drop an `AISpawner` near the start. In the Inspector wire:
   - `vehicle_scene` → `scenes/vehicle.tscn`
   - `ai_model_scene` → a model scene (e.g. `scenes/car-model.tscn`). Optional; if left empty, AI uses the vehicle's default model.
   - `path` → your `Path3D`
   - `profile` → a difficulty preset (see below). Optional; if left empty, AI uses Normal defaults.
3. Set `count` and run.

The AI path is **independent of `Checkpoint`s** — Path3D is the racing line, Checkpoints are lap detectors. AI cars do trip Checkpoints though, so their laps appear in `main.gd`'s race log alongside the player's (prefixed by vehicle name, e.g. `[Race] AIVehicle_0 lap 1 in 23.45s`). Filter by vehicle name or group if you want player-only events.

##### Difficulty profiles

AI tuning lives in an **`AIProfile`** resource (`scripts/ai-profile.gd`) — a named bundle of five knobs, the same pattern as `VehicleConfig` for vehicle handling. The kit ships three presets in `scenes/`:

| Preset | Feel | Key differences |
|---|---|---|
| `ai-easy.tres` | Slow, cautious, beatable | Low `target_throttle` (0.6), short `lookahead` (7 — reacts late) |
| `ai-normal.tres` | Balanced | The tuned baseline values |
| `ai-hard.tres` | Fast, looks far ahead, carries corner speed | High `target_throttle` (0.95), long `lookahead` (12), higher `min_corner_throttle` |

Wire one into `AISpawner.profile` to set the difficulty for every car that spawner produces. For a mixed field, use multiple `AISpawner`s with different profiles. To make your own, duplicate a `.tres` and edit:

| Parameter | What it does |
|---|---|
| `lookahead` | How far ahead on the curve the AI aims, in meters. Higher = earlier reactions; too far cuts the apex. |
| `steering_softness` | Larger = gentler steering for the same lateral error. Too small and the AI oscillates on straights. |
| `target_throttle` | Cruise throttle on straights, in `[0, 1]`. |
| `corner_brake_threshold` | Steering magnitude at which braking begins. Lower = AI brakes earlier into corners. |
| `min_corner_throttle` | Floor throttle through the tightest corners. |

If AI clips inside walls on tight turns, lower `target_throttle` or `min_corner_throttle`. If AI reacts too late, raise `lookahead`. If AI oscillates on straights, raise `steering_softness`.

### License

MIT License

Copyright (c) 2026 Kenney

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Assets included in this package (2D sprites, 3D models and sound effects) are [CC0 licensed](https://creativecommons.org/publicdomain/zero/1.0/)
