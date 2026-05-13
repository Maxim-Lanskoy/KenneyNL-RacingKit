class_name Checkpoint extends Area3D

# Emits `passed(vehicle, index)` when a Vehicle's sphere enters this area.
# Order checkpoints by setting `index` 0..N around the track; RaceManager
# uses it to detect a completed lap.

# Group all Checkpoints register themselves to so RaceManager can
# auto-discover them. Kept on Checkpoint (not RaceManager) to avoid a
# circular class reference.
const GROUP := "checkpoints"

@export var index: int = 0
@export var visual_indicator: Node3D

signal passed(vehicle: Vehicle, index: int)

func _ready() -> void:

	# Join the group so RaceManager can auto-discover us
	# (RaceManager defers its own setup by one frame to allow this).
	add_to_group(GROUP)

	body_entered.connect(_on_body_entered)

	# Hide the editor-only translucent box at runtime so players don't see it.

	if visual_indicator != null:
		visual_indicator.visible = false

func _on_body_entered(body: Node) -> void:

	# The colliding body is the vehicle's physics sphere; walk up to find
	# the Vehicle root.

	var node: Node = body
	while node != null:
		if node is Vehicle:
			passed.emit(node, index)
			return
		node = node.get_parent()
