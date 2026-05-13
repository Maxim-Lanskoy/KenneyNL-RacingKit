class_name RaceManager extends Node

# Tracks per-vehicle progress around an ordered list of checkpoints and
# emits race events. Wire the scene's checkpoints into the `checkpoints`
# array (sorted by their index). Vehicles are tracked the first time
# they cross checkpoint 0.

@export var checkpoints: Array[Checkpoint] = []
@export var total_laps: int = 3

signal race_started
signal lap_completed(vehicle: Vehicle, lap: int, time_seconds: float)
signal vehicle_finished(vehicle: Vehicle, total_time_seconds: float)

var _progress: Dictionary = {}

func _ready() -> void:
	for cp in checkpoints:
		cp.passed.connect(_on_checkpoint_passed)
	race_started.emit()

func _on_checkpoint_passed(vehicle: Vehicle, index: int) -> void:

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

	p.next_index = (p.next_index + 1) % checkpoints.size()

	if p.next_index == 0:
		var now := Time.get_ticks_msec()
		var lap_seconds: float = (now - int(p.lap_start_ms)) / 1000.0
		p.lap += 1
		lap_completed.emit(vehicle, p.lap, lap_seconds)
		p.lap_start_ms = now

		if p.lap >= total_laps:
			var total_seconds: float = (now - int(p.race_start_ms)) / 1000.0
			vehicle_finished.emit(vehicle, total_seconds)
