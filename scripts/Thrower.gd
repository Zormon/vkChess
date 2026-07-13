# Thrower.gd - Orchestrates baton throw state machine and physics.
# State flow: AIMING --(freeze)--> FROZEN --(throw)--> THROWN --(stopped)--> AIMING
class_name Thrower
extends Node3D

signal state_changed(new_state: int)

enum State {AIMING, FROZEN, THROWN, INVALID}

# Typed snapshot of the controller's aim/force state.
class AimSnapshot extends RefCounted:
	var yaw: float = 0.0
	var pitch: float = 0.0
	var roll: float = 0.0
	var force: float = 0.0
	var spin: Vector3 = Vector3.ZERO

@export_group("Node References")
@export var baton_spawn: Node3D
@export var ui_controller: Node

@export_group("Aim Tuning")
@export_range(0.0, 60.0, 1.0) var max_yaw_degrees: float = 25.0
@export_range(0.0, 45.0, 1.0) var min_pitch_degrees: float = 5.0
@export_range(30.0, 89.0, 1.0) var max_pitch_degrees: float = 55.0

@export_group("Force / Spin")
@export_range(0.1, 20.0, 0.1) var min_force: float = 0.6
@export_range(0.5, 30.0, 0.1) var max_force: float = 3.0
@export_range(0.0, 30.0, 0.5) var max_spin_rad: float = 10.0
@export_range(0.0, 1.0, 0.2) var max_visual_roll: float = 2.0

var _state: int = State.INVALID
var _baton = null

var _yaw: float = 0.0
var _pitch: float = deg_to_rad(35.0)
var _roll: float = 0.0
var _force: float = 0.0
var _spin: Vector3 = Vector3.ZERO
var _aim: AimSnapshot


func _ready() -> void:
	# Deferred so the PhysicsServer3D has registered the new RigidBody3D
	# call_deferred("_spawn_baton")
	_change_state(State.AIMING)

func _process(_delta: float) -> void:
	# Hold to freeze, release to throw
	match _state:
		State.AIMING:
			_update_baton_transform_from_input()
			if Input.is_action_just_pressed('pl_launch'):
				_change_state(State.FROZEN)
		
		State.FROZEN:
			if Input.is_action_just_released('pl_launch'):
				_change_state(State.THROWN)

			elif Input.is_action_just_pressed('pl_cancel'):
				_change_state(State.AIMING)

	# --- Debug actions ---
	if Input.is_action_just_pressed('debug_reset_baton') and _state == State.THROWN:
		_change_state(State.AIMING)

#----------------- State Management -----------------

func _change_state(new_state: State) -> void:
	if _state == new_state:
		return

	var old_state = _state
	_exit_state(old_state, new_state)
	_state = new_state
	_enter_state(old_state, new_state)
	state_changed.emit(new_state)

func _exit_state(_old_state: State, _new_state: State) -> void:
	# Currently no exit actions needed.
	pass

func _enter_state(_old_state: State, new_state: State) -> void:
	match new_state:
		State.AIMING:
			_spawn_baton()

		State.FROZEN:
			pass

		State.THROWN:
			_throw()

# ----------------- Events -----------------

func _on_baton_stopped() -> void:
	_change_state(State.AIMING)

# ----------------- Actions -----------------

# Spawns or resets the baton to the launch position
func _spawn_baton() -> void:
	# Remove current baton
	if _baton != null and is_instance_valid(_baton):
		_baton.free()

	var baton = Globals.KastpinneScene.instantiate()
	# baton.freeze = true
	# baton.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	baton.linear_velocity = Vector3.ZERO
	baton.angular_velocity = Vector3.ZERO

	baton.stopped_moving.connect(_on_baton_stopped)
	add_child(baton)
	_baton = baton

func _throw() -> void:
	if _baton == null: # No deberia de ocurrir
		_change_state(State.AIMING)
		return
	
	_baton.throw(_aim_direction_world() * _force, _spin)

# ----------------- UI helper -----------------

# TODO: Mover esto al ui gamemanager y suscribirse al evento onchanged state
# func _update_ui_state_label(state: State) -> void:
# 	if OS.has_feature("editor"):
# 		ui_controller.call("set_state_label", State.keys()[state])


# ----------------- Computers -----------------

# Apply a snapshot to local state and the baton
func _update_baton_transform_from_input() -> void:
	var input_aim: Vector2 = Input.get_vector('pl_aim_left', 'pl_aim_right', 'pl_aim_down', 'pl_aim_up')
	var input_force: float = Input.get_axis('pl_force_down', 'pl_force_up')
	var input_spin: float = Input.get_axis('pl_spin_left', 'pl_spin_right')

	# Points to the front
	_aim.yaw = input_aim.x * deg_to_rad(max_yaw_degrees)
	_aim.pitch = deg_to_rad(_pitch_from_input(input_aim.y))
	_aim.force = lerp(min_force, max_force, clampf(input_force, 0.0, 1.0))
	_aim.roll = input_spin * max_visual_roll
	_aim.spin = Vector3(0.0, 0.0, -input_spin * max_spin_rad)

	if _baton != null:
		_baton.reset_to(_compute_baton_transform())

# ----------------- Math helpers -----------------

# Aim direction in world space
func _aim_direction_world() -> Vector3:
	return Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), - cos(_yaw) * cos(_pitch)).normalized()

func _compute_baton_transform() -> Transform3D:
	var fwd: Vector3 = _aim_direction_world()
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
	var basisn: Basis = Basis(x_axis, y_axis, z_axis)
	return Transform3D(basisn, global_position)

func _pitch_from_input(input_value: float) -> float:
	var t: float = clampf((input_value + 1.0) * 0.5, 0.0, 1.0)
	return lerp(min_pitch_degrees, max_pitch_degrees, t)
