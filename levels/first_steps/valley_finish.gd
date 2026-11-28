extends CanvasLayer

signal replay_requested
signal level_select_requested

class StitchOverlay extends Control:
	const THREAD_COLOR := Color("#f5c8a9")

	func _draw() -> void:
		var inset := 16.0
		for x in range(int(inset), int(size.x - inset), 15):
			draw_line(Vector2(x, inset), Vector2(x + 7, inset), THREAD_COLOR, 1.5, true)
			draw_line(Vector2(x, size.y - inset), Vector2(x + 7, size.y - inset), THREAD_COLOR, 1.5, true)
		for y in range(int(inset + 7.0), int(size.y - inset), 15):
			draw_line(Vector2(inset, y), Vector2(inset, y + 7), THREAD_COLOR, 1.5, true)
			draw_line(Vector2(size.x - inset, y), Vector2(size.x - inset, y + 7), THREAD_COLOR, 1.5, true)


const MAIN_MENU_SCRIPT := preload("res://ui/menu/main_menu.gd")
const MAIN_MENU_SCENE := "res://ui/menu/main_menu.tscn"
const FIRST_STEPS_SCENE := "res://levels/first_steps/first_steps_valley.tscn"
const FIRST_STEPS_ID: StringName = &"first_steps"
const JOURNAL_FONT: Font = preload("res://ui/menu/berry_journal_font.tres")
const BODY_FONT: Font = preload("res://assets/fonts/lora/Lora.ttf")
const DESKTOP_PAPER: Texture2D = preload("res://ui/menu/art/pause_journal/desktop_paper_tile.png")
const DESKTOP_RIBBON: Texture2D = preload("res://ui/menu/art/buttons/ribbon_base.png")
const MOBILE_PATCH: Texture2D = preload("res://ui/menu/art/buttons/patch_base.png")
const FOCUS_BERRY: Texture2D = preload("res://ui/menu/art/title_berry.png")

@onready var _dimmer: ColorRect = $Dimmer
@onready var _card_rim: Panel = $CardRim
@onready var _paper: Panel = $Paper
@onready var _paper_texture: TextureRect = $PaperTexture
@onready var _eyebrow_label: Label = $EyebrowLabel
@onready var _title_label: Label = $TitleLabel
@onready var _description_label: Label = $DescriptionLabel
@onready var _status_label: Label = $StatusLabel
@onready var _replay_button: TextureButton = $ReplayButton
@onready var _level_select_button: TextureButton = $LevelSelectButton
@onready var _replay_label: Label = $ReplayButton/Label
@onready var _level_select_label: Label = $LevelSelectButton/Label
@onready var _replay_focus_ring: Panel = $ReplayButton/FocusRing
@onready var _level_select_focus_ring: Panel = $LevelSelectButton/FocusRing
@onready var _replay_berry: TextureRect = $ReplayButton/FocusBerry
@onready var _level_select_berry: TextureRect = $LevelSelectButton/FocusBerry

var _stitch_overlay: StitchOverlay
var _completion_shown := false
var _choice_committed := false
var _hovered_buttons: Dictionary = {}
var _mobile_layout := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_replay_button.accessibility_name = "Replay First Steps Valley"
	_replay_button.accessibility_description = "Start a fresh run at the valley trailhead."
	_replay_button.tooltip_text = "Start a fresh run from the beginning."
	_level_select_button.accessibility_name = "Level Select"
	_level_select_button.accessibility_description = "Return to the atlas with First Steps Valley selected."
	_level_select_button.tooltip_text = "Choose a destination from the atlas."
	_replay_button.pressed.connect(_on_replay_pressed)
	_level_select_button.pressed.connect(_on_level_select_pressed)
	for button in [_replay_button, _level_select_button]:
		button.mouse_entered.connect(_on_button_hover.bind(button, true))
		button.mouse_exited.connect(_on_button_hover.bind(button, false))
		button.focus_entered.connect(_on_button_focus.bind(button, true))
		button.focus_exited.connect(_on_button_focus.bind(button, false))
	_replay_button.focus_neighbor_left = _replay_button.get_path_to(_replay_button)
	_replay_button.focus_neighbor_right = _replay_button.get_path_to(_level_select_button)
	_replay_button.focus_next = _replay_button.get_path_to(_level_select_button)
	_replay_button.focus_previous = _replay_button.get_path_to(_level_select_button)
	_level_select_button.focus_neighbor_left = _level_select_button.get_path_to(_replay_button)
	_level_select_button.focus_neighbor_right = _level_select_button.get_path_to(_level_select_button)
	_level_select_button.focus_next = _level_select_button.get_path_to(_replay_button)
	_level_select_button.focus_previous = _level_select_button.get_path_to(_replay_button)
	_dimmer.color = Color(0.12, 0.055, 0.105, 0.78)
	_paper_texture.texture = DESKTOP_PAPER
	_replay_berry.texture = FOCUS_BERRY
	_level_select_berry.texture = FOCUS_BERRY
	_stitch_overlay = StitchOverlay.new()
	_stitch_overlay.name = "StitchOverlay"
	_stitch_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stitch_overlay.z_index = 2
	add_child(_stitch_overlay)
	if not get_viewport().size_changed.is_connected(_fit_layout):
		get_viewport().size_changed.connect(_fit_layout)
	_fit_layout()


