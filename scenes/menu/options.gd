extends Control

signal back_requested

const DESIGN_SIZE := Vector2(1280.0, 720.0)
const BACKGROUND_PATH := "res://scenes/menu/art/options_background.png"
const BERRY_JOURNAL_FONT: Font = preload("res://scenes/menu/berry_journal_font.tres")
const OPTIONS_VISUALS_SCRIPT := preload("res://scenes/menu/options_visuals.gd")
const SFX_PREVIEW_STREAM := preload("res://assets/audio/SFX_Jump.wav")

const SLIDER_NODE_NAMES := {
	&"master_volume": "MasterVolumeSlider",
	&"music_volume": "MusicVolumeSlider",
	&"sfx_volume": "SFXVolumeSlider",
	&"sensitivity": "SensitivitySlider",
	&"quality": "QualitySlider",
}

const FOCUS_COLOR := Color("#d72e63")
const FOCUS_FILL := Color(0.84, 0.18, 0.39, 0.075)

@onready var _artwork_canvas: Control = $ArtworkCanvas

var _visuals: Control
var _sliders: Dictionary = {}
var _invert_button: Button
var _view_controls_button: Button
var _back_button: Button
var _controls_modal: Control
var _controls_close_button: Button
var _sfx_preview_player: AudioStreamPlayer
var _sfx_preview_timer: Timer
var _transparent_texture: ImageTexture


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var menu_theme := Theme.new()
	menu_theme.default_font = BERRY_JOURNAL_FONT
	theme = menu_theme
	resized.connect(_fit_canvas)
	_fit_canvas()
	_load_background()
	_create_transparent_texture()
	_create_visual_layer()
	_create_sliders()
	_create_invert_toggle()
	_create_quality_label_buttons()
	_create_navigation_buttons()
	_create_sfx_preview()
	_create_controls_modal()
	_wire_focus_order()
	call_deferred("_focus_initial_control")


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or event.is_echo():
		return
	if _controls_modal != null and _controls_modal.visible:
		_close_controls()
	else:
		back_requested.emit()
	get_viewport().set_input_as_handled()


func _fit_canvas() -> void:
	if _artwork_canvas == null:
		return
	var fit_scale := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	_artwork_canvas.scale = Vector2.ONE * fit_scale
	_artwork_canvas.position = (size - DESIGN_SIZE * fit_scale) * 0.5


func _load_background() -> void:
	var background := $ArtworkCanvas/Background as TextureRect
	var texture := load(BACKGROUND_PATH) as Texture2D
	if texture == null:
		push_warning("Options background is missing: %s" % BACKGROUND_PATH)
		return
	background.texture = texture


func _create_transparent_texture() -> void:
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	_transparent_texture = ImageTexture.create_from_image(image)


func _create_visual_layer() -> void:
	_visuals = OPTIONS_VISUALS_SCRIPT.new() as Control
	_visuals.name = "WidgetVisuals"
	_visuals.position = Vector2.ZERO
	_visuals.size = DESIGN_SIZE
	_visuals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visuals.set("serif_font", BERRY_JOURNAL_FONT)
	_artwork_canvas.add_child(_visuals)


func _create_sliders() -> void:
	_add_slider(&"master_volume", Rect2(345.0, 213.0, 238.0, 34.0), 0.0, 1.0, 0.01)
	_add_slider(&"music_volume", Rect2(350.0, 252.0, 230.0, 34.0), 0.0, 1.0, 0.01)
	_add_slider(&"sfx_volume", Rect2(350.0, 292.0, 230.0, 34.0), 0.0, 1.0, 0.01)
	_add_slider(&"sensitivity", Rect2(342.0, 432.0, 240.0, 34.0), 0.5, 2.0, 0.01)
	_add_slider(&"quality", Rect2(695.0, 282.0, 346.0, 28.0), 0.0, 3.0, 1.0)
	_visuals.set("sliders", _sliders)


