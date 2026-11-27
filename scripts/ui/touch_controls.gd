class_name TouchControlsHUD
extends CanvasLayer

## Routes each finger to its starting control for the lifetime of that touch.

const Circle := preload("res://scripts/ui/touch_control_circle.gd")
const DEBUGGER_SCENE := preload("res://addons/godot_state_charts/utilities/state_chart_debugger.tscn")
const PALETTE := preload("res://scripts/gym/rooftop_palette.gd")

enum Role { NONE, MOVE, LOOK, JUMP, SLIDE, PICKUP, GEAR }

const STICK_RANGE := 48.0
const STICK_DEADZONE := 7.0
const ACTION_ROLES := [Role.JUMP, Role.SLIDE, Role.PICKUP]
const Journal := preload("res://scenes/menu/pause_journal.gd")

@export var chibi_input: ChibiInput
@export var state_chart: StateChart

var touch_visible := false
var menu_open := false

var _mobile := false
var _previously_paused := false
var _root: Control
var _touch_root: Control
var _menu_root: Control
var _pause_backdrop: TextureRect
var _pause_backdrop_scrim: ColorRect
var _journal: Journal
var _journal_pointer := preload("res://scripts/ui/menu_touch_pointer.gd").new()
var _prior_quit_on_back := true
var _pause_capture_generation := 0
var _pause_capture_pending := false
var _pause_capture_root_was_visible := true
var _recapture_after_focus := false
var _status_label: Label
var _state_debugger: Control
var _stick: Circle
var _circles: Dictionary[int, Circle] = {}
var _owners: Dictionary[int, int] = {}
var _stick_origin := Vector2.ZERO
var _bounds := Rect2()
var _layout_scale := 1.0
var _state_name := ""
var _wall_climb_active := false
var _scarf_available := false
var _scarf_active := false


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mobile = OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--mobile-menu")
	_root = _full_control(self, "HUDRoot")
	_touch_root = _full_control(_root, "TouchRoot")
	_stick = _make_circle(_touch_root, "Joystick", "", "stick", PALETTE.MINT)
	_stick.held = true
	_stick.hide()
	_circles[Role.JUMP] = _make_circle(_touch_root, "Jump", "Jump", "jump", PALETTE.MINT)
	_circles[Role.SLIDE] = _make_circle(_touch_root, "Slide", "Slide", "slide", PALETTE.LAVENDER)
	_circles[Role.PICKUP] = _make_circle(_touch_root, "Pickup", "Pick Up", "pickup", PALETTE.PEACH)
	set_pickup_available(false)
	_circles[Role.GEAR] = _make_circle(_root, "PauseGear", "", "gear", PALETTE.LAVENDER)
	_circles[Role.GEAR].hit_padding = 10.0
	_build_debugger()
	_build_menu()
	get_viewport().size_changed.connect(_layout)
	_layout()
	set_touch_visible(_mobile)


func _exit_tree() -> void:
	if menu_open:
		get_tree().paused = _previously_paused
		get_tree().quit_on_go_back = _prior_quit_on_back


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and menu_open:
		_handle_menu_back()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_reset_touches()
		if _pause_capture_pending:
			_cancel_pause_capture()
			_recapture_after_focus = menu_open
	if (what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN) and _recapture_after_focus and menu_open:
		_recapture_after_focus = false
		_start_pause_capture()


func _full_control(parent: Node, control_name: String) -> Control:
	var control := Control.new()
	control.name = control_name
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(control)
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return control


func _make_circle(parent: Control, control_name: String, caption: String, symbol: String, accent: Color) -> Circle:
	var control := Circle.new()
	control.name = control_name
	control.caption = caption
	control.symbol = symbol
	control.accent = accent
	parent.add_child(control)
	return control


func _build_debugger() -> void:
	_status_label = Label.new()
	_status_label.name = "StateReadout"
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.add_theme_color_override("font_outline_color", Circle.INK)
	_status_label.add_theme_constant_override("outline_size", 4)
	_status_label.hide()
	_root.add_child(_status_label)

	_state_debugger = DEBUGGER_SCENE.instantiate() as Control
	_state_debugger.hide()
	_root.add_child(_state_debugger)
	_state_debugger.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	bind_state_chart(state_chart)


