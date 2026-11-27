extends Control

signal options_requested

enum MenuAction {
	CONTINUE,
	NEW_GAME,
	OPTIONS,
	QUIT,
}

const ACTION_NAMES: Array[String] = ["continue", "new_game", "options", "quit"]
const ACTION_LABELS: Array[String] = ["Continue", "New Game", "Options", "Quit"]
const ENABLED_ACTIONS: Array[int] = [MenuAction.NEW_GAME, MenuAction.OPTIONS, MenuAction.QUIT]
const ROOFTOP_SCENE := "res://scenes/gym/rooftop_parkour_gym.tscn"
const MOBILE_LAYOUT_ARGUMENT := "--mobile-menu"

const DESKTOP_POSITIONS: Array[Vector2] = [
	Vector2(28.0, 622.0),
	Vector2(206.0, 622.0),
	Vector2(400.0, 622.0),
	Vector2(562.0, 622.0),
]
const DESKTOP_SIZES: Array[Vector2] = [
	Vector2(170.0, 72.0),
	Vector2(186.0, 72.0),
	Vector2(154.0, 72.0),
	Vector2(144.0, 72.0),
]
const MOBILE_POSITIONS: Array[Vector2] = [
	Vector2(36.0, 452.0),
	Vector2(338.0, 452.0),
	Vector2(36.0, 576.0),
	Vector2(338.0, 576.0),
]
const MOBILE_BUTTON_SIZE := Vector2(290.0, 112.0)

const DISABLED_MODULATE := Color.WHITE
const FOCUSED_MODULATE := Color(1.0, 0.96, 0.88, 1.0)
const FOCUS_SCALE := Vector2(1.055, 1.055)
const FOCUS_LIFT := 7.0
const MOBILE_FOCUS_SCALE := Vector2(1.08, 1.08)
const MOBILE_FOCUS_LIFT := 8.0
const MOBILE_FOCUS_HIGHLIGHT_SCALE := Vector2(1.16, 1.16)
const MOBILE_FOCUS_HIGHLIGHT_COLOR := Color("#ffe48c")
const MOBILE_BOTTOM_MARGIN := 28.0
const MOBILE_SAFE_MARGIN := Vector2(24.0, MOBILE_BOTTOM_MARGIN)

var _buttons: Array[TextureButton] = []
var _focus_highlights: Array[TextureRect] = []
var _base_positions: Array[Vector2] = []
var _mobile_offset := Vector2.ZERO
var mobile_layout := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	mobile_layout = OS.has_feature("mobile") or OS.get_cmdline_user_args().has(MOBILE_LAYOUT_ARGUMENT)
	_buttons = [
		$ContinueButton as TextureButton,
		$NewGameButton as TextureButton,
		$OptionsButton as TextureButton,
		$QuitButton as TextureButton,
	]
	_base_positions.resize(MenuAction.size())
	_focus_highlights.resize(MenuAction.size())

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
		button.focus_entered.connect(_on_button_focus_entered.bind(action))
		button.pressed.connect(_activate_action.bind(action))
		button.accessibility_name = ACTION_LABELS[action]
		button.tooltip_text = ACTION_LABELS[action]
		if action == MenuAction.CONTINUE:
			button.accessibility_description = "Continue is not available yet."
		_load_button_texture(button, action)

	_layout_buttons()
	_create_focus_highlights()
	_configure_focus_neighbors()
	_buttons[MenuAction.NEW_GAME].grab_focus()
	_update_button_visuals()


func _load_button_texture(button: TextureButton, action: int) -> void:
	var family := "patch" if mobile_layout else "ribbon"
	var texture_path := "res://scenes/menu/art/buttons/%s_%s.png" % [family, ACTION_NAMES[action]]
	var texture := load(texture_path) as Texture2D
	if texture == null:
		push_error("Missing title menu button texture: %s" % texture_path)
		return
	button.texture_normal = texture
	button.texture_hover = texture
	button.texture_pressed = texture
	button.texture_focused = texture
	button.texture_disabled = texture


