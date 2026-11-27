extends Control

signal resume_requested
signal toggle_touch_requested
signal toggle_inspector_requested

enum Page { GEAR, MAP, JOURNAL, OPTIONS }

const DESKTOP_SIZE := Vector2(1280.0, 720.0)
const MOBILE_SIZE := Vector2(923.0, 426.0)
const JOURNAL_FONT: Font = preload("res://ui/menu/berry_journal_font.tres")
const SCARF_PREVIEW_SCRIPT := preload("res://ui/menu/journal_scarf_preview.gd")
const SCARF_ICON_PREVIEW_SCRIPT := preload("res://ui/menu/journal_scarf_icon_preview.gd")
const SETTINGS_SCRIPT := preload("res://ui/menu/journal_settings.gd")
const CATEGORY_TABS_SCRIPT := preload("res://ui/menu/journal_category_tabs.gd")
const LevelProgressProvider := preload("res://ui/hud/journal_level_progress_provider.gd")

const DESKTOP_ART_PATHS := [
	"res://ui/menu/art/pause_journal/desktop_gear.png",
	"res://ui/menu/art/pause_journal/desktop_map.png",
	"res://ui/menu/art/pause_journal/desktop_journal.png",
	"res://ui/menu/art/pause_journal/desktop_options.png",
]
const MOBILE_ART_PATHS := [
	"res://ui/menu/art/pause_journal/mobile_gear.png",
	"res://ui/menu/art/pause_journal/mobile_map.png",
	"res://ui/menu/art/pause_journal/mobile_journal.png",
	"res://ui/menu/art/pause_journal/mobile_options.png",
]
const DESKTOP_STAMP_FILLED := "res://ui/menu/art/pause_journal/journal_stamp_filled_desktop.png"
const DESKTOP_STAMP_EMPTY := "res://ui/menu/art/pause_journal/journal_stamp_empty_desktop.png"
const MOBILE_STAMP_FILLED := "res://ui/menu/art/pause_journal/journal_stamp_filled_mobile.png"
const MOBILE_STAMP_EMPTY := "res://ui/menu/art/pause_journal/journal_stamp_empty_mobile.png"
const GEAR_TITLES := ["Peach Scarf", "Dive Goggles", "Lantern"]
const GEAR_DESCRIPTIONS := [
	"Glide while falling.",
	"Automatically deploys while Chibi swims.",
	"Bring the lantern to Pip.",
]

# Centers of the painted rims, in spread artwork coordinates.
const DESKTOP_GEAR_RIMS: Array[Rect2] = [
	Rect2(192, 257, 187, 162),
	Rect2(393, 260, 185, 158),
	Rect2(191, 431, 187, 147),
]
const MOBILE_GEAR_RIMS: Array[Rect2] = [
	Rect2(148, 88, 137, 134),
	Rect2(303, 90, 132, 133),
	Rect2(148, 242, 136, 133),
]

const INK := Color("#4f1939")
const HOVER_FILL := Color(1.0, 0.97, 0.86, 0.22)
const FOCUS_EDGE := Color("#9c427e")

var _mobile := false
var _active_page := Page.GEAR
var _touch_enabled := false
var _inspector_enabled := false

var _design_canvas: Control
var _background: TextureRect
var _tab_buttons: Array[Button] = []
var _resume_button: Button

var _gear_overlay: Control
var _gear_preview: Control
var _scarf_icon_preview: Control
var _gear_details_title: Label
var _gear_details_body: Label
var _selected_gear := 0
var _gear_buttons: Array[Button] = []
var _gear_selection: Panel
var _show_keyboard_focus := false


var _map_overlay: Control
var _map_title_label: Label
var _map_route_label: Label
var _map_start_label: Label

var _journal_overlay: Control
var _berry_count_label: Label
var _journal_area_label: Label
var _pip_field_note_label: Label
var _stamp_container: Control
var _stamp_textures: Array[Texture2D] = []

