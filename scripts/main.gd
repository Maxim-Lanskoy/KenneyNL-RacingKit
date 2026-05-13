extends Node3D

# Demo glue: prints race events to the output console. Wire RaceManager's
# signals to these handlers in the scene file. Replace with your real
# game logic (HUD updates, results screen, etc.) in your project.

func _on_race_started() -> void:
	print("[Race] Started")

func _on_lap_completed(_vehicle: Vehicle, lap: int, time_seconds: float) -> void:
	print("[Race] Lap %d completed in %.2fs" % [lap, time_seconds])

func _on_vehicle_finished(_vehicle: Vehicle, total_time_seconds: float) -> void:
	print("[Race] Finished in %.2fs" % total_time_seconds)
