extends Control

signal back_requested

const DESIGN_SIZE := Vector2(1686.0, 772.0)
const BACKGROUND_PATH := "res://scenes/menu/art/mobile_options/background.png"
const SELECTED_TAB_OVERLAY_PATH := "res://scenes/menu/art/mobile_options/tab_selected_overlay.png"
const AUDIO_INACTIVE_OVERLAY_PATH := "res://scenes/menu/art/mobile_options/tab_audio_inactive.png"
const BERRY_JOURNAL_FONT: Font = preload("res://scenes/menu/berry_journal_font.tres")
const VISUALS_SCRIPT := preload("res://scenes/menu/mobile_options_visuals.gd")
const HUD_CIRCLE_SCRIPT := preload("res://scripts/ui/touch_control_circle.gd")
const SFX_PREVIEW_STREAM := preload("res://assets/audio/SFX_Jump.wav")

enum Section { AUDIO, CAMERA, GRAPHICS }

const QUALITY_NAMES := ["Low", "Medium", "High", "Ultra"]
const TAB_RECTS := [
	Rect2(159.0, 189.0, 350.0, 129.0),
	Rect2(159.0, 335.0, 346.0, 115.0),
	Rect2(159.0, 473.0, 346.0, 117.0),
]
const SLIDER_BOUNDS := {
	&"master_volume": Rect2(977.0, 180.0, 528.0, 108.0),
	&"music_volume": Rect2(977.0, 299.0, 528.0, 108.0),
	&"sfx_volume": Rect2(977.0, 415.0, 528.0, 108.0),
	&"sensitivity": Rect2(977.0, 206.0, 528.0, 108.0),
	&"quality": Rect2(699.0, 261.0, 736.0, 108.0),
}

const INK := Color("#4f1939")
const BERRY := Color("#cc2857")
const BERRY_DARK := Color("#98244d")
const BUTTON_FILL := Color("#ffe4cf")
const SOFT_PINK := Color("#f7d4c5")
const LABEL_BOUNDS := {
	&"master_volume": Rect2(600.0, 208.0, 340.0, 52.0),
	&"music_volume": Rect2(600.0, 327.0, 340.0, 52.0),
	&"sfx_volume": Rect2(600.0, 443.0, 340.0, 52.0),
}

@onready var _design_canvas: Control = $DesignCanvas
@onready var _page_background: TextureRect = $DesignCanvas/Background

var _settings: Node
var _visuals: Control
var _selected_tab_overlay: TextureRect
var _audio_inactive_overlay: TextureRect
var _active_section: int = Section.AUDIO
var _pages: Array[Control] = []
var _sliders: Dictionary = {}
var _invert_button: Button
var _view_controls_button: Button
var _back_button: Button
var _back_child_original_index: int = -1
var _quality_buttons: Array[Button] = []
var _quality_current_label: Label
var _controls_guide: Control
var _sfx_preview_player: AudioStreamPlayer
var _sfx_preview_timer: Timer
var _pending_preview_bus: StringName = &"SFX"
var _transparent_texture: ImageTexture
var _window: Window
var _previous_quit_on_go_back: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings = get_node_or_null("/root/GameSettings")
	if _settings == null:
		push_error("Mobile Options requires the GameSettings autoload.")
	_create_serif_font()
	_window = get_window()
	_previous_quit_on_go_back = get_tree().quit_on_go_back
	get_tree().quit_on_go_back = false
	if _window != null and not _window.go_back_requested.is_connected(_on_platform_back):
		_window.go_back_requested.connect(_on_platform_back)
	if not get_viewport().size_changed.is_connected(_fit_to_safe_area):
		get_viewport().size_changed.connect(_fit_to_safe_area)
	_create_transparent_texture()
	_create_visual_layer()
	_load_backgrounds()
	_create_tabs()
	_create_pages()
	_create_back_button()
	_create_sfx_preview()
	_create_controls_guide()
	_update_section(Section.AUDIO, false)
	_fit_to_safe_area()
	call_deferred("_focus_initial_control")


