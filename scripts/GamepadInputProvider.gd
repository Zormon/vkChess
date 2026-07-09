# GamepadInputProvider.gd — Xbox controller implementation of InputProvider.
# Maps the Xbox layout: left stick aim, right stick force+spin, RT freeze/throw.
class_name GamepadInputProvider
extends InputProvider

# Xbox controller axis indices (SDL2 / Godot JoyAxis mapping).
const AXIS_LX: int = 0
const AXIS_LY: int = 1
const AXIS_RX: int = 2
const AXIS_RY: int = 3
const AXIS_LT: int = 4
const AXIS_RT: int = 5

@export_group("Tuning")
## Bigger default deadzone helps with Bluetooth controllers (Switch Pro, etc.)
## that tend to drift more than wired Xbox pads.
@export_range(0.0, 0.5, 0.01) var stick_deadzone: float = 0.2
@export_range(0.0, 0.5, 0.01) var trigger_threshold: float = 0.3
@export_range(0.0, 1.0, 0.01) var initial_force: float = 0.5
## Some controllers (or platforms) map the right trigger as a digital button
## (Switch Pro ZR = button 7) instead of axis 5. We read both for robustness.
@export var fallback_zr_button: int = 7

# Internal state.
var _current_force: float = 0.0
var _current_aim: Vector2 = Vector2.ZERO
var _current_spin: float = 0.0


func _ready() -> void:
	_current_force = initial_force


func update(_delta: float) -> void:
	# Read raw axes.
	var lx: float = _normalize_axis(_get_axis(AXIS_LX))
	var ly: float = _normalize_axis(_get_axis(AXIS_LY))
	# Left stick: x -> yaw input, -y -> pitch input (up = higher pitch).
	_current_aim = Vector2(lx, -ly)

	var ry: float = _normalize_axis(_get_axis(AXIS_RY))
	# Map ry [-1, 1] -> [0, 1] force.
	_current_force = clampf((ry + 1.0) * 0.5, 0.0, 1.0)

	_current_spin = _normalize_axis(_get_axis(AXIS_RX))

	# Button presses for reset actions (via the InputMap actions).
	if InputMap.has_action("reset_baton") and Input.is_action_just_pressed("reset_baton"):
		reset_baton_requested.emit()
	if InputMap.has_action("reset_kubbs") and Input.is_action_just_pressed("reset_kubbs"):
		reset_kubbs_requested.emit()


func get_aim() -> Vector2:
	return _current_aim


func get_force() -> float:
	return _current_force


func get_spin() -> float:
	return _current_spin


func is_freeze_held() -> bool:
	# Primary: analog right trigger (axis 5). Works on Xbox, most wired pads.
	if _get_axis(AXIS_RT) > trigger_threshold:
		return true
	# Fallback: digital ZR button on Switch Pro / platforms that map the
	# trigger as a button instead of an axis.
	if fallback_zr_button >= 0 and Input.is_joy_button_pressed(0, fallback_zr_button):
		return true
	return false


func get_device_name() -> String:
	var pads: Array = Input.get_connected_joypads()
	if pads.is_empty():
		return "Gamepad (none connected)"
	var joy_name: String = Input.get_joy_name(pads[0])
	if joy_name.is_empty():
		joy_name = "Gamepad"
	# Append the device id for clarity when multiple pads are connected.
	if pads.size() > 1:
		joy_name += " (+%d more)" % (pads.size() - 1)
	return joy_name


func on_activated() -> void:
	var pads: Array = Input.get_connected_joypads()
	if not pads.is_empty():
		print("[GamepadInputProvider] Activated with: %s (device %d)" % [Input.get_joy_name(pads[0]), pads[0]])


func on_deactivated() -> void:
	pass


# ----------------- Helpers -----------------

func _get_axis(axis: int) -> float:
	return Input.get_joy_axis(0, axis)


func _normalize_axis(value: float) -> float:
	if absf(value) < stick_deadzone:
		return 0.0
	return signf(value) * (absf(value) - stick_deadzone) / (1.0 - stick_deadzone)