func _layout_buttons() -> void:
	_mobile_offset = _mobile_buttons_offset()
	for action in MenuAction.size():
		var button := _buttons[action]
		var target_position := MOBILE_POSITIONS[action] if mobile_layout else DESKTOP_POSITIONS[action]
		var target_size := MOBILE_BUTTON_SIZE if mobile_layout else DESKTOP_SIZES[action]
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
	var button_left := MOBILE_POSITIONS[MenuAction.CONTINUE].x
	var button_right := MOBILE_POSITIONS[MenuAction.QUIT].x + MOBILE_BUTTON_SIZE.x
	var button_top := MOBILE_POSITIONS[MenuAction.NEW_GAME].y
	var button_bottom := MOBILE_POSITIONS[MenuAction.QUIT].y + MOBILE_BUTTON_SIZE.y
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


func _create_focus_highlights() -> void:
	for action in MenuAction.size():
		var button := _buttons[action]
		var highlight := TextureRect.new()
		highlight.name = "FocusHighlight_%s" % ACTION_NAMES[action]
		highlight.position = button.position
		highlight.size = button.size
		highlight.pivot_offset = button.size * 0.5
		highlight.texture = button.texture_normal
		highlight.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		highlight.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		highlight.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		highlight.modulate = MOBILE_FOCUS_HIGHLIGHT_COLOR
		highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
		highlight.focus_mode = Control.FOCUS_NONE
		highlight.visible = false
		add_child(highlight)
		move_child(highlight, button.get_index())
		_focus_highlights[action] = highlight


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

	_buttons[MenuAction.NEW_GAME].focus_neighbor_top = _buttons[MenuAction.NEW_GAME].get_path_to(_buttons[MenuAction.OPTIONS])
	_buttons[MenuAction.NEW_GAME].focus_neighbor_bottom = _buttons[MenuAction.NEW_GAME].get_path_to(_buttons[MenuAction.QUIT])
	_buttons[MenuAction.OPTIONS].focus_neighbor_top = _buttons[MenuAction.OPTIONS].get_path_to(_buttons[MenuAction.NEW_GAME])
	_buttons[MenuAction.OPTIONS].focus_neighbor_bottom = _buttons[MenuAction.OPTIONS].get_path_to(_buttons[MenuAction.QUIT])
	_buttons[MenuAction.QUIT].focus_neighbor_top = _buttons[MenuAction.QUIT].get_path_to(_buttons[MenuAction.NEW_GAME])
	_buttons[MenuAction.QUIT].focus_neighbor_bottom = _buttons[MenuAction.QUIT].get_path_to(_buttons[MenuAction.OPTIONS])


func _on_button_gui_input(event: InputEvent, action: int) -> void:
	if event is InputEventMouseMotion:
		_focus_button(action)


func _focus_button(action: int) -> void:
	if action in ENABLED_ACTIONS:
		_buttons[action].grab_focus()


func _on_button_focus_entered(_action: int) -> void:
	_update_button_visuals()


func _focused_action() -> int:
	for action in ENABLED_ACTIONS:
		if _buttons[action].has_focus():
			return action
	return -1


func _update_button_visuals() -> void:
	var focused_action := _focused_action()
	for action in MenuAction.size():
		var button := _buttons[action]
		button.position = _base_positions[action]
		button.scale = Vector2.ONE
		button.z_index = 0
		button.modulate = DISABLED_MODULATE if button.disabled else Color.WHITE
		var highlight := _focus_highlights[action]
		highlight.position = button.position
		highlight.scale = Vector2.ONE
		highlight.visible = false
		if action == focused_action:
			button.z_index = 1
			if mobile_layout:
				button.position.y -= MOBILE_FOCUS_LIFT
				button.scale = MOBILE_FOCUS_SCALE
				highlight.position = button.position
				highlight.scale = MOBILE_FOCUS_HIGHLIGHT_SCALE
				highlight.visible = true
			else:
				button.position.y -= FOCUS_LIFT
				button.scale = FOCUS_SCALE
			button.modulate = FOCUSED_MODULATE


func _activate_action(action: int) -> void:
	if action not in ENABLED_ACTIONS:
		return
	_focus_button(action)
	match action:
		MenuAction.NEW_GAME:
			get_tree().change_scene_to_file(ROOFTOP_SCENE)
		MenuAction.OPTIONS:
			options_requested.emit()
		MenuAction.QUIT:
			get_tree().quit()
