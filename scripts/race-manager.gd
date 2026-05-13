class_name RaceManager extends Node

# Tracks per-vehicle progress around an ordered set of checkpoints and
# emits race events.
#
# By default, all Checkpoint nodes in the scene are auto-discovered via
# the "checkpoints" group (Checkpoint adds itself to the group on _ready)
# and sorted by their `index` property. Drop a new Checkpoint into the
# scene and it joins the race automatically.
#
# For multi-track or filtered setups, populate the `checkpoints` array
# explicitly in the Inspector — when non-empty, it overrides discovery.

@export var checkpoints: Array[Checkpoint] = []
@export var total_laps: int = 3

signal race_started
signal lap_completed(vehicle: Vehicle, lap: int, time_seconds: float)
signal vehicle_finished(vehicle: Vehicle, total_time_seconds: float)

var _progress: Dictionary = {}
var _active_checkpoints: Array[Checkpoint] = []

func _ready() -> void:
	# Defer one frame so every Checkpoint has had its own _ready (and
	# joined the group) before we discover and connect them.
	_setup.call_deferred()

func _setup() -> void:

	_active_checkpoints = checkpoints if not checkpoints.is_empty() else _discover_checkpoints()
	_active_checkpoints.sort_custom(func(a, b): return a.index < b.index)

	for cp in _active_checkpoints:
		cp.passed.connect(_on_checkpoint_passed)

	race_started.emit()

func _discover_checkpoints() -> Array[Checkpoint]:

	var result: Array[Checkpoint] = []
	for node in get_tree().get_nodes_in_group(Checkpoint.GROUP):
		if node is Checkpoint:
			result.append(node)
	return result

func _on_checkpoint_passed(vehicle: Vehicle, index: int) -> void:

	if _active_checkpoints.is_empty(): return

	if not _progress.has(vehicle):
		var now := Time.get_ticks_msec()
		_progress[vehicle] = {
			"next_index": 0,
			"lap": 0,
			"lap_start_ms": now,
			"race_start_ms": now,
		}

	var p: Dictionary = _progress[vehicle]
	if index != p.next_index:
		return # crossed out of order; ignore

	p.next_index = (p.next_index + 1) % _active_checkpoints.size()

	if p.next_index == 0:
		var now := Time.get_ticks_msec()
		var lap_seconds: float = (now - int(p.lap_start_ms)) / 1000.0
		p.lap += 1
		lap_completed.emit(vehicle, p.lap, lap_seconds)
		p.lap_start_ms = now

		if p.lap >= total_laps:
			var total_seconds: float = (now - int(p.race_start_ms)) / 1000.0
			vehicle_finished.emit(vehicle, total_seconds)
