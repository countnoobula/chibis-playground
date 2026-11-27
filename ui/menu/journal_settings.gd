extends Control

signal toggle_touch_requested
signal toggle_inspector_requested

enum Section { AUDIO, CAMERA, GRAPHICS }

class SliderVisualOverlay extends Control:
	var target_slider: HSlider
	var thumb_texture: Texture2D
	var mobile_layout := false
	var fill_color := Color("#cc2857")
	var rail_color := Color("#f0cbb7")
	var border_color := Color("#98244d")
	var focus_color := Color("#cc2857")

	func _draw() -> void:
		if not is_instance_valid(target_slider) or not target_slider.is_visible_in_tree():
			return
		var local_transform := get_global_transform_with_canvas().affine_inverse() * target_slider.get_global_transform_with_canvas()
		var slider_rect := Rect2(local_transform.origin, local_transform.basis_xform(target_slider.size))
		var thumb_size := 30.0 if mobile_layout else 28.0
		var rail_height := 12.0 if mobile_layout else 14.0
		var rail_rect := Rect2(
			slider_rect.position.x + thumb_size * 0.5,
			slider_rect.get_center().y - rail_height * 0.5,
			maxf(0.0, slider_rect.size.x - thumb_size),
			rail_height
		)
		if target_slider.has_focus():
			draw_style_box(_round_style(Color(1.0, 1.0, 1.0, 0.0), focus_color, 2, 18), rail_rect.grow(10.0))
		draw_style_box(_round_style(rail_color, border_color, 2, int(rail_height * 0.5)), rail_rect)
		var value_range := target_slider.max_value - target_slider.min_value
		var fraction := 0.0 if value_range <= 0.0 else clampf((target_slider.value - target_slider.min_value) / value_range, 0.0, 1.0)
		var fill_width := clampf(rail_rect.size.x * fraction, 0.0, rail_rect.size.x)
		if fill_width > 0.5:
			draw_style_box(_round_style(fill_color, Color.TRANSPARENT, 0, int(rail_height * 0.5)), Rect2(rail_rect.position, Vector2(fill_width, rail_rect.size.y)))
		for index in 4:
			var marker_x := rail_rect.position.x + rail_rect.size.x * float(index) / 3.0
			var marker_center := Vector2(marker_x, rail_rect.get_center().y)
			draw_circle(marker_center, rail_height * 0.30, Color("#fff0db"))
			draw_arc(marker_center, rail_height * 0.30, 0.0, TAU, 24, border_color, 2.0, true)
		var thumb_center := Vector2(rail_rect.position.x + rail_rect.size.x * fraction, rail_rect.get_center().y)
		if thumb_texture != null:
			draw_texture_rect(thumb_texture, Rect2(thumb_center - Vector2.ONE * thumb_size * 0.5, Vector2.ONE * thumb_size), false)

	func _round_style(fill: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
		var style := StyleBoxFlat.new()
		style.bg_color = fill
		style.border_color = border
		style.set_border_width_all(border_width)
		style.set_corner_radius_all(radius)
		style.anti_aliasing = true
		return style


const QUALITY_NAMES := ["Low", "Medium", "High", "Ultra"]
const DEBUG_MENU_ARG := "--debug-menu"
const INK := Color("#4f1939")
const BERRY := Color("#cc2857")
const BERRY_DARK := Color("#98244d")
const RAIL := Color("#f0cbb7")
const CREAM := Color("#fff0db")
const BUTTON_FILL := Color("#ffe4cf")
const SOFT_PINK := Color("#f7d4c5")
const LAVENDER := Color("#9583bd")
const LAVENDER_DARK := Color("#766499")
const LAVENDER_RAIL := Color("#d8c9b5")
const JOURNAL_FONT: Font = preload("res://ui/menu/berry_journal_font.tres")
const SLIDER_THUMB: Texture2D = preload("res://ui/menu/art/mobile_options/slider_thumb.png")
const SFX_PREVIEW_STREAM: AudioStream = preload("res://assets/audio/SFX_Jump.wav")

var _configured := false
var _mobile := false
var _active_section := Section.AUDIO
var _settings: Node
var _audio_page: Control
var _camera_page: Control
var _graphics_page: Control
var _audio_heading: Label
var _camera_heading: Label
var _graphics_heading: Label
var _graphics_presets_heading: Label
var _graphics_left_panel: Panel
var _graphics_right_panel: Panel
var _graphics_slider_overlay: SliderVisualOverlay
var _audio_labels: Dictionary = {}
var _camera_labels: Dictionary = {}
var _sliders: Dictionary = {}
var _invert_button: Button
var _view_controls_button: Button
var _graphics_button: Button
var _graphics_back_button: Button
var _quality_label: Label
var _quality_buttons: Array[Button] = []
var _guide: Control
var _modal_host: Control
var _guide_panel: Panel
var _guide_title: Label
var _guide_rows: VBoxContainer
var _touch_toggle: Button
var _inspector_toggle: Button
var _guide_close_button: Button
var _return_focus: Control
var _touch_enabled := false
var _inspector_enabled := false
var _preview_player: AudioStreamPlayer
var _preview_timer: Timer
var _slider_thumb_texture: Texture2D
var _slider_thumb_textures: Dictionary = {}
var _transparent_slider_textures: Dictionary = {}
var _slider_fill := BERRY
var _slider_rail := RAIL
var _slider_border := BERRY_DARK
var _focus_color := BERRY


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout_content)
	if _configured:
		call_deferred("_layout_content")


