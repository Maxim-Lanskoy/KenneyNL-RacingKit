class_name AISpawner extends Marker3D

# Spawns N AI-driven Vehicles distributed around the shared Path3D.
# Each spawn is a regular `vehicle.tscn` instance — same sphere physics,
# same model adapter (wheels spin, trails emit, engine audio, collisions
# with the player) — with its bundled LocalInputProvider swapped for an
# AIInputProvider wired to the path and the chosen difficulty profile.
#
# `count = 0` is valid: nothing spawns, no errors.

@export_group("Spawning")
@export var vehicle_scene: PackedScene
@export var ai_model_scene: PackedScene
@export var path: Path3D
@export var count: int = 3
@export var spacing_along_path: float = 8.0

@export_group("AI")
# Difficulty preset, forwarded to every spawned AIInputProvider. Pick an
# ai-easy / ai-normal / ai-hard .tres, or leave null for Normal defaults.
@export var profile: AIProfile

var _spawned: Array[Vehicle] = []

func _ready() -> void:
	# Deferred so `add_child` doesn't race with the parent scene's setup
	# (same fix as SpawnPoint).
	_spawn_all.call_deferred()

func _spawn_all() -> void:

	if count <= 0: return
	if vehicle_scene == null:
		push_error("AISpawner: vehicle_scene not set"); return
	if path == null:
		push_error("AISpawner: path not set"); return
	var curve := path.curve
	if curve == null or curve.get_baked_length() <= 0.0:
		push_error("AISpawner: path has no usable curve"); return

	var base_offset: float = curve.get_closest_offset(path.to_local(global_position))
	var baked_length: float = curve.get_baked_length()

	for i in range(count):
		var progress: float = fmod(base_offset + i * spacing_along_path, baked_length)
		var spawn_local := curve.sample_baked(progress)
		var spawn_world := path.to_global(spawn_local)
		var ahead_local := curve.sample_baked(fmod(progress + 0.5, baked_length))
		var ahead_world := path.to_global(ahead_local)
		var forward_world: Vector3 = ahead_world - spawn_world
		if forward_world.length() < 0.001:
			forward_world = Vector3.FORWARD
		else:
			forward_world = forward_world.normalized()
		_spawn_one(spawn_world, forward_world, i)

func _spawn_one(spawn_world: Vector3, forward_world: Vector3, index: int) -> void:

	var vehicle: Vehicle = vehicle_scene.instantiate()
	vehicle.name = "AIVehicle_%d" % index
	if ai_model_scene != null:
		vehicle.model_scene = ai_model_scene

	# Build a transform whose local +Z (the asset's nose direction in
	# kit convention) aligns with the path tangent; Y stays world-up.
	var up := Vector3.UP
	var fwd := forward_world
	if absf(fwd.dot(up)) > 0.99:
		fwd = Vector3.FORWARD
	var x_axis: Vector3 = up.cross(fwd).normalized()
	var spawn_basis := Basis(x_axis, up, fwd).orthonormalized()
	vehicle.transform = Transform3D(spawn_basis, spawn_world)

	# Swap the kit's LocalInputProvider for an AI provider BEFORE the
	# vehicle enters the tree, so the kit's `assert(input_provider)` in
	# Vehicle._ready sees the AI provider on first frame.
	var local := vehicle.get_node_or_null("LocalInputProvider")
	if local != null:
		vehicle.remove_child(local)
		local.queue_free()

	var ai := AIInputProvider.new()
	ai.name = "AIInputProvider"
	ai.path = path
	ai.profile = profile
	vehicle.add_child(ai)
	vehicle.input_provider = ai

	get_tree().current_scene.add_child(vehicle)
	_spawned.append(vehicle)

func get_spawned() -> Array[Vehicle]:
	return _spawned