var _category_tabs: Control
var _settings_control: Control
var _viewport: Viewport
var _level_progress_provider: LevelProgressProvider


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport = get_viewport()
	var journal_theme := Theme.new()
	journal_theme.default_font = JOURNAL_FONT
	journal_theme.default_font_size = 22
	journal_theme.set_color("font_color", "Label", INK)
	journal_theme.set_color("font_color", "Button", INK)
	theme = journal_theme
	_build_canvas()
	_build_gear_page()
	_build_map_page()
	_build_journal_page()
	_build_settings_page()
	_build_navigation()
	if not _viewport.size_changed.is_connected(_fit_canvas):
		_viewport.size_changed.connect(_fit_canvas)
	_update_content()
	_fit_canvas()
	call_deferred("_focus_active_tab")


func _exit_tree() -> void:
	if _viewport != null and _viewport.size_changed.is_connected(_fit_canvas):
		_viewport.size_changed.disconnect(_fit_canvas)
	if _level_progress_provider != null and _level_progress_provider.progress_changed.is_connected(_on_level_progress_changed):
		_level_progress_provider.progress_changed.disconnect(_on_level_progress_changed)


## Set the layout before first display, and refresh the data when reopening.
func configure(mobile: bool) -> void:
	_mobile = mobile
	if not is_node_ready():
		return
	if _settings_control != null and _settings_control.has_method("configure"):
		_settings_control.call("configure", _mobile)
	_fit_canvas()
	_update_content()
	_focus_active_tab.call_deferred()


## The gameplay HUD supplies the active level's explicit progress provider.
func bind_level_progress_provider(provider: LevelProgressProvider) -> void:
	if _level_progress_provider == provider:
		return
	if _level_progress_provider != null and _level_progress_provider.progress_changed.is_connected(_on_level_progress_changed):
		_level_progress_provider.progress_changed.disconnect(_on_level_progress_changed)
	_level_progress_provider = provider
	if _level_progress_provider != null and not _level_progress_provider.progress_changed.is_connected(_on_level_progress_changed):
		_level_progress_provider.progress_changed.connect(_on_level_progress_changed)
	if _journal_overlay != null:
		_update_content()


## Forward current HUD toggles so the Options controls guide shows live state.
func set_hud_state(touch_enabled: bool, inspector_enabled: bool) -> void:
	_touch_enabled = touch_enabled
	_inspector_enabled = inspector_enabled
	if _settings_control != null and _settings_control.has_method("set_hud_state"):
		_settings_control.call("set_hud_state", touch_enabled, inspector_enabled)


## The HUD calls this before resuming, giving an open controls guide first chance to close.
func close_guide() -> bool:
	if _active_page != Page.OPTIONS or _settings_control == null:
		return false
	if not _settings_control.has_method("close_guide"):
		return false
	return bool(_settings_control.call("close_guide"))


func _build_canvas() -> void:
	_design_canvas = Control.new()
	_design_canvas.name = "DesignCanvas"
	_design_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_design_canvas.position = Vector2.ZERO
	_design_canvas.size = DESKTOP_SIZE
	add_child(_design_canvas)

	_background = TextureRect.new()
	_background.name = "JournalArtwork"
	_background.position = Vector2.ZERO
	_background.size = DESKTOP_SIZE
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_SCALE
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_design_canvas.add_child(_background)


