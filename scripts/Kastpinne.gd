# Kastpinne.gd — RigidBody3D-based throwing baton (Swedish throwing stick).
# Tunable via @export for fast iteration during prototyping.
class_name Kastpinne
extends RigidBody3D

## Emitted on every collision with another physics body.
signal hit(body: Node)

## Emitted when the baton comes to rest after being thrown (auto-reset hook).
signal stopped_moving()

# --- Tunable physics parameters ---
# Defaults approximate a light wooden Kastpinne (~30 cm long, ~0.3 kg).
@export_group("Physics")
@export var mass_kg: float = 0.3
@export_range(0.0, 3.0, 0.05) var gravity_scale_value: float = 1.0
@export_range(0.0, 2.0, 0.05) var linear_damping: float = 0.1
@export_range(0.0, 2.0, 0.05) var angular_damping: float = 0.1
## Wood-like bounce: low friction, moderate bounce.
@export var physics_material_friction: float = 0.4
@export var physics_material_bounce: float = 0.2

# --- Reset / stop detection ---
@export_group("Reset Detection")
@export var contact_threshold_speed: float = 0.08
@export var stopped_time_threshold: float = 1.0

var _stopped_timer: float = 0.0
var _is_in_flight: bool = false


func _ready() -> void:
	mass = mass_kg
	gravity_scale = gravity_scale_value
	linear_damp = linear_damping
	angular_damp = angular_damping
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	# Apply a wood-like PhysicsMaterialOverride so bounces feel right.
	var pmat: PhysicsMaterial = PhysicsMaterial.new()
	pmat.friction = physics_material_friction
	pmat.bounce = physics_material_bounce
	physics_material_override = pmat
	# Start frozen in spawn position. LaunchController calls throw() to release.
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


## Release the baton with a linear impulse and angular velocity.
## force: linear impulse (Newton·seconds). With mass=0.3, 3.6 N·s ≈ 12 m/s.
## spin: angular velocity in radians/sec on each axis.
func throw(force: Vector3, spin: Vector3) -> void:
	freeze = false
	sleeping = false
	apply_central_impulse(force)
	angular_velocity = spin
	_is_in_flight = true
	_stopped_timer = 0.0


## Reset to a given transform and freeze (kinematic, still collidable).
## Strategy:
## 1. Freeze the body first (so the physics server is OK with us writing transform).
## 2. Set global_transform directly — when freeze=true, the physics server
##    treats this as authoritative and the next physics step uses our value
##    (instead of writing over it as happens with live bodies).
## 3. Clear velocities and sleep.
## This works for both the first-spawn case (RID may not be valid yet) and
## subsequent resets, because it does not rely on the physics server's RID.
func reset_to(transform_xform: Transform3D) -> void:
	_is_in_flight = false
	_stopped_timer = 0.0
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	# Direct transform write — safe because the body is frozen.
	global_transform = transform_xform
	# Also push to the physics server if the RID is already valid, so the
	# frozen body's colliders move with it.
	if get_rid().is_valid():
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, transform_xform)
	sleeping = true
	# Stay frozen — the LaunchController will call throw() to release us.


func _physics_process(delta: float) -> void:
	if not _is_in_flight:
		return
	# Detect "stopped" condition for auto-reset.
	if (linear_velocity.length() < contact_threshold_speed
			and angular_velocity.length() < contact_threshold_speed):
		_stopped_timer += delta
		if _stopped_timer >= stopped_time_threshold:
			_is_in_flight = false
			_stopped_timer = 0.0
			stopped_moving.emit()
	else:
		_stopped_timer = 0.0


func _on_body_entered(body: Node) -> void:
	hit.emit(body)
