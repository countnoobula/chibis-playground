extends CanvasLayer

const Lighting := preload("res://levels/rooftop_gym/rooftop_celestial_lighting.gd")
const TouchPointer := preload("res://ui/hud/menu_touch_pointer.gd")
const PHASE_NAMES := [
	"New moon", "Waxing crescent", "First quarter", "Waxing gibbous",
	"Full moon", "Waning gibbous", "Last quarter", "Waning crescent",
]

var _lighting: Lighting
var _input_handler: ChibiInput
var _touch_hud: CanvasLayer
var _pointer := TouchPointer.new()
var _trigger: Button
var _panel: PanelContainer
var _time: HSlider
var _phase: HSlider
var _time_label: Label
var _phase_label: Label
var _touch_was_processing := true


func setup(lighting: Lighting, player: ParkourController) -> void:
	_lighting = lighting
	_input_handler = player.chibi_input
	_touch_hud = player.touch_hud


func _ready() -> void:
	layer = 30
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_trigger = Button.new()
	_trigger.name = "SkyPreviewButton"
	_trigger.text = "Sky [L]"
	_trigger.position = Vector2(16.0, 16.0)
	_trigger.custom_minimum_size = Vector2(82.0, 42.0)
	_trigger.pressed.connect(_toggle)
	root.add_child(_trigger)

	_panel = PanelContainer.new()
	_panel.name = "SkyPreviewPanel"
	_panel.position = _trigger.position
	_panel.hide()
	root.add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "Rooftop sky"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_button(header, "Default", _restore)
	_button(header, "Close", _toggle)

	var presets := HBoxContainer.new()
	column.add_child(presets)
	for preset in Lighting.PRESETS:
		var button := _button(presets, preset.label, _choose_hour.bind(float(preset.hour)))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_time_label = Label.new()
	_time_label.text = "Time of day · Authored"
	column.add_child(_time_label)
	_time = _slider(column, "TimeSlider", 24.0, 0.05, 9.0)
	_phase_label = Label.new()
	column.add_child(_phase_label)
	_phase = _slider(column, "PhaseSlider", 1.0, 0.005, 0.5)
	_update_phase_label()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_L or event.physical_keycode == KEY_L:
			_toggle()
			get_viewport().set_input_as_handled()
		elif _panel.visible and event.is_action_pressed(&"ui_cancel"):
			_toggle()
			get_viewport().set_input_as_handled()
		elif _panel.visible and (event.keycode == KEY_F or event.physical_keycode == KEY_F):
			get_viewport().set_input_as_handled()
	elif _panel.visible and (event is InputEventScreenTouch or event is InputEventScreenDrag):
		_pointer.forward(get_viewport(), event)
	elif event is InputEventScreenTouch and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.pressed and not event.canceled and _trigger.get_global_rect().has_point(event.position):
			_toggle()
			get_viewport().set_input_as_handled()


func _toggle() -> void:
	if _panel.visible:
		_pointer.reset(get_viewport())
		_panel.hide()
		_trigger.show()
		if is_instance_valid(_touch_hud):
			_touch_hud.set_process_input(_touch_was_processing)
		_input_handler.set_menu_open(false)
		return
	if _input_handler.is_menu_open():
		return
	_input_handler.clear_touch_input()
	_input_handler.set_menu_open(true)
	if is_instance_valid(_touch_hud):
		_touch_hud.call("_reset_touches")
		_touch_was_processing = _touch_hud.is_processing_input()
		_touch_hud.set_process_input(false)
	_trigger.hide()
	_panel.show()
	_time.grab_focus()


func _button(parent: Container, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(62.0, 42.0)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _slider(parent: Container, node_name: String, limit: float, increment: float, initial: float) -> HSlider:
	var slider := HSlider.new()
	slider.name = node_name
	slider.accessibility_name = "Time of day" if node_name == "TimeSlider" else "Moon phase"
	slider.custom_minimum_size.y = 36.0
	slider.max_value = limit
	slider.step = increment
	slider.value = initial
	slider.value_changed.connect(_update_preview)
	parent.add_child(slider)
	return slider


func _choose_hour(hour: float) -> void:
	_time.set_value_no_signal(hour)
	_update_preview(hour)


func _update_preview(_value: float) -> void:
	_lighting.apply_preview(_time.value, _phase.value)
	var minutes := roundi(_time.value * 60.0) % 1440
	_time_label.text = "Time of day · %02d:%02d" % [floori(minutes / 60.0), minutes % 60]
	_update_phase_label()


func _update_phase_label() -> void:
	var name_index := roundi(_phase.value * PHASE_NAMES.size()) % PHASE_NAMES.size()
	var lit_percent := roundi(100.0 * Lighting.moon_fraction(_phase.value))
	_phase_label.text = "Moon phase · %s (%d%% lit)" % [PHASE_NAMES[name_index], lit_percent]


func _restore() -> void:
	_lighting.restore_authored()
	_time_label.text = "Time of day · Authored"
