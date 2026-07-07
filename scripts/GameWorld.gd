# GameWorld.gd — Root scene script. Minimal glue.
# All input handling is now done by the LaunchController via InputProvider.
extends Node3D


func _ready() -> void:
	# Ensure the mouse is visible by default when the game starts, since
	# the MouseKeyboardInputProvider will take over and use absolute mouse pos.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
