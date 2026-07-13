# This script is used to handle input actions and emit signals when specific actions are triggered.
extends Node

signal throw_released()
signal freeze_started()

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("sys_accept"):
		throw_released.emit()
		
	if Input.is_action_just_pressed("congelar"):
		freeze_started.emit()
		