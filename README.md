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

#### 5. How to use a different input source (multiplayer, AI, networking)?

`Vehicle.input_provider` accepts any node that extends `InputProvider`. The default `LocalInputProvider` reads `InputMap` actions and supports an `action_prefix` for multiple local players (e.g. set `"p2_"` to read `p2_left`/`p2_right`/`p2_back`/`p2_forward`). For AI or networked players, write a subclass overriding `get_steering()` and `get_throttle()`, and swap it in via the editor.

#### 6. Race scaffold

The kit ships with three building blocks for racing logic:

- **`scenes/spawn-point.tscn`** — a `Marker3D` that instantiates a Vehicle scene at its transform. Set `vehicle_scene` in the editor and disable `auto_spawn` if you want a `RaceManager` to control timing.
- **`scenes/checkpoint.tscn`** — an `Area3D` with a `BoxShape3D` trigger. Set `index` to order checkpoints around the track. Emits `passed(vehicle, index)`.
- **`scripts/race-manager.gd`** — a `Node` that watches checkpoints, tracks per-vehicle lap progress, and emits `race_started`, `lap_completed(vehicle, lap, time)`, and `vehicle_finished(vehicle, total_time)`. Add it to your scene and wire its `checkpoints` array.

### License

MIT License

Copyright (c) 2026 Kenney

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Assets included in this package (2D sprites, 3D models and sound effects) are [CC0 licensed](https://creativecommons.org/publicdomain/zero/1.0/)