## Call after adding this Control to the journal canvas and setting its rect.
func configure(mobile: bool) -> void:
	_mobile = mobile
	_slider_fill = LAVENDER if mobile else BERRY
	_slider_rail = LAVENDER_RAIL if mobile else RAIL
	_slider_border = LAVENDER_DARK if mobile else BERRY_DARK
	_focus_color = LAVENDER if mobile else BERRY
	var page_theme := Theme.new()
	page_theme.default_font = JOURNAL_FONT
	theme = page_theme
	if not _configured:
		_settings = get_node_or_null("/root/GameSettings")
		if _settings == null:
			push_error("Journal Settings requires the GameSettings autoload.")
		_create_pages()
		_create_audio_preview()
		_configured = true
	_apply_static_label_visibility()
	_set_active_section(_active_section)
	_layout_content()


## PauseJournal supplies its viewport-sized root so the guide can cover the spread.
func set_modal_host(host: Control) -> void:
	if is_instance_valid(_modal_host) and _modal_host != host and _modal_host.resized.is_connected(_layout_guide):
		_modal_host.resized.disconnect(_layout_guide)
	_modal_host = host
	if is_instance_valid(_modal_host) and not _modal_host.resized.is_connected(_layout_guide):
		_modal_host.resized.connect(_layout_guide)
	if _guide != null and is_instance_valid(_guide) and is_instance_valid(_modal_host) and _guide.get_parent() != _modal_host:
		_guide.reparent(_modal_host)
		_guide.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_layout_guide()


## Journal-owned category buttons can pass their enum index or a section name.
func set_section(section: Variant) -> void:
	var section_index := _section_index(section)
	if section_index < 0:
		return
	_set_active_section(section_index)
	var category_tabs := get_node_or_null("CategoryTabs")
	if category_tabs != null and category_tabs.has_method("set_selected"):
		category_tabs.call("set_selected", section_index)
	_layout_content()


func set_hud_state(touch_enabled: bool, inspector_enabled: bool) -> void:
	_touch_enabled = touch_enabled
	_inspector_enabled = inspector_enabled
	_update_hud_toggle_labels()
	queue_redraw()


## Returns true when it closed the guide, allowing the journal to consume Escape.
func close_guide() -> bool:
	if _guide == null or not _guide.visible:
		return false
	_guide.hide()
	if is_instance_valid(_return_focus):
		_return_focus.call_deferred("grab_focus")
	elif is_instance_valid(_view_controls_button):
		_view_controls_button.call_deferred("grab_focus")
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not event.is_echo() and close_guide():
		get_viewport().set_input_as_handled()


func _create_pages() -> void:
	_audio_page = _new_page("AudioPage")
	_camera_page = _new_page("CameraPage")
	_graphics_page = _new_page("GraphicsPage")
	_create_audio_page()
	_create_camera_page()
	_create_graphics_page()


func _new_page(page_name: String) -> Control:
	var page := Control.new()
	page.name = page_name
	page.position = Vector2.ZERO
	page.size = size
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page)
	return page


func _create_audio_page() -> void:
	_audio_heading = _new_label(_audio_page, "AudioHeading", "Audio")
	for row in [
		[&"master_volume", "Master Volume", 0.0, 1.0, 0.01],
		[&"music_volume", "Music", 0.0, 1.0, 0.01],
		[&"sfx_volume", "Sound Effects", 0.0, 1.0, 0.01],
	]:
		var key: StringName = row[0]
		_audio_labels[key] = _new_label(_audio_page, "%sLabel" % _pascal_case(key), String(row[1]))
		_sliders[key] = _new_slider(_audio_page, key, float(row[2]), float(row[3]), float(row[4]))
	_graphics_button = _new_button(_audio_page, "GraphicsButton", "Graphics  ›")
	_graphics_button.pressed.connect(set_section.bind(Section.GRAPHICS))


func _create_camera_page() -> void:
	_camera_heading = _new_label(_camera_page, "CameraHeading", "Camera")
	_camera_labels[&"sensitivity"] = _new_label(_camera_page, "SensitivityLabel", "Sensitivity")
	_sliders[&"sensitivity"] = _new_slider(_camera_page, &"sensitivity", 0.5, 2.0, 0.01)
	_camera_labels[&"invert_y"] = _new_label(_camera_page, "InvertYLabel", "Invert Y")
	_invert_button = Button.new()
	_invert_button.name = "InvertYToggle"
	_invert_button.toggle_mode = true
	_invert_button.button_pressed = bool(_read_setting(&"invert_y"))
	_invert_button.text = ""
	_invert_button.focus_mode = Control.FOCUS_ALL
	_invert_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_invert_button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_invert_button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	_invert_button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	_invert_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_invert_button.toggled.connect(_on_invert_toggled)
	_invert_button.focus_entered.connect(queue_redraw)
	_invert_button.focus_exited.connect(queue_redraw)
	_camera_page.add_child(_invert_button)
	_view_controls_button = _new_button(_camera_page, "ViewControlsButton", "View Controls")
	_view_controls_button.pressed.connect(_open_controls_guide)