func _exit_tree() -> void:
	if _window != null and _window.go_back_requested.is_connected(_on_platform_back):
		_window.go_back_requested.disconnect(_on_platform_back)
	if get_tree() != null:
		get_tree().quit_on_go_back = _previous_quit_on_go_back


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		_handle_back()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if _sfx_preview_timer != null:
			_sfx_preview_timer.stop()
		if _sfx_preview_player != null and _sfx_preview_player.playing:
			_sfx_preview_player.stop()


func _load_backgrounds() -> void:
	var page_texture: Texture2D
	if ResourceLoader.exists(BACKGROUND_PATH):
		page_texture = load(BACKGROUND_PATH) as Texture2D
	if page_texture == null:
		push_warning("Mobile Options background is missing: %s" % BACKGROUND_PATH)
	else:
		_page_background.texture = page_texture
	var overlay_texture: Texture2D
	if ResourceLoader.exists(SELECTED_TAB_OVERLAY_PATH):
		overlay_texture = load(SELECTED_TAB_OVERLAY_PATH) as Texture2D
	if overlay_texture != null:
		_selected_tab_overlay.texture = overlay_texture
	var inactive_texture: Texture2D
	if ResourceLoader.exists(AUDIO_INACTIVE_OVERLAY_PATH):
		inactive_texture = load(AUDIO_INACTIVE_OVERLAY_PATH) as Texture2D
	if inactive_texture != null:
		_audio_inactive_overlay.texture = inactive_texture
	_visuals.set("has_selected_tab_overlay", overlay_texture != null)


func _fit_to_safe_area() -> void:
	if _design_canvas == null:
		return
	var visible_bounds := get_viewport().get_visible_rect()
	var fit_bounds := _safe_view_bounds(visible_bounds)
	var fit_scale := minf(fit_bounds.size.x / DESIGN_SIZE.x, fit_bounds.size.y / DESIGN_SIZE.y)
	_design_canvas.scale = Vector2.ONE * fit_scale
	_design_canvas.position = fit_bounds.position + (fit_bounds.size - DESIGN_SIZE * fit_scale) * 0.5


func _safe_view_bounds(viewport_bounds: Rect2) -> Rect2:
	if not OS.has_feature("mobile"):
		return viewport_bounds
	var safe_screen_rect := Rect2(DisplayServer.get_display_safe_area())
	if not safe_screen_rect.has_area():
		return viewport_bounds
	var screen_to_viewport := get_viewport().get_screen_transform().affine_inverse()
	var window_origin := Vector2(DisplayServer.window_get_position())
	var safe_view_rect := Rect2(
		screen_to_viewport * (safe_screen_rect.position - window_origin),
		screen_to_viewport.basis_xform(safe_screen_rect.size)
	)
	var clipped := viewport_bounds.intersection(safe_view_rect)
	return clipped if clipped.has_area() else viewport_bounds


func _create_transparent_texture() -> void:
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	_transparent_texture = ImageTexture.create_from_image(image)


func _create_serif_font() -> void:
	var mobile_theme := Theme.new()
	mobile_theme.default_font = BERRY_JOURNAL_FONT
	_design_canvas.theme = mobile_theme


func _create_visual_layer() -> void:
	_audio_inactive_overlay = TextureRect.new()
	_audio_inactive_overlay.name = "AudioInactiveOverlay"
	_audio_inactive_overlay.position = Vector2(154.0, 184.0)
	_audio_inactive_overlay.size = Vector2(360.0, 140.0)
	_audio_inactive_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_audio_inactive_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	_audio_inactive_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_audio_inactive_overlay.visible = false
	_design_canvas.add_child(_audio_inactive_overlay)
	_selected_tab_overlay = TextureRect.new()
	_selected_tab_overlay.name = "SelectedTabOverlay"
	_selected_tab_overlay.position = TAB_RECTS[Section.AUDIO].position
	_selected_tab_overlay.size = TAB_RECTS[Section.AUDIO].size
	_selected_tab_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_selected_tab_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	_selected_tab_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_design_canvas.add_child(_selected_tab_overlay)
	_visuals = VISUALS_SCRIPT.new() as Control
	_visuals.name = "WidgetVisuals"
	_visuals.position = Vector2.ZERO
	_visuals.size = DESIGN_SIZE
	_visuals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visuals.set("serif_font", BERRY_JOURNAL_FONT)
	_design_canvas.add_child(_visuals)


