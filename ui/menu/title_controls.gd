extends Control

signal play_requested
signal options_requested

enum MenuAction {
	PLAY,
	OPTIONS,
	QUIT,
}

const JOURNAL_FONT := preload("res://ui/menu/berry_journal_font.tres")
const ACTION_LABELS: Array[String] = ["Play", "Options", "Quit"]
const ENABLED_ACTIONS: Array[int] = [MenuAction.PLAY, MenuAction.OPTIONS, MenuAction.QUIT]
const MOBILE_LAYOUT_ARGUMENT := "--mobile-menu"

const DESKTOP_POSITIONS: Array[Vector2] = [
	Vector2(28.0, 622.0),
	Vector2(232.0, 622.0),
	Vector2(436.0, 622.0),
]
const DESKTOP_BUTTON_SIZE := Vector2(186.0, 72.0)
const MOBILE_POSITIONS: Array[Vector2] = [
	Vector2(36.0, 452.0),
	Vector2(338.0, 452.0),
	Vector2(187.0, 576.0),
]
const MOBILE_BUTTON_SIZE := Vector2(290.0, 112.0)

const IDLE_RIM := preload("res://ui/menu/title_idle_rim.gdshader")
const FOCUS_SCALE := Vector2(1.055, 1.055)
const FOCUS_LIFT := 7.0
const MOBILE_FOCUS_SCALE := Vector2(1.08, 1.08)
const MOBILE_FOCUS_LIFT := 8.0
const MOBILE_BOTTOM_MARGIN := 28.0
const MOBILE_SAFE_MARGIN := Vector2(24.0, MOBILE_BOTTOM_MARGIN)

var _buttons: Array[TextureButton] = []
var _idle_material := ShaderMaterial.new()
var _base_positions: Array[Vector2] = []
var _mobile_offset := Vector2.ZERO
var mobile_layout := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	mobile_layout = OS.has_feature("mobile") or OS.get_cmdline_user_args().has(MOBILE_LAYOUT_ARGUMENT)
	_buttons = [
		$PlayButton as TextureButton,
		$OptionsButton as TextureButton,
		$QuitButton as TextureButton,
	]
	_base_positions.resize(MenuAction.size())
	_idle_material.shader = IDLE_RIM

	for action in MenuAction.size():
		var button := _buttons[action]
		var enabled := action in ENABLED_ACTIONS
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.disabled = not enabled
		button.gui_input.connect(_on_button_gui_input.bind(action))
		button.mouse_entered.connect(_focus_button.bind(action))
		button.focus_entered.connect(_set_button_focus.bind(action, true))
		button.focus_exited.connect(_set_button_focus.bind(action, false))
		button.pressed.connect(_activate_action.bind(action))
		button.accessibility_name = ACTION_LABELS[action]
		button.tooltip_text = ACTION_LABELS[action]
		_dress_button(button, action)

	_layout_buttons()
	_configure_focus_neighbors()
	_buttons[MenuAction.PLAY].grab_focus()
	_update_button_visuals()


func _dress_button(button: TextureButton, action: int) -> void:
	button.texture_normal = preload("res://ui/menu/art/buttons/patch_base.png") if mobile_layout else preload("res://ui/menu/art/buttons/ribbon_base.png")
	var caption := Label.new()
	caption.name = "Caption"
	caption.text = ACTION_LABELS[action]
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var optical_lift := 6.0 if mobile_layout else 4.0
	caption.offset_top = -optical_lift
	caption.offset_bottom = -optical_lift
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_font_override("font", JOURNAL_FONT)
	caption.add_theme_font_size_override("font_size", 37 if mobile_layout else 26)
	caption.add_theme_color_override("font_color", Color("#591c35"))
	button.add_child(caption)

	var berry := TextureRect.new()
	berry.name = "FocusBerry"
	berry.texture = preload("res://ui/menu/art/title_berry.png")
	berry.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	berry.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	berry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(berry)
	berry.anchor_left = 0.79
	berry.anchor_right = 0.92
	berry.anchor_top = 0.23
	berry.anchor_bottom = 0.73
	berry.hide()


func _layout_buttons() -> void:
	_mobile_offset = _mobile_buttons_offset()
	for action in MenuAction.size():
		var button := _buttons[action]
		var target_position := MOBILE_POSITIONS[action] if mobile_layout else DESKTOP_POSITIONS[action]
		var target_size := MOBILE_BUTTON_SIZE if mobile_layout else DESKTOP_BUTTON_SIZE
		if mobile_layout:
			target_position += _mobile_offset
		button.position = target_position
		button.size = target_size
		button.pivot_offset = target_size * 0.5
		_base_positions[action] = target_position