func _create_graphics_page() -> void:
	_graphics_left_panel = _new_graphics_panel("GraphicsOverviewPanel")
	_graphics_page.add_child(_graphics_left_panel)
	_graphics_right_panel = _new_graphics_panel("GraphicsPresetsPanel")
	_graphics_page.add_child(_graphics_right_panel)
	_graphics_heading = _new_label(_graphics_page, "GraphicsHeading", "Graphics")
	_graphics_presets_heading = _new_label(_graphics_page, "QualityPresetsHeading", "Quality Presets")
	_quality_label = _new_label(_graphics_page, "QualityCurrentLabel", "")
	_sliders[&"quality"] = _new_slider(_graphics_page, &"quality", 0.0, 3.0, 1.0)
	for index in QUALITY_NAMES.size():
		var quality_button := _new_button(
			_graphics_page,
			"Quality%sButton" % QUALITY_NAMES[index],
			QUALITY_NAMES[index]
		)
		quality_button.pressed.connect(_on_quality_button_pressed.bind(index))
		_quality_buttons.append(quality_button)
	_graphics_back_button = _new_button(_graphics_page, "BackToSettingsButton", "‹  Back")
	_graphics_back_button.pressed.connect(set_section.bind(Section.AUDIO))
	_graphics_slider_overlay = SliderVisualOverlay.new()
	_graphics_slider_overlay.name = "GraphicsSliderVisualOverlay"
	_graphics_slider_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_graphics_slider_overlay.target_slider = _sliders[&"quality"] as HSlider
	_graphics_page.add_child(_graphics_slider_overlay)
	_update_quality_label()


func _new_graphics_panel(panel_name: String) -> Panel:
	var panel := Panel.new()
	panel.name = panel_name
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#fff0db")
	style.border_color = Color("#dfb99e")
	style.set_border_width_all(2)
	style.set_corner_radius_all(24)
	style.shadow_color = Color(0.32, 0.14, 0.19, 0.16)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 3)
	style.anti_aliasing = true
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _new_slider(parent: Control, key: StringName, minimum: float, maximum: float, step_size: float) -> HSlider:
	var slider := HSlider.new()
	slider.name = "%sSlider" % _pascal_case(key)
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
	_set_slider_thumb(slider)
	slider.value_changed.connect(_on_slider_value_changed.bind(key))
	slider.focus_entered.connect(queue_redraw)
	slider.focus_exited.connect(queue_redraw)
	parent.add_child(slider)
	return slider


func _new_label(parent: Control, label_name: String, label_text: String) -> Label:
	var label := Label.new()
	label.name = label_name
	label.text = label_text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _new_button(parent: Control, button_name: String, button_text: String) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = button_text
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for property in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color", &"font_focus_color"]:
		button.add_theme_color_override(property, INK)
	var normal_fill := Color("#f8ecdc") if _mobile else BUTTON_FILL
	var normal_border := LAVENDER_DARK if _mobile else BERRY_DARK
	var hover_fill := Color("#eee7f4") if _mobile else SOFT_PINK
	var hover_border := LAVENDER if _mobile else BERRY
	var pressed_fill := Color("#e1d7ed") if _mobile else Color("#f0b8aa")
	button.add_theme_stylebox_override("normal", _button_box(normal_fill, normal_border, 18))
	button.add_theme_stylebox_override("hover", _button_box(hover_fill, hover_border, 18))
	button.add_theme_stylebox_override("pressed", _button_box(pressed_fill, normal_border, 18))
	button.add_theme_stylebox_override("focus", _focus_box(18))
	button.focus_entered.connect(queue_redraw)
	button.focus_exited.connect(queue_redraw)
	parent.add_child(button)
	return button


func _create_audio_preview() -> void:
	_preview_player = AudioStreamPlayer.new()
	_preview_player.name = "SFXPreviewPlayer"
	_preview_player.stream = SFX_PREVIEW_STREAM
	_preview_player.volume_db = -4.0
	_preview_player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(_preview_player)
	_preview_timer = Timer.new()
	_preview_timer.name = "SFXPreviewDebounce"
	_preview_timer.one_shot = true
	_preview_timer.wait_time = 0.18
	_preview_timer.timeout.connect(_play_sfx_preview)
	add_child(_preview_timer)


