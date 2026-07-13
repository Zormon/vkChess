# GameManager.gd — Spawns and resets the kubb formation on the field.
# The kubb layout is the GameManager's responsibility; the LaunchController
# just routes the "reset kubbs" user action to the public reset_kubbs() API.
class_name GameManager
extends Node

@export_group("Field Layout")
@export var kubb_spawn1: Node3D = null
@export var kubb_spawn2: Node3D = null
@export_range(1, 10, 1) var kubb_count: int = 5
@export_range(2.0, 12.0, 0.5) var spawn_length: float = 8.0

var _kubbs1: Array = []
var _kubbs2: Array = []


func _ready() -> void:
	InputBus.reset_kubbs_requested.connect(reset_kubbs)
	_spawn_kubbs()


## Public entry point: clears any fallen kubbs and rebuilds the formation.
## Called by the LaunchController when the user requests a kubb reset
## (gamepad Y / keyboard T). Safe to call any number of times.
func reset_kubbs() -> void:
	_spawn_kubbs()


# Spawns the kubbs in their starting positions on the field. Clears any
# existing kubbs first, then fills each non-null spawn point with a row
# of `kubb_count` kubbs distributed along its local +X axis.
func _spawn_kubbs() -> void:
	_clear_kubbs()
	if kubb_spawn1 != null:
		_kubbs1 = _spawn_row(kubb_spawn1)
	if kubb_spawn2 != null:
		_kubbs2 = _spawn_row(kubb_spawn2)


# Spawns one row of `kubb_count` kubbs as children of `parent`, raised
# 0.25m so the rigid bodies settle cleanly on the ground.
func _spawn_row(parent: Node3D) -> Array:
	var row: Array = []
	for i in kubb_count:
		var kubb: RigidBody3D = Globals.KubbScene.instantiate()
		kubb.translate_object_local(Vector3(i * (spawn_length / kubb_count), 0.25, 0.0))
		parent.add_child(kubb)
		row.append(kubb)
	return row


func _clear_kubbs() -> void:
	for k in _kubbs1:
		if is_instance_valid(k):
			k.queue_free()
	for k in _kubbs2:
		if is_instance_valid(k):
			k.queue_free()
	_kubbs1.clear()
	_kubbs2.clear()