func _add_slider(
	key: StringName,
	control_rect: Rect2,
	minimum: float,
	maximum: float,
	step_size: float
) -> void:
	var slider := HSlider.new()
	slider.name = SLIDER_NODE_NAMES[key]
	slider.position = control_rect.position
	slider.size = control_rect.size
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step_size
	slider.value = clampf(float(_read_setting(key)), minimum, maximum)
	slider.focus_mode = Control.FOCUS_ALL
	slider.mouse_filter = Control.MOUSE_FILTER_STOP
	slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	slider.add_theme_stylebox_override("slider", StyleBoxEmpty.new())
	slider.add_theme_stylebox_override("grabber_area", StyleBoxEmpty.new())
	slider.add_theme_stylebox_override("grabber_area_highlight", StyleBoxEmpty.new())
	slider.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	slider.add_theme_icon_override("grabber", _transparent_texture)
	slider.add_theme_icon_override("grabber_highlight", _transparent_texture)
	slider.add_theme_icon_override("grabber_disabled", _transparent_texture)
	slider.value_changed.connect(_on_slider_value_changed.bind(key))
	slider.focus_entered.connect(_on_widget_focus_changed)
	slider.focus_exited.connect(_on_widget_focus_changed)
	slider.mouse_entered.connect(slider.grab_focus)
	_artwork_canvas.add_child(slider)
	_sliders[key] = slider


func _create_invert_toggle() -> void:
	_invert_button = Button.new()
	_invert_button.name = "InvertYToggle"
	_invert_button.position = Vector2(365.0, 468.0)
	_invert_button.size = Vector2(113.0, 42.0)
	_invert_button.toggle_mode = true
	_invert_button.button_pressed = bool(_read_setting(&"invert_y"))
	_invert_button.focus_mode = Control.FOCUS_ALL
	_invert_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_invert_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_apply_invisible_button_theme(_invert_button)
	_invert_button.toggled.connect(_on_invert_toggled)
	_invert_button.focus_entered.connect(_on_widget_focus_changed)
	_invert_button.focus_exited.connect(_on_widget_focus_changed)
	_invert_button.mouse_entered.connect(_invert_button.grab_focus)
	_artwork_canvas.add_child(_invert_button)
	_visuals.set("invert_button", _invert_button)
	_visuals.set("invert_enabled", _invert_button.button_pressed)


func _create_quality_label_buttons() -> void:
	var stop_xs: Array[float] = [695.0, 810.0, 926.0, 1041.0]
	for index in stop_xs.size():
		var hit_target := Button.new()
		hit_target.name = "QualityLabel%d" % index
		hit_target.position = Vector2(stop_xs[index] - 53.0, 310.0)
		hit_target.size = Vector2(106.0, 42.0)
		hit_target.flat = true
		hit_target.focus_mode = Control.FOCUS_NONE
		hit_target.mouse_filter = Control.MOUSE_FILTER_STOP
		hit_target.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_apply_empty_button_theme(hit_target)
		hit_target.pressed.connect(_on_quality_label_pressed.bind(index))
		_artwork_canvas.add_child(hit_target)


func _create_navigation_buttons() -> void:
	_view_controls_button = _new_invisible_button(
		"ViewControlsButton", Rect2(244.0, 550.0, 286.0, 54.0)
	)
	_view_controls_button.pressed.connect(_open_controls)
	_back_button = _new_invisible_button("BackButton", Rect2(968.0, 616.0, 280.0, 76.0))
	_back_button.pressed.connect(_request_back)


func _new_invisible_button(button_name: String, control_rect: Rect2) -> Button:
	var button := Button.new()
	button.name = button_name
	button.position = control_rect.position
	button.size = control_rect.size
	button.text = ""
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_apply_invisible_button_theme(button)
	button.focus_entered.connect(_on_widget_focus_changed)
	button.focus_exited.connect(_on_widget_focus_changed)
	button.mouse_entered.connect(button.grab_focus)
	_artwork_canvas.add_child(button)
	return button


func _apply_invisible_button_theme(button: Button) -> void:
	_apply_empty_button_theme(button)
	var focus_style := StyleBoxFlat.new()
	focus_style.bg_color = FOCUS_FILL
	focus_style.border_color = FOCUS_COLOR
	focus_style.border_width_left = 2
	focus_style.border_width_top = 2
	focus_style.border_width_right = 2
	focus_style.border_width_bottom = 2
	focus_style.corner_radius_top_left = 18
	focus_style.corner_radius_top_right = 18
	focus_style.corner_radius_bottom_left = 18
	focus_style.corner_radius_bottom_right = 18
	button.add_theme_stylebox_override("focus", focus_style)
	button.add_theme_color_override("font_color", Color.TRANSPARENT)
	button.add_theme_color_override("font_hover_color", Color.TRANSPARENT)
	button.add_theme_color_override("font_pressed_color", Color.TRANSPARENT)
	button.add_theme_color_override("font_hover_pressed_color", Color.TRANSPARENT)
	button.add_theme_color_override("font_focus_color", Color.TRANSPARENT)


