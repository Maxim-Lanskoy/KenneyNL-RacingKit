extends Node3D

# Demo glue: prints race events to the output console. Wire RaceManager's
# signals to these handlers in the scene file. Replace with your real
# game logic (HUD updates, results screen, etc.) in your project.

func _on_race_started() -> void:
	print("[Race] Started")

func _on_lap_completed(vehicle: Vehicle, lap: int, time_seconds: float) -> void:
	print("[Race] %s lap %d in %.2fs" % [vehicle.name, lap, time_seconds])

func _on_vehicle_finished(vehicle: Vehicle, total_time_seconds: float) -> void:
	print("[Race] %s finished in %.2fs" % [vehicle.name, total_time_seconds])