func _create_tabs() -> void:
	var tab_names := ["AudioTabButton", "CameraTabButton", "GraphicsTabButton"]
	for index in TAB_RECTS.size():
		var tab := Button.new()
		tab.name = tab_names[index]
		tab.position = TAB_RECTS[index].position
		tab.size = TAB_RECTS[index].size
		tab.flat = true
		tab.text = ""
		tab.focus_mode = Control.FOCUS_ALL
		tab.mouse_filter = Control.MOUSE_FILTER_STOP
		tab.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_apply_invisible_button_theme(tab)
		tab.pressed.connect(_on_tab_pressed.bind(index))
		tab.focus_entered.connect(_on_widget_focus_changed)
		tab.focus_exited.connect(_on_widget_focus_changed)
		_design_canvas.add_child(tab)


func _create_pages() -> void:
	var audio_page := _new_page("AudioPage")
	var camera_page := _new_page("CameraPage")
	var graphics_page := _new_page("GraphicsPage")
	_pages = [audio_page, camera_page, graphics_page]
	_create_audio_page(audio_page)
	_create_camera_page(camera_page)
	_create_graphics_page(graphics_page)
	_visuals.set("sliders", _sliders)
	_visuals.set("invert_button", _invert_button)


func _new_page(page_name: String) -> Control:
	var page := Control.new()
	page.name = page_name
	page.position = Vector2.ZERO
	page.size = DESIGN_SIZE
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_design_canvas.add_child(page)
	return page


func _create_audio_page(page: Control) -> void:
	_new_label(page, "MasterVolumeLabel", "Master Volume", LABEL_BOUNDS[&"master_volume"], 42)
	_new_label(page, "MusicVolumeLabel", "Music", LABEL_BOUNDS[&"music_volume"], 42)
	_new_label(page, "SFXVolumeLabel", "Sound Effects", LABEL_BOUNDS[&"sfx_volume"], 42)
	_add_slider(page, &"master_volume", 0.0, 1.0, 0.01)
	_add_slider(page, &"music_volume", 0.0, 1.0, 0.01)
	_add_slider(page, &"sfx_volume", 0.0, 1.0, 0.01)


func _create_camera_page(page: Control) -> void:
	_new_label(page, "SensitivityLabel", "Sensitivity", Rect2(600.0, 234.0, 340.0, 52.0), 46)
	_add_slider(page, &"sensitivity", 0.5, 2.0, 0.01)
	_new_label(page, "InvertYLabel", "Invert Y", Rect2(600.0, 346.0, 340.0, 52.0), 46)
	_invert_button = Button.new()
	_invert_button.name = "InvertYToggle"
	_invert_button.position = Vector2(977.0, 318.0)
	_invert_button.size = Vector2(528.0, 108.0)
	_invert_button.toggle_mode = true
	_invert_button.button_pressed = bool(_read_setting(&"invert_y"))
	_invert_button.focus_mode = Control.FOCUS_ALL
	_invert_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_invert_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_apply_invisible_button_theme(_invert_button)
	_invert_button.toggled.connect(_on_invert_toggled)
	_invert_button.focus_entered.connect(_on_widget_focus_changed)
	_invert_button.focus_exited.connect(_on_widget_focus_changed)
	page.add_child(_invert_button)
	_visuals.set("invert_button", _invert_button)
	_visuals.set("invert_enabled", _invert_button.button_pressed)
	_view_controls_button = _new_styled_button(
		page,
		"ViewControlsButton",
		"View Controls",
		Rect2(977.0, 420.0, 528.0, 108.0),
		44
	)
	_view_controls_button.pressed.connect(_open_controls_guide)


