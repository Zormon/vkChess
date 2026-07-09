# MouseKeyboardInputProvider.gd — Mouse + keyboard fallback for development without a gamepad.
# Mapping:
#   Mouse position (absolute, virtual stick) -> aim (yaw, pitch)
#   LMB hold + mouse Y drag                -> force charge (two-stage)
#   LMB release                            -> throw
#   Mouse wheel                            -> spin
#   R                                      -> reset baton
#   T                                      -> reset kubbs
#   Tab                                    -> (handled by controller) switch provider
class_name MouseKeyboardInputProvider
extends InputProvider

@export_group("Tuning")
@export_range(0.0, 0.5, 0.01) var aim_deadzone: float = 0.08
@export_range(0.1, 5.0, 0.1) var force_sensitivity: float = 2.0
@export_range(0.0, 5.0, 0.1) var spin_per_wheel_step: float = 0.5
@export_range(0.5, 10.0, 0.1) var spin_decay_per_sec: float = 1.2
@export_range(0.0, 1.0, 0.01) var initial_force: float = 0.5

# Internal state.
var _current_aim: Vector2 = Vector2.ZERO
var _current_force: float = 0.0
var _current_spin: float = 0.0
var _was_freeze_held: bool = false
# Cached mouse delta while charging (consumed each frame).
var _pending_mouse_dy: float = 0.0
var _pending_wheel_delta: float = 0.0


func _ready() -> void:
	_current_force = initial_force


func update(delta: float) -> void:
	_update_aim()
	_update_freeze()
	_update_force(delta)
	_update_spin(delta)
	_update_keyboard_resets()


func get_aim() -> Vector2:
	return _current_aim


func get_force() -> float:
	return _current_force


func get_spin() -> float:
	return _current_spin


func is_freeze_held() -> bool:
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func get_device_name() -> String:
	return "Mouse + Keyboard"


func on_activated() -> void:
	# Keep the cursor visible so the player can see where they're aiming.
	# MOUSE_MODE_CONFINED is best for absolute position aim (virtual stick),
	# but MOUSE_MODE_VISIBLE also works and lets the cursor escape the window.
	# We go with VISIBLE so the player can still alt-tab easily.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func on_deactivated() -> void:
	_was_freeze_held = false


# ----------------- Input handlers -----------------

# Use _input (not _unhandled_input) so wheel events always reach us even if
# a Control node (Label, ProgressBar) intercepts them in _gui_input.
# This runs BEFORE the per-frame update so the values are ready when update() reads them.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# Accumulate the vertical delta while the LMB is held (charging).
		# We don't clamp here; update() applies the time-scaled integration.
		if _was_freeze_held or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_pending_mouse_dy += event.relative.y
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_pending_wheel_delta += 1.0
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_pending_wheel_delta -= 1.0


# ----------------- Per-frame logic -----------------

func _update_aim() -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		_current_aim = Vector2.ZERO
		return
	var mouse_pos: Vector2 = viewport.get_mouse_position()
	var rect: Rect2 = viewport.get_visible_rect()
	var size: Vector2 = rect.size
	if size.x <= 0.0 or size.y <= 0.0:
		_current_aim = Vector2.ZERO
		return
	# Map mouse position to [-1, 1]. (0,0) at top-left, (1,1) at bottom-right.
	var n: Vector2 = (mouse_pos / size) * 2.0 - Vector2.ONE
	# y inverted: up = +1 (higher pitch).
	n.y = -n.y
	# Circular deadzone: if the pointer is too close to the screen center, treat as neutral.
	if n.length() < aim_deadzone:
		_current_aim = Vector2.ZERO
	else:
		_current_aim = n.normalized() * (n.length() - aim_deadzone) / (1.0 - aim_deadzone)
		# Clamp to [-1, 1] just in case the window has odd dimensions.
		_current_aim = _current_aim.limit_length(1.0)


func _update_freeze() -> void:
	var lmb_held: bool = is_freeze_held()
	if lmb_held and not _was_freeze_held:
		# Edge: LMB just pressed -> enter freeze.
		freeze_started.emit()
	elif _was_freeze_held and not lmb_held:
		# Edge: LMB just released -> fire throw.
		throw_released.emit()
	_was_freeze_held = lmb_held


func _update_force(delta: float) -> void:
	# Only accumulate force while the LMB is held.
	if is_freeze_held():
		# Pulling the mouse up (negative Y delta) increases force.
		# sensitivity * delta normalizes across frame rates.
		_current_force += -_pending_mouse_dy * force_sensitivity * delta
		_current_force = clampf(_current_force, 0.0, 1.0)
	# In AIMING (no LMB), force is held at its current value so the player
	# can choose when to commit it. Reset the pending delta either way.
	_pending_mouse_dy = 0.0


func _update_spin(delta: float) -> void:
	# Discrete wheel steps add to the accumulator.
	_current_spin += _pending_wheel_delta * spin_per_wheel_step
	_pending_wheel_delta = 0.0
	# Decay toward zero when no new input arrives AND we're not holding LMB.
	# (While held, the player is in charge mode and shouldn't have their spin wander.)
	if not is_freeze_held():
		var decay: float = exp(-spin_decay_per_sec * delta)
		_current_spin *= decay
		if absf(_current_spin) < 0.005:
			_current_spin = 0.0
	_current_spin = clampf(_current_spin, -1.0, 1.0)


func _update_keyboard_resets() -> void:
	if InputMap.has_action("reset_baton_kb") and Input.is_action_just_pressed("reset_baton_kb"):
		reset_baton_requested.emit()
	if InputMap.has_action("reset_kubbs_kb") and Input.is_action_just_pressed("reset_kubbs_kb"):
		reset_kubbs_requested.emit()
