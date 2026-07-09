# InputProvider.gd — Abstract base class for input providers.
# Subclasses implement concrete schemes: GamepadInputProvider, MouseKeyboardInputProvider, etc.
# The LaunchController polls this interface, not the raw Input singleton,
# so the same control flow works with any physical device.
@warning_ignore("unused_signal")
class_name InputProvider
extends Node

## Emitted when the freeze/charge action starts (e.g. RT pressed or LMB pressed).
signal freeze_started()

## Emitted when the throw is released (e.g. RT released or LMB released).
signal throw_released()

## Emitted when the user requests a baton reset.
signal reset_baton_requested()

## Emitted when the user requests a kubb reset.
signal reset_kubbs_requested()

## Normalized aim vector. x = yaw input (-1=left, +1=right), y = pitch input (-1=low, +1=high).
## Each provider is responsible for deadzone / clamping.
func get_aim() -> Vector2:
	return Vector2.ZERO

## Normalized force input in [0, 1]. 0 = no force, 1 = max force.
func get_force() -> float:
	return 0.0

## Normalized spin input in [-1, 1]. -1 = spin one way, +1 = the other.
func get_spin() -> float:
	return 0.0

## True while the freeze/charge action is held (analog of gamepad RT pressed).
func is_freeze_held() -> bool:
	return false

## Called every frame so the provider can update its internal state
## (e.g. read mouse deltas, decay the spin accumulator, detect button edges).
func update(_delta: float) -> void:
	pass

## Human-readable name for UI / debug display.
func get_device_name() -> String:
	return "Unknown"

## Called when the provider becomes active (after a hot-swap or initial selection).
## Use this to grab focus, capture the mouse, log a message, etc.
func on_activated() -> void:
	pass

## Called when the provider is being replaced. Release any held resources.
func on_deactivated() -> void:
	pass
