# GameManager.gd — Spawns and resets the kubb formation on the field.
class_name GameManager
extends Node

const KubbScript = preload("res://scripts/Kubb.gd")

@export_group("Field Layout")
@export var kubb_spawn1: Node3D = null
@export var kubb_spawn2: Node3D = null
@export_range(1, 10, 1) var kubb_count: int = 5
@export_range(2.0, 12.0, 0.5) var spawn_length: float = 8.0

var _kubbs1: Array = []
var _kubbs2: Array = []


func _ready() -> void:
	_spawn_kubbs()


# Spawns the kubbs in their starting positions on the field. Clears any existing kubbs first.
func _spawn_kubbs() -> void:
	_clear_kubbs()

	for i in kubb_count:
		var kubb = Globals.KubbScene.instantiate()
		kubb.translate_object_local(Vector3(i * (spawn_length / kubb_count), 0.25, 0.0))
		kubb_spawn1.add_child(kubb)
		_kubbs1.append(kubb)


func _clear_kubbs() -> void:
	for k in _kubbs1:
		if is_instance_valid(k):
			k.queue_free()
	_kubbs1.clear()
