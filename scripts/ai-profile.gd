class_name AIProfile extends Resource

# Difficulty / behavior profile for AI drivers. Bundles the AIInputProvider
# tuning knobs into a named Resource so "Easy / Normal / Hard" is a .tres
# swap instead of a pile of loose numbers — mirrors how a VehicleModel
# carries a VehicleConfig.
#
# Wire a .tres into AISpawner.profile (it forwards it to every spawned
# AIInputProvider), or into an AIInputProvider directly. Leave it null to
# fall back to these defaults, which match the Normal preset.

@export_group("Pure Pursuit")
# How far ahead on the curve the AI aims, in meters. Higher = earlier
# reactions; too far and the AI cuts the apex.
@export var lookahead: float = 9.0
# Larger = gentler steering for the same lateral error. Too small and the
# AI oscillates on straights.
@export var steering_softness: float = 3.0

@export_group("Throttle")
# Cruise throttle on straights, in [0, 1].
@export var target_throttle: float = 0.8
# Steering magnitude at which corner braking begins. Lower = brakes earlier.
@export var corner_brake_threshold: float = 0.18
# Floor throttle through the tightest corners.
@export var min_corner_throttle: float = 0.25

@export_group("Hit Reaction")
# Seconds the controller stays limp after hitting another vehicle, so the
# impact's momentum actually shoves the car off-line before it corrects.
@export var hit_recovery_time: float = 0.5
# Steering authority during recovery (0 = can't steer, 1 = full control).
@export var hit_recovery_steering: float = 0.15
# How far sideways (meters) a hit shoves the pursued racing line.
@export var hit_lateral_impulse: float = 2.5
# Ceiling on the lateral offset so repeated hits can't send a car miles wide.
@export var max_lateral_offset: float = 4.0
# How fast (meters/sec) the lateral offset decays back to the racing line.
@export var lateral_recenter_rate: float = 1.5
