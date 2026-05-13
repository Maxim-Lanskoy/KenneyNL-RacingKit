class_name LocalInputProvider extends InputProvider

# Reads InputMap actions. Set action_prefix to namespace per player
# (e.g. "p1_" reads "p1_left"/"p1_right"/"p1_back"/"p1_forward")
# without modifying this script. Empty prefix uses the default
# "left"/"right"/"back"/"forward" actions.

@export var action_prefix: String = ""

func get_steering() -> float:
	return Input.get_axis(action_prefix + "left", action_prefix + "right")

func get_throttle() -> float:
	return Input.get_axis(action_prefix + "back", action_prefix + "forward")