func _create_graphics_page(page: Control) -> void:
	_quality_current_label = _new_label(
		page, "QualityCurrentLabel", "", Rect2(590.0, 190.0, 920.0, 54.0), 36, HORIZONTAL_ALIGNMENT_CENTER
	)
	_add_slider(page, &"quality", 0.0, 3.0, 1.0)
	var stop_centers: Array[float] = [699.0, 944.0, 1189.0, 1435.0]
	for index in QUALITY_NAMES.size():
		var quality_button := Button.new()
		quality_button.name = "Quality%sButton" % QUALITY_NAMES[index]
		quality_button.position = Vector2(stop_centers[index] - 75.0, 366.0)
		quality_button.size = Vector2(150.0, 108.0)
		quality_button.text = QUALITY_NAMES[index]
		quality_button.focus_mode = Control.FOCUS_ALL
		quality_button.mouse_filter = Control.MOUSE_FILTER_STOP
		quality_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		quality_button.add_theme_font_size_override("font_size", 34)
		quality_button.add_theme_color_override("font_color", INK)
		quality_button.add_theme_color_override("font_hover_color", INK)
		quality_button.add_theme_color_override("font_pressed_color", INK)
		quality_button.add_theme_color_override("font_focus_color", INK)
		quality_button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		quality_button.add_theme_stylebox_override("hover", _button_box(SOFT_PINK, Color("#e39ab0"), 22))
		quality_button.add_theme_stylebox_override("pressed", _button_box(Color("#f3b9b0"), BERRY, 22))
		quality_button.add_theme_stylebox_override("focus", _focus_box(22))
		quality_button.pressed.connect(_on_quality_stop_pressed.bind(index))
		quality_button.focus_entered.connect(_on_widget_focus_changed)
		quality_button.focus_exited.connect(_on_widget_focus_changed)
		page.add_child(quality_button)
		_quality_buttons.append(quality_button)
	_update_quality_label()


func _add_slider(parent: Control, key: StringName, minimum: float, maximum: float, step_size: float) -> void:
	var slider := HSlider.new()
	slider.name = _slider_node_name(key)
	slider.position = SLIDER_BOUNDS[key].position
	slider.size = SLIDER_BOUNDS[key].size
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
	parent.add_child(slider)
	_sliders[key] = slider


func _slider_node_name(key: StringName) -> String:
	match key:
		&"master_volume": return "MasterVolumeSlider"
		&"music_volume": return "MusicVolumeSlider"
		&"sfx_volume": return "SFXVolumeSlider"
		&"sensitivity": return "SensitivitySlider"
		_: return "QualitySlider"


func _new_label(
	parent: Control,
	label_name: String,
	text: String,
	label_rect: Rect2,
	font_size: int,
	h_align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
) -> Label:
	var label := Label.new()
	label.name = label_name
	label.position = label_rect.position
	label.size = label_rect.size
	label.text = text
	label.horizontal_alignment = h_align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _new_styled_button(parent: Control, button_name: String, text: String, button_rect: Rect2, font_size: int) -> Button:
	var button := Button.new()
	button.name = button_name
	button.position = button_rect.position
	button.size = button_rect.size
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", font_size)
	for property in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color", &"font_focus_color"]:
		button.add_theme_color_override(property, INK)
	button.add_theme_stylebox_override("normal", _button_box(BUTTON_FILL, BERRY_DARK, 30))
	button.add_theme_stylebox_override("hover", _button_box(SOFT_PINK, BERRY, 30))
	button.add_theme_stylebox_override("pressed", _button_box(Color("#f0b8aa"), BERRY_DARK, 30))
	button.add_theme_stylebox_override("focus", _focus_box(30))
	button.focus_entered.connect(_on_widget_focus_changed)
	button.focus_exited.connect(_on_widget_focus_changed)
	parent.add_child(button)
	return button