func _build_gear_page() -> void:
	_gear_overlay = _new_overlay("GearContent")
	_gear_preview = SCARF_PREVIEW_SCRIPT.new() as Control
	_gear_preview.name = "ScarfPreview"
	_gear_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gear_overlay.add_child(_gear_preview)

	_scarf_icon_preview = SCARF_ICON_PREVIEW_SCRIPT.new() as Control
	_scarf_icon_preview.name = "ScarfIconPreview"
	_scarf_icon_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gear_overlay.add_child(_scarf_icon_preview)

	_gear_details_title = _new_label(_gear_overlay, "GearDetailsTitle", 27)
	_gear_details_body = _new_label(_gear_overlay, "GearDetailsBody", 20)
	_gear_details_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var scarf_button := _new_button("ScarfItemButton", _gear_overlay, "Preview Peach Scarf")
	scarf_button.pressed.connect(_select_gear.bind(0))
	_gear_buttons.append(scarf_button)
	var dive_button := _new_button("DiveGearItemButton", _gear_overlay, "Preview dive goggles")
	dive_button.pressed.connect(_select_gear.bind(1))
	_gear_buttons.append(dive_button)
	var lantern_button := _new_button("LanternItemButton", _gear_overlay, "Preview petal lantern")
	lantern_button.pressed.connect(_select_gear.bind(2))
	_gear_buttons.append(lantern_button)
	for button in _gear_buttons:
		_connect_dashed_outline(button, false)

	_gear_selection = Panel.new()
	_gear_selection.name = "GearSelection"
	_gear_selection.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gear_overlay.add_child(_gear_selection)


func _build_journal_page() -> void:
	_journal_overlay = _new_overlay("JournalContent")
	_berry_count_label = _new_label(_journal_overlay, "BerryCountLabel", 27)
	_berry_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_berry_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_journal_area_label = _new_label(_journal_overlay, "JournalAreaLabel", 18)
	_journal_area_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_journal_area_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pip_field_note_label = _new_label(_journal_overlay, "PipFieldNoteLabel", 27)
	_pip_field_note_label.text = "Pip Field Note"
	_stamp_container = Control.new()
	_stamp_container.name = "BerryStamps"
	_stamp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_journal_overlay.add_child(_stamp_container)


func _build_map_page() -> void:
	_map_overlay = _new_overlay("MapContent")
	_map_title_label = _new_label(_map_overlay, "MapTitleLabel", 40)
	_map_title_label.text = "Woodland Field Guide"
	_map_route_label = _new_label(_map_overlay, "MapRouteLabel", 27)
	_map_route_label.text = "Pip’s lantern route"
	_map_route_label.position = Vector2(672, 452)
	_map_route_label.size = Vector2(397, 46)
	_map_start_label = _new_label(_map_overlay, "MapStartLabel", 22)
	_map_start_label.text = "Trail start"
	_map_start_label.position = Vector2(735, 529)
	_map_start_label.size = Vector2(104, 42)



func _build_settings_page() -> void:
	_settings_control = SETTINGS_SCRIPT.new() as Control
	_settings_control.name = "SettingsPage"
	_settings_control.mouse_filter = Control.MOUSE_FILTER_STOP
	_design_canvas.add_child(_settings_control)
	if _settings_control.has_signal("toggle_touch_requested"):
		_settings_control.connect("toggle_touch_requested", _forward_touch_toggle)
	if _settings_control.has_signal("toggle_inspector_requested"):
		_settings_control.connect("toggle_inspector_requested", _forward_inspector_toggle)
	if _settings_control.has_method("set_modal_host"):
		_settings_control.call("set_modal_host", self)
	var categories := CATEGORY_TABS_SCRIPT.new() as Control
	categories.name = "CategoryTabs"
	_settings_control.add_child(categories)
	_category_tabs = categories
	if categories.has_signal("section_selected"):
		categories.connect("section_selected", _on_category_section_selected)
	if _settings_control.has_method("configure"):
		_settings_control.call("configure", _mobile)
	if _settings_control.has_method("set_hud_state"):
		_settings_control.call("set_hud_state", _touch_enabled, _inspector_enabled)


