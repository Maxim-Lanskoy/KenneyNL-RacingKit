class_name VehicleModel extends Node3D

# Base class for vehicle visual adapters. Subclass per vehicle type to
# wire its specific parts (wheels, fork, etc.). The Vehicle rig calls
# update_pose every physics frame and on_landed when transitioning from
# air to ground, and set_trail_emit when the drift threshold is crossed.

@export var body: Node3D
@export var engine_stream: AudioStream

@export_group("Trails")
@export var trail_left: GPUParticles3D
@export var trail_right: GPUParticles3D

func update_pose(_input: Vector3, linear_speed: float, acceleration: float, calculated_lean: float, delta: float) -> void:

	if body == null: return

	body.rotation.x = lerp_angle(body.rotation.x, -(linear_speed - acceleration) / 6, delta * 10)
	body.rotation.z = calculated_lean
	body.position = body.position.lerp(Vector3(0, 0.2, 0), delta * 5)

func on_landed() -> void:

	if body != null:
		body.position = Vector3(0, 0.1, 0)

func set_trail_emit(emit: bool) -> void:

	if trail_left != null: trail_left.emitting = emit
	if trail_right != null: trail_right.emitting = emit
