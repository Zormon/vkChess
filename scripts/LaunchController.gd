# LaunchController.gd - Orchestrates input, state machine, baton lifecycle, and arc preview.
# State flow: AIMING --(freeze)--> FROZEN --(throw)--> THROWN --(stopped)--> AIMING
# Input is read from an InputProvider so the same state machine works with
# gamepad or mouse+keyboard (see InputProvider.gd and its subclasses).
class_name LaunchController
extends Node

const GamepadInputProviderScript = preload("res://scripts/GamepadInputProvider.gd")

signal state_changed(new_state: int)
signal input_provider_changed(provider_name: String)

enum State {AIMING, FROZEN, THROWN}

@export_group("Node References")
@export var baton_spawn: Node3D
@export var ui_controller: Node
@export var field_root: Node

@export_group("Aim Tuning")
@export_range(0.0, 60.0, 1.0) var max_yaw_degrees: float = 25.0
@export_range(0.0, 45.0, 1.0) var min_pitch_degrees: float = 5.0
@export_range(30.0, 89.0, 1.0) var max_pitch_degrees: float = 55.0

@export_group("Force / Spin")
@export_range(0.1, 20.0, 0.1) var min_force: float = 0.6
@export_range(0.5, 30.0, 0.1) var max_force: float = 3.0
@export_range(0.0, 30.0, 0.5) var max_spin_rad: float = 10.0
@export_range(0.0, 1.0, 0.2) var max_visual_roll: float = 2.0

var input_provider: Node = null

var _state: int = State.AIMING
var _yaw: float = 0.0
var _pitch: float = 0.0
var _roll: float = 0.0
var _force: float = 0.0
var _spin: Vector3 = Vector3.ZERO
var _active_baton = null
var _frozen_impulse: Vector3 = Vector3.ZERO
var _frozen_spin: Vector3 = Vector3.ZERO


func _ready() -> void:
	_auto_select_input_provider()
	_pitch = deg_to_rad(35.0)
	# Deferred so the PhysicsServer3D has registered the new RigidBody3D
	call_deferred("_spawn_baton")

func _process(delta: float) -> void:
	if input_provider != null:
		input_provider.call("update", delta)

	if _state == State.AIMING:
		_read_input_from_provider()
		_update_baton_transform()

	# "Hold to freeze, release to throw" — driven entirely by the held state.
	if input_provider != null:
		var held: bool = bool(input_provider.call("is_freeze_held"))
		if _state == State.AIMING and held:
			_freeze_values()
		elif _state == State.FROZEN and not held:
			_throw()


# ----------------- Input provider management -----------------

func _auto_select_input_provider() -> void:
	_set_input_provider(GamepadInputProviderScript.new())


func _set_input_provider(new_provider: Node) -> void:
	if input_provider != null and is_instance_valid(input_provider):
		input_provider.call("on_deactivated")
		input_provider.queue_free()
	input_provider = new_provider
	add_child(input_provider)
	if input_provider.has_signal("reset_baton_requested") and not input_provider.reset_baton_requested.is_connected(_on_reset_baton_requested):
		input_provider.reset_baton_requested.connect(_on_reset_baton_requested)
	if input_provider.has_signal("reset_kubbs_requested") and not input_provider.reset_kubbs_requested.is_connected(_on_reset_kubbs_requested):
		input_provider.reset_kubbs_requested.connect(_on_reset_kubbs_requested)
	input_provider.call("on_activated")
	var provider_name: String = input_provider.call("get_device_name")
	input_provider_changed.emit(provider_name)
	ui_controller.call("set_input_provider", input_provider)


func _on_reset_baton_requested() -> void:
	if _state == State.THROWN or _state == State.FROZEN:
		_respawn_baton()


func _on_reset_kubbs_requested() -> void:
	var parent: Node = get_parent()
	if parent == null:
		return
	for child in parent.get_children():
		if child.has_method("reset_kubbs"):
			child.call("reset_kubbs")
			return


