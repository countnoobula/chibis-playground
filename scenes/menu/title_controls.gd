extends Control

signal options_requested

enum MenuAction {
	CONTINUE,
	NEW_GAME,
	OPTIONS,
	QUIT,
}

const ACTION_NAMES: Array[String] = ["continue", "new_game", "options", "quit"]
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
const FOCUSED_MODULATE := Color(1.0, 0.92, 0.82, 1.0)
const FOCUS_SCALE := Vector2(1.055, 1.055)
const FOCUS_LIFT := 7.0

var _buttons: Array[TextureButton] = []
var _base_positions: Array[Vector2] = []
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
		_load_button_texture(button, action)

	_layout_buttons()
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
	for action in MenuAction.size():
		var button := _buttons[action]
		var target_position := MOBILE_POSITIONS[action] if mobile_layout else DESKTOP_POSITIONS[action]
		var target_size := MOBILE_BUTTON_SIZE if mobile_layout else DESKTOP_SIZES[action]
		button.position = target_position
		button.size = target_size
		button.pivot_offset = target_size * 0.5
		_base_positions[action] = target_position


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
		button.modulate = DISABLED_MODULATE if button.disabled else Color.WHITE
		if action == focused_action:
			if not mobile_layout:
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
