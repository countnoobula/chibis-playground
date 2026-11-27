extends CanvasLayer
## Small, keyboard- and touch-friendly expression picker for the rooftop HUD.

const PRIORITY := 100
const EXPRESSION_SECONDS := 2.5
const GRID_COLUMNS := 5
const GRID_BUTTON_SIZE := Vector2(48.0, 54.0)
const PREVIEW_PATHS := [
	"res://features/runner/expressions/cloud/cloud00.png",
	"res://features/runner/expressions/cloud/cloud01.png",
	"res://features/runner/expressions/cloud/cloud02.png",
	"res://features/runner/expressions/cloud/cloud03.png",
	"res://features/runner/expressions/cloud/cloud04.png",
	"res://features/runner/expressions/cloud/cloud05.png",
	"res://features/runner/expressions/cloud/cloud06.png",
	"res://features/runner/expressions/cloud/cloud07.png",
	"res://features/runner/expressions/cloud/cloud08.png",
	"res://features/runner/expressions/cloud/cloud09.png",
	"res://features/runner/expressions/cloud/cloud10.png",
	"res://features/runner/expressions/cloud/cloud11.png",
	"res://features/runner/expressions/cloud/cloud12.png",
	"res://features/runner/expressions/cloud/cloud13.png",
	"res://features/runner/expressions/cloud/cloud14.png",
	"res://features/runner/expressions/cloud/cloud15.png",
	"res://features/runner/expressions/cloud/cloud16.png",
	"res://features/runner/expressions/cloud/cloud17.png",
	"res://features/runner/expressions/cloud/cloud18.png",
	"res://features/runner/expressions/cloud/cloud19.png",
]
const INK := Color("553449")
const PAPER := Color("fff5ef")
const SOFT_PINK := Color("f0dde0")
const BORDER := Color("d9b9bb")
const LAVENDER := Color("c3b1d9")

var _player: Node
var _director: Node
var _chibi_input: Node
var _touch_hud: Node
var _ids: Array = []
var _names: Array = []
var _preview_textures: Array[Texture2D] = []

var _root: Control
var _backdrop: ColorRect
var _trigger: Button
var _popup: Panel
var _header: HBoxContainer
var _title_label: Label
var _mode_row: HBoxContainer
var _grid_scroll: ScrollContainer
var _grid: GridContainer
var _action_row: HBoxContainer
var _status_label: Label
var _keyboard_hint: Label
var _mode_buttons: Dictionary = {}
var _timed_button: Button
var _hold_button: Button
var _auto_button: Button
var _first_expression_button: Button

var _is_open := false
var _hold_mode := true
var _output_mode: StringName = &"both"
var _active_handle := -1
var _active_index := -1
var _touch_input_was_processing := true
var _game_input_suspended := false


func _ready() -> void:
	layer = 35
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_layout):
		viewport.size_changed.connect(_layout)
	_layout()


func setup(player: Node) -> void:
	_player = player
	if not is_instance_valid(_player):
		return
	_director = _player.get_node_or_null("ExpressionDirector")
	_chibi_input = _player.get_node_or_null("ChibiInput")
	_touch_hud = _player.get_node_or_null("TouchControlsHUD")
	_read_expression_catalog()
	_populate_expression_grid()
	_sync_pause_menu_visibility()
	_layout()


func _exit_tree() -> void:
	_restore_game_input(not _pause_menu_is_open())
	_release_active_expression()


