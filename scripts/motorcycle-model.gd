class_name MotorcycleModel extends VehicleModel

@export var fork: Node3D
@export var wheel_front: MeshInstance3D
@export var wheel_back: MeshInstance3D

# Motorcycle leans the entire model around z; only the body subnode
# pitches forward/back. Steering rotates the fork and front wheel.

func update_pose(input: Vector3, linear_speed: float, acceleration: float, _calculated_lean: float, delta: float) -> void:

	rotation.z = lerp_angle(rotation.z, input.x * linear_speed, delta * 3)

	if body != null:
		body.rotation.x = lerp_angle(body.rotation.x, -(linear_speed - acceleration) / 6, delta * 10)

	for wheel in [wheel_front, wheel_back]:
		if wheel != null:
			wheel.rotation.x += acceleration

	if fork != null:
		fork.rotation.y = lerp_angle(fork.rotation.y, -input.x / 1.5, delta * 5)
	if wheel_front != null:
		wheel_front.rotation.y = lerp_angle(wheel_front.rotation.y, -input.x / 1.5, delta * 10)
