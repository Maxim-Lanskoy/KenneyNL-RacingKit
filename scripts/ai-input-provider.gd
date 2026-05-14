class_name AIInputProvider extends InputProvider

# Pure-pursuit AI driver. Reads its host Vehicle's position each physics
# frame, projects it onto the shared Path3D, samples a point `lookahead`
# meters farther along the curve, and returns steering/throttle to drive
# the kit's regular Vehicle rig toward that point. Throttle is reduced
# when the corner is sharp so the sphere doesn't drift through the wall.
#
# All tuning lives in an AIProfile resource (the difficulty preset). Leave
# `profile` null to fall back to AIProfile's defaults (= the Normal preset).

@export var path: Path3D
@export var profile: AIProfile

var _vehicle: Vehicle
var _profile: AIProfile
var _steering: float = 0.0
var _throttle: float = 0.0

func _ready() -> void:

	_vehicle = get_parent() as Vehicle
	assert(_vehicle != null, "AIInputProvider must be a child of a Vehicle")
	assert(path != null, "AIInputProvider.path is not set")
	assert(path.curve != null and path.curve.get_baked_length() > 0.0, "AIInputProvider.path has no usable curve")

	_profile = profile if profile != null else AIProfile.new()

func _physics_process(_delta: float) -> void:

	if _vehicle == null or path == null: return
	var curve := path.curve
	if curve == null: return
	var baked_length := curve.get_baked_length()
	if baked_length <= 0.0: return

	var vehicle_world := _vehicle.get_vehicle_position()
	var vehicle_local := path.to_local(vehicle_world)
	var current_offset := curve.get_closest_offset(vehicle_local)

	var target_offset := fmod(current_offset + _profile.lookahead, baked_length)
	var target_local_path := curve.sample_baked(target_offset)
	var target_world := path.to_global(target_local_path)

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

	_steering = steering
	_throttle = throttle

func get_steering() -> float:
	return _steering

func get_throttle() -> float:
	return _throttle