func _build_navigation() -> void:
	var names := ["GearTabButton", "MapTabButton", "JournalTabButton", "OptionsTabButton"]
	var accessible_names := ["Gear", "Map", "Journal", "Options"]
	for index in Page.size():
		var tab := _new_button(names[index], _design_canvas, accessible_names[index])
		tab.pressed.connect(_on_tab_pressed.bind(index))
		_connect_dashed_outline(tab, true)
		_tab_buttons.append(tab)
	_resume_button = _new_button("ResumeButton", _design_canvas, "Resume game")
	_resume_button.pressed.connect(_on_resume_pressed)

	for index in _tab_buttons.size():
		var button := _tab_buttons[index]
		button.focus_neighbor_left = button.get_path_to(_tab_buttons[(index - 1 + _tab_buttons.size()) % _tab_buttons.size()])
		button.focus_neighbor_right = button.get_path_to(_tab_buttons[(index + 1) % _tab_buttons.size()])
	_tab_buttons[0].focus_neighbor_bottom = _tab_buttons[0].get_path_to(_gear_buttons[0])
	_gear_buttons[0].focus_neighbor_top = _gear_buttons[0].get_path_to(_tab_buttons[0])
	_gear_buttons[0].focus_neighbor_right = _gear_buttons[0].get_path_to(_gear_buttons[1])
	_gear_buttons[1].focus_neighbor_left = _gear_buttons[1].get_path_to(_gear_buttons[0])
	_gear_buttons[1].focus_neighbor_bottom = _gear_buttons[1].get_path_to(_gear_buttons[2])
	_gear_buttons[2].focus_neighbor_top = _gear_buttons[2].get_path_to(_gear_buttons[0])
	_gear_buttons[2].focus_neighbor_right = _gear_buttons[2].get_path_to(_gear_buttons[1])
	_gear_buttons[2].focus_neighbor_left = _gear_buttons[2].get_path_to(_gear_buttons[0])
	_tab_buttons.back().focus_neighbor_right = _tab_buttons.back().get_path_to(_resume_button)
	_resume_button.focus_neighbor_left = _resume_button.get_path_to(_tab_buttons.back())
	_resume_button.focus_neighbor_right = _resume_button.get_path_to(_tab_buttons[0])


func _new_overlay(overlay_name: String) -> Control:
	var overlay := Control.new()
	overlay.name = overlay_name
	overlay.position = Vector2.ZERO
	overlay.size = DESKTOP_SIZE
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_design_canvas.add_child(overlay)
	return overlay


func _new_label(parent: Control, label_name: String, font_size: int) -> Label:
	var label := Label.new()
	label.name = label_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", INK)
	label.add_theme_font_size_override("font_size", font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label


func _new_button(button_name: String, parent: Control, accessible_name: String) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = ""
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", _highlight_style(HOVER_FILL, Color.TRANSPARENT, 0, 17))
	button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	var focus := _highlight_style(Color.TRANSPARENT, FOCUS_EDGE, 2, 12)
	focus.set_expand_margin_all(-5.0)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_color", Color.TRANSPARENT)
	button.add_theme_color_override("font_hover_color", Color.TRANSPARENT)
	button.add_theme_color_override("font_pressed_color", Color.TRANSPARENT)
	button.add_theme_color_override("font_focus_color", Color.TRANSPARENT)
	_set_accessibility_name(button, accessible_name)
	parent.add_child(button)
	return button


func _connect_dashed_outline(button: Button, is_tab: bool) -> void:
	var empty := StyleBoxEmpty.new()
	button.add_theme_stylebox_override("focus", empty)
	button.add_theme_stylebox_override("hover", empty)
	button.focus_entered.connect(button.queue_redraw)
	button.focus_exited.connect(button.queue_redraw)
	button.mouse_entered.connect(button.queue_redraw)
	button.mouse_exited.connect(button.queue_redraw)
	button.draw.connect(_draw_dashed_outline.bind(button, is_tab))


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var keyboard_focus := _show_keyboard_focus
	if event is InputEventMouseMotion or (event is InputEventMouseButton and event.pressed):
		keyboard_focus = false
	elif event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev") \
			or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right") \
			or event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		keyboard_focus = true
	if keyboard_focus == _show_keyboard_focus:
		return
	_show_keyboard_focus = keyboard_focus
	for button in _gear_buttons + _tab_buttons:
		button.queue_redraw()