func _apply_empty_button_theme(button: Button) -> void:
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())


func _create_sfx_preview() -> void:
	_sfx_preview_player = AudioStreamPlayer.new()
	_sfx_preview_player.name = "SFXPreview"
	_sfx_preview_player.stream = SFX_PREVIEW_STREAM
	_sfx_preview_player.volume_db = -4.0
	_sfx_preview_player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_artwork_canvas.add_child(_sfx_preview_player)
	_sfx_preview_timer = Timer.new()
	_sfx_preview_timer.name = "SFXPreviewDebounce"
	_sfx_preview_timer.one_shot = true
	_sfx_preview_timer.wait_time = 0.18
	_sfx_preview_timer.timeout.connect(_play_sfx_preview)
	_artwork_canvas.add_child(_sfx_preview_timer)


func _create_controls_modal() -> void:
	_controls_modal = Control.new()
	_controls_modal.name = "ControlsModal"
	_controls_modal.position = Vector2.ZERO
	_controls_modal.size = DESIGN_SIZE
	_controls_modal.visible = false
	_controls_modal.z_index = 20
	_controls_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_artwork_canvas.add_child(_controls_modal)

	var dimmer := ColorRect.new()
	dimmer.position = Vector2.ZERO
	dimmer.size = DESIGN_SIZE
	dimmer.color = Color(0.14, 0.055, 0.12, 0.72)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_controls_modal.add_child(dimmer)

	var panel := Panel.new()
	panel.name = "ControlsPanel"
	panel.position = Vector2(284.0, 112.0)
	panel.size = Vector2(712.0, 496.0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#fff1dc")
	panel_style.border_color = Color("#b64c71")
	panel_style.border_width_left = 4
	panel_style.border_width_top = 4
	panel_style.border_width_right = 4
	panel_style.border_width_bottom = 4
	panel_style.corner_radius_top_left = 30
	panel_style.corner_radius_top_right = 30
	panel_style.corner_radius_bottom_left = 30
	panel_style.corner_radius_bottom_right = 30
	panel.add_theme_stylebox_override("panel", panel_style)
	_controls_modal.add_child(panel)

	var title := Label.new()
	title.position = Vector2(42.0, 24.0)
	title.size = Vector2(628.0, 62.0)
	title.text = "Controls"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color("#642044"))
	panel.add_child(title)

	var rows := VBoxContainer.new()
	rows.position = Vector2(86.0, 102.0)
	rows.size = Vector2(540.0, 274.0)
	rows.add_theme_constant_override("separation", 14)
	panel.add_child(rows)
	_add_control_row(rows, "Move", "WASD / Arrow Keys  ·  Left Stick")
	_add_control_row(rows, "Look", "Mouse  ·  Right Stick")
	_add_control_row(rows, "Jump", "Space  ·  Gamepad South")
	_add_control_row(rows, "Slide / Roll", "C or Left Ctrl  ·  Gamepad East")
	_add_control_row(rows, "Pick Up", "E  ·  Gamepad West")
	_add_control_row(rows, "Touch Controls", "F2")

	var escape_hint := Label.new()
	escape_hint.position = Vector2(44.0, 380.0)
	escape_hint.size = Vector2(624.0, 28.0)
	escape_hint.text = "Press Escape to return to Options"
	escape_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	escape_hint.add_theme_font_size_override("font_size", 17)
	escape_hint.add_theme_color_override("font_color", Color("#8b4662"))
	panel.add_child(escape_hint)

	_controls_close_button = Button.new()
	_controls_close_button.name = "ReturnToOptionsButton"
	_controls_close_button.position = Vector2(216.0, 424.0)
	_controls_close_button.size = Vector2(280.0, 58.0)
	_controls_close_button.text = "Back to Options"
	_controls_close_button.focus_mode = Control.FOCUS_ALL
	_controls_close_button.pressed.connect(_close_controls)
	_controls_close_button.add_theme_font_size_override("font_size", 22)
	_controls_close_button.add_theme_color_override("font_color", Color("#642044"))
	_controls_close_button.add_theme_color_override("font_hover_color", Color("#642044"))
	_controls_close_button.add_theme_color_override("font_pressed_color", Color("#642044"))
	_controls_close_button.add_theme_color_override("font_hover_pressed_color", Color("#642044"))
	_controls_close_button.add_theme_color_override("font_focus_color", Color("#642044"))
	_controls_close_button.add_theme_stylebox_override("normal", _modal_button_style(Color("#ffe1cc")))
	_controls_close_button.add_theme_stylebox_override("hover", _modal_button_style(Color("#ffd0c4")))
	_controls_close_button.add_theme_stylebox_override("pressed", _modal_button_style(Color("#f6b6b0")))
	_controls_close_button.add_theme_stylebox_override("focus", _modal_button_style(Color("#ffe1cc"), FOCUS_COLOR))
	var close_path := NodePath(".")
	_controls_close_button.focus_next = close_path
	_controls_close_button.focus_previous = close_path
	_controls_close_button.focus_neighbor_left = close_path
	_controls_close_button.focus_neighbor_right = close_path
	_controls_close_button.focus_neighbor_top = close_path
	_controls_close_button.focus_neighbor_bottom = close_path
	panel.add_child(_controls_close_button)


