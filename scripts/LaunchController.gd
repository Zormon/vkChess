# LaunchController.gd — Orchestrates input, state machine, baton lifecycle, and arc preview.
# State flow: AIMING --(RT pressed)--> FROZEN --(RT released)--> THROZEN --(stopped)--> AIMING
class_name LaunchController
extends Node

# Preload to avoid depending on global class_name resolution in fresh scans.
const KastpinneScript = preload("res://scripts/Kastpinne.gd")
const TrajectoryPreviewScript = preload("res://scripts/TrajectoryPreview.gd")

signal state_changed(new_state: int)

enum State { AIMING, FROZEN, THROWN }

@export_group("Node References")
@export var baton_scene: PackedScene
@export var baton_spawn: Node3D
# Use loose typing here so we don't depend on TrajectoryPreview class_name resolution.
@export var trajectory: Node3D
@export var ground_marker: MeshInstance3D
## Parent for the instantiated active baton (usually the scene root). If null, defaults to parent of this controller.
@export var field_root: Node = null

@export_group("Aim Tuning")
@export_range(0.0, 60.0, 1.0) var max_yaw_degrees: float = 25.0
@export_range(5.0, 45.0, 1.0) var min_pitch_degrees: float = 15.0
@export_range(30.0, 89.0, 1.0) var max_pitch_degrees: float = 70.0

@export_group("Force / Spin")
@export_range(0.5, 20.0, 0.1) var min_force: float = 3.0
@export_range(0.5, 30.0, 0.1) var max_force: float = 14.0
@export_range(0.0, 30.0, 0.5) var max_spin_rad: float = 10.0
@export_range(0.0, 1.0, 0.2) var max_visual_roll: float = 1.2

@export_group("Input")
@export_range(0.0, 0.5, 0.01) var stick_deadzone: float = 0.15
@export_range(0.0, 0.5, 0.01) var trigger_threshold: float = 0.3
@export_range(0.0, 1.0, 0.01) var initial_force_ratio: float = 0.5

var _state: int = State.AIMING
# Internal aim parameters (live during AIMING, frozen during FROZEN).
var _yaw: float = 0.0      # radians
var _pitch: float = 0.0    # radians (elevation above horizon)
var _roll: float = 0.0     # visual roll (radians) — not physical
var _force: float = 0.0    # Newton·seconds magnitude of the throw impulse
var _spin: Vector3 = Vector3.ZERO  # angular velocity (rad/s)
var _active_baton = null  # Typed as Kastpinne in spirit; kept loose to avoid class_name resolution.
var _frozen_params: Dictionary = {}


func _ready() -> void:
	# Default field_root to our parent if not set in the scene.
	if field_root == null:
		var p: Node = get_parent()
		field_root = p
	# Default baton_spawn by searching the parent tree.
	if baton_spawn == null:
		var p: Node = get_parent()
		if p != null:
			baton_spawn = p.get_node_or_null("Thrower/BatonSpawnPoint")
	# Defer spawning by one frame so all sibling nodes have completed _ready.
	call_deferred("_deferred_spawn_baton")


func _deferred_spawn_baton() -> void:
	# Initial pitch sits in the middle of the allowed range.
	_pitch = deg_to_rad(35.0)
	_force = lerp(min_force, max_force, initial_force_ratio)
	_spawn_baton()


func _process(_delta: float) -> void:
	match _state:
		State.AIMING:
			_read_input()
			_update_baton_transform()
			_update_trajectory()
		State.FROZEN:
			pass  # Values stay frozen, trajectory stays visible in frozen color.
		State.THROWN:
			pass  # Physics owns the baton; we wait for stopped_moving.

	# Right trigger drives the state transitions (Xbox RT = axis 5).
	var rt_value: float = _get_axis(5)
	var rt_pressed: bool = rt_value > trigger_threshold

	if _state == State.AIMING and rt_pressed:
		_freeze_values()
	elif _state == State.FROZEN and not rt_pressed:
		_throw()

	# Optional manual reset (A button -> "reset_baton" action).
	if InputMap.has_action("reset_baton") and Input.is_action_just_pressed("reset_baton"):
		if _state == State.THROWN:
			_respawn_baton()


# ----------------- Input -----------------

func _read_input() -> void:
	# Xbox controller axes: 0=LX, 1=LY, 2=RX, 3=RY, 4=LT, 5=RT.
	var lx: float = _normalize_axis(_get_axis(0))
	var ly: float = _normalize_axis(_get_axis(1))
	# Left stick left (lx<0) -> yaw left. Up (ly<0) -> higher pitch.
	_yaw = -lx * deg_to_rad(max_yaw_degrees)
	_pitch = deg_to_rad(_pitch_from_input(-ly))

	var ry: float = _normalize_axis(_get_axis(3))
	_force = lerp(min_force, max_force, clampf((ry + 1.0) * 0.5, 0.0, 1.0))

	_spin_input_to_spin(_normalize_axis(_get_axis(2)))


func _spin_input_to_spin(spin_input: float) -> void:
	# Right stick X controls roll-style spin around the baton's long axis.
	# This is a *visual* preview right now; physical spin is applied at throw time.
	_roll = spin_input * max_visual_roll
	_spin = Vector3(0.0, 0.0, -spin_input * max_spin_rad)


# ----------------- Baton control -----------------