func _create_back_button() -> void:
	_back_button = Button.new()
	_back_button.name = "BackButton"
	_back_button.position = Vector2(1297.0, 597.0)
	_back_button.size = Vector2(300.0, 112.0)
	_back_button.text = ""
	_back_button.flat = true
	_back_button.focus_mode = Control.FOCUS_ALL
	_back_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_back_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_apply_invisible_button_theme(_back_button)
	_back_button.pressed.connect(_handle_back)
	_design_canvas.add_child(_back_button)
	_back_child_original_index = _back_button.get_index()


func _create_sfx_preview() -> void:
	_sfx_preview_player = AudioStreamPlayer.new()
	_sfx_preview_player.name = "AudioPreviewPlayer"
	_sfx_preview_player.stream = SFX_PREVIEW_STREAM
	_sfx_preview_player.volume_db = -4.0
	_sfx_preview_player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_design_canvas.add_child(_sfx_preview_player)
	_sfx_preview_timer = Timer.new()
	_sfx_preview_timer.name = "AudioPreviewDebounce"
	_sfx_preview_timer.one_shot = true
	_sfx_preview_timer.wait_time = 0.18
	_sfx_preview_timer.timeout.connect(_play_audio_preview)
	_design_canvas.add_child(_sfx_preview_timer)