func _draw_dashed_outline(button: Button, is_tab: bool) -> void:
	var emphasized := not button.disabled and (button.has_focus() if _show_keyboard_focus else button.is_hovered())
	if not is_tab and not emphasized:
		return
	var outline := _trace_tab_stitching(button) if is_tab else _trace_gear_rim(button.size)
	var thread_color := FOCUS_EDGE if emphasized else Color("#fff0da")
	var perimeter := outline.get_baked_length()
	var count := maxi(1, roundi(perimeter / (12.0 if is_tab else 11.0)))
	var pitch := perimeter / count
	for dash in count:
		var points := PackedVector2Array()
		for sample in range(4):
			points.append(outline.sample_baked(pitch * (dash + 0.18 + 0.19 * sample)))
		if is_tab:
			button.draw_polyline(points, Color("#8e513d66"), 4.2, true)
		button.draw_polyline(points, thread_color, 2.6, true)


func _trace_tab_stitching(button: Button) -> Curve2D:
	# Trace the thread along the tab cutout, leaving more cloth above Gear
	# and to the left of Journal. Hover only changes the thread color.
	var index := _tab_buttons.find(button)
	var outer_radius := Vector2(19.0, 19.0) if _mobile else Vector2(22.8, 24.37)
	var top := 4.0 if _mobile else 0.0
	var binding := 49.0 if _mobile else 56.0
	var edge_inset := 8.0 if _mobile else 9.0
	var left_inset := edge_inset + (3.0 if index == Page.JOURNAL else 0.0)
	var top_inset := edge_inset + (3.0 if index == Page.GEAR else 0.0)
	var left_center := Vector2(outer_radius.x, top + outer_radius.y)
	var right_center := Vector2(button.size.x - outer_radius.x, top + outer_radius.y)
	var left_radius := outer_radius - Vector2(left_inset, top_inset)
	var right_radius := outer_radius - Vector2(edge_inset, top_inset)
	var outline := Curve2D.new()
	outline.bake_interval = 1.0
	outline.add_point(Vector2(left_inset, binding))
	for step in range(13):
		var angle := PI + step * PI / 24.0
		outline.add_point(left_center + Vector2.from_angle(angle) * left_radius)
	for step in range(13):
		var angle := -PI * 0.5 + step * PI / 24.0
		outline.add_point(right_center + Vector2.from_angle(angle) * right_radius)
	outline.add_point(Vector2(button.size.x - edge_inset, binding))
	return outline


func _trace_gear_rim(size: Vector2) -> Curve2D:
	var inset := 6.0
	var rect := Rect2(Vector2.ZERO, size).grow(-inset)
	var radius := _gear_corner_radius() - inset
	var centers := [
		rect.position + Vector2(radius, radius),
		Vector2(rect.end.x - radius, rect.position.y + radius),
		rect.end - Vector2(radius, radius),
		Vector2(rect.position.x + radius, rect.end.y - radius),
	]
	var outline := Curve2D.new()
	outline.bake_interval = 1.0
	for corner in centers.size():
		var start_angle := PI + corner * PI * 0.5
		for step in range(7):
			var angle := start_angle + step * PI / 12.0
			outline.add_point(centers[corner] + Vector2.from_angle(angle) * radius)
	outline.add_point(outline.get_point_position(0))
	return outline


func _gear_corner_radius() -> int:
	return 18 if _mobile else 25


