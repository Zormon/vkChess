# GameManager.gd — Spawns and resets the kubb formation on the field.
class_name GameManager
extends Node

# Preload the Kubb script so type hints work without relying on
# global class_name registration (which lags behind fresh project scans).
const KubbScript = preload("res://scripts/Kubb.gd")

@export_group("Setup")
@export var kubb_scene: PackedScene
@export var kubb_root: Node3D = null

@export_group("Field Layout")
@export_range(1, 10, 1) var kubb_count: int = 5
@export_range(0.2, 2.0, 0.05) var kubb_spacing: float = 0.8
@export_range(2.0, 12.0, 0.5) var field_length: float = 8.0

var _kubbs: Array = []
var _kubb_start_transforms: Array[Transform3D] = []


func _ready() -> void:
	# Default kubb_root to a sibling named "Kubbs" if not set in the scene.
	if kubb_root == null:
		var parent: Node = get_parent()
		if parent != null:
			var n: Node = parent.get_node_or_null("Field/Kubbs")
			if n != null:
				kubb_root = n
	_spawn_kubbs()


func _spawn_kubbs() -> void:
	_clear_kubbs()
	if kubb_scene == null or kubb_root == null:
		push_warning("GameManager: missing kubb_scene or kubb_root")
		return
	# Kubbs line up on the baseline at the far end of the field (negative Z).
	var baseline_z: float = -field_length * 0.5
	for i in kubb_count:
		var kubb = kubb_scene.instantiate()
		kubb_root.add_child(kubb)
		# Center the line around X=0. With 5 kubbs and spacing 0.8 the row is 3.2m wide.
		var x: float = (float(i) - float(kubb_count - 1) * 0.5) * kubb_spacing
		var t: Transform3D = Transform3D(Basis.IDENTITY, Vector3(x, 0.075, baseline_z))
		kubb.global_transform = t
		_kubbs.append(kubb)
		_kubb_start_transforms.append(t)


func _clear_kubbs() -> void:
	for k in _kubbs:
		if is_instance_valid(k):
			k.queue_free()
	_kubbs.clear()
	_kubb_start_transforms.clear()


## Reset every kubb back to its starting position.
func reset_kubbs() -> void:
	for i in _kubbs.size():
		if is_instance_valid(_kubbs[i]):
			_kubbs[i].reset_to(_kubb_start_transforms[i])
