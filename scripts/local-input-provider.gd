class_name LocalInputProvider extends InputProvider

# Reads InputMap actions. The optional action_prefix is prepended to
# each action name — useful if you want to drive this provider from a
# differently-named action set without subclassing. Empty prefix (the
# default) reads "left"/"right"/"back"/"forward".

@export var action_prefix: String = ""

func get_steering() -> float:
	return Input.get_axis(action_prefix + "left", action_prefix + "right")

func get_throttle() -> float:
	return Input.get_axis(action_prefix + "back", action_prefix + "forward")