func _highlight_style(fill: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	return style


func _set_accessibility_name(control: Control, accessible_name: String) -> void:
	for property in control.get_property_list():
		if StringName(property.get("name", "")) == &"accessibility_name":
			control.set("accessibility_name", accessible_name)
			return


func _layout_controls() -> void:
	if _design_canvas == null:
		return
	var design_size := MOBILE_SIZE if _mobile else DESKTOP_SIZE
	_design_canvas.size = design_size
	_background.size = design_size
	for overlay in [_gear_overlay, _map_overlay, _journal_overlay]:
		overlay.size = design_size

	if _mobile:
		_gear_preview.position = Vector2(449.0, 52.0)
		_gear_preview.size = Vector2(219.0, 340.0)
		_scarf_icon_preview.position = Vector2(151.0, 94.0)
		_scarf_icon_preview.size = Vector2(130.0, 126.0)
		_gear_details_title.position = Vector2(665.0, 106.0)
		_gear_details_title.size = Vector2(172.0, 43.0)
		_gear_details_title.add_theme_font_size_override("font_size", 21)
		_gear_details_body.position = Vector2(665.0, 151.0)
		_gear_details_body.size = Vector2(172.0, 92.0)
		_gear_details_body.add_theme_font_size_override("font_size", 16)
		_berry_count_label.position = Vector2(130.0, 124.0)
		_berry_count_label.size = Vector2(321.0, 35.0)
		_berry_count_label.add_theme_font_size_override("font_size", 19)
		_journal_area_label.position = Vector2(133.0, 157.0)
		_journal_area_label.size = Vector2(315.0, 25.0)
		_journal_area_label.add_theme_font_size_override("font_size", 14)
		_pip_field_note_label.position = Vector2(505.0, 297.0)
		_pip_field_note_label.size = Vector2(326.0, 34.0)
		_pip_field_note_label.add_theme_font_size_override("font_size", 19)
		_stamp_container.position = Vector2(130.0, 184.0)
		_stamp_container.size = Vector2(320.0, 145.0)
		_map_title_label.text = "Woodland Field Guide · Lantern Cottage"
		_map_title_label.position = Vector2(146.0, 344.0)
		_map_title_label.size = Vector2(586.0, 38.0)
		_map_title_label.add_theme_font_size_override("font_size", 16)
	else:
		_gear_preview.position = Vector2(738.0, 101.0)
		_gear_preview.size = Vector2(382.0, 354.0)
		_scarf_icon_preview.position = Vector2(201.0, 263.0)
		_scarf_icon_preview.size = Vector2(180.0, 152.0)
		_gear_details_title.position = Vector2(748.0, 462.0)
		_gear_details_title.size = Vector2(316.0, 38.0)
		_gear_details_title.add_theme_font_size_override("font_size", 27)
		_gear_details_body.position = Vector2(750.0, 503.0)
		_gear_details_body.size = Vector2(314.0, 67.0)
		_gear_details_body.add_theme_font_size_override("font_size", 19)
		_berry_count_label.position = Vector2(164.0, 260.0)
		_berry_count_label.size = Vector2(434.0, 43.0)
		_berry_count_label.add_theme_font_size_override("font_size", 28)
		_journal_area_label.position = Vector2(164.0, 302.0)
		_journal_area_label.size = Vector2(434.0, 28.0)
		_journal_area_label.add_theme_font_size_override("font_size", 18)
		_pip_field_note_label.position = Vector2(654.0, 479.0)
		_pip_field_note_label.size = Vector2(431.0, 48.0)
		_pip_field_note_label.add_theme_font_size_override("font_size", 27)
		_stamp_container.position = Vector2(163.0, 331.0)
		_stamp_container.size = Vector2(435.0, 236.0)
		_map_title_label.text = "Woodland Field Guide"
		_map_title_label.position = Vector2(214.0, 130.0)
		_map_title_label.size = Vector2(391.0, 70.0)
		_map_title_label.add_theme_font_size_override("font_size", 34)

	_map_route_label.visible = not _mobile
	_map_start_label.visible = not _mobile
	var gear_rims := MOBILE_GEAR_RIMS if _mobile else DESKTOP_GEAR_RIMS
	for index in _gear_buttons.size():
		var button := _gear_buttons[index]
		button.position = gear_rims[index].position
		button.size = gear_rims[index].size
	var selection_style := _highlight_style(Color.TRANSPARENT, Color("#ad529d"), 3, _gear_corner_radius())
	selection_style.set_expand_margin_all(1.0)
	_gear_selection.add_theme_stylebox_override("panel", selection_style)

	for index in _tab_buttons.size():
		var rect := _tab_rect(index)
		_tab_buttons[index].position = rect.position
		_tab_buttons[index].size = rect.size
	var resume_rect := Rect2(950.0, 609.0, 292.0, 90.0)
	if _mobile:
		resume_rect = Rect2(742.0, 342.0, 169.0, 68.0)
	_resume_button.position = resume_rect.position
	_resume_button.size = resume_rect.size
	if _settings_control != null:
		_settings_control.position = Vector2(0.0, 64.0) if _mobile else Vector2(168.0, 145.0)
		_settings_control.size = Vector2(923.0, 300.0) if _mobile else Vector2(945.0, 474.0)
	if _category_tabs != null:
		_category_tabs.visible = _mobile and _active_page == Page.OPTIONS
	_update_gear_details()


func _tab_rect(index: int) -> Rect2:
	if _mobile:
		var mobile_rects := [
			Rect2(145.0, 4.0, 156.0, 53.0),
			Rect2(320.0, 4.0, 151.0, 53.0),
			Rect2(491.0, 4.0, 153.0, 53.0),
			Rect2(665.0, 4.0, 156.0, 53.0),
		]
		return mobile_rects[index]
	var desktop_rects := [
		Rect2(277.0, 44.0, 187.0, 59.0),
		Rect2(470.0, 44.0, 181.0, 59.0),
		Rect2(657.0, 44.0, 184.0, 59.0),
		Rect2(847.0, 44.0, 187.0, 59.0),
	]
	return desktop_rects[index]


func _fit_canvas() -> void:
	if _design_canvas == null or _viewport == null:
		return
	var bounds := _viewport.get_visible_rect()
	var safe_bounds := _safe_view_bounds(bounds)
	var design_size := MOBILE_SIZE if _mobile else DESKTOP_SIZE
	var fit_scale := minf(safe_bounds.size.x / design_size.x, safe_bounds.size.y / design_size.y)
	_design_canvas.scale = Vector2.ONE * fit_scale
	_design_canvas.position = safe_bounds.position + (safe_bounds.size - design_size * fit_scale) * 0.5
	_layout_controls()


func _safe_view_bounds(viewport_bounds: Rect2) -> Rect2:
	if not OS.has_feature("mobile"):
		return viewport_bounds
	var safe_screen_rect := Rect2(DisplayServer.get_display_safe_area())
	if not safe_screen_rect.has_area():
		return viewport_bounds
	var screen_to_viewport := _viewport.get_screen_transform().affine_inverse()
	var window_origin := Vector2(DisplayServer.window_get_position())
	var safe_view_rect := Rect2(
		screen_to_viewport * (safe_screen_rect.position - window_origin),
		screen_to_viewport.basis_xform(safe_screen_rect.size)
	)
	var clipped := viewport_bounds.intersection(safe_view_rect)
	return clipped if clipped.has_area() else viewport_bounds


func _update_content() -> void:
	if _background == null:
		return
	var art_paths: Array = MOBILE_ART_PATHS if _mobile else DESKTOP_ART_PATHS
	_background.texture = load(art_paths[_active_page]) as Texture2D
	_update_page_visibility()
	if _active_page == Page.JOURNAL:
		_update_journal_content()
	else:
		_clear_stamps()
	_update_gear_details()


func _update_page_visibility() -> void:
	if _gear_overlay != null:
		_gear_overlay.visible = _active_page == Page.GEAR
	if _map_overlay != null:
		_map_overlay.visible = _active_page == Page.MAP
	if _journal_overlay != null:
		_journal_overlay.visible = _active_page == Page.JOURNAL
	if _settings_control != null:
		_settings_control.visible = _active_page == Page.OPTIONS
		_settings_control.mouse_filter = Control.MOUSE_FILTER_STOP if _active_page == Page.OPTIONS else Control.MOUSE_FILTER_IGNORE
	if _category_tabs != null:
		_category_tabs.visible = _mobile and _active_page == Page.OPTIONS


func _update_journal_content() -> void:
	var progress := Vector2i.ZERO
	var area_name := LevelProgressProvider.EMPTY_AREA_NAME
	if _level_progress_provider != null:
		progress = _level_progress_provider.get_berry_progress()
		area_name = _level_progress_provider.get_area_name()
	_berry_count_label.text = "%d / %d collected" % [progress.x, progress.y]
	_journal_area_label.text = area_name
	_clear_stamps()
	if progress.y <= 0:
		return
	var filled_path := MOBILE_STAMP_FILLED if _mobile else DESKTOP_STAMP_FILLED
	var empty_path := MOBILE_STAMP_EMPTY if _mobile else DESKTOP_STAMP_EMPTY
	var filled_stamp := load(filled_path) as Texture2D
	var empty_stamp := load(empty_path) as Texture2D
	if filled_stamp == null or empty_stamp == null:
		return
	_stamp_textures = [filled_stamp, empty_stamp]
	var visible_total := mini(progress.y, 8)
	var icon_size := Vector2(82.0, 94.0) if _mobile else Vector2(122.0, 138.0)
	if visible_total > 1:
		icon_size *= 0.65
	var gap := 8.0
	@warning_ignore("integer_division")
	var row_count := (visible_total + 3) / 4
	var top := (_stamp_container.size.y - row_count * icon_size.y - (row_count - 1) * gap) * 0.5
	for index in visible_total:
		@warning_ignore("integer_division")
		var row := index / 4
		var columns := mini(4, visible_total - row * 4)
		var left := (_stamp_container.size.x - columns * icon_size.x - (columns - 1) * gap) * 0.5
		var stamp := TextureRect.new()
		stamp.name = "BerryStamp%d" % (index + 1)
		stamp.texture = filled_stamp if index < progress.x else empty_stamp
		stamp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stamp.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stamp.position = Vector2(left + (index % 4) * (icon_size.x + gap), top + row * (icon_size.y + gap))
		stamp.size = icon_size
		_stamp_container.add_child(stamp)


func _on_level_progress_changed() -> void:
	if _active_page == Page.JOURNAL and _journal_overlay != null and _journal_overlay.is_visible_in_tree():
		_update_journal_content()


func _clear_stamps() -> void:
	if _stamp_container != null:
		for child in _stamp_container.get_children():
			child.queue_free()
	_stamp_textures.clear()


func _update_gear_details() -> void:
	var selected := _gear_buttons[_selected_gear]
	var slot := selected.get_rect()
	_gear_selection.position = slot.position
	_gear_selection.size = slot.size
	_gear_details_title.visible = true
	_gear_details_body.visible = true
	_gear_details_title.text = GEAR_TITLES[_selected_gear]
	_gear_details_body.text = GEAR_DESCRIPTIONS[_selected_gear]
	if _gear_preview != null and _gear_preview.has_method("set_selected_item"):
		_gear_preview.call("set_selected_item", _selected_gear)


func _select_gear(index: int) -> void:
	_selected_gear = clampi(index, 0, 2)
	_update_gear_details()


func _on_tab_pressed(page: int) -> void:
	_active_page = page
	_update_content()
	_layout_controls()
	call_deferred("_focus_active_tab")


func _focus_active_tab() -> void:
	if _tab_buttons.size() > 0:
		_tab_buttons[_active_page].grab_focus()


func _on_category_section_selected(section: Variant) -> void:
	if _settings_control != null and _settings_control.has_method("set_section"):
		_settings_control.call("set_section", section)


func _on_resume_pressed() -> void:
	resume_requested.emit()


func _forward_touch_toggle() -> void:
	toggle_touch_requested.emit()


func _forward_inspector_toggle() -> void:
	toggle_inspector_requested.emit()