func _layout_content() -> void:
	if not _configured or size.x <= 0.0 or size.y <= 0.0:
		return
	for page in [_audio_page, _camera_page, _graphics_page]:
		page.position = Vector2.ZERO
		page.size = size
	_graphics_slider_overlay.position = Vector2.ZERO
	_graphics_slider_overlay.size = size
	var width := size.x
	var height := size.y
	var label_size := 23 if _mobile else 27
	var heading_size := 38 if not _mobile else 25
	var button_size := 21 if not _mobile else 19
	var slider_height := 34.0 if _mobile else 42.0
	var thumb_size := 30 if _mobile else 28
	_slider_thumb_texture = _scaled_thumb(thumb_size)
	_graphics_slider_overlay.mobile_layout = _mobile
	_graphics_slider_overlay.thumb_texture = _slider_thumb_texture
	_graphics_slider_overlay.fill_color = _slider_fill
	_graphics_slider_overlay.rail_color = _slider_rail
	_graphics_slider_overlay.border_color = _slider_border
	_graphics_slider_overlay.focus_color = _focus_color
	for slider in _sliders.values():
		_set_slider_thumb(slider)

	if _mobile:
		_audio_heading.hide()
		_camera_heading.hide()
		_graphics_heading.hide()
		_graphics_presets_heading.hide()
		_graphics_left_panel.hide()
		_graphics_right_panel.hide()
		var label_x := width * 0.355
		var label_width := width * 0.205
		var slider_x := width * 0.58
		var slider_width := width * 0.313
		var audio_centers := [height * 0.21, height * 0.43, height * 0.65]
		var audio_keys: Array[StringName] = [&"master_volume", &"music_volume", &"sfx_volume"]
		for index in audio_keys.size():
			var key := audio_keys[index]
			_audio_labels[key].show()
			_set_rect(_audio_labels[key], label_x, audio_centers[index] - 22.0, label_width, 44.0)
			_set_font_size(_audio_labels[key], label_size)
			_set_rect(_sliders[key], slider_x, audio_centers[index] - slider_height * 0.5, slider_width, slider_height)
		_set_rect(_graphics_button, width * 0.80, height * 0.82, width * 0.17, height * 0.12)
		_graphics_button.hide()

		var sensitivity_center := height * 0.25
		_camera_labels[&"sensitivity"].show()
		_set_rect(_camera_labels[&"sensitivity"], label_x, sensitivity_center - 22.0, label_width, 44.0)
		_set_font_size(_camera_labels[&"sensitivity"], label_size)
		_set_rect(_sliders[&"sensitivity"], slider_x, sensitivity_center - slider_height * 0.5, slider_width, slider_height)
		var invert_center := height * 0.46
		_camera_labels[&"invert_y"].show()
		_set_rect(_camera_labels[&"invert_y"], label_x, invert_center - 22.0, label_width, 44.0)
		_set_font_size(_camera_labels[&"invert_y"], label_size)
		_set_rect(_invert_button, slider_x, invert_center - 22.0, slider_width, 44.0)
		_set_rect(_view_controls_button, slider_x, height * 0.55, slider_width, height * 0.20)
		_set_font_size(_view_controls_button, button_size)

		_set_rect(_quality_label, width * 0.35, height * 0.11, width * 0.61, height * 0.14)
		_quality_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_set_font_size(_quality_label, 18)
		var quality_slider_x := width * 0.41
		var quality_slider_width := width * 0.47
		_set_rect(_sliders[&"quality"], quality_slider_x, height * 0.31, quality_slider_width, slider_height)
		for index in _quality_buttons.size():
			var button_width := width * 0.12
			var stop_start_x := quality_slider_x + thumb_size * 0.5
			var stop_span := quality_slider_width - thumb_size
			var center_x := stop_start_x + stop_span * float(index) / float(_quality_buttons.size() - 1)
			_set_rect(_quality_buttons[index], center_x - button_width * 0.5, height * 0.48, button_width, height * 0.19)
			_set_font_size(_quality_buttons[index], 19)
		_set_rect(_graphics_back_button, width * 0.39, height * 0.72, width * 0.24, height * 0.16)
		_set_font_size(_graphics_back_button, button_size)
	else:
		_set_rect(_audio_heading, width * 0.04, height * 0.05, width * 0.43, height * 0.15)
		_audio_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_set_font_size(_audio_heading, heading_size)
		_set_rect(_camera_heading, width * 0.53, height * 0.05, width * 0.43, height * 0.15)
		_camera_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_set_font_size(_camera_heading, heading_size)
		_graphics_heading.show()
		_set_rect(_graphics_heading, width * 0.23, height * 0.04, width * 0.54, height * 0.14)
		_graphics_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_set_font_size(_graphics_heading, heading_size)
		_graphics_presets_heading.show()
		_graphics_presets_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_set_font_size(_graphics_presets_heading, 29)
		var panel_y := -4.0
		var panel_h := height * 0.85
		var panel_w := width * 0.48
		var left_panel_x := -14.0
		var right_panel_x := width * 0.52
		_set_rect(_graphics_left_panel, left_panel_x, panel_y, panel_w, panel_h)
		_set_rect(_graphics_right_panel, right_panel_x, panel_y, panel_w, panel_h)
		_set_rect(_graphics_heading, left_panel_x + 18.0, panel_y + 12.0, panel_w - 36.0, 56.0)
		_set_rect(_quality_label, left_panel_x + 22.0, panel_y + 103.0, panel_w - 44.0, 38.0)
		_set_font_size(_quality_label, 21)
		_set_rect(_sliders[&"quality"], left_panel_x + 25.0, panel_y + 177.0, panel_w - 50.0, slider_height)
		_set_rect(_graphics_presets_heading, right_panel_x + 18.0, panel_y + 12.0, panel_w - 36.0, 56.0)
		var preset_margin := 24.0
		var preset_gap_x := 16.0
		var preset_button_width := (panel_w - preset_margin * 2.0 - preset_gap_x) * 0.5
		var preset_button_height := 58.0
		for index in _quality_buttons.size():
			var column := index % 2
			var row := index / 2
			var button_x := right_panel_x + preset_margin + column * (preset_button_width + preset_gap_x)
			var button_y := panel_y + 132.0 + row * 82.0
			_set_rect(_quality_buttons[index], button_x, button_y, preset_button_width, preset_button_height)
			_set_font_size(_quality_buttons[index], 19)
		_set_rect(_graphics_back_button, left_panel_x + 25.0, panel_y + panel_h - 76.0, panel_w - 50.0, 52.0)
		_set_font_size(_graphics_back_button, 19)
		var label_x := 0.0
		var label_width := width * 0.18
		var slider_x := width * 0.205
		var slider_width := width * 0.25
		var audio_centers := [height * 0.35, height * 0.52, height * 0.69]
		var audio_keys: Array[StringName] = [&"master_volume", &"music_volume", &"sfx_volume"]
		for index in audio_keys.size():
			var key := audio_keys[index]
			_set_rect(_audio_labels[key], label_x, audio_centers[index] - 22.0, label_width, 44.0)
			_set_font_size(_audio_labels[key], label_size)
			_set_rect(_sliders[key], slider_x, audio_centers[index] - slider_height * 0.5, slider_width, slider_height)
		_set_rect(_graphics_button, width * 0.02, height * 0.77, width * 0.20, height * 0.095)
		_set_font_size(_graphics_button, 18)

		label_x = width * 0.525
		label_width = width * 0.16
		slider_x = width * 0.705
		slider_width = width * 0.24
		var sensitivity_center := height * 0.35
		_set_rect(_camera_labels[&"sensitivity"], label_x, sensitivity_center - 22.0, label_width, 44.0)
		_set_font_size(_camera_labels[&"sensitivity"], label_size)
		_set_rect(_sliders[&"sensitivity"], slider_x, sensitivity_center - slider_height * 0.5, slider_width, slider_height)
		var invert_center := height * 0.52
		_set_rect(_camera_labels[&"invert_y"], label_x, invert_center - 22.0, label_width, 44.0)
		_set_font_size(_camera_labels[&"invert_y"], label_size)
		_set_rect(_invert_button, width * 0.74, invert_center - height * 0.045, width * 0.14, height * 0.09)
		_set_rect(_view_controls_button, width * 0.58, height * 0.66, width * 0.35, height * 0.14)
		_set_font_size(_view_controls_button, button_size)

	_update_section_visibility()
	_update_quality_label()
	_layout_guide()
	_graphics_slider_overlay.queue_redraw()
	queue_redraw()


