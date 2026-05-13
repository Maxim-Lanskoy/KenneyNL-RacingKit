class_name Vehicle extends Node3D

@export_category("Nodes")
@export var sphere: RigidBody3D
@export var raycast: RayCast3D
@export var model_holder: Node3D

@export_category("Model")
@export var model_scene: PackedScene

@export_category("Audio")
@export var screech_sound: AudioStreamPlayer3D
@export var engine_sound: AudioStreamPlayer3D
@export var impact_sound: AudioStreamPlayer3D

var input: Vector3
var normal: Vector3

var acceleration: float
var angular_speed: float
var linear_speed: float

var colliding: bool

var linear_velocity: Vector3
var prev_position: Vector3

var calculated_lean: float

var _model: VehicleModel

# Public Functions

func get_vehicle_position() -> Vector3:
	return model_holder.global_position

# Private Functions

func _ready():

	assert(model_scene != null, "Vehicle requires model_scene to be set")

	_model = model_scene.instantiate()
	model_holder.add_child(_model)

	engine_sound.stream = _model.engine_stream
	engine_sound.play()

func _physics_process(delta):

	_handle_input(delta)

	var direction = sign(linear_speed)
	if direction == 0: direction = sign(input.z) if abs(input.z) > 0.1 else 1

	var steering_grip = clamp(abs(linear_speed), 0.2, 1.0)

	var target_angular = -input.x * steering_grip * 4 * direction
	angular_speed = lerp(angular_speed, target_angular, delta * 4)

	model_holder.rotate_y(angular_speed * delta)

	# Ground alignment

	if raycast.is_colliding():
		if !colliding:
			_model.on_landed()
			input.z = 0

		normal = raycast.get_collision_normal()

		if normal.dot(model_holder.global_basis.y) > 0.5:
			var xform = _align_with_y(model_holder.global_transform, normal)
			model_holder.global_transform = model_holder.global_transform.interpolate_with(xform, 0.2).orthonormalized()

	colliding = raycast.is_colliding()

	var target_speed = input.z

	if (target_speed < 0 and linear_speed > 0.01):
		linear_speed = lerp(linear_speed, 0.0, delta * 8)
	else:
		if (target_speed < 0):
			linear_speed = lerp(linear_speed, target_speed / 2, delta * 2)
		else:
			linear_speed = lerp(linear_speed, target_speed, delta * 6)

	acceleration = lerpf(acceleration, linear_speed + (abs(sphere.angular_velocity.length() * linear_speed) / 100), delta * 1)

	# Match the pivot to the physics sphere

	model_holder.position = sphere.position - Vector3(0, 0.65, 0)
	raycast.position = sphere.position

	linear_velocity = (model_holder.position - prev_position) / delta
	prev_position = model_holder.position

	calculated_lean = lerp_angle(calculated_lean, -input.x / 5 * linear_speed, delta * 5)

	# Visual and audio effects

	_effect_engine(delta)
	_model.update_pose(input, linear_speed, acceleration, calculated_lean, delta)
	_effect_trails()

# Handle input when vehicle is colliding with ground

func _handle_input(delta):

	if raycast.is_colliding():
		input.x = Input.get_axis("left", "right")
		input.z = Input.get_axis("back", "forward")

	sphere.angular_velocity += model_holder.get_global_transform().basis.x * (linear_speed * 100) * delta

# Engine sound

func _effect_engine(delta):

	var speed_factor = clamp(abs(linear_speed), 0.0, 1.0)
	var throttle_factor = clamp(abs(input.z), 0.0, 1.0)

	var target_volume = remap(speed_factor + (throttle_factor * 0.5), 0.0, 1.5, -15.0, -5.0)
	engine_sound.volume_db = lerp(engine_sound.volume_db, target_volume, delta * 5.0)

	var target_pitch = remap(speed_factor, 0.0, 1.0, 0.5, 3)
	if throttle_factor > 0.1: target_pitch += 0.2

	engine_sound.pitch_scale = lerp(engine_sound.pitch_scale, target_pitch, delta * 2.0)

# Drift detection: model handles trails, rig handles the skid sound

func _effect_trails():

	var drift_intensity = abs(linear_speed - acceleration) + (abs(calculated_lean) * 2.0)
	var should_emit = drift_intensity > 0.25

	_model.set_trail_emit(should_emit)

	var target_volume = -80.0
	if should_emit: target_volume = remap(clamp(drift_intensity, 0.25, 2.0), 0.25, 2.0, -10.0, 0.0)

	screech_sound.pitch_scale = lerp(screech_sound.pitch_scale, clamp(abs(linear_speed), 1.0, 3.0), 0.1)
	screech_sound.volume_db = lerp(screech_sound.volume_db, target_volume, 10.0 * get_physics_process_delta_time())

# Align transform basis with a ground normal

func _align_with_y(xform, new_y):

	xform.basis.y = new_y
	xform.basis.x = -xform.basis.z.cross(new_y)
	xform.basis = xform.basis.orthonormalized()
	return xform

# Detect collisions and play impact sound

func _on_sphere_body_entered(_body: Node) -> void:

	if _model.body == null: return

	if not impact_sound.playing:
		var impact_velocity := absf(linear_velocity.dot(_model.body.global_basis.z))
		impact_sound.volume_db = clampf(remap(impact_velocity, 0.0, 6.0, -20.0, 0.0), -20.0, 0.0)
		impact_sound.play()
