class_name VehicleConfig extends Resource

# Per-vehicle handling profile. Each VehicleModel carries one of these
# so a car can feel heavy and a motorcycle agile without touching the
# rig script. Wire a .tres into a model's `config` export, or leave it
# null to fall back to these defaults.

@export_group("Steering")
@export var max_steering: float = 4.0
@export var steering_smoothing: float = 4.0
@export var min_steering_grip: float = 0.2
@export var max_steering_grip: float = 1.0

@export_group("Acceleration")
@export var forward_rate: float = 6.0
@export var reverse_rate: float = 2.0
@export var brake_rate: float = 8.0
@export var accel_smoothing: float = 1.0

@export_group("Sphere Coupling")
@export var sphere_offset_y: float = 0.65

@export_group("Engine Audio")
@export var engine_pitch_min: float = 0.5
@export var engine_pitch_max: float = 3.0
@export var engine_volume_min: float = -15.0
@export var engine_volume_max: float = -5.0