func _exit_tree() -> void:
	if get_viewport() != null and get_viewport().size_changed.is_connected(_fit_layout):
		get_viewport().size_changed.disconnect(_fit_layout)
	if _completion_shown:
		_set_game_input_menu_open(false)
		if get_tree() != null and get_tree().paused:
			get_tree().paused = false


## Show the completion choice when the runner reaches the grounded overlook finish.
func show_completion() -> void:
	if _completion_shown:
		return
	_completion_shown = true
	_choice_committed = false
	_status_label.text = ""
	_status_label.hide()
	visible = true
	_fit_layout()
	_set_game_input_menu_open(true)
	get_tree().paused = true
	_replay_button.disabled = false
	_level_select_button.disabled = false
	_replay_button.grab_focus.call_deferred()


func _fit_layout() -> void:
	if not is_node_ready():
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var margin := Vector2(24.0, 20.0)
	var card_size := Vector2(minf(700.0, viewport_size.x - margin.x * 2.0), minf(448.0, viewport_size.y - margin.y * 2.0))
	card_size.x = maxf(320.0, card_size.x)
	card_size.y = maxf(300.0, card_size.y)
	_mobile_layout = viewport_size.y < 520.0 or viewport_size.x < 700.0
	var card_position := (viewport_size - card_size) * 0.5
	_card_rim.position = card_position
	_card_rim.size = card_size
	_paper.position = card_position + Vector2(9.0, 9.0)
	_paper.size = card_size - Vector2(18.0, 18.0)
	_paper_texture.position = card_position + Vector2(18.0, 18.0)
	_paper_texture.size = card_size - Vector2(36.0, 36.0)
	_paper_texture.modulate = Color(1.0, 1.0, 1.0, 0.14)
	_stitch_overlay.position = card_position
	_stitch_overlay.size = card_size
	var content_left := card_position.x + 34.0
	var content_width := card_size.x - 68.0
	var top := card_position.y + (29.0 if _mobile_layout else 38.0)
	var eyebrow_height := 22.0
	_eyebrow_label.position = Vector2(content_left, top)
	_eyebrow_label.size = Vector2(content_width, eyebrow_height)
	_eyebrow_label.add_theme_font_override("font", JOURNAL_FONT)
	_eyebrow_label.add_theme_font_size_override("font_size", 13 if _mobile_layout else 15)
	_eyebrow_label.add_theme_color_override("font_color", Color("#9a4550"))
	_eyebrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_eyebrow_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.position = Vector2(content_left, top + eyebrow_height)
	_title_label.size = Vector2(content_width, 56.0 if _mobile_layout else 68.0)
	_title_label.add_theme_font_override("font", JOURNAL_FONT)
	_title_label.add_theme_color_override("font_color", Color("#591c35"))
	_title_label.add_theme_font_size_override("font_size", 31 if _mobile_layout else 42)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_description_label.position = Vector2(content_left + 12.0, _title_label.position.y + _title_label.size.y + 2.0)
	_description_label.size = Vector2(content_width - 24.0, 62.0 if _mobile_layout else 70.0)
	_description_label.add_theme_font_override("font", BODY_FONT)
	_description_label.add_theme_color_override("font_color", Color("#6d4250"))
	_description_label.add_theme_font_size_override("font_size", 17 if _mobile_layout else 20)
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_description_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var button_gap := 20.0
	var button_width := (content_width - button_gap) * 0.5
	var button_height := minf(92.0 if _mobile_layout else 100.0, card_size.y * 0.235)
	var button_y := card_position.y + card_size.y - button_height - 28.0
	_status_label.position = Vector2(content_left, button_y - 30.0)
	_status_label.size = Vector2(content_width, 24.0)
	_status_label.add_theme_font_override("font", BODY_FONT)
	_status_label.add_theme_color_override("font_color", Color("#8a394a"))
	_status_label.add_theme_font_size_override("font_size", 14 if _mobile_layout else 16)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_replay_button.position = Vector2(content_left, button_y)
	_replay_button.size = Vector2(button_width, button_height)
	_level_select_button.position = Vector2(content_left + button_width + button_gap, button_y)
	_level_select_button.size = Vector2(button_width, button_height)
	var base_texture := MOBILE_PATCH if _mobile_layout else DESKTOP_RIBBON
	for button in [_replay_button, _level_select_button]:
		button.texture_normal = base_texture
		button.texture_hover = base_texture
		button.texture_pressed = base_texture
		button.texture_focused = base_texture
		button.texture_disabled = base_texture
		button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_replay_label.add_theme_font_override("font", JOURNAL_FONT)
	_level_select_label.add_theme_font_override("font", JOURNAL_FONT)
	_replay_label.add_theme_font_size_override("font_size", 25 if _mobile_layout else 27)
	_level_select_label.add_theme_font_size_override("font_size", 24 if _mobile_layout else 25)
	_replay_berry.size = Vector2(button_height * 0.34, button_height * 0.34)
	_level_select_berry.size = _replay_berry.size
	_replay_berry.position = Vector2(button_width - button_height * 0.49, button_height * 0.18)
	_level_select_berry.position = Vector2(button_width - button_height * 0.49, button_height * 0.18)
	_stitch_overlay.queue_redraw()