func _build_menu() -> void:
	_menu_root = _full_control(_root, "PauseMenu")
	_menu_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_root.hide()
	_pause_backdrop_scrim = ColorRect.new()
	_pause_backdrop_scrim.name = "BackdropScrim"
	_pause_backdrop_scrim.color = Color(Circle.INK, 0.56)
	_pause_backdrop_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_root.add_child(_pause_backdrop_scrim)
	_pause_backdrop_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_backdrop = TextureRect.new()
	_pause_backdrop.name = "GameplayBackdrop"
	_pause_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pause_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_pause_backdrop.modulate = Color(0.56, 0.56, 0.56, 1.0)
	_menu_root.add_child(_pause_backdrop)
	_pause_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_root.move_child(_pause_backdrop_scrim, 0)
	_menu_root.move_child(_pause_backdrop, 1)


func _start_pause_capture() -> void:
	if not menu_open or _root == null or _pause_backdrop == null:
		return
	_cancel_pause_capture()
	_pause_capture_generation += 1
	var capture_generation := _pause_capture_generation
	_pause_backdrop.texture = null
	_pause_backdrop_scrim.show()
	if DisplayServer.get_name() == "headless":
		return
	_pause_capture_pending = true
	_pause_capture_root_was_visible = _root.visible
	_root.hide()
	_capture_pause_backdrop(capture_generation)


func _capture_pause_backdrop(capture_generation: int) -> void:
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	if capture_generation != _pause_capture_generation or not _pause_capture_pending:
		return
	_pause_capture_pending = false
	if menu_open:
		var viewport := get_viewport()
		var image := viewport.get_texture().get_image()
		if image != null and not image.is_empty():
			var snapshot := ImageTexture.create_from_image(_make_bokeh_blurred_snapshot(image))
			_pause_backdrop.texture = snapshot
			_pause_backdrop_scrim.hide()
	_root.visible = _pause_capture_root_was_visible


func _make_bokeh_blurred_snapshot(image: Image) -> Image:
	var original_size := image.get_size()
	# Bound CPU work to a small image; the full-rect TextureRect scales it to cover.
	var uniform_scale := minf(0.125, 256.0 / float(maxi(original_size.x, original_size.y)))
	var reduced_size := Vector2i(
		maxi(1, roundi(float(original_size.x) * uniform_scale)),
		maxi(1, roundi(float(original_size.y) * uniform_scale))
	)
	var reduced: Image = image.duplicate()
	reduced.resize(reduced_size.x, reduced_size.y, Image.INTERPOLATE_LANCZOS)
	var softened := Image.create(reduced_size.x, reduced_size.y, false, Image.FORMAT_RGBA8)
	for y in range(reduced_size.y):
		for x in range(reduced_size.x):
			var total := Color(0.0, 0.0, 0.0, 0.0)
			var brightest := 0.0
			for offset_y in range(-1, 2):
				for offset_x in range(-1, 2):
					var sample: Color = reduced.get_pixel(
						clampi(x + offset_x, 0, reduced_size.x - 1),
						clampi(y + offset_y, 0, reduced_size.y - 1)
					)
					var weight := 4.0 if offset_x == 0 and offset_y == 0 else 2.0 if offset_x == 0 or offset_y == 0 else 1.0
					total += sample * weight
					brightest = maxf(brightest, maxf(sample.r, maxf(sample.g, sample.b)))
			var color := total / 16.0
			var bokeh_glow := maxf(brightest - 0.78, 0.0) * 0.12
			color.r = clampf(color.r + bokeh_glow, 0.0, 1.0)
			color.g = clampf(color.g + bokeh_glow * 0.88, 0.0, 1.0)
			color.b = clampf(color.b + bokeh_glow * 0.96, 0.0, 1.0)
			color.a = 1.0
			softened.set_pixel(x, y, color)
	return softened


