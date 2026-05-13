class_name Checkpoint extends Area3D

# Emits `passed(vehicle, index)` when a Vehicle's sphere enters this area.
# Order checkpoints by setting `index` 0..N around the track; RaceManager
# uses it to detect a completed lap.

@export var index: int = 0

signal passed(vehicle: Vehicle, index: int)

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:

	# The colliding body is the vehicle's physics sphere; walk up to find
	# the Vehicle root.

	var node: Node = body
	while node != null:
		if node is Vehicle:
			passed.emit(node, index)
			return
		node = node.get_parent()