func _set_active_section(section: int) -> void:
	_active_section = clampi(section, Section.AUDIO, Section.GRAPHICS)
	_update_section_visibility()
	if _active_section == Section.GRAPHICS:
		_update_quality_label()


func _update_section_visibility() -> void:
	if not _configured:
		return
	if _mobile:
		_audio_page.visible = _active_section == Section.AUDIO
		_camera_page.visible = _active_section == Section.CAMERA
		_graphics_page.visible = _active_section == Section.GRAPHICS
		_graphics_button.hide()
		_graphics_back_button.hide()
		_graphics_slider_overlay.visible = _active_section == Section.GRAPHICS
		_graphics_left_panel.hide()
		_graphics_right_panel.hide()
	else:
		var show_graphics := _active_section == Section.GRAPHICS
		_audio_page.visible = not show_graphics
		_camera_page.visible = not show_graphics
		_graphics_page.visible = show_graphics
		_graphics_button.visible = not show_graphics
		_graphics_back_button.visible = show_graphics
		_graphics_slider_overlay.visible = show_graphics
		_graphics_left_panel.visible = show_graphics
		_graphics_right_panel.visible = show_graphics
		_graphics_heading.visible = show_graphics
		_graphics_presets_heading.visible = show_graphics
	queue_redraw()


func _apply_static_label_visibility() -> void:
	if not _configured:
		return
	_audio_heading.hide()
	_camera_heading.hide()
	for label in _audio_labels.values():
		(label as Control).visible = _mobile
	for label in _camera_labels.values():
		(label as Control).visible = _mobile


func _section_index(section: Variant) -> int:
	if section is int:
		return clampi(int(section), Section.AUDIO, Section.GRAPHICS)
	var section_name := String(section).to_lower()
	match section_name:
		"audio": return Section.AUDIO
		"camera": return Section.CAMERA
		"graphics": return Section.GRAPHICS
		_: return -1


func _set_rect(control: Control, x: float, y: float, width: float, height: float) -> void:
	control.position = Vector2(x, y)
	control.size = Vector2(width, height)


func _set_font_size(control: Control, font_size: int) -> void:
	control.add_theme_font_size_override("font_size", font_size)


func _set_slider_thumb(slider: HSlider) -> void:
	var diameter := 30 if _mobile else 28
	var texture := _transparent_slider_texture(diameter)
	for icon_name in ["grabber", "grabber_highlight", "grabber_disabled"]:
		slider.add_theme_icon_override(icon_name, texture)