func _modal_button_style(fill: Color, border: Color = Color("#b64c71")) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_left = 18
	style.corner_radius_bottom_right = 18
	return style


func _add_control_row(container: VBoxContainer, action: String, binding: String) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(540.0, 34.0)
	row.add_theme_constant_override("separation", 18)
	var action_label := Label.new()
	action_label.text = action
	action_label.custom_minimum_size = Vector2(170.0, 34.0)
	action_label.add_theme_font_size_override("font_size", 22)
	action_label.add_theme_color_override("font_color", Color("#642044"))
	row.add_child(action_label)
	var binding_label := Label.new()
	binding_label.text = binding
	binding_label.add_theme_font_size_override("font_size", 20)
	binding_label.add_theme_color_override("font_color", Color("#783653"))
	row.add_child(binding_label)
	container.add_child(row)


func _wire_focus_order() -> void:
	var focusables: Array[Control] = [
		_sliders[&"master_volume"],
		_sliders[&"music_volume"],
		_sliders[&"sfx_volume"],
		_sliders[&"sensitivity"],
		_invert_button,
		_sliders[&"quality"],
		_view_controls_button,
		_back_button,
	]
	for index in focusables.size():
		var control := focusables[index]
		if index > 0:
			control.focus_neighbor_top = control.get_path_to(focusables[index - 1])
		if index < focusables.size() - 1:
			control.focus_neighbor_bottom = control.get_path_to(focusables[index + 1])
	for control in focusables:
		control.focus_next = control.get_path_to(focusables[(focusables.find(control) + 1) % focusables.size()])
		control.focus_previous = control.get_path_to(focusables[posmod(focusables.find(control) - 1, focusables.size())])


func _focus_initial_control() -> void:
	if is_instance_valid(_sliders.get(&"master_volume")):
		(_sliders[&"master_volume"] as Control).grab_focus()


func _on_slider_value_changed(value: float, key: StringName) -> void:
	_save_setting(key, value)
	_visuals.queue_redraw()
	if key == &"sfx_volume":
		_sfx_preview_timer.start()


func _on_invert_toggled(enabled: bool) -> void:
	_visuals.set("invert_enabled", enabled)
	_visuals.queue_redraw()
	_save_setting(&"invert_y", enabled)


func _on_quality_label_pressed(index: int) -> void:
	(_sliders[&"quality"] as HSlider).value = index
	(_sliders[&"quality"] as HSlider).grab_focus()


func _on_widget_focus_changed() -> void:
	_visuals.queue_redraw()


func _open_controls() -> void:
	_controls_modal.visible = true
	_controls_close_button.call_deferred("grab_focus")


func _close_controls() -> void:
	_controls_modal.visible = false
	_view_controls_button.call_deferred("grab_focus")


func _request_back() -> void:
	back_requested.emit()


func _play_sfx_preview() -> void:
	if _sfx_preview_player.playing:
		_sfx_preview_player.stop()
	_sfx_preview_player.play()


func _read_setting(key: StringName) -> Variant:
	var settings := get_node_or_null("/root/GameSettings")
	if settings == null:
		push_error("Options requires the GameSettings autoload.")
		return null
	return settings.get(String(key))


func _save_setting(key: StringName, value: Variant) -> void:
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null and settings.has_method("set_setting"):
		settings.call("set_setting", key, value)