func _cancel_pause_capture() -> void:
	if not _pause_capture_pending:
		return
	_pause_capture_generation += 1
	_pause_capture_pending = false
	if _root != null:
		_root.visible = _pause_capture_root_was_visible


func _prepare_journal() -> void:
	if _journal == null:
		_journal = Journal.new()
		_journal.name = "Journal"
		_journal.configure(_mobile)
		_menu_root.add_child(_journal)
		_journal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_journal.resume_requested.connect(set_menu_open.bind(false))
		_journal.toggle_touch_requested.connect(func() -> void: set_touch_visible(not touch_visible))
		_journal.toggle_inspector_requested.connect(_toggle_state_debugger)
	else:
		_journal.configure(_mobile)
	_refresh_menu_labels()


func _layout() -> void:
	_reset_touches()
	_bounds = get_viewport().get_visible_rect()
	var safe_px := Rect2(DisplayServer.get_display_safe_area()) if _mobile else Rect2()
	if safe_px.has_area():
		var to_viewport := get_viewport().get_screen_transform().affine_inverse()
		var window_origin := Vector2(DisplayServer.window_get_position())
		var safe_local := Rect2(to_viewport * (safe_px.position - window_origin), to_viewport.basis_xform(safe_px.size))
		var clipped := _bounds.intersection(safe_local)
		if clipped.has_area():
			_bounds = clipped

	_layout_scale = clampf(minf(_bounds.size.x / 520.0, _bounds.size.y / 450.0), 0.55, 1.0)
	var corner := _bounds.end
	_place_circle(_circles[Role.JUMP], corner + Vector2(-82, -82) * _layout_scale, 104.0)
	_place_circle(_circles[Role.SLIDE], corner + Vector2(-202, -74) * _layout_scale, 90.0)
	_place_circle(_circles[Role.PICKUP], corner + Vector2(-76, -200) * _layout_scale, 82.0)
	_place_circle(_circles[Role.GEAR], Vector2(corner.x, _bounds.position.y) + Vector2(-55, 52) * _layout_scale, 62.0)
	_status_label.position = _bounds.position + Vector2(16, 16)
	var inspector_width := minf(350.0, _bounds.size.x * 0.46)
	var inspector_height := minf(298.0, _bounds.size.y * 0.43)
	_state_debugger.position = Vector2(corner.x - inspector_width - 16.0, _bounds.position.y + 96.0)
	_state_debugger.size = Vector2(inspector_width, inspector_height)


func _place_circle(circle: Circle, center: Vector2, diameter: float) -> void:
	circle.size = Vector2.ONE * diameter * _layout_scale
	circle.position = center - circle.size * 0.5


func bind_state_chart(chart: StateChart) -> void:
	state_chart = chart
	if _state_debugger != null and state_chart != null:
		var was_visible := _state_debugger.visible
		_state_debugger.call("debug_node", state_chart)
		_state_debugger.visible = was_visible


func set_touch_visible(show_controls: bool) -> void:
	if touch_visible != show_controls:
		_reset_touches()
	touch_visible = show_controls
	if chibi_input != null:
		chibi_input.set_touch_mode(touch_visible)
	_sync_visibility()
	_refresh_menu_labels()


func set_menu_open(open_menu: bool) -> void:
	if menu_open == open_menu:
		return
	_reset_touches()
	menu_open = open_menu
	if chibi_input != null:
		chibi_input.set_menu_open(menu_open)
	_sync_visibility()
	if menu_open:
		_previously_paused = get_tree().paused
		get_tree().paused = true
		_prior_quit_on_back = get_tree().quit_on_go_back
		get_tree().quit_on_go_back = false
		_prepare_journal()
		_start_pause_capture()
	else:
		_cancel_pause_capture()
		_recapture_after_focus = false
		_journal.close_guide()
		get_tree().quit_on_go_back = _prior_quit_on_back
		get_tree().paused = _previously_paused


func _sync_visibility() -> void:
	_touch_root.visible = touch_visible and not menu_open
	_circles[Role.GEAR].visible = (_mobile or touch_visible) and not menu_open
	_menu_root.visible = menu_open


