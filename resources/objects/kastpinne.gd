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
var _flying: bool = false


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
func throw(force: Vector3, spin: float) -> void:
	freeze = false
	sleeping = false
	apply_central_impulse(force)
	angular_velocity = Vector3(0.0, 0.0, spin)
	_flying = true
	_stopped_timer = 0.0


## Reset to a given transform and freeze (kinematic, still collidable).
func reset_to(transform_xform: Transform3D) -> void:
	_flying = false
	_stopped_timer = 0.0
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = transform_xform
	# Also push to the physics server if the RID is already valid, so the
	# frozen body's colliders move with it.
	if get_rid().is_valid():
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, transform_xform)
	sleeping = true
	# Stay frozen — the LaunchController will call throw() to release us.


func _physics_process(delta: float) -> void:
	if not _flying:
		return
	# Detect "stopped" condition for auto-reset.
	if (linear_velocity.length() < contact_threshold_speed
			and angular_velocity.length() < contact_threshold_speed):
		_stopped_timer += delta
		if _stopped_timer >= stopped_time_threshold:
			_flying = false
			_stopped_timer = 0.0
			stopped_moving.emit()
	else:
		_stopped_timer = 0.0


func _on_body_entered(body: Node) -> void:
	hit.emit(body)
