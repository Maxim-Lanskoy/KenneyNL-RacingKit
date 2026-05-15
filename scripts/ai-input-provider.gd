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
# Three forward feeler rays add obstacle avoidance: a wall or another car
# detected ahead biases the steering away from it and (dead ahead) eases
# the throttle. The feelers follow the local ground slope and ignore
# drivable surfaces, so they work on hilly tracks, not just flat ones.
#
# All tuning lives in an AIProfile resource (the difficulty preset). Leave
# `profile` null to fall back to AIProfile's defaults (= the Normal preset).

@export var path: Path3D
@export var profile: AIProfile

# Side feeler rays sit this far off the forward axis (≈ tan of the spread
# angle; 0.5 ≈ 27°). Feelers query layer 1 (ground/walls) and layer 4
# (vehicles); other vehicles always count as obstacles, while static
# geometry only counts if its surface normal is steeper than
# _AVOID_WALL_DOT_MAX — so the road, ramps and banking read as drivable.
# _AVOID_SMOOTH lerps the steering bias so a ray flickering on/off at an
# obstacle's edge doesn't twitch the wheel.
const _AVOID_RAY_SPREAD := 0.5
const _AVOID_RAY_MASK := 9
const _AVOID_WALL_DOT_MAX := 0.5
const _AVOID_SMOOTH := 12.0

var _vehicle: Vehicle
var _profile: AIProfile
var _steering: float = 0.0
var _throttle: float = 0.0

# Per-vehicle runtime state — never stored on the shared AIProfile resource.
# _last_path_normal is the curve's world-space horizontal normal at the
# lookahead point; _avoid_steer is the smoothed feeler-ray steering bias.
var _recovery_timer: float = 0.0
var _lateral_offset: float = 0.0
var _last_path_normal: Vector3 = Vector3.ZERO
var _avoid_steer: float = 0.0

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

	# --- path following ---
	var path_steer := -clampf(lateral / safe_softness, -1.0, 1.0)

	if ahead < 0.0:
		# Target behind us — force a hard turn so we don't sit straight
		# when lateral happens to be near zero.
		var side := signf(lateral)
		if side == 0.0: side = 1.0
		path_steer = -side

	# Recovery stun: after a hit, cut path-following steering authority so
	# the impact's momentum carries the car off-line. Avoidance (below) is
	# left at full strength — a dazed driver still flinches from a wall,
	# which also stops a hit-shoved car from grinding along one.
	if _recovery_timer > 0.0:
		path_steer *= _profile.hit_recovery_steering

	# --- obstacle avoidance: three forward feeler rays ---
	var target_avoid := 0.0
	var avoid_brake := false
	if _vehicle.sphere != null:
		# Orient the feelers along the local ground plane (not dead-horizontal)
		# so they follow the track up and down slopes instead of plunging into
		# a rise or flying over a dip. _vehicle.normal is the ground normal
		# under the car, refreshed each frame by the rig's down-raycast.
		var ground_normal := _vehicle.normal
		if ground_normal.length() < 0.01:
			ground_normal = Vector3.UP
		var holder_basis := _vehicle.model_holder.global_basis
		var fwd := holder_basis.z - ground_normal * holder_basis.z.dot(ground_normal)
		var side_axis := holder_basis.x - ground_normal * holder_basis.x.dot(ground_normal)
		if fwd.length() > 0.01 and side_axis.length() > 0.01:
			fwd = fwd.normalized()
			side_axis = side_axis.normalized()
			var origin := _vehicle.sphere.global_position
			var space := _vehicle.get_world_3d().direct_space_state
			var exclude: Array[RID] = [_vehicle.sphere.get_rid()]
			var reach := _profile.avoidance_ray_length
			# side_axis is the model's local +X (its left). A left-feeler hit
			# steers right (positive bias); a right-feeler hit steers left.
			var left_hit := _ray_obstacle(space, origin, (fwd + side_axis * _AVOID_RAY_SPREAD).normalized(), reach, exclude)
			var right_hit := _ray_obstacle(space, origin, (fwd - side_axis * _AVOID_RAY_SPREAD).normalized(), reach, exclude)
			var center_hit := _ray_obstacle(space, origin, fwd, reach, exclude)
			if left_hit: target_avoid += _profile.avoidance_strength
			if right_hit: target_avoid -= _profile.avoidance_strength
			if center_hit:
				avoid_brake = true
				if not left_hit and not right_hit:
					# Obstacle dead ahead, both flanks clear — commit to a side.
					target_avoid += _profile.avoidance_strength

	# Smooth the bias so a feeler flickering at an obstacle's edge doesn't
	# twitch the wheel.
	_avoid_steer = lerpf(_avoid_steer, target_avoid, clampf(delta * _AVOID_SMOOTH, 0.0, 1.0))

	var steering := clampf(path_steer + _avoid_steer, -1.0, 1.0)

	# --- throttle ---
	var turn := absf(steering)
	var throttle := _profile.target_throttle
	if turn > safe_brake_threshold:
		# Drop throttle through tight corners. The kit's sphere keeps its
		# linear velocity vector while the model rotates; at full throttle
		# it slides outside the corner before steering can pull it back.
		var t := (turn - safe_brake_threshold) / (1.0 - safe_brake_threshold)
		throttle = lerpf(_profile.target_throttle, _profile.min_corner_throttle, clampf(t, 0.0, 1.0))
	if avoid_brake:
		# Something dead ahead — ease off so the steering bias has room to work.
		throttle = minf(throttle, _profile.avoidance_throttle)

	_steering = steering
	_throttle = throttle

func _on_sphere_hit(body: Node) -> void:

	# React only to other vehicles, not the ground or walls — vehicle
	# spheres sit on collision layer 4.
	if not (body is RigidBody3D and (body as RigidBody3D).get_collision_layer_value(4)):
		return

	_recovery_timer = _profile.hit_recovery_time

	# Shove the pursued racing line away from the impact. The sign of the
	# impact direction (sphere-to-sphere) projected onto the path normal
	# picks which side of the track to drift toward.
	var away: Vector3 = _vehicle.sphere.global_position - body.global_position
	_lateral_offset += signf(away.dot(_last_path_normal)) * _profile.hit_lateral_impulse
	_lateral_offset = clampf(_lateral_offset, -_profile.max_lateral_offset, _profile.max_lateral_offset)

func get_steering() -> float:
	return _steering

func get_throttle() -> float:
	return _throttle

func _ray_obstacle(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3, reach: float, exclude: Array[RID]) -> bool:

	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * reach)
	query.collision_mask = _AVOID_RAY_MASK
	query.exclude = exclude
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return false
	# A dynamic body — another vehicle, or any RigidBody3D obstacle — always
	# counts (a slope-tilted ray can otherwise return a floor-like normal off
	# another car's sphere and wrongly skip it). For static geometry, a
	# floor-like surface — the road, a ramp, banking — is drivable; only
	# steep / wall-like faces count.
	if hit.collider is RigidBody3D:
		return true
	return hit.normal.dot(Vector3.UP) < _AVOID_WALL_DOT_MAX
