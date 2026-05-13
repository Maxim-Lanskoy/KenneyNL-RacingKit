class_name CarModel extends VehicleModel

@export var wheel_fl: MeshInstance3D
@export var wheel_fr: MeshInstance3D
@export var wheel_bl: MeshInstance3D
@export var wheel_br: MeshInstance3D

func update_pose(input: Vector3, linear_speed: float, acceleration: float, calculated_lean: float, delta: float) -> void:

	super.update_pose(input, linear_speed, acceleration, calculated_lean, delta)

	for wheel in [wheel_fl, wheel_fr, wheel_bl, wheel_br]:
		if wheel != null:
			wheel.rotation.x += acceleration

	if wheel_fl != null: wheel_fl.rotation.y = lerp_angle(wheel_fl.rotation.y, -input.x / 1.5, delta * 10)
	if wheel_fr != null: wheel_fr.rotation.y = lerp_angle(wheel_fr.rotation.y, -input.x / 1.5, delta * 10)
