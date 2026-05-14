class_name AIInputProvider extends InputProvider

# Pure-pursuit AI driver. Reads its host Vehicle's position each physics
# frame, projects it onto the shared Path3D, samples a point `lookahead`
# meters farther along the curve, and returns steering/throttle to drive
# the kit's regular Vehicle rig toward that point. Throttle is reduced
# when the corner is sharp so the sphere doesn't drift through the wall.
#
# Reacts to collisions with other vehicles: a hit briefly cuts steering
# authority (so the impact's momentum carries the car off-line) and shoves
# the pursued racing line sideways, which then decays back over time.
#
# All tuning lives in an AIProfile resource (the difficulty preset). Leave
# `profile` null to fall back to AIProfile's defaults (= the Normal preset).

@export var path: Path3D
@export var profile: AIProfile

var _vehicle: Vehicle
var _profile: AIProfile
var _steering: float = 0.0
var _throttle: float = 0.0

# Hit-reaction runtime state — per vehicle, never stored on the shared
# AIProfile resource. _last_path_normal is the curve's world-space
# horizontal normal at the lookahead point, refreshed each physics frame.
var _recovery_timer: float = 0.0
var _lateral_offset: float = 0.0
var _last_path_normal: Vector3 = Vector3.ZERO

func _ready() -> void:

	_vehicle = get_parent() as Vehicle
	assert(_vehicle != null, "AIInputProvider must be a child of a Vehicle")
	assert(path != null, "AIInputProvider.path is not set")
	assert(path.curve != null and path.curve.get_baked_length() > 0.0, "AIInputProvider.path has no usable curve")

	_profile = profile if profile != null else AIProfile.new()

	if _vehicle.sphere != null:
		_vehicle.sphere.body_entered.connect(_on_sphere_hit)

func _physics_process(delta: float) -> void:

	if _vehicle == null or path == null: return
	var curve := path.curve
	if curve == null: return
	var baked_length := curve.get_baked_length()
	if baked_length <= 0.0: return

	if _recovery_timer > 0.0:
		_recovery_timer -= delta
	_lateral_offset = move_toward(_lateral_offset, 0.0, _profile.lateral_recenter_rate * delta)

	var vehicle_world := _vehicle.get_vehicle_position()
	var vehicle_local := path.to_local(vehicle_world)
	var current_offset := curve.get_closest_offset(vehicle_local)

	var target_offset := fmod(current_offset + _profile.lookahead, baked_length)
	var target_world_base := path.to_global(curve.sample_baked(target_offset))

	# Curve tangent + horizontal normal at the lookahead point, world space.
	# The normal lets a hit shove the pursued line sideways (_lateral_offset)
	# and recenter it over time. Assumes a roughly flat track.
	var tangent_probe := fmod(target_offset + 0.5, baked_length)
	var tangent_world: Vector3 = path.to_global(curve.sample_baked(tangent_probe)) - target_world_base
	if tangent_world.length() < 0.0001:
		tangent_world = Vector3.FORWARD
	else:
		tangent_world = tangent_world.normalized()
	_last_path_normal = Vector3.UP.cross(tangent_world).normalized()

	var target_world := target_world_base + _last_path_normal * _lateral_offset

	# Kit forward = local +Z. Steering math: `angular_speed = -input.x`
	# and `rotate_y(positive)` rotates +Z toward +X. So input.x = -1
	# turns the model toward its local +X side. Hence input.x =
	# -lateral/softness aims the nose at positive-x targets and vice versa.
	var target_local := _vehicle.model_holder.to_local(target_world)
	var lateral := target_local.x
	var ahead := target_local.z

	# Guard against degenerate profile values: softness = 0 would NaN
	# the lateral-to-steering map (0/0 case); a brake threshold of 1.0 or
	# higher would div-by-zero the corner-brake ramp below.
	var safe_softness := maxf(_profile.steering_softness, 0.0001)
	var safe_brake_threshold := clampf(_profile.corner_brake_threshold, 0.0, 0.99)

	var steering := -clampf(lateral / safe_softness, -1.0, 1.0)

	if ahead < 0.0:
		# Target behind us — force a hard turn so we don't sit straight
		# when lateral happens to be near zero.
		var side := signf(lateral)
		if side == 0.0: side = 1.0
		steering = -side

	var turn := absf(steering)
	var throttle := _profile.target_throttle
	if turn > safe_brake_threshold:
		# Drop throttle through tight corners. The kit's sphere keeps its
		# linear velocity vector while the model rotates; at full throttle
		# it slides outside the corner before steering can pull it back.
		var t := (turn - safe_brake_threshold) / (1.0 - safe_brake_threshold)
		throttle = lerpf(_profile.target_throttle, _profile.min_corner_throttle, clampf(t, 0.0, 1.0))

	# Recovery stun: after a hit, cut steering authority so the impact's
	# momentum carries the car off-line. Throttle still brakes for the
	# corner (computed above) — the car slows but can't correct.
	if _recovery_timer > 0.0:
		steering *= _profile.hit_recovery_steering

	_steering = steering
	_throttle = throttle

func _on_sphere_hit(body: Node) -> void:

	# React only to other vehicles, not the ground or walls — vehicle
	# spheres sit on collision layer 4.
	if not (body is RigidBody3D and (body as RigidBody3D).get_collision_layer_value(4)):
		return

	_recovery_timer = _profile.hit_recovery_time

	# Shove the pursued racing line away from the impact. The sign of the
	# impact direction projected onto the path normal picks which side of
	# the track to drift toward.
	var away: Vector3 = _vehicle.get_vehicle_position() - body.global_position
	_lateral_offset += signf(away.dot(_last_path_normal)) * _profile.hit_lateral_impulse
	_lateral_offset = clampf(_lateral_offset, -_profile.max_lateral_offset, _profile.max_lateral_offset)

func get_steering() -> float:
	return _steering

func get_throttle() -> float:
	return _throttle
