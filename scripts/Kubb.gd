# Kubb.gd — Target wooden block that can be toppled by thrown batons.
class_name Kubb
extends RigidBody3D

## Emitted exactly once when this kubb transitions from upright to fallen.
signal knocked_down()

@export_group("Physics")
@export var mass_kg: float = 0.5
@export_range(0.0, 2.0, 0.05) var angular_damping: float = 0.5
@export var physics_material_friction: float = 0.6
@export var physics_material_bounce: float = 0.1

## How aligned the local Y must be with world UP to count as "upright".
## 1.0 = perfectly upright, 0.0 = on its side, <0 = inverted.
@export_range(0.0, 1.0, 0.05) var upright_threshold: float = 0.7

var _was_upright: bool = true


func _ready() -> void:
	mass = mass_kg
	angular_damp = angular_damping
	contact_monitor = true
	max_contacts_reported = 2
	var pmat: PhysicsMaterial = PhysicsMaterial.new()
	pmat.friction = physics_material_friction
	pmat.bounce = physics_material_bounce
	physics_material_override = pmat


func _physics_process(_delta: float) -> void:
	var up_dir: Vector3 = global_transform.basis.y
	var alignment: float = up_dir.dot(Vector3.UP)
	var is_upright: bool = alignment > upright_threshold
	if _was_upright and not is_upright:
		knocked_down.emit()
	_was_upright = is_upright


## Reset to the given transform and put the body to sleep.
## IMPORTANT: in Godot 4, setting global_transform directly on a live RigidBody3D
## from a non-physics callback (like an Input handler) can be silently
## overwritten by the next physics step, leaving the kubb in its old position.
## The robust pattern is: freeze, teleport via PhysicsServer3D, sleep, and defer
## the unfreeze so the physics server has time to commit the new transform.
func reset_to(transform_xform: Transform3D) -> void:
	var was_frozen: bool = freeze
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	# Use PhysicsServer3D to atomically push the new transform to the physics
	# engine. This bypasses the regular transform setter path that gets
	# overridden by queued physics steps.
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, transform_xform)
	sleeping = true
	_was_upright = true
	# If the body wasn't frozen before, defer the unfreeze so the physics
	# server commits the teleport before the body is simulated again.
	if not was_frozen:
		call_deferred("_unfreeze_after_reset")


func _unfreeze_after_reset() -> void:
	freeze = false
