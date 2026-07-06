# GameWorld.gd — Root scene script. Wires up global input (reset_kubbs).
extends Node3D

# Load by path so we don't depend on global class_name resolution,
# which isn't available until the editor scans the project.
const GameManagerScript = preload("res://scripts/GameManager.gd")


func _process(_delta: float) -> void:
	# X button on Xbox controller -> reset all kubbs to their starting positions.
	if InputMap.has_action("reset_kubbs") and Input.is_action_just_pressed("reset_kubbs"):
		var gm = _find_game_manager()
		if gm != null:
			gm.reset_kubbs()


func _find_game_manager() -> Node:
	for child in get_children():
		if child is GameManagerScript:
			return child
	return null