func _toggle_state_debugger() -> void:
	if not OS.get_cmdline_user_args().has("--debug-menu"):
		return
	_state_debugger.visible = not _state_debugger.visible
	_status_label.visible = _state_debugger.visible
	_refresh_menu_labels()


func _refresh_menu_labels() -> void:
	if _journal != null:
		_journal.set_hud_state(touch_visible, _state_debugger.visible)


func update_hud(state_name: String, flow_level: float, speed_mps: float, wall_climb: bool = false, scarf_available: bool = false, scarf_active: bool = false) -> void:
	if _status_label == null:
		return
	if _status_label.visible:
		_status_label.text = "%s  ·  Flow %d%%  ·  %.1f m/s" % [state_name, roundi(flow_level * 100.0), speed_mps]
	if scarf_active and not _scarf_active and _has_normal_jump_action(state_name) and _owners.values().has(Role.JUMP) and is_instance_valid(chibi_input):
		# Keep the owning finger attached to Jump until it lifts, but cancel its held/queued input.
		# It cannot also trigger the newly displayed Drop action when the finger lifts.
		chibi_input.set_touch_jump(false, true)
		_circles[Role.JUMP].held = false
		_circles[Role.JUMP].queue_redraw()
	if state_name == _state_name and wall_climb == _wall_climb_active and scarf_available == _scarf_available and scarf_active == _scarf_active:
		return
	_state_name = state_name
	_wall_climb_active = wall_climb
	_scarf_available = scarf_available
	_scarf_active = scarf_active
	var jump := ["Jump", "jump"]
	var slide := ["Slide", "slide"]
	match state_name:
		"PoolSwim":
			jump = ["Rise", "swim_up"]
			slide = ["Dive", "dive"]
		"LedgeHang":
			jump = ["Climb Up", "ledge"]
			slide = ["Drop", "drop"]
		"RopeLine", "ZipLine":
			jump = ["Jump Off", "off"]
			slide = ["Drop", "drop"]
		"Climbing":
			if wall_climb:
				jump = ["Leap", "wall_leap"]
				slide = ["Drop", "drop"]
			else:
				jump = ["Drop", "drop"]
		"RopeSwing":
			jump = ["Jump Off", "off"]
	var normal_jump_action: bool = jump[1] == "jump"
	if scarf_active and normal_jump_action:
		jump = ["Drop", "drop"]
	elif scarf_available and normal_jump_action:
		jump = ["Glide", "parachute"]
	_set_caption(_circles[Role.JUMP], jump[0], jump[1])
	if _circles[Role.JUMP].inactive:
		_circles[Role.JUMP].inactive = false
		_circles[Role.JUMP].queue_redraw()
	_set_caption(_circles[Role.SLIDE], slide[0], slide[1])
	_circles[Role.SLIDE].visible = wall_climb or state_name not in ["Climbing", "RopeSwing"]


func set_pickup_available(available: bool) -> void:
	var button: Circle = _circles.get(Role.PICKUP)
	if button != null:
		button.visible = available


func _has_normal_jump_action(state_name: String) -> bool:
	return state_name not in ["PoolSwim", "LedgeHang", "RopeLine", "ZipLine", "Climbing", "RopeSwing"]


func _set_caption(circle: Circle, caption: String, symbol: String) -> void:
	circle.caption = caption
	circle.symbol = symbol
	circle.queue_redraw()


func _handle_menu_back() -> void:
	if menu_open and _journal.close_guide():
		return
	set_menu_open(not menu_open)


func _input(event: InputEvent) -> void:
	var gamepad_pause: bool = event is InputEventJoypadButton and event.button_index == JOY_BUTTON_START and event.pressed
	if event.is_action_pressed(&"ui_cancel") or gamepad_pause:
		_handle_menu_back()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"toggle_touch"):
		set_touch_visible(not touch_visible)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"toggle_state_debug"):
		_toggle_state_debugger()
		get_viewport().set_input_as_handled()
	elif menu_open:
		if event is InputEventScreenTouch or event is InputEventScreenDrag:
			get_viewport().set_input_as_handled()
			if event.device != InputEvent.DEVICE_ID_EMULATION:
				_journal_pointer.forward(get_viewport(), event)
	elif event is InputEventScreenTouch and _handle_touch(event):
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _handle_drag(event):
		get_viewport().set_input_as_handled()