func _transparent_slider_texture(diameter: int) -> Texture2D:
	if _transparent_slider_textures.has(diameter):
		return _transparent_slider_textures[diameter] as Texture2D
	var image := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var texture := ImageTexture.create_from_image(image)
	_transparent_slider_textures[diameter] = texture
	return texture


func _scaled_thumb(diameter: int) -> Texture2D:
	if _slider_thumb_textures.has(diameter):
		return _slider_thumb_textures[diameter] as Texture2D
	var image := SLIDER_THUMB.get_image()
	if image == null:
		return SLIDER_THUMB
	image = image.duplicate() as Image
	image.resize(diameter, diameter, Image.INTERPOLATE_LANCZOS)
	var texture := ImageTexture.create_from_image(image)
	_slider_thumb_textures[diameter] = texture
	return texture


func _draw() -> void:
	if not _configured:
		return
	for key in _sliders:
		var slider := _sliders[key] as HSlider
		if slider == null or not slider.is_visible_in_tree():
			continue
		if key == &"quality":
			continue
		_draw_slider(slider, false)
	if _invert_button != null and _invert_button.is_visible_in_tree():
		_draw_invert_toggle()


func _draw_slider(slider: HSlider, quality_slider: bool) -> void:
	var local_transform := get_global_transform_with_canvas().affine_inverse() * slider.get_global_transform_with_canvas()
	var control_rect := Rect2(local_transform.origin, local_transform.basis_xform(slider.size))
	var rail_height := 12.0 if _mobile else 14.0
	var thumb_size := 30.0 if _mobile else 28.0
	var rail_start_x := control_rect.position.x + thumb_size * 0.5
	var rail_width := maxf(0.0, control_rect.size.x - thumb_size)
	var rail_rect := Rect2(rail_start_x, control_rect.get_center().y - rail_height * 0.5, rail_width, rail_height)
	if slider.has_focus():
		draw_style_box(_round_style(Color(1.0, 1.0, 1.0, 0.0), _focus_color, 2, 18), rail_rect.grow(10.0))
	draw_style_box(_round_style(_slider_rail, _slider_border, 2, int(rail_height * 0.5)), rail_rect)
	var fraction := _value_fraction(slider)
	var fill_width := clampf(rail_rect.size.x * fraction, 0.0, rail_rect.size.x)
	if fill_width > 0.5:
		draw_style_box(_round_style(_slider_fill, Color.TRANSPARENT, 0, int(rail_height * 0.5)), Rect2(rail_rect.position, Vector2(fill_width, rail_rect.size.y)))
	if quality_slider:
		for index in QUALITY_NAMES.size():
			var marker_x := rail_rect.position.x + rail_rect.size.x * float(index) / float(QUALITY_NAMES.size() - 1)
			var marker_center := Vector2(marker_x, rail_rect.get_center().y)
			draw_circle(marker_center, rail_height * 0.30, CREAM)
			draw_arc(marker_center, rail_height * 0.30, 0.0, TAU, 24, _slider_border, 2.0, true)
	var thumb_center := Vector2(rail_rect.position.x + rail_rect.size.x * fraction, rail_rect.get_center().y)
	if _slider_thumb_texture != null:
		draw_texture_rect(_slider_thumb_texture, Rect2(thumb_center - Vector2.ONE * thumb_size * 0.5, Vector2.ONE * thumb_size), false)
	else:
		draw_circle(thumb_center, thumb_size * 0.5, CREAM)
		draw_arc(thumb_center, thumb_size * 0.5, 0.0, TAU, 32, BERRY_DARK, 2.0, true)


func _draw_invert_toggle() -> void:
	var local_transform := get_global_transform_with_canvas().affine_inverse() * _invert_button.get_global_transform_with_canvas()
	var button_rect := Rect2(local_transform.origin, local_transform.basis_xform(_invert_button.size))
	var inset := 5.0 if _mobile else 6.0
	var track_rect := button_rect.grow_individual(0.0, -inset, 0.0, -inset)
	var toggle_fill := Color("#d9d0e7") if _mobile else Color("#e8b5ad")
	var toggle_border := LAVENDER_DARK if _mobile else Color("#aa5369")
	draw_style_box(_round_style(toggle_fill, toggle_border, 2, int(track_rect.size.y * 0.5)), track_rect)
	var thumb_radius := minf(track_rect.size.y * 0.34, 16.0)
	var knob_x := track_rect.position.x + thumb_radius + 5.0 if not _invert_button.button_pressed else track_rect.end.x - thumb_radius - 5.0
	var knob_center := Vector2(knob_x, track_rect.get_center().y)
	if _slider_thumb_texture != null:
		draw_texture_rect(_slider_thumb_texture, Rect2(knob_center - Vector2.ONE * thumb_radius, Vector2.ONE * thumb_radius * 2.0), false)
	var state_text := "On" if _invert_button.button_pressed else "Off"
	var state_x := track_rect.position.x + track_rect.size.x * (0.60 if not _invert_button.button_pressed else 0.24)
	draw_string(JOURNAL_FONT, Vector2(state_x, track_rect.get_center().y + 7.0), state_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20 if _mobile else 23, INK)
	if _invert_button.has_focus():
		draw_style_box(_round_style(Color(1.0, 1.0, 1.0, 0.0), _focus_color, 2, int(track_rect.size.y * 0.5)), track_rect.grow(5.0))


