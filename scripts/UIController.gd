# UIController.gd - Minimal in-game UI for the gamepad-only prototype.
# Shows: device name, state, aim/force/spin debug, power bar, spin bar, control hints.
class_name UIController
extends CanvasLayer

var _device_label: Label
var _power_bar: ProgressBar
var _spin_bar: ProgressBar
var _hint_label: Label
var _state_label: Label
var _aim_label: Label


func _ready() -> void:
	_build_ui()
	InputBus.provider_name_changed.connect(_on_provider_name_changed)
	# provider_name_changed only fires on swaps, not on the initial state,
	# so seed the label with whatever the bus is currently using.
	if _device_label != null:
		_device_label.text = "Input: %s" % InputBus.get_device_name()


func _on_provider_name_changed(device_name: String) -> void:
	if _device_label != null:
		_device_label.text = "Input: %s" % device_name


func _process(_delta: float) -> void:
	# Force bar: 0 to 1, brighter when freeze is held.
	if _power_bar != null:
		var force: float = InputBus.get_force()
		_power_bar.value = force * 100.0
		var held: bool = InputBus.is_freeze_held()
		_power_bar.modulate.a = 0.4 if not held else 1.0

	# Spin bar: -1 (left) to +1 (right), centered at 0.
	# Color: green-ish for +, red-ish for -, white for 0.
	if _spin_bar != null:
		var spin: float = InputBus.get_spin()
		_spin_bar.value = spin
		if spin > 0.05:
			_spin_bar.modulate = Color(0.55, 1.0, 0.55)
		elif spin < -0.05:
			_spin_bar.modulate = Color(1.0, 0.55, 0.55)
		else:
			_spin_bar.modulate = Color(1, 1, 1)

	# Debug overlay with live values.
	if _aim_label != null:
		var aim: Vector2 = InputBus.get_aim()
		var spin_val: float = InputBus.get_spin()
		var force_val: float = InputBus.get_force()
		var held: bool = InputBus.is_freeze_held()
		var tag: String = "ZR" if held else "  "
		_aim_label.text = "aim(%+.2f,%+.2f)  spin(%+.2f)  force(%.2f)  [%s]" % [aim.x, aim.y, spin_val, force_val, tag]


func set_state_label(text: String) -> void:
	if _state_label != null:
		_state_label.text = "Estado: %s" % text


func _build_ui() -> void:
	var top_box: VBoxContainer = VBoxContainer.new()
	top_box.position = Vector2(16, 16)
	add_child(top_box)

	_device_label = Label.new()
	_device_label.text = "Input: ..."
	top_box.add_child(_device_label)

	_state_label = Label.new()
	_state_label.text = "Estado: AIMING"
	top_box.add_child(_state_label)

	_aim_label = Label.new()
	_aim_label.text = "aim(0.00, 0.00)  spin(0.00)  force(0.00)  [  ]"
	top_box.add_child(_aim_label)

	# Switch Pro layout: B (button 0) and Y (button 2) for resets.
	_hint_label = Label.new()
	_hint_label.text = "Left stick = aim (X yaw / Y pitch)\nRight stick Y = fuerza | Right stick X = spin\nZR (gatillo derecho) = fijar y lanzar\nB = reset palo | Y = reset kubbs"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.anchor_left = 1.0
	_hint_label.anchor_right = 1.0
	_hint_label.offset_left = -460.0
	_hint_label.offset_top = 16.0
	_hint_label.size = Vector2(444, 72)
	add_child(_hint_label)

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
	add_child(_spin_bar)
