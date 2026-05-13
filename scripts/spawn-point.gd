class_name SpawnPoint extends Marker3D

# Spawns a Vehicle scene at this marker's transform. Set vehicle_scene
# in the editor. If auto_spawn is true (default), the vehicle appears
# on _ready; otherwise call spawn() from a RaceManager or similar.

@export var vehicle_scene: PackedScene
@export var auto_spawn: bool = true

signal spawned(vehicle: Vehicle)

var _spawned: Vehicle

func _ready() -> void:
	if auto_spawn:
		# Defer until after the scene's _ready propagation completes,
		# otherwise `add_child` would race with the parent still being
		# initialized.
		spawn.call_deferred()

func spawn() -> Vehicle:
	if vehicle_scene == null:
		push_error("SpawnPoint: vehicle_scene is not set")
		return null

	if _spawned != null and is_instance_valid(_spawned):
		_spawned.queue_free()

	_spawned = vehicle_scene.instantiate()
	get_parent().add_child(_spawned)
	_spawned.global_transform = global_transform
	spawned.emit(_spawned)
	return _spawned

func get_spawned() -> Vehicle:
	return _spawned
