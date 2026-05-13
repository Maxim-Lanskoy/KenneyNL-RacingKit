class_name InputProvider extends Node

# Base class for vehicle input sources. Subclasses return steering and
# throttle values in [-1.0, 1.0]. Swap LocalInputProvider for an AI or
# network-driven provider to retarget a Vehicle without script changes.

func get_steering() -> float:
	return 0.0

func get_throttle() -> float:
	return 0.0