func _mobile_buttons_offset() -> Vector2:
	if not mobile_layout:
		return Vector2.ZERO
	var canvas := get_parent_control()
	if canvas == null or is_zero_approx(canvas.scale.y):
		return Vector2.ZERO
	var viewport_bounds := _safe_view_bounds(get_viewport().get_visible_rect())
	var local_safe_bounds := Rect2(
		(viewport_bounds.position - canvas.position) / canvas.scale,
		viewport_bounds.size / canvas.scale
	)
	var button_left := MOBILE_POSITIONS[0].x
	var button_right := MOBILE_POSITIONS[0].x + MOBILE_BUTTON_SIZE.x
	var button_top := MOBILE_POSITIONS[0].y
	var button_bottom := MOBILE_POSITIONS[0].y + MOBILE_BUTTON_SIZE.y
	for action in range(1, MOBILE_POSITIONS.size()):
		var button_position: Vector2 = MOBILE_POSITIONS[action]
		button_left = minf(button_left, button_position.x)
		button_right = maxf(button_right, button_position.x + MOBILE_BUTTON_SIZE.x)
		button_top = minf(button_top, button_position.y)
		button_bottom = maxf(button_bottom, button_position.y + MOBILE_BUTTON_SIZE.y)
	var min_x_shift := local_safe_bounds.position.x + MOBILE_SAFE_MARGIN.x - button_left
	var max_x_shift := local_safe_bounds.end.x - MOBILE_SAFE_MARGIN.x - button_right
	var min_y_shift := local_safe_bounds.position.y + MOBILE_SAFE_MARGIN.y - button_top
	var max_y_shift := local_safe_bounds.end.y - MOBILE_SAFE_MARGIN.y - button_bottom
	var x_shift := clampf(0.0, min_x_shift, max_x_shift) if min_x_shift <= max_x_shift else local_safe_bounds.get_center().x - (button_left + button_right) * 0.5
	var y_shift := clampf(0.0, min_y_shift, max_y_shift) if min_y_shift <= max_y_shift else local_safe_bounds.get_center().y - (button_top + button_bottom) * 0.5
	return Vector2(x_shift, y_shift)


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


func fit_to_visible_area() -> void:
	_layout_buttons()
	_update_button_visuals()


func _configure_focus_neighbors() -> void:
	for index in ENABLED_ACTIONS.size():
		var action := ENABLED_ACTIONS[index]
		var button := _buttons[action]
		var previous_action := ENABLED_ACTIONS[posmod(index - 1, ENABLED_ACTIONS.size())]
		var next_action := ENABLED_ACTIONS[(index + 1) % ENABLED_ACTIONS.size()]
		button.focus_neighbor_left = button.get_path_to(_buttons[previous_action])
		button.focus_neighbor_right = button.get_path_to(_buttons[next_action])
		button.focus_previous = button.get_path_to(_buttons[previous_action])
		button.focus_next = button.get_path_to(_buttons[next_action])

	if not mobile_layout:
		return

	_buttons[MenuAction.PLAY].focus_neighbor_left = _buttons[MenuAction.PLAY].get_path_to(_buttons[MenuAction.PLAY])
	_buttons[MenuAction.PLAY].focus_neighbor_right = _buttons[MenuAction.PLAY].get_path_to(_buttons[MenuAction.OPTIONS])
	_buttons[MenuAction.PLAY].focus_neighbor_top = _buttons[MenuAction.PLAY].get_path_to(_buttons[MenuAction.PLAY])
	_buttons[MenuAction.PLAY].focus_neighbor_bottom = _buttons[MenuAction.PLAY].get_path_to(_buttons[MenuAction.QUIT])
	_buttons[MenuAction.OPTIONS].focus_neighbor_left = _buttons[MenuAction.OPTIONS].get_path_to(_buttons[MenuAction.PLAY])
	_buttons[MenuAction.OPTIONS].focus_neighbor_right = _buttons[MenuAction.OPTIONS].get_path_to(_buttons[MenuAction.OPTIONS])
	_buttons[MenuAction.OPTIONS].focus_neighbor_top = _buttons[MenuAction.OPTIONS].get_path_to(_buttons[MenuAction.OPTIONS])
	_buttons[MenuAction.OPTIONS].focus_neighbor_bottom = _buttons[MenuAction.OPTIONS].get_path_to(_buttons[MenuAction.QUIT])
	_buttons[MenuAction.QUIT].focus_neighbor_top = _buttons[MenuAction.QUIT].get_path_to(_buttons[MenuAction.PLAY])
	_buttons[MenuAction.QUIT].focus_neighbor_left = _buttons[MenuAction.QUIT].get_path_to(_buttons[MenuAction.PLAY])
	_buttons[MenuAction.QUIT].focus_neighbor_right = _buttons[MenuAction.QUIT].get_path_to(_buttons[MenuAction.OPTIONS])
	_buttons[MenuAction.QUIT].focus_neighbor_bottom = _buttons[MenuAction.QUIT].get_path_to(_buttons[MenuAction.QUIT])


func _on_button_gui_input(event: InputEvent, action: int) -> void:
	if event is InputEventMouseMotion:
		_focus_button(action)


func _focus_button(action: int) -> void:
	if action in ENABLED_ACTIONS:
		_buttons[action].grab_focus()


func _update_button_visuals() -> void:
	for action in MenuAction.size():
		_set_button_focus(action, _buttons[action].has_focus())


func _set_button_focus(action: int, focused: bool) -> void:
	var button := _buttons[action]
	button.position = _base_positions[action]
	button.scale = Vector2.ONE
	button.z_index = int(focused)
	button.material = null if focused else _idle_material
	button.get_node("FocusBerry").visible = focused
	if focused:
		button.position.y -= MOBILE_FOCUS_LIFT if mobile_layout else FOCUS_LIFT
		button.scale = MOBILE_FOCUS_SCALE if mobile_layout else FOCUS_SCALE


func _activate_action(action: int) -> void:
	if action not in ENABLED_ACTIONS:
		return
	_focus_button(action)
	match action:
		MenuAction.PLAY:
			play_requested.emit()
		MenuAction.OPTIONS:
			options_requested.emit()
		MenuAction.QUIT:
			get_tree().quit()
