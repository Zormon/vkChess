# UIController.gd - Debug UI
# Shows: thrower state, aim/force/spin, force,
class_name UIdev
extends CanvasLayer

@export var thrower: Thrower

var _state_label: Label
var _aim_label: Label


func _ready() -> void:
	_build_ui()
	thrower.aim_changed.connect(_aimdata_changed)
	thrower.state_changed.connect(_status_changed)

func _process(_delta: float) -> void:
	pass

func _aimdata_changed(data: Thrower.AimSnapshot) -> void:
	_aim_label.text = "aim(%.2f, %.2f)  spin(%.2f)  force(%.2f)" % [data.yaw, data.pitch, data.spin, data.force]

func _status_changed(state: Thrower.State) -> void:
	print('cambiado estado')
	_state_label.text = Thrower.State.keys()[state]

func _build_ui() -> void:
	var top_box: VBoxContainer = VBoxContainer.new()
	top_box.position = Vector2(16, 16)
	add_child(top_box)

	_state_label = Label.new()
	_state_label.text = "-"
	top_box.add_child(_state_label)

	_aim_label = Label.new()
	_aim_label.text = '-'
	top_box.add_child(_aim_label)