func _update_baton_transform() -> void:
	if _active_baton == null or baton_spawn == null:
		return
	_active_baton.reset_to(_compute_baton_transform())


func _spawn_baton() -> void:
	if _active_baton != null and is_instance_valid(_active_baton):
		_active_baton.queue_free()
		_active_baton = null
	if baton_scene == null or field_root == null or baton_spawn == null:
		push_warning("LaunchController: missing baton_scene / field_root / baton_spawn")
		return
	var baton = baton_scene.instantiate()
	field_root.add_child(baton)
	_active_baton = baton
	_update_baton_transform()
	# Connect stopped signal (one-shot) to respawn.
	if baton.has_signal("stopped_moving") and not baton.stopped_moving.is_connected(_on_baton_stopped):
		baton.stopped_moving.connect(_on_baton_stopped)


func _respawn_baton() -> void:
	_spawn_baton()
	_state = State.AIMING
	state_changed.emit(_state)


func _on_baton_stopped() -> void:
	_respawn_baton()


# ----------------- State transitions -----------------

func _freeze_values() -> void:
	if _active_baton == null:
		return
	_frozen_params = {
		"impulse": _compute_initial_impulse(),
		"spin": _spin,
	}
	if trajectory and trajectory.has_method("set_frozen_color"):
		trajectory.set_frozen_color()
	_state = State.FROZEN
	state_changed.emit(_state)


func _throw() -> void:
	if _active_baton == null:
		_state = State.AIMING
		return
	_state = State.THROWN
	state_changed.emit(_state)
	_active_baton.call("throw",
		_frozen_params.get("impulse", Vector3.ZERO),
		_frozen_params.get("spin", Vector3.ZERO)
	)
	if trajectory and trajectory.has_method("hide_arc"):
		trajectory.hide_arc()
	if ground_marker:
		ground_marker.visible = false


# ----------------- Trajectory preview -----------------

func _update_trajectory() -> void:
	if trajectory == null or _active_baton == null:
		return
	# trajectory is loosely typed; call methods via duck typing.
	if trajectory.has_method("set_aiming_color"):
		trajectory.set_aiming_color()
	var origin: Vector3 = _active_baton.global_position
	var velocity: Vector3 = _compute_initial_velocity()
	var exclude: Array[RID] = [_active_baton.get_rid()] if _active_baton.get_rid().is_valid() else []
	var pts: PackedVector3Array = trajectory.call("update_arc", origin, velocity, exclude, 0xFFFFFFFF)
	_update_ground_marker(pts)


func _update_ground_marker(pts: PackedVector3Array) -> void:
	if ground_marker == null or pts.size() < 2:
		return
	ground_marker.global_position = pts[pts.size() - 1] + Vector3(0.0, 0.02, 0.0)
	ground_marker.visible = true


# ----------------- Math helpers -----------------

func _compute_baton_transform() -> Transform3D:
	if baton_spawn == null:
		return Transform3D.IDENTITY
	# Throw direction in world space (yaw + pitch).
	var fwd: Vector3 = Vector3(
		sin(_yaw) * cos(_pitch),
		sin(_pitch),
		-cos(_yaw) * cos(_pitch)
	).normalized()
	# Build a basis where the baton's local Y (its long axis) points along fwd.
	var y_axis: Vector3 = fwd
	var up_ref: Vector3 = Vector3.UP
	var x_axis: Vector3 = up_ref.cross(y_axis)
	if x_axis.length() < 0.001:
		x_axis = Vector3.RIGHT
	x_axis = x_axis.normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	y_axis = z_axis.cross(x_axis).normalized()
	# Apply visual roll around the baton's long axis.
	if abs(_roll) > 0.001:
		var roll_b: Basis = Basis(y_axis, _roll)
		x_axis = roll_b * x_axis
		z_axis = roll_b * z_axis
	var basis: Basis = Basis(x_axis, y_axis, z_axis)
	return Transform3D(basis, baton_spawn.global_position)


func _compute_initial_velocity() -> Vector3:
	# Velocity magnitude that, given baton mass, produces the chosen impulse.
	# impulse = m * v  =>  v = impulse / m. We return velocity directly here.
	if _active_baton == null:
		return _compute_initial_impulse()  # fallback
	var v_mag: float = _force
	var fwd: Vector3 = Vector3(
		sin(_yaw) * cos(_pitch),
		sin(_pitch),
		-cos(_yaw) * cos(_pitch)
	).normalized()
	return fwd * v_mag


func _compute_initial_impulse() -> Vector3:
	# impulse vector = direction * force. Force is treated as "Newton-seconds at unit mass".
	var fwd: Vector3 = Vector3(
		sin(_yaw) * cos(_pitch),
		sin(_pitch),
		-cos(_yaw) * cos(_pitch)
	).normalized()
	return fwd * _force


func _pitch_from_input(input_value: float) -> float:
	# input in [-1, 1]: -1 = min_pitch, +1 = max_pitch.
	var t: float = clampf((input_value + 1.0) * 0.5, 0.0, 1.0)
	return lerp(min_pitch_degrees, max_pitch_degrees, t)


# ----------------- Raw input helpers -----------------

func _get_axis(axis: int) -> float:
	return Input.get_joy_axis(0, axis)


func _normalize_axis(value: float) -> float:
	if abs(value) < stick_deadzone:
		return 0.0
	return signf(value) * (absf(value) - stick_deadzone) / (1.0 - stick_deadzone)