func _on_button_hover(button: TextureButton, hovered: bool) -> void:
	_hovered_buttons[button] = hovered
	if hovered:
		button.grab_focus()
	_update_button_visual(button)


func _on_button_focus(button: TextureButton, focused: bool) -> void:
	_update_button_visual(button, focused)


func _update_button_visual(button: TextureButton, focused_override: bool = false) -> void:
	var emphasized := focused_override or button.has_focus() or bool(_hovered_buttons.get(button, false))
	if button == _replay_button:
		_replay_focus_ring.visible = emphasized
		_replay_berry.visible = emphasized
	else:
		_level_select_focus_ring.visible = emphasized
		_level_select_berry.visible = emphasized


func _begin_choice() -> bool:
	if not _completion_shown or _choice_committed:
		return false
	_choice_committed = true
	_replay_button.disabled = true
	_level_select_button.disabled = true
	get_tree().paused = false
	return true


func _set_game_input_menu_open(open: bool) -> void:
	var input_nodes := get_tree().get_nodes_in_group(&"chibi_input")
	if input_nodes.is_empty() and open and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for input_node in input_nodes:
		if input_node.has_method("set_menu_open"):
			input_node.call("set_menu_open", open)
		if open and input_node.has_method("clear_touch_input"):
			input_node.call("clear_touch_input")


func _on_replay_pressed() -> void:
	if not _begin_choice():
		return
	replay_requested.emit()
	var result := get_tree().change_scene_to_file(FIRST_STEPS_SCENE)
	if result != OK:
		_restore_after_failed_choice("The valley could not be loaded. Choose an action again.")


func _on_level_select_pressed() -> void:
	if not _begin_choice():
		return
	level_select_requested.emit()
	MAIN_MENU_SCRIPT.request_atlas_return(FIRST_STEPS_ID)
	var result := get_tree().change_scene_to_file(MAIN_MENU_SCENE)
	if result != OK:
		MAIN_MENU_SCRIPT.cancel_atlas_return()
		_restore_after_failed_choice("The atlas could not be opened. Choose an action again.")


func _restore_after_failed_choice(message: String) -> void:
	_choice_committed = false
	_set_game_input_menu_open(true)
	get_tree().paused = true
	_replay_button.disabled = false
	_level_select_button.disabled = false
	_status_label.text = message
	_status_label.show()
	_replay_button.grab_focus.call_deferred()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
