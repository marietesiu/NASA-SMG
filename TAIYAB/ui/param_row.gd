class_name ParamRow
extends VBoxContainer
## One adjustable variable: label + typed numeric entry (SpinBox) + slider, kept in sync.
## Both inputs enforce the same min/max, so values can never leave the realistic range.

signal value_changed(key: String, value: float)

var key: String = ""
var _slider: HSlider
var _spin: SpinBox


func setup(p_key: String, def: Dictionary) -> void:
	key = p_key
	add_theme_constant_override("separation", 3)

	var top: HBoxContainer = HBoxContainer.new()
	add_child(top)
	var name_label: Label = Label.new()
	name_label.text = def["label"]
	name_label.tooltip_text = def["desc"]
	name_label.mouse_filter = Control.MOUSE_FILTER_STOP
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)

	_spin = SpinBox.new()
	_spin.min_value = def["min"]
	_spin.max_value = def["max"]
	_spin.step = def["step"]
	_spin.allow_greater = false
	_spin.allow_lesser = false
	_spin.select_all_on_focus = true
	_spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var unit: String = def["unit"]
	_spin.suffix = (" " + unit) if unit != "" else ""
	_spin.custom_minimum_size = Vector2(160, 0)
	_spin.tooltip_text = def["desc"]
	top.add_child(_spin)

	_slider = HSlider.new()
	_slider.min_value = def["min"]
	_slider.max_value = def["max"]
	_slider.step = def["step"]
	_slider.exp_edit = bool(def["exp"])
	_slider.tooltip_text = def["desc"]
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_slider)

	_slider.value_changed.connect(_on_slider)
	_spin.value_changed.connect(_on_spin)


func get_value() -> float:
	return _slider.value


func set_value_silent(v: float) -> void:
	_slider.set_value_no_signal(v)
	_spin.set_value_no_signal(v)


## Re-bound the control (e.g. fuel can never exceed 95 % of the launch mass). Clamps without signalling.
func set_limits(lo: float, hi: float) -> void:
	_slider.set_block_signals(true)
	_spin.set_block_signals(true)
	_slider.min_value = lo
	_slider.max_value = hi
	_spin.min_value = lo
	_spin.max_value = hi
	var v: float = clampf(_slider.value, lo, hi)
	_slider.value = v
	_spin.value = v
	_slider.set_block_signals(false)
	_spin.set_block_signals(false)


func _on_slider(v: float) -> void:
	_spin.set_value_no_signal(v)
	value_changed.emit(key, v)


func _on_spin(v: float) -> void:
	_slider.set_value_no_signal(v)
	value_changed.emit(key, v)
