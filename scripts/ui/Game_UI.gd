# Game_UI.gd - Minimal in-game UI.
class_name Game_UI
extends CanvasLayer

@export var thrower: Thrower

var _spin_bar: ProgressBar

func _ready() -> void:
	_build_ui()
	thrower.aim_changed.connect(on_aimdata_updated)

func _process(_delta: float) -> void:
	pass

func _build_ui() -> void:
	# Spin bar (-1 to +1, centered at 0).
	_spin_bar = ProgressBar.new()
	_spin_bar.min_value = -1.0
	_spin_bar.max_value = 1.0
	_spin_bar.value = 0.0
	_spin_bar.show_percentage = false
	_spin_bar.custom_minimum_size = Vector2(280, 18)
	_spin_bar.anchor_left = 0.5
	_spin_bar.anchor_right = 0.5
	_spin_bar.anchor_top = 1.0
	_spin_bar.anchor_bottom = 1.0
	_spin_bar.offset_left = -140.0
	_spin_bar.offset_right = 140.0
	_spin_bar.offset_top = -96.0
	_spin_bar.offset_bottom = -78.0
	_spin_bar.modulate = Color(1, 1, 1)
	add_child(_spin_bar)

func on_aimdata_updated(aimData: Thrower.AimSnapshot) -> void:
	_spin_bar.value = aimData.spin / thrower.max_spin
