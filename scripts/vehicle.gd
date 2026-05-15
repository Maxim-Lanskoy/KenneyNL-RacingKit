class_name Vehicle extends Node3D

# A fast-spinning physics sphere pressed against a wall or another sphere
# converts its spin into a vertical climb via contact friction. While
# grounded, upward velocity is capped to this fraction of horizontal speed
# (0.5 ≈ a 27° climb). Lower it if cars still ride up walls; raise it if a
# steep track needs the vehicle to climb faster than this.
const MAX_CLIMB_RATIO := 0.15

@export_category("Nodes")
@export var sphere: RigidBody3D
@export var raycast: RayCast3D
@export var model_holder: Node3D

@export_category("Model")
@export var model_scene: PackedScene

@export_category("Input")
@export var input_provider: InputProvider

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
var _config: VehicleConfig

# Public Functions

func get_vehicle_position() -> Vector3:
	return model_holder.global_position

# Private Functions

func _ready():

	assert(model_scene != null, "Vehicle requires model_scene to be set")
	assert(input_provider != null, "Vehicle requires input_provider to be set")

	_model = model_scene.instantiate()
	model_holder.add_child(_model)

	_config = _model.config if _model.config != null else VehicleConfig.new()

	engine_sound.stream = _model.engine_stream
	engine_sound.play()

func _physics_process(delta):

	_handle_input(delta)

	# Suppress wall / sphere climbing: a fast-spinning sphere converts its
	# spin into a vertical climb via contact friction. While grounded, cap
	# upward velocity to a fraction of horizontal speed — a car driving up a
	# slope keeps its climb; a car stuck against a wall (≈ zero horizontal
	# speed) cannot rise.
	if raycast.is_colliding():
		var v := sphere.linear_velocity
		if v.y > 0.0:
			var horizontal := Vector2(v.x, v.z).length()
			v.y = minf(v.y, horizontal * MAX_CLIMB_RATIO)
			sphere.linear_velocity = v

	var direction = sign(linear_speed)
	if direction == 0: direction = sign(input.z) if abs(input.z) > 0.1 else 1

	var steering_grip = clamp(abs(linear_speed), _config.min_steering_grip, _config.max_steering_grip)

	var target_angular = -input.x * steering_grip * _config.max_steering * direction
	angular_speed = lerp(angular_speed, target_angular, delta * _config.steering_smoothing)

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
		linear_speed = lerp(linear_speed, 0.0, delta * _config.brake_rate)
	else:
		if (target_speed < 0):
			linear_speed = lerp(linear_speed, target_speed / 2, delta * _config.reverse_rate)
		else:
			linear_speed = lerp(linear_speed, target_speed, delta * _config.forward_rate)

	acceleration = lerpf(acceleration, linear_speed + (abs(sphere.angular_velocity.length() * linear_speed) / 100), delta * _config.accel_smoothing)

	# Match the pivot to the physics sphere

	model_holder.position = sphere.position - Vector3(0, _config.sphere_offset_y, 0)
	raycast.position = sphere.position

	linear_velocity = (model_holder.position - prev_position) / delta
	prev_position = model_holder.position

	calculated_lean = lerp_angle(calculated_lean, -input.x / 5 * linear_speed, delta * 5)

	# Visual and audio effects

	_effect_engine(delta)
	_model.update_pose(input, linear_speed, acceleration, calculated_lean, delta)
	_effect_trails()

# Read steering/throttle from the wired input provider when grounded

func _handle_input(delta):

	if raycast.is_colliding():
		input.x = input_provider.get_steering()
		input.z = input_provider.get_throttle()

	sphere.angular_velocity += model_holder.get_global_transform().basis.x * (linear_speed * 100) * delta

# Engine sound

func _effect_engine(delta):

	var speed_factor = clamp(abs(linear_speed), 0.0, 1.0)
	var throttle_factor = clamp(abs(input.z), 0.0, 1.0)

	var target_volume = remap(speed_factor + (throttle_factor * 0.5), 0.0, 1.5, _config.engine_volume_min, _config.engine_volume_max)
	engine_sound.volume_db = lerp(engine_sound.volume_db, target_volume, delta * 5.0)

	var target_pitch = remap(speed_factor, 0.0, 1.0, _config.engine_pitch_min, _config.engine_pitch_max)
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