func _on_slider_value_changed(value: float, key: StringName) -> void:
	_save_setting(key, value)
	queue_redraw()
	if key == &"quality":
		_graphics_slider_overlay.queue_redraw()
		_update_quality_label()
	elif key == &"sfx_volume" and _preview_timer != null:
		_preview_timer.start()


func _on_invert_toggled(enabled: bool) -> void:
	_save_setting(&"invert_y", enabled)
	queue_redraw()


func _on_quality_button_pressed(index: int) -> void:
	(_sliders[&"quality"] as HSlider).value = index
	(_sliders[&"quality"] as HSlider).grab_focus()
	_update_quality_label()


func _update_quality_label() -> void:
	if _quality_label == null:
		return
	var quality := clampi(int(_read_setting(&"quality")), 0, QUALITY_NAMES.size() - 1)
	_quality_label.text = "Current Quality: %s" % QUALITY_NAMES[quality]
	for index in _quality_buttons.size():
		var selected := index == quality
		var quality_style: StyleBoxFlat
		if _mobile:
			quality_style = _button_box(Color("#ded7ec"), LAVENDER_DARK, 16) if selected else _button_box(Color("#f8ecdc"), Color("#cbbcb0"), 16)
		else:
			quality_style = _button_box(Color("#f6d1c2"), BERRY_DARK, 16) if selected else _button_box(BUTTON_FILL, Color("#d9ab9e"), 16)
		_quality_buttons[index].add_theme_stylebox_override(
			"normal",
			quality_style
		)
		_quality_buttons[index].add_theme_stylebox_override("focus", _focus_box(16))


func _play_sfx_preview() -> void:
	if _preview_player.playing:
		_preview_player.stop()
	_preview_player.play()


func _open_controls_guide() -> void:
	if _guide == null:
		_create_controls_guide()
	_return_focus = get_viewport().gui_get_focus_owner()
	_guide.show()
	_update_hud_toggle_labels()
	_layout_guide()
	_guide_close_button.call_deferred("grab_focus")


func _create_controls_guide() -> void:
	_guide = Control.new()
	_guide.name = "ControlsGuide"
	_guide.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_guide.z_index = 1000
	_guide.mouse_filter = Control.MOUSE_FILTER_STOP
	_guide.hide()
	var guide_host := _modal_host if is_instance_valid(_modal_host) else self
	guide_host.add_child(_guide)
	_guide.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scrim := ColorRect.new()
	scrim.name = "GuideScrim"
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.20, 0.07, 0.16, 0.76)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_guide.add_child(scrim)
	_guide_panel = Panel.new()
	_guide_panel.name = "GuidePanel"
	_guide_panel.add_theme_stylebox_override("panel", _panel_box())
	_guide.add_child(_guide_panel)
	_guide_title = _new_label(_guide_panel, "GuideTitle", "View Controls")
	_guide_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_guide_rows = VBoxContainer.new()
	_guide_rows.name = "ControlRows"
	_guide_rows.add_theme_constant_override("separation", 2)
	_guide_panel.add_child(_guide_rows)
	if _mobile:
		_add_guide_row("Move", "Drag the left stick")
		_add_guide_row("Look", "Swipe on the right side")
		_add_guide_row("Jump", "Tap Jump")
		_add_guide_row("Slide / Roll", "Tap Slide")
		_add_guide_row("Pick Up", "Tap when it appears")
		_add_guide_row("Pause", "Tap the gear")
	else:
		_add_guide_row("Move", "WASD / Arrow Keys  ·  Left Stick")
		_add_guide_row("Look", "Mouse  ·  Right Stick")
		_add_guide_row("Jump", "Space  ·  Gamepad South")
		_add_guide_row("Slide / Roll", "C or Left Ctrl  ·  Gamepad East")
		_add_guide_row("Pick Up", "E  ·  Gamepad West")
		_add_guide_row("Pause", "Escape  ·  Gamepad Start")
	_touch_toggle = _new_button(_guide_panel, "TouchControlsToggle", "Touch Controls  ·  Off")
	_touch_toggle.pressed.connect(_on_touch_toggle_pressed)
	if _debug_menu_enabled():
		_inspector_toggle = _new_button(_guide_panel, "StateInspectorToggle", "State Inspector  ·  Off")
		_inspector_toggle.pressed.connect(_on_inspector_toggle_pressed)
	_guide_close_button = _new_button(_guide_panel, "CloseControlsGuideButton", "Back to Options")
	_guide_close_button.pressed.connect(close_guide)
	_layout_guide()