# ----------------- Read input values and update local variables -----------------
func _read_input_from_provider() -> void:
	if input_provider == null:
		return
	var aim: Vector2 = input_provider.call("get_aim")
	var force01: float = float(input_provider.call("get_force"))
	var spin: float = float(input_provider.call("get_spin"))

	# Positive aim.x -> throw to the player's left (-X), since the baton
	# launches toward -Z where the kubbs are.
	_yaw = aim.x * deg_to_rad(max_yaw_degrees)
	_pitch = deg_to_rad(_pitch_from_input(aim.y))
	_force = lerp(min_force, max_force, clampf(force01, 0.0, 1.0))
	_roll = spin * max_visual_roll
	_spin = Vector3(0.0, 0.0, -spin * max_spin_rad)


func _update_baton_transform() -> void:
	if _active_baton == null:
		return
	_active_baton.reset_to(_compute_baton_transform())


func _spawn_baton() -> void:
	if _active_baton != null and is_instance_valid(_active_baton):
		_active_baton.queue_free()
		_active_baton = null
	var baton = Globals.KastpinneScene.instantiate()
	field_root.add_child(baton)
	# Freeze before assigning so reset_to() has a sleeping body to teleport.
	baton.freeze = true
	baton.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	baton.linear_velocity = Vector3.ZERO
	baton.angular_velocity = Vector3.ZERO
	_active_baton = baton
	_update_baton_transform()
	if baton.has_signal("stopped_moving") and not baton.stopped_moving.is_connected(_on_baton_stopped):
		baton.stopped_moving.connect(_on_baton_stopped)


func _respawn_baton() -> void:
	_spawn_baton()
	_state = State.AIMING
	state_changed.emit(_state)
	_update_ui_state_label()


func _on_baton_stopped() -> void:
	_respawn_baton()


# ----------------- State transitions -----------------

func _freeze_values() -> void:
	if _active_baton == null:
		return
	_frozen_impulse = _compute_initial_impulse()
	_frozen_spin = _spin
	_state = State.FROZEN
	state_changed.emit(_state)
	_update_ui_state_label()


func _throw() -> void:
	if _active_baton == null:
		_state = State.AIMING
		_update_ui_state_label()
		return
	_state = State.THROWN
	state_changed.emit(_state)
	_update_ui_state_label()
	_active_baton.call("throw", _frozen_impulse, _frozen_spin)

# ----------------- UI helper -----------------

func _update_ui_state_label() -> void:
	var label: String = "AIMING"
	if _state == State.FROZEN:
		label = "FROZEN (cargando fuerza)"
	elif _state == State.THROWN:
		label = "THROWN (en vuelo)"
	ui_controller.call("set_state_label", label)


# ----------------- Math helpers -----------------

func _compute_baton_transform() -> Transform3D:
	var fwd: Vector3 = Vector3(
		sin(_yaw) * cos(_pitch),
		sin(_pitch),
		- cos(_yaw) * cos(_pitch)
	).normalized()
	var y_axis: Vector3 = fwd
	var up_ref: Vector3 = Vector3.UP
	var x_axis: Vector3 = up_ref.cross(y_axis)
	if x_axis.length() < 0.001:
		x_axis = Vector3.RIGHT
	x_axis = x_axis.normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	y_axis = z_axis.cross(x_axis).normalized()
	if abs(_roll) > 0.001:
		var roll_b: Basis = Basis(y_axis, _roll)
		x_axis = roll_b * x_axis
		z_axis = roll_b * z_axis
	var basis: Basis = Basis(x_axis, y_axis, z_axis)
	return Transform3D(basis, baton_spawn.global_position)


func _compute_initial_impulse() -> Vector3:
	var fwd: Vector3 = Vector3(
		sin(_yaw) * cos(_pitch),
		sin(_pitch),
		- cos(_yaw) * cos(_pitch)
	).normalized()
	return fwd * _force


func _pitch_from_input(input_value: float) -> float:
	var t: float = clampf((input_value + 1.0) * 0.5, 0.0, 1.0)
	return lerp(min_pitch_degrees, max_pitch_degrees, t)
