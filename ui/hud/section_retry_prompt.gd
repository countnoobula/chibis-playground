extends Control

## Small checkpoint indicator with a touch, mouse, and keyboard retry affordance.

signal retry_requested

const INK := Color("302b3d")
const CREAM := Color("fff8ee")
const MINT := Color("9ccfc1")
const PAPER := Color("f0dfbf")

var _panel: PanelContainer
var _section_label: Label
var _checkpoint_available := false
var _mobile_ui := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	set_process_unhandled_key_input(true)
	_mobile_ui = OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--mobile-menu")
	_panel = PanelContainer.new()
	_panel.name = "CheckpointPanel"
	_panel.position = Vector2(16.0, 68.0)
	_panel.custom_minimum_size = Vector2(246.0, 62.0)
	_panel.size = _panel.custom_minimum_size
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_panel.add_child(row)

	var labels := VBoxContainer.new()
	labels.add_theme_constant_override("separation", 1)
	row.add_child(labels)

	var heading := Label.new()
	heading.text = "CHECKPOINT"
	heading.add_theme_color_override("font_color", MINT)
	heading.add_theme_font_size_override("font_size", 11)
	labels.add_child(heading)

	_section_label = Label.new()
	_section_label.text = "Dry Crossing"
	_section_label.add_theme_color_override("font_color", CREAM)
	_section_label.add_theme_font_size_override("font_size", 16)
	labels.add_child(_section_label)

	var retry_button := Button.new()
	retry_button.name = "RetryButton"
	retry_button.text = "Retry"
	retry_button.tooltip_text = "Retry from this checkpoint (R)"
	retry_button.custom_minimum_size = Vector2(82.0, 42.0)
	retry_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	retry_button.focus_mode = Control.FOCUS_ALL
	retry_button.add_theme_stylebox_override("normal", _button_style(PAPER))
	retry_button.add_theme_stylebox_override("hover", _button_style(Color("f8e9cf")))
	retry_button.add_theme_stylebox_override("pressed", _button_style(MINT))
	retry_button.add_theme_color_override("font_color", INK)
	retry_button.add_theme_color_override("font_hover_color", INK)
	retry_button.add_theme_color_override("font_pressed_color", INK)
	retry_button.add_theme_color_override("font_focus_color", INK)
	retry_button.pressed.connect(_request_retry)
	row.add_child(retry_button)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_sync_visibility()


func show_checkpoint(section_name: String) -> void:
	_section_label.text = section_name
	_checkpoint_available = true
	_sync_visibility()


func _process(_delta: float) -> void:
	_sync_visibility()


func _sync_visibility() -> void:
	visible = _checkpoint_available and not get_tree().paused


func _layout() -> void:
	if _panel == null:
		return
	var safe_offset := Vector2.ZERO
	if _mobile_ui:
		var safe_px := Rect2(DisplayServer.get_display_safe_area())
		if safe_px.has_area():
			var to_viewport := get_viewport().get_screen_transform().affine_inverse()
			var window_origin := Vector2(DisplayServer.window_get_position())
			var safe_local := Rect2(
				to_viewport * (safe_px.position - window_origin),
				to_viewport.basis_xform(safe_px.size)
			)
			var clipped := get_viewport().get_visible_rect().intersection(safe_local)
			if clipped.has_area():
				safe_offset = clipped.position
		_panel.position = safe_offset + (Vector2(16.0, 16.0) if _mobile_ui else Vector2(16.0, 68.0))


func _request_retry() -> void:
	retry_requested.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or get_tree().paused or not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if key_event.pressed and not key_event.echo and key_event.keycode == KEY_R:
		_request_retry()
		get_viewport().set_input_as_handled()


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(INK, 0.94)
	style.border_color = MINT
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = MINT
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style