func _process(_delta: float) -> void:
	_sync_pause_menu_visibility()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _is_open:
		_close_picker()
		get_viewport().set_input_as_handled()
	elif what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT] and _is_open:
		_close_picker()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	var is_shortcut := key.keycode == KEY_F or key.physical_keycode == KEY_F
	if _is_open:
		if is_shortcut:
			_close_picker()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(&"ui_cancel"):
			_close_picker()
			get_viewport().set_input_as_handled()
		return
	if is_shortcut and _can_open():
		_open_picker()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "EmojiPickerRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_backdrop = ColorRect.new()
	_backdrop.name = "DismissBackdrop"
	_backdrop.color = Color(0.0, 0.0, 0.0, 0.0)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_backdrop_gui_input)
	_backdrop.hide()
	_root.add_child(_backdrop)

	_popup = Panel.new()
	_popup.name = "ExpressionPicker"
	_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_popup.add_theme_stylebox_override("panel", _flat_style(PAPER, BORDER, 16, 1))
	_popup.hide()
	_root.add_child(_popup)

	var content := Control.new()
	content.name = "Content"
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup.add_child(content)

	_header = HBoxContainer.new()
	_header.name = "Header"
	_header.add_theme_constant_override("separation", 6)
	content.add_child(_header)

	_title_label = Label.new()
	_title_label.text = "Expressions"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_color_override("font_color", INK)
	_title_label.add_theme_font_size_override("font_size", 16)
	_header.add_child(_title_label)

	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "×"
	close_button.tooltip_text = "Close the expression picker"
	close_button.custom_minimum_size = Vector2(40.0, 36.0)
	close_button.focus_mode = Control.FOCUS_ALL
	close_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_button.add_theme_color_override("font_color", INK)
	close_button.add_theme_color_override("font_hover_color", INK)
	close_button.add_theme_color_override("font_pressed_color", INK)
	close_button.add_theme_font_size_override("font_size", 16)
	close_button.add_theme_stylebox_override("normal", _flat_style(PAPER, BORDER, 9, 1))
	close_button.add_theme_stylebox_override("hover", _flat_style(SOFT_PINK, BORDER, 9, 1))
	close_button.pressed.connect(_close_picker)
	_header.add_child(close_button)

	_mode_row = HBoxContainer.new()
	_mode_row.name = "OutputMode"
	_mode_row.add_theme_constant_override("separation", 5)
	content.add_child(_mode_row)
	_add_mode_button(_mode_row, &"both", "Both")
	_add_mode_button(_mode_row, &"face", "Face")
	_add_mode_button(_mode_row, &"cloud", "Cloud")

	_grid_scroll = ScrollContainer.new()
	_grid_scroll.name = "ExpressionGridScroll"
	_grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid_scroll.custom_minimum_size = Vector2.ZERO
	content.add_child(_grid_scroll)

	_grid = GridContainer.new()
	_grid.name = "ExpressionGrid"
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_scroll.add_child(_grid)

	_action_row = HBoxContainer.new()
	_action_row.name = "DurationAndAuto"
	_action_row.add_theme_constant_override("separation", 4)
	content.add_child(_action_row)

	var duration_label := Label.new()
	duration_label.text = "Use for"
	duration_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	duration_label.add_theme_color_override("font_color", INK)
	duration_label.add_theme_font_size_override("font_size", 10)
	_action_row.add_child(duration_label)

	_timed_button = _make_choice_button("2.5s")
	_timed_button.tooltip_text = "Return to automatic expressions after 2.5 seconds"
	_timed_button.pressed.connect(_set_hold_mode.bind(false))
	_action_row.add_child(_timed_button)

	_hold_button = _make_choice_button("Hold")
	_hold_button.tooltip_text = "Keep this expression until Auto is pressed"
	_hold_button.pressed.connect(_set_hold_mode.bind(true))
	_action_row.add_child(_hold_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_action_row.add_child(spacer)

	_auto_button = _make_choice_button("Auto")
	_auto_button.tooltip_text = "Clear this picker’s expression and return to automatic expressions"
	_auto_button.pressed.connect(_clear_active_expression)
	_action_row.add_child(_auto_button)

	_status_label = Label.new()
	_status_label.name = "ExpressionHint"
	_status_label.text = "Choose a cloud, or press F."
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(0.0, 18.0)
	_status_label.add_theme_color_override("font_color", INK)
	_status_label.add_theme_font_size_override("font_size", 12)
	content.add_child(_status_label)

	_keyboard_hint = Label.new()
	_keyboard_hint.text = "F open  ·  Esc close  ·  arrows + Enter"
	_keyboard_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_keyboard_hint.add_theme_color_override("font_color", Color(INK.r, INK.g, INK.b, 0.72))
	_keyboard_hint.add_theme_font_size_override("font_size", 9)
	content.add_child(_keyboard_hint)

	_trigger = Button.new()
	_trigger.name = "ExpressionsButton"
	_trigger.text = "F"
	_trigger.tooltip_text = "Open the expression picker (F)"
	_trigger.focus_mode = Control.FOCUS_ALL
	_trigger.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_trigger.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_trigger.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_trigger.add_theme_constant_override("icon_max_width", 28)
	_trigger.add_theme_color_override("font_color", INK)
	_trigger.add_theme_font_size_override("font_size", 10)
	_trigger.add_theme_stylebox_override("normal", _flat_style(PAPER, BORDER, 15, 1))
	_trigger.add_theme_stylebox_override("hover", _flat_style(SOFT_PINK, BORDER, 15, 1))
	_trigger.add_theme_stylebox_override("pressed", _flat_style(Color("ead3dc"), BORDER, 15, 1))
	_trigger.pressed.connect(_toggle_picker)
	_root.add_child(_trigger)

func _add_mode_button(parent: Control, mode: StringName, caption: String) -> void:
	var button := _make_choice_button(caption)
	button.name = "%sMode" % caption
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = "%s expressions" % caption
	button.pressed.connect(_set_output_mode.bind(mode))
	parent.add_child(button)
	_mode_buttons[mode] = button


func _make_choice_button(caption: String) -> Button:
	var button := Button.new()
	button.text = caption
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.custom_minimum_size = Vector2(48.0, 32.0)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_stylebox_override("normal", _flat_style(Color("fffaf6"), BORDER, 9, 1))
	button.add_theme_stylebox_override("hover", _flat_style(SOFT_PINK, BORDER, 9, 1))
	button.add_theme_stylebox_override("pressed", _flat_style(LAVENDER, INK, 9, 1))
	button.add_theme_stylebox_override("focus", _flat_style(Color("fffaf6"), INK, 9, 2))
	return button


func _read_expression_catalog() -> void:
	_ids.clear()
	_names.clear()
	if not is_instance_valid(_director):
		return
	var director_script := _director.get_script() as Script
	if director_script == null:
		return
	var constants := director_script.get_script_constant_map()
	_ids = constants.get("IDS", [])
	_names = constants.get("NAMES", [])


func _populate_expression_grid() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_first_expression_button = null
	_preview_textures.clear()
	for path in PREVIEW_PATHS:
		var texture := load(path) as Texture2D
		_preview_textures.append(texture)

	var count := mini(_ids.size(), _names.size())
	count = mini(count, PREVIEW_PATHS.size())
	for index in count:
		var expression_name := str(_names[index])
		var button := Button.new()
		button.name = "Expression%02d" % index
		button.text = ""
		button.tooltip_text = "%s — choose this expression" % expression_name
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.custom_minimum_size = GRID_BUTTON_SIZE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_stylebox_override("normal", _flat_style(Color("fffaf6"), BORDER, 9, 1))
		button.add_theme_stylebox_override("hover", _flat_style(Color("f7e7e6"), BORDER, 9, 1))
		button.add_theme_stylebox_override("pressed", _flat_style(Color("ead3dc"), BORDER, 9, 1))
		button.add_theme_stylebox_override("focus", _flat_style(Color("fffaf6"), INK, 9, 2))
		button.pressed.connect(_apply_expression.bind(index))
		button.focus_entered.connect(_show_expression_hint.bind(index))
		button.mouse_entered.connect(_show_expression_hint.bind(index))
		_set_accessibility_label(button, expression_name)
		_grid.add_child(button)

		var preview := TextureRect.new()
		preview.name = "CloudPreview"
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.focus_mode = Control.FOCUS_NONE
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.texture = _preview_textures[index]
		preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		preview.offset_left = 5.0
		preview.offset_top = 4.0
		preview.offset_right = -5.0
		preview.offset_bottom = -4.0
		button.add_child(preview)
		if _first_expression_button == null:
			_first_expression_button = button

	if count != 20:
		_status_label.text = "Expression previews are unavailable."
	_sync_output_buttons()
	_sync_duration_buttons()
	if _preview_textures.size() > 0 and _trigger != null:
		_trigger.icon = _preview_textures[0]


func _show_expression_hint(index: int) -> void:
	if index < 0 or index >= _names.size():
		return
	var expression_name := str(_names[index])
	var mode_name := "Both" if _output_mode == &"both" else "Face" if _output_mode == &"face" else "Cloud"
	var duration_name := "until Auto" if _hold_mode else "2.5 seconds"
	_status_label.text = "%s · %s · %s" % [expression_name, mode_name, duration_name]


func _toggle_picker() -> void:
	if _is_open:
		_close_picker()
	else:
		_open_picker()


func _can_open() -> bool:
	return is_instance_valid(_player) \
		and is_instance_valid(_director) \
		and _ids.size() == 20 \
		and _names.size() == 20 \
		and not _pause_menu_is_open()


func _open_picker() -> void:
	if _is_open or not _can_open():
		return
	_is_open = true
	_backdrop.show()
	_popup.show()
	_suspend_game_input()
	_sync_output_buttons()
	_sync_duration_buttons()
	_layout()
	_status_label.text = "Choose a cloud, or press F."
	if _active_index >= 0 and _director.call("has_request", _active_handle):
		(_grid.get_child(_active_index) as Button).grab_focus()
	elif _first_expression_button != null:
		_first_expression_button.grab_focus()


func _close_picker() -> void:
	if not _is_open:
		return
	_is_open = false
	_backdrop.hide()
	_popup.hide()
	_restore_game_input(not _pause_menu_is_open())
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null and _root.is_ancestor_of(focus_owner):
		focus_owner.release_focus()


func _suspend_game_input() -> void:
	if _game_input_suspended:
		return
	_game_input_suspended = true
	if is_instance_valid(_touch_hud):
		if _touch_hud.has_method("_reset_touches"):
			_touch_hud.call("_reset_touches")
		_touch_input_was_processing = _touch_hud.is_processing_input()
		_touch_hud.set_process_input(false)
	if is_instance_valid(_chibi_input):
		if _chibi_input.has_method("clear_touch_input"):
			_chibi_input.call("clear_touch_input")
		if _chibi_input.has_method("set_menu_open"):
			_chibi_input.call("set_menu_open", true)


func _restore_game_input(restore_cursor: bool) -> void:
	if not _game_input_suspended:
		return
	_game_input_suspended = false
	if is_instance_valid(_touch_hud):
		_touch_hud.set_process_input(_touch_input_was_processing)
	if restore_cursor and is_instance_valid(_chibi_input) and _chibi_input.has_method("set_menu_open"):
		_chibi_input.call("set_menu_open", false)


func _sync_pause_menu_visibility() -> void:
	var pause_open := _pause_menu_is_open()
	if _trigger != null:
		_trigger.visible = not pause_open
	if _is_open and pause_open:
		_is_open = false
		_backdrop.hide()
		_popup.hide()
		_restore_game_input(false)


func _pause_menu_is_open() -> bool:
	if not is_instance_valid(_touch_hud):
		return false
	var value: Variant = _touch_hud.get("menu_open")
	return bool(value) if value != null else false


func _apply_expression(index: int, close_after: bool = true) -> void:
	if not is_instance_valid(_director) or index < 0 or index >= _ids.size():
		return
	_release_active_expression()
	var duration := 0.0 if _hold_mode else EXPRESSION_SECONDS
	var handle: int = int(_director.call(
		"request_expression",
		StringName(_ids[index]),
		duration,
		PRIORITY,
		_output_mode
	))
	if handle < 0:
		_status_label.text = "That expression could not be applied."
		return
	_active_handle = handle
	_active_index = index
	var expression_name := str(_names[index])
	_status_label.text = "%s · %s" % [expression_name, "held" if _hold_mode else "2.5 seconds"]
	if close_after:
		_close_picker()


func _clear_active_expression() -> void:
	_release_active_expression()
	_status_label.text = "Automatic expressions restored."


func _release_active_expression() -> void:
	if _active_handle >= 0 and is_instance_valid(_director):
		_director.call("release_expression", _active_handle)
	_active_handle = -1
	_active_index = -1


func _set_output_mode(mode: StringName) -> void:
	_output_mode = mode
	_sync_output_buttons()
	if _active_index >= 0:
		_apply_expression(_active_index, false)


func _set_hold_mode(enabled: bool) -> void:
	_hold_mode = enabled
	_sync_duration_buttons()
	if _active_index >= 0:
		_apply_expression(_active_index, false)


func _sync_output_buttons() -> void:
	for mode in _mode_buttons:
		var button: Button = _mode_buttons[mode]
		var selected: bool = StringName(mode) == _output_mode
		button.add_theme_stylebox_override(
			"normal",
			_flat_style(LAVENDER if selected else Color("fffaf6"), INK if selected else BORDER, 9, 1)
		)


func _sync_duration_buttons() -> void:
	if _timed_button == null or _hold_button == null:
		return
	_timed_button.add_theme_stylebox_override(
		"normal",
		_flat_style(LAVENDER if not _hold_mode else Color("fffaf6"), INK if not _hold_mode else BORDER, 9, 1)
	)
	_hold_button.add_theme_stylebox_override(
		"normal",
		_flat_style(LAVENDER if _hold_mode else Color("fffaf6"), INK if _hold_mode else BORDER, 9, 1)
	)


func _on_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_picker()
		_backdrop.accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		_close_picker()
		_backdrop.accept_event()


func _layout() -> void:
	if _root == null or _trigger == null or _popup == null:
		return
	var bounds := get_viewport().get_visible_rect()
	if not bounds.has_area():
		bounds = Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var trigger_size := Vector2(76.0, 50.0)
	_trigger.size = trigger_size
	_trigger.position = Vector2(bounds.end.x - trigger_size.x - 16.0, bounds.position.y + 94.0)
	_trigger.icon = _preview_textures[0] if not _preview_textures.is_empty() else null

	var popup_width := minf(356.0, bounds.size.x - 24.0)
	popup_width = maxf(250.0, popup_width)
	var available_height := bounds.end.y - _trigger.position.y - _trigger.size.y - 20.0
	var popup_height := minf(420.0, maxf(190.0, available_height))
	_popup.size = Vector2(popup_width, popup_height)
	var panel_x := clampf(
		_trigger.position.x + _trigger.size.x - popup_width,
		bounds.position.x + 12.0,
		bounds.end.x - popup_width - 12.0
	)
	var panel_y := _trigger.position.y + _trigger.size.y + 8.0
	panel_y = minf(panel_y, bounds.end.y - popup_height - 10.0)
	panel_y = maxf(bounds.position.y + 10.0, panel_y)
	_popup.position = Vector2(panel_x, panel_y)

	_header.position = Vector2(12.0, 7.0)
	_header.size = Vector2(popup_width - 24.0, 36.0)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_row.position = Vector2(12.0, 46.0)
	_mode_row.size = Vector2(popup_width - 24.0, 38.0)
	_grid_scroll.position = Vector2(12.0, 90.0)
	_grid_scroll.size = Vector2(popup_width - 24.0, maxf(56.0, popup_height - 188.0))
	_grid.custom_minimum_size.x = popup_width - 24.0
	_action_row.position = Vector2(12.0, popup_height - 88.0)
	_action_row.size = Vector2(popup_width - 24.0, 38.0)
	_status_label.position = Vector2(12.0, popup_height - 47.0)
	_status_label.size = Vector2(popup_width - 24.0, 19.0)
	_keyboard_hint.position = Vector2(12.0, popup_height - 25.0)
	_keyboard_hint.size = Vector2(popup_width - 24.0, 16.0)


func _set_accessibility_label(control: Control, accessible_name: String) -> void:
	for property: Dictionary in control.get_property_list():
		if str(property.get("name", "")) == "accessibility_name":
			control.set("accessibility_name", accessible_name)
			return


func _flat_style(background: Color, outline: Color, radius: int, outline_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = outline
	style.set_border_width_all(outline_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 8.0
	style.content_margin_top = 4.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 4.0
	return style