func _handle_touch(event: InputEventScreenTouch) -> bool:
	if event.canceled or not event.pressed:
		if _owners.has(event.index):
			var role := _owners[event.index]
			_owners.erase(event.index)
			_release_role(role, event.position, event.canceled)
			return true
		return menu_open
	if _owners.has(event.index):
		return true
	var role := _role_at(event.position)
	if role == Role.NONE or role in _owners.values():
		return menu_open
	_owners[event.index] = role
	_press_role(role, event.position)
	return true


func _role_at(point: Vector2) -> int:
	if _circles[Role.GEAR].contains_point(point):
		return Role.GEAR
	if not touch_visible or not _bounds.has_point(point):
		return Role.NONE
	if _state_debugger.visible and _state_debugger.get_global_rect().has_point(point):
		return Role.NONE
	for role in ACTION_ROLES:
		if _circles[role].contains_point(point):
			return role
	if point.x >= _bounds.get_center().x:
		return Role.LOOK
	if point.y >= _bounds.position.y + _bounds.size.y * 0.45:
		return Role.MOVE
	return Role.NONE


func _press_role(role: int, point: Vector2) -> void:
	if _circles.has(role):
		_circles[role].held = true
		_circles[role].queue_redraw()
	if role == Role.MOVE:
		_stick_origin = point
		_place_circle(_stick, point, 144.0)
		_stick.show()
	if chibi_input == null:
		return
	match role:
		Role.JUMP:
			if not _circles[Role.JUMP].inactive:
				chibi_input.set_touch_jump(true)
		Role.SLIDE:
			chibi_input.set_touch_slide(true)
		Role.PICKUP:
			chibi_input.trigger_touch_pickup()


func _release_role(role: int, point: Vector2, canceled: bool) -> void:
	if _circles.has(role):
		_circles[role].held = false
		_circles[role].queue_redraw()
	match role:
		Role.MOVE:
			_stick.hide()
			_stick.stick_offset = Vector2.ZERO
			if chibi_input != null:
				chibi_input.set_touch_move(Vector2.ZERO)
		Role.JUMP:
			if chibi_input != null:
				chibi_input.set_touch_jump(false, canceled)
		Role.SLIDE:
			if chibi_input != null:
				chibi_input.set_touch_slide(false, canceled)
		Role.PICKUP:
			if chibi_input != null and canceled:
				chibi_input.cancel_touch_pickup()
		Role.GEAR:
			if not canceled and _circles[role].contains_point(point):
				set_menu_open(true)

func _handle_drag(event: InputEventScreenDrag) -> bool:
	if not _owners.has(event.index):
		return menu_open
	if chibi_input == null:
		return true
	match _owners[event.index]:
		Role.MOVE:
			var reach := STICK_RANGE * _layout_scale
			var deadzone := STICK_DEADZONE * _layout_scale
			var offset := (event.position - _stick_origin).limit_length(reach)
			var magnitude := clampf(inverse_lerp(deadzone, reach, offset.length()), 0.0, 1.0)
			_stick.stick_offset = offset
			_stick.queue_redraw()
			chibi_input.set_touch_move(offset.normalized() * magnitude)
		Role.LOOK:
			var window_size := DisplayServer.window_get_size()
			var shorter_side := mini(window_size.x, window_size.y)
			var delta := event.screen_relative * (720.0 / shorter_side) if shorter_side > 0 else event.relative
			chibi_input.add_touch_look(delta)
	return true


func _reset_touches() -> void:
	_journal_pointer.reset(get_viewport())
	_owners.clear()
	if _stick != null:
		_stick.stick_offset = Vector2.ZERO
		_stick.hide()
	for circle in _circles.values():
		if circle.held:
			circle.held = false
			circle.queue_redraw()
	if is_instance_valid(chibi_input):
		chibi_input.clear_touch_input()