func _create_controls_guide() -> void:
	_controls_guide = Control.new()
	_controls_guide.name = "ControlsGuide"
	_controls_guide.position = Vector2.ZERO
	_controls_guide.size = DESIGN_SIZE
	_controls_guide.visible = false
	_controls_guide.z_index = 100
	_controls_guide.mouse_filter = Control.MOUSE_FILTER_STOP
	_design_canvas.add_child(_controls_guide)

	var scrim := ColorRect.new()
	scrim.name = "GuideScrim"
	scrim.position = Vector2.ZERO
	scrim.size = DESIGN_SIZE
	scrim.color = Color(0.20, 0.07, 0.16, 0.74)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_controls_guide.add_child(scrim)

	var panel := Panel.new()
	panel.name = "GuidePanel"
	panel.position = Vector2(174.0, 86.0)
	panel.size = Vector2(1338.0, 600.0)
	panel.add_theme_stylebox_override("panel", _panel_box())
	_controls_guide.add_child(panel)

	var title := _new_label(panel, "GuideTitle", "Touch Controls", Rect2(48.0, 22.0, 1242.0, 58.0), 48, HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_color_override("font_color", INK)
	var hud_preview := Panel.new()
	hud_preview.name = "HUDPreview"
	hud_preview.position = Vector2(50.0, 112.0)
	hud_preview.size = Vector2(400.0, 342.0)
	hud_preview.add_theme_stylebox_override("panel", _button_box(Color("#f7e8dc"), Color("#e9c7b6"), 24))
	panel.add_child(hud_preview)
	_add_hud_preview_circle(hud_preview, "PreviewMoveStick", "stick", Color("#91c8b4"), Vector2(47.0, 193.0), 116.0)
	_add_hud_preview_circle(hud_preview, "PreviewJumpButton", "jump", Color("#91c8b4"), Vector2(268.0, 76.0), 68.0)
	_add_hud_preview_circle(hud_preview, "PreviewSlideButton", "slide", Color("#c3b1d9"), Vector2(218.0, 195.0), 68.0)
	_add_hud_preview_circle(hud_preview, "PreviewPickupButton", "pickup", Color("#e8b69d"), Vector2(309.0, 195.0), 68.0)
	_new_label(hud_preview, "MovePreviewLabel", "MOVE", Rect2(41.0, 302.0, 130.0, 30.0), 24, HORIZONTAL_ALIGNMENT_CENTER)
	_new_label(hud_preview, "ActionPreviewLabel", "ACTION BUTTONS", Rect2(196.0, 302.0, 190.0, 30.0), 22, HORIZONTAL_ALIGNMENT_CENTER)

	var instructions := VBoxContainer.new()
	instructions.name = "GestureInstructions"
	instructions.position = Vector2(500.0, 115.0)
	instructions.size = Vector2(780.0, 352.0)
	instructions.add_theme_constant_override("separation", 8)
	panel.add_child(instructions)
	_add_guide_row(instructions, "Move", "Drag the left stick")
	_add_guide_row(instructions, "Look", "Swipe on the right side")
	_add_guide_row(instructions, "Jump", "Tap Jump")
	_add_guide_row(instructions, "Slide / Roll", "Tap Slide")
	_add_guide_row(instructions, "Pick Up", "Tap Pick Up when it appears")
	_add_guide_row(instructions, "Pause", "Tap the gear in the top corner")



func _add_hud_preview_circle(parent: Control, node_name: String, symbol: String, accent: Color, position: Vector2, diameter: float) -> void:
	var circle := HUD_CIRCLE_SCRIPT.new() as Control
	circle.name = node_name
	circle.position = position
	circle.size = Vector2.ONE * diameter
	circle.set("symbol", symbol)
	circle.set("accent", accent)
	circle.set("held", true)
	circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(circle)


func _add_guide_row(container: VBoxContainer, action: String, gesture: String) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(760.0, 48.0)
	row.add_theme_constant_override("separation", 20)
	var action_label := Label.new()
	action_label.text = action
	action_label.custom_minimum_size = Vector2(210.0, 48.0)
	action_label.add_theme_font_size_override("font_size", 31)
	action_label.add_theme_color_override("font_color", INK)
	row.add_child(action_label)
	var gesture_label := Label.new()
	gesture_label.text = gesture
	gesture_label.add_theme_font_size_override("font_size", 30)
	gesture_label.add_theme_color_override("font_color", Color("#78415c"))
	row.add_child(gesture_label)
	container.add_child(row)


func _panel_box() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#fff2df")
	style.border_color = Color("#bb5276")
	style.set_border_width_all(4)
	style.set_corner_radius_all(34)
	style.shadow_color = Color(0.22, 0.08, 0.17, 0.30)
	style.shadow_size = 12
	return style


func _button_box(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	return style


func _focus_box(radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 0.0)
	style.border_color = BERRY
	style.set_border_width_all(3)
	style.set_corner_radius_all(radius)
	return style


func _apply_invisible_button_theme(button: Button) -> void:
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("focus", _focus_box(30))
	for property in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color", &"font_focus_color"]:
		button.add_theme_color_override(property, Color.TRANSPARENT)


func _on_tab_pressed(section: int) -> void:
	_update_section(section, true)


func _update_section(section: int, focus_content: bool) -> void:
	_active_section = section
	for index in _pages.size():
		_pages[index].visible = index == section
	_selected_tab_overlay.visible = section != Section.AUDIO
	_audio_inactive_overlay.visible = section != Section.AUDIO
	if section != Section.AUDIO:
		_selected_tab_overlay.position = TAB_RECTS[section].position
		_selected_tab_overlay.size = TAB_RECTS[section].size
	_visuals.set("selected_section", section)
	_visuals.queue_redraw()
	if section == Section.GRAPHICS:
		_update_quality_label()
	if focus_content:
		var target: Control
		match section:
			Section.AUDIO: target = _sliders[&"master_volume"]
			Section.CAMERA: target = _sliders[&"sensitivity"]
			Section.GRAPHICS: target = _sliders[&"quality"]
		target.call_deferred("grab_focus")


func _on_slider_value_changed(value: float, key: StringName) -> void:
	_save_setting(key, value)
	_visuals.queue_redraw()
	if key == &"quality":
		_update_quality_label()
	elif key == &"sfx_volume":
		_pending_preview_bus = &"SFX"
		_sfx_preview_timer.start()


func _on_invert_toggled(enabled: bool) -> void:
	_visuals.set("invert_enabled", enabled)
	_visuals.queue_redraw()
	_save_setting(&"invert_y", enabled)


func _on_quality_stop_pressed(index: int) -> void:
	(_sliders[&"quality"] as HSlider).value = index
	_update_quality_label()
	_visuals.queue_redraw()


func _update_quality_label() -> void:
	if _quality_current_label == null:
		return
	var quality_value := clampi(int(_read_setting(&"quality")), 0, QUALITY_NAMES.size() - 1)
	_quality_current_label.text = "Current Quality: %s" % _quality_name(quality_value)
	for index in _quality_buttons.size():
		var selected := index == quality_value
		_quality_buttons[index].add_theme_stylebox_override(
			"normal",
			_button_box(Color("#f6d1c2"), BERRY_DARK, 24) if selected else StyleBoxEmpty.new()
		)
		_quality_buttons[index].add_theme_stylebox_override(
			"focus",
			_focus_box(24)
		)


func _quality_name(index: int) -> String:
	if _settings != null and _settings.has_method("get_quality_label"):
		return String(_settings.call("get_quality_label"))
	return QUALITY_NAMES[index]


func _on_widget_focus_changed() -> void:
	if _visuals != null:
		_visuals.queue_redraw()


func _open_controls_guide() -> void:
	_controls_guide.visible = true
	_design_canvas.move_child(_back_button, _design_canvas.get_child_count() - 1)
	_back_button.flat = false
	_back_button.text = "Back to Camera"
	_back_button.z_index = 101
	_back_button.add_theme_stylebox_override("normal", _button_box(BUTTON_FILL, BERRY_DARK, 28))
	_back_button.add_theme_stylebox_override("hover", _button_box(Color("#ffe5d2"), BERRY, 28))
	_back_button.add_theme_stylebox_override("pressed", _button_box(Color("#f3c3b6"), BERRY_DARK, 28))
	_back_button.add_theme_stylebox_override("focus", _button_box(BUTTON_FILL, BERRY, 28))
	for property in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color", &"font_focus_color"]:
		_back_button.add_theme_color_override(property, INK)
	_back_button.add_theme_font_size_override("font_size", 32)
	var self_path := NodePath(".")
	_back_button.focus_next = self_path
	_back_button.focus_previous = self_path
	_back_button.focus_neighbor_left = self_path
	_back_button.focus_neighbor_right = self_path
	_back_button.focus_neighbor_top = self_path
	_back_button.focus_neighbor_bottom = self_path
	_back_button.call_deferred("grab_focus")


func _close_controls_guide() -> void:
	_controls_guide.visible = false
	_back_button.z_index = 0
	_back_button.flat = true
	_back_button.text = ""
	_apply_invisible_button_theme(_back_button)
	_back_button.focus_next = NodePath("")
	_back_button.focus_previous = NodePath("")
	_back_button.focus_neighbor_left = NodePath("")
	_back_button.focus_neighbor_right = NodePath("")
	_back_button.focus_neighbor_top = NodePath("")
	_back_button.focus_neighbor_bottom = NodePath("")
	_design_canvas.move_child(_back_button, _back_child_original_index)
	_update_section(Section.CAMERA, false)
	_view_controls_button.call_deferred("grab_focus")


func _handle_back() -> void:
	if _controls_guide != null and _controls_guide.visible:
		_close_controls_guide()
	else:
		_request_back()


func _on_platform_back() -> void:
	_handle_back()


func _request_back() -> void:
	back_requested.emit()


func _focus_initial_control() -> void:
	if _sliders.has(&"master_volume"):
		(_sliders[&"master_volume"] as Control).grab_focus()


func _play_audio_preview() -> void:
	if AudioServer.get_bus_index(_pending_preview_bus) >= 0:
		_sfx_preview_player.bus = String(_pending_preview_bus)
	else:
		_sfx_preview_player.bus = "Master"
	if _sfx_preview_player.playing:
		_sfx_preview_player.stop()
	_sfx_preview_player.play()


func _read_setting(key: StringName) -> Variant:
	if _settings == null:
		return null
	return _settings.get(String(key))


func _save_setting(key: StringName, value: Variant) -> void:
	if _settings != null and _settings.has_method("set_setting"):
		_settings.call("set_setting", key, value)