func _layout_guide() -> void:
	if _guide == null or _guide_panel == null:
		return
	var guide_size := _guide.size
	if guide_size.x <= 0.0 or guide_size.y <= 0.0:
		guide_size = get_viewport_rect().size
	var margin_x := guide_size.x * (0.035 if _mobile else 0.08)
	var margin_y := guide_size.y * (0.035 if _mobile else 0.07)
	_guide_panel.position = Vector2(margin_x, margin_y)
	_guide_panel.size = guide_size - Vector2(margin_x * 2.0, margin_y * 2.0)
	var panel_width := _guide_panel.size.x
	var panel_height := _guide_panel.size.y
	_guide_title.position = Vector2(panel_width * 0.04, panel_height * 0.03)
	_guide_title.size = Vector2(panel_width * 0.92, panel_height * 0.13)
	_guide_title.add_theme_font_size_override("font_size", 30 if _mobile else 38)
	_guide_rows.position = Vector2(panel_width * 0.08, panel_height * 0.18)
	_guide_rows.size = Vector2(panel_width * 0.84, panel_height * 0.54)
	var button_height := maxf(48.0, panel_height * 0.13)
	var button_gap := panel_width * 0.02
	var button_margin := 24.0 if _mobile else panel_width * 0.035
	var guide_buttons: Array[Button] = [_touch_toggle]
	if is_instance_valid(_inspector_toggle):
		guide_buttons.append(_inspector_toggle)
	guide_buttons.append(_guide_close_button)
	var button_width := (panel_width - button_margin * 2.0 - button_gap * float(guide_buttons.size() - 1)) / float(guide_buttons.size())
	var button_y := panel_height * 0.75
	var buttons_width := button_width * guide_buttons.size() + button_gap * (guide_buttons.size() - 1)
	var button_start_x := (panel_width - buttons_width) * 0.5
	for index in guide_buttons.size():
		var button := guide_buttons[index]
		button.position = Vector2(button_start_x + float(index) * (button_width + button_gap), button_y)
		button.size = Vector2(button_width, button_height)
		var previous_button := guide_buttons[(index - 1 + guide_buttons.size()) % guide_buttons.size()]
		var next_button := guide_buttons[(index + 1) % guide_buttons.size()]
		button.focus_neighbor_left = button.get_path_to(previous_button)
		button.focus_neighbor_right = button.get_path_to(next_button)
		button.focus_neighbor_top = button.get_path_to(button)
		button.focus_neighbor_bottom = button.get_path_to(button)
		button.focus_previous = button.get_path_to(previous_button)
		button.focus_next = button.get_path_to(next_button)
		_set_font_size(button, 24 if _mobile else 28)
	var row_font_size := clampi(roundi(panel_width / 39.0), 18 if _mobile else 22, 30)
	_guide_rows.add_theme_constant_override("separation", 4 if _mobile else 7)
	for child in _guide_rows.get_children():
		if child is HBoxContainer:
			child.custom_minimum_size.y = panel_height * (0.083 if _mobile else 0.078)
			var action_label := child.get_child(0) as Label
			var binding_label := child.get_child(1) as Label
			action_label.custom_minimum_size.x = panel_width * 0.24
			action_label.add_theme_font_size_override("font_size", row_font_size)
			binding_label.add_theme_font_size_override("font_size", row_font_size)


func _add_guide_row(action: String, binding: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var action_label := Label.new()
	action_label.text = action
	action_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	action_label.add_theme_color_override("font_color", INK)
	row.add_child(action_label)
	var binding_label := Label.new()
	binding_label.text = binding
	binding_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	binding_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	binding_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	binding_label.add_theme_color_override("font_color", Color("#78415c"))
	row.add_child(binding_label)
	_guide_rows.add_child(row)


func _on_touch_toggle_pressed() -> void:
	_touch_enabled = not _touch_enabled
	_update_hud_toggle_labels()
	toggle_touch_requested.emit()


func _on_inspector_toggle_pressed() -> void:
	_inspector_enabled = not _inspector_enabled
	_update_hud_toggle_labels()
	toggle_inspector_requested.emit()


func _update_hud_toggle_labels() -> void:
	if _touch_toggle != null:
		_touch_toggle.text = "Touch Controls  ·  %s" % ("On" if _touch_enabled else "Off")
	if _inspector_toggle != null:
		_inspector_toggle.text = "State Inspector  ·  %s" % ("On" if _inspector_enabled else "Off")


func _debug_menu_enabled() -> bool:
	return OS.get_cmdline_user_args().has(DEBUG_MENU_ARG)


func _on_widget_focus_changed() -> void:
	queue_redraw()


func _read_setting(key: StringName) -> Variant:
	if _settings == null:
		return false if key == &"invert_y" else 1.0
	return _settings.get(String(key))


func _save_setting(key: StringName, value: Variant) -> void:
	if _settings != null and _settings.has_method("set_setting"):
		_settings.call("set_setting", key, value)


func _value_fraction(slider: HSlider) -> float:
	if is_equal_approx(slider.max_value, slider.min_value):
		return 0.0
	return clampf(inverse_lerp(slider.min_value, slider.max_value, slider.value), 0.0, 1.0)


func _round_style(fill: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	return style


func _button_box(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	return _round_style(fill, border, 2, radius)


func _focus_box(radius: int) -> StyleBoxFlat:
	return _round_style(Color(1.0, 1.0, 1.0, 0.0), BERRY, 3, radius)


func _panel_box() -> StyleBoxFlat:
	var panel := _round_style(Color("#fff2df"), Color("#bb5276"), 3, 24)
	panel.shadow_color = Color(0.22, 0.08, 0.17, 0.30)
	panel.shadow_size = 8
	return panel


func _pascal_case(key: StringName) -> String:
	var parts := String(key).split("_")
	var result := ""
	for part in parts:
		result += part.capitalize()
	return result
