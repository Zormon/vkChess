# Thrower.gd - Orchestrates baton throw state machine and physics.
# State flow: AIMING --(freeze)--> FROZEN --(throw)--> THROWN --(stopped)--> AIMING
# @tool
class_name Thrower
extends Node3D

signal state_changed(state: State)
signal aim_changed(aimData: AimSnapshot)

enum State {AIMING, FROZEN, THROWN, INVALID}

# Typed snapshot of the controller's aim/force state.
class AimSnapshot extends RefCounted:
	var yaw: float = 0.0
	var pitch: float = 0.0
	var roll: float = 0.0
	var force: float = 0.0
	var spin: float = 0.0

@export var kastpinneScene: PackedScene:
	set(value):
		kastpinneScene = value
		update_configuration_warnings()

@export_group("Aim Tuning")
@export_range(0.0, 60.0, 1.0) var max_yaw_degrees: float = 25.0
@export_range(-25.0, 45.0, 1.0) var min_pitch_degrees: float = 5.0
@export_range(30.0, 89.0, 1.0) var max_pitch_degrees: float = 55.0

@export_group("Spin")
@export_range(0.1, 20.0, 0.1) var min_force: float = 0.6
@export_range(0.5, 30.0, 0.1) var max_force: float = 3.0
@export_range(0.0, 30.0, 0.5) var max_spin: float = 10.0

var _state: int = State.INVALID
var _baton = null
var _aim: AimSnapshot = AimSnapshot.new()

func _get_configuration_warnings() -> PackedStringArray:
	var warnings = PackedStringArray()

	# var script_raiz = kastpinneScene.get_state().get_node_script(0)
	# if script_raiz == null or not (script_raiz.new() is Kastpinne):
	# 	warnings.append("¡ERROR! La escena asignada en 'kastpinneScene' debe tener el script 'Kastpinne' en su nodo raíz.")
	warnings.append("¡ERROR! La escena asignada en 'kastpinneScene' debe tener el script 'Kastpinne' en su nodo raíz.")

	return warnings


func _ready() -> void:
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
	if Input.is_action_just_pressed('dev_reset_baton') and _state == State.THROWN:
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
func _spawn_baton(reset: bool = false) -> void:
	# Remove current baton
	if reset and is_instance_valid(_baton):
		_baton.free()

	var baton = kastpinneScene.instantiate() as Kastpinne
	baton.freeze = true
	baton.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	baton.linear_velocity = Vector3.ZERO
	baton.angular_velocity = Vector3.ZERO

	baton.stopped_moving.connect(_on_baton_stopped)
	add_child(baton)
	_baton = baton

func _throw() -> void:
	if _baton == null: # No deberia de ocurrir
		_change_state(State.AIMING)
		return
	
	_baton.throw(_aim_direction_world() * _aim.force, _aim.spin)

# ----------------- Computers -----------------

# Apply a snapshot to local state and the baton
func _update_baton_transform_from_input() -> void:
	var input_aim: Vector2 = Input.get_vector('pl_aim_left', 'pl_aim_right', 'pl_aim_down', 'pl_aim_up')
	var input_force: float = Input.get_axis('pl_force_down', 'pl_force_up')
	var input_spin: float = Input.get_axis('pl_spin_left', 'pl_spin_right')

	# Points to the front
	_aim.yaw = input_aim.x * deg_to_rad(max_yaw_degrees)
	_aim.pitch = deg_to_rad(_pitch_from_input(input_aim.y))
	_aim.force = lerp(min_force, max_force, input_force * 0.5 + 0.5)
	_aim.roll = input_spin * 2
	_aim.spin = input_spin * max_spin

	if _baton != null:
		_baton.reset_to(_compute_baton_transform())

	aim_changed.emit(_aim)

# ----------------- Math helpers -----------------

# Aim direction in world space
func _aim_direction_world() -> Vector3:
	return Vector3(sin(_aim.yaw) * cos(_aim.pitch), sin(_aim.pitch), - cos(_aim.yaw) * cos(_aim.pitch)).normalized()

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
	if abs(_aim.roll) > 0.001:
		var roll_b: Basis = Basis(y_axis, _aim.roll)
		x_axis = roll_b * x_axis
		z_axis = roll_b * z_axis
	var basisn: Basis = Basis(x_axis, y_axis, z_axis)
	return Transform3D(basisn, global_transform.origin)

func _pitch_from_input(input_value: float) -> float:
	var t: float = clampf((input_value + 1.0) * 0.5, 0.0, 1.0)
	return lerp(min_pitch_degrees, max_pitch_degrees, t)
