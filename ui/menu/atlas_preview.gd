extends Control

signal back_requested
signal launch_requested(scene_path: String)

const DESIGN_SIZE := Vector2(1280.0, 720.0)
const MAP_VIEW_SIZE := Vector2(950.0, 720.0)
const WORLD_SIZE := Vector2(1550.0, 720.0)
const MAP_SCROLL_MIN_X := 0.0
const MAP_SCROLL_MAX_X := 600.0
const INITIAL_MAP_SCROLL_X := 600.0
const MAP_PAN_STEP := 160.0
const DRAG_THRESHOLD := 12.0
const CATALOG = preload("res://ui/menu/atlas_catalog.gd")
const PIN_SCENE := preload("res://ui/menu/atlas_map_pin.tscn")
const POSTCARD_SCENE_PATH := "res://ui/menu/atlas_postcard.tscn"

@export_file("*.json") var catalog_path: String = CATALOG.DEFAULT_PATH

@onready var design_canvas: Control = $DesignCanvas
@onready var map_viewport: Control = $DesignCanvas/MapViewport
@onready var landscape: Sprite2D = $DesignCanvas/Landscape
@onready var world_map: Control = $DesignCanvas/MapViewport/WorldMap
@onready var back_button: TextureButton = $DesignCanvas/BackButton
@onready var back_focus_ring: Panel = $DesignCanvas/BackButton/FocusRing
@onready var drag_hint: TextureRect = $DesignCanvas/DragHint

var selected_destination_id: StringName = &""
var destination_order: Array[StringName] = []
var map_scroll_min_x: float:
	get:
		return MAP_SCROLL_MIN_X
var map_scroll_max_x: float:
	get:
		return MAP_SCROLL_MAX_X
var map_scroll_x: float:
	get:
		return _map_scroll_x

var _map_scroll_x := INITIAL_MAP_SCROLL_X
var catalog := CATALOG.new()
var _postcard: Control
var _pin_nodes: Dictionary = {}
var _pin_tips_world: Dictionary = {}
var _pointer_down := false
var _pointer_dragging := false
var _pointer_press_local := Vector2.ZERO
var _scroll_at_pointer_press := INITIAL_MAP_SCROLL_X
var _interaction_enabled := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	back_button.accessibility_name = "Back"
	back_button.accessibility_description = "Return to the title screen."
	back_button.tooltip_text = "Back to title"
	drag_hint.set("accessibility_name", "Drag to explore")
	drag_hint.set("accessibility_description", "Drag or swipe across the map to explore the illustrated world.")
	back_button.pressed.connect(_on_back_pressed)
	back_button.focus_entered.connect(_show_back_focus_ring)
	back_button.focus_exited.connect(_hide_back_focus_ring)
	get_viewport().size_changed.connect(_fit_design_canvas)
	resized.connect(_fit_design_canvas)
	catalog.read_catalog(catalog_path)
	_setup_postcard()
	_setup_pins()
	if destination_order.is_empty():
		if is_instance_valid(_postcard):
			_postcard.hide()
	else:
		var initial_id: StringName = catalog.default_id
		if not _pin_nodes.has(initial_id):
			initial_id = destination_order[0]
		_set_selected_destination(initial_id)
	_update_focus_links()
	map_viewport.focus_mode = Control.FOCUS_ALL
	_fit_design_canvas()
	_apply_map_scroll()


func _setup_postcard() -> void:
	var packed_scene := load(POSTCARD_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Missing atlas postcard scene: %s" % POSTCARD_SCENE_PATH)
		return
	_postcard = packed_scene.instantiate() as Control
	_postcard.name = "Postcard"
	_postcard.position = Vector2(MAP_VIEW_SIZE.x, 0.0)
	_postcard.size = DESIGN_SIZE - Vector2(MAP_VIEW_SIZE.x, 0.0)
	design_canvas.add_child(_postcard)
	if _postcard.has_signal("launch_requested"):
		_postcard.connect("launch_requested", _on_postcard_launch_requested)


func _setup_pins() -> void:
	for raw_id in catalog.destinations.keys():
		var id := StringName(raw_id)
		var record: Dictionary = catalog.destinations[id]
		var pin := PIN_SCENE.instantiate() as Button
		pin.name = String(id).to_pascal_case() + "Pin"
		pin.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		world_map.add_child(pin)
		pin.call("configure", record)
		var position: Array = record["position"]
		var tip_world := Vector2(float(position[0]), float(position[1]))
		var tip_offset: Vector2 = pin.get("tip_offset")
		pin.position = tip_world - tip_offset
		pin.connect("destination_activated", _on_pin_activated)
		pin.focus_entered.connect(_on_pin_focus_entered.bind(id))
		_pin_nodes[id] = pin
		_pin_tips_world[id] = tip_world
		destination_order.append(id)


func _fit_design_canvas() -> void:
	if not is_node_ready() or size.x <= 0.0 or size.y <= 0.0:
		return
	var fit_scale := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	design_canvas.size = DESIGN_SIZE
	design_canvas.scale = Vector2.ONE * fit_scale
	design_canvas.position = (size - DESIGN_SIZE * fit_scale) * 0.5


func fit_to_visible_area() -> void:
	_fit_design_canvas()


func focus_back() -> void:
	back_button.grab_focus()


func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled
	back_button.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	back_button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	map_viewport.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	for pin in _pin_nodes.values():
		pin.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		pin.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	if is_instance_valid(_postcard):
		var launch_button := _postcard.get_node_or_null("LaunchButton") as BaseButton
		if launch_button != null:
			launch_button.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
			launch_button.focus_mode = Control.FOCUS_ALL if enabled and _launch_is_enabled() else Control.FOCUS_NONE
	if enabled:
		_update_focus_links()


func get_pin_center_screen(destination_id: StringName) -> Vector2:
	var pin := _pin_nodes.get(destination_id) as Control
	if pin == null:
		return Vector2(-1.0, -1.0)
	return pin.get_global_transform_with_canvas() * (pin.size * 0.5)


func get_pin_tip_screen(destination_id: StringName) -> Vector2:
	if not _pin_tips_world.has(destination_id):
		return Vector2(-1.0, -1.0)
	return map_to_screen(_pin_tips_world[destination_id])


func map_to_screen(world_position: Vector2) -> Vector2:
	return world_map.get_global_transform_with_canvas() * world_position


func _set_selected_destination(destination_id: StringName) -> void:
	if not _pin_nodes.has(destination_id):
		return
	selected_destination_id = destination_id
	for id in _pin_nodes:
		_pin_nodes[id].call("set_selected", id == destination_id)
	if is_instance_valid(_postcard):
		var record: Variant = catalog.destinations.get(destination_id)
		if record is Dictionary:
			_postcard.call("present", record)
			_postcard.show()
	_update_focus_links()


func _on_pin_activated(destination_id: StringName) -> void:
	_set_selected_destination(destination_id)
	_reveal_focused_pin(destination_id)


func _on_pin_focus_entered(destination_id: StringName) -> void:
	if _pointer_down:
		return
	_set_selected_destination(destination_id)
	_reveal_focused_pin(destination_id)


func _reveal_focused_pin(destination_id: StringName) -> void:
	var pin := _pin_nodes.get(destination_id) as Control
	if pin == null:
		return
	var pin_left := pin.position.x - _map_scroll_x
	var pin_right := pin_left + pin.size.x
	var margin := 22.0
	if pin_left < margin:
		_set_map_scroll(pin.position.x - margin)
	elif pin_right > MAP_VIEW_SIZE.x - margin:
		_set_map_scroll(pin.position.x + pin.size.x - MAP_VIEW_SIZE.x + margin)


func _update_focus_links() -> void:
	if destination_order.is_empty():
		var empty_target := back_button
		back_button.focus_neighbor_right = back_button.get_path_to(empty_target)
		back_button.focus_neighbor_bottom = back_button.get_path_to(empty_target)
		return
	var selected_pin := _pin_nodes.get(selected_destination_id) as Control
	if selected_pin == null:
		selected_pin = map_viewport
	back_button.focus_neighbor_right = back_button.get_path_to(selected_pin)
	back_button.focus_neighbor_bottom = back_button.get_path_to(selected_pin)
	back_button.focus_neighbor_left = back_button.get_path_to(back_button)
	back_button.focus_neighbor_top = back_button.get_path_to(back_button)
	back_button.focus_next = back_button.get_path_to(selected_pin)
	back_button.focus_previous = back_button.get_path_to(back_button)
	if not is_instance_valid(_postcard):
		return
	var launch_button := _postcard.get_node_or_null("LaunchButton") as BaseButton
	if launch_button == null:
		return
	var launch_enabled := _launch_is_enabled()
	launch_button.focus_mode = Control.FOCUS_ALL if launch_enabled else Control.FOCUS_NONE
	for id in _pin_nodes:
		var pin := _pin_nodes[id] as Control
		for action in [&"ui_left", &"ui_right", &"ui_up", &"ui_down"]:
			var neighbor_id := _neighbor_pin_id(id, action)
			var neighbor: Control = _pin_nodes.get(neighbor_id) as Control if neighbor_id != &"" else null
			if action == &"ui_right" and id == selected_destination_id and launch_enabled:
				neighbor = launch_button
			if neighbor == null:
				neighbor = map_viewport
			_set_focus_neighbor(pin, action, neighbor)
		var order_index := destination_order.find(id)
		var next_id := destination_order[posmod(order_index + 1, destination_order.size())]
		var previous_id := destination_order[posmod(order_index - 1, destination_order.size())]
		var next_node: Control = launch_button if id == selected_destination_id and launch_enabled else _pin_nodes[next_id]
		var previous_node: Control = _pin_nodes[previous_id]
		pin.focus_next = pin.get_path_to(next_node)
		pin.focus_previous = pin.get_path_to(previous_node)
	launch_button.focus_neighbor_left = launch_button.get_path_to(selected_pin)
	launch_button.focus_neighbor_top = launch_button.get_path_to(selected_pin)
	launch_button.focus_neighbor_right = launch_button.get_path_to(map_viewport)
	launch_button.focus_neighbor_bottom = launch_button.get_path_to(map_viewport)
	launch_button.focus_previous = launch_button.get_path_to(selected_pin)
	launch_button.focus_next = launch_button.get_path_to(back_button)
	map_viewport.focus_neighbor_left = map_viewport.get_path_to(map_viewport)
	map_viewport.focus_neighbor_right = map_viewport.get_path_to(map_viewport)
	map_viewport.focus_neighbor_top = map_viewport.get_path_to(map_viewport)
	map_viewport.focus_neighbor_bottom = map_viewport.get_path_to(map_viewport)


func _set_focus_neighbor(control: Control, action: StringName, neighbor: Control) -> void:
	var path := control.get_path_to(neighbor)
	match action:
		&"ui_left": control.focus_neighbor_left = path
		&"ui_right": control.focus_neighbor_right = path
		&"ui_up": control.focus_neighbor_top = path
		&"ui_down": control.focus_neighbor_bottom = path


func _neighbor_pin_id(current_id: StringName, action: StringName) -> StringName:
	if not _pin_tips_world.has(current_id):
		return &""
	var origin: Vector2 = _pin_tips_world[current_id]
	var best_id: StringName = &""
	var best_score := INF
	for candidate_id in _pin_tips_world:
		if candidate_id == current_id:
			continue
		var delta: Vector2 = _pin_tips_world[candidate_id] - origin
		var is_in_direction := (
			(action == &"ui_left" and delta.x < -1.0)
			or (action == &"ui_right" and delta.x > 1.0)
			or (action == &"ui_up" and delta.y < -1.0)
			or (action == &"ui_down" and delta.y > 1.0)
		)
		if not is_in_direction:
			continue
		var primary := absf(delta.x) if action in [&"ui_left", &"ui_right"] else absf(delta.y)
		var secondary := absf(delta.y) if action in [&"ui_left", &"ui_right"] else absf(delta.x)
		var score := primary + secondary * 1.5
		if score < best_score:
			best_score = score
			best_id = candidate_id
	return best_id


func _input(event: InputEvent) -> void:
	if not _interaction_enabled:
		return
	if event is InputEventMouseButton:
		if _handle_map_mouse_button(event):
			return
	if event is InputEventMouseMotion:
		if _handle_map_mouse_motion(event):
			return
	if event.is_action_pressed(&"ui_cancel") and not (event is InputEventKey and event.echo):
		get_viewport().set_input_as_handled()
		back_requested.emit()
		return
	_handle_navigation_action(event)


func _handle_map_mouse_button(event: InputEventMouseButton) -> bool:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return false
	var map_point := _screen_to_map_viewport(event.position)
	var inside_map := Rect2(Vector2.ZERO, MAP_VIEW_SIZE).has_point(map_point)
	if event.pressed:
		if event.canceled or not inside_map:
			return false
		_pointer_down = true
		_pointer_dragging = false
		_pointer_press_local = map_point
		_scroll_at_pointer_press = _map_scroll_x
		return false
	if not _pointer_down:
		return false
	var did_drag := _pointer_dragging
	if did_drag or event.canceled:
		_cancel_pressed_pins()
		get_viewport().set_input_as_handled()
	_pointer_down = false
	_pointer_dragging = false
	return did_drag or event.canceled


func _handle_map_mouse_motion(event: InputEventMouseMotion) -> bool:
	if not _pointer_down:
		return false
	var map_point := _screen_to_map_viewport(event.position)
	var delta := map_point - _pointer_press_local
	if not _pointer_dragging and delta.length() >= DRAG_THRESHOLD:
		_pointer_dragging = true
		_cancel_pressed_pins()
		map_viewport.grab_focus()
	if not _pointer_dragging:
		return false
	_set_map_scroll(_scroll_at_pointer_press - delta.x)
	get_viewport().set_input_as_handled()
	return true


func _screen_to_map_viewport(screen_point: Vector2) -> Vector2:
	return map_viewport.get_global_transform_with_canvas().affine_inverse() * screen_point


func _cancel_pressed_pins() -> void:
	for pin in _pin_nodes.values():
		if pin is BaseButton:
			pin.set_pressed_no_signal(false)
	if back_button.button_pressed:
		back_button.set_pressed_no_signal(false)


func _handle_navigation_action(event: InputEvent) -> void:
	var direction: StringName = &""
	for action in [&"ui_left", &"ui_right", &"ui_up", &"ui_down"]:
		if event.is_action_pressed(action) and not (event is InputEventKey and event.echo):
			direction = action
			break
	var focus_owner := get_viewport().gui_get_focus_owner()
	if direction == &"":
		if event.is_action_pressed(&"ui_accept") and focus_owner == map_viewport:
			var selected_pin := _pin_nodes.get(selected_destination_id) as Control
			if selected_pin != null:
				selected_pin.grab_focus()
				get_viewport().set_input_as_handled()
		return
	if focus_owner == back_button:
		if direction in [&"ui_right", &"ui_down"]:
			_focus_selected_pin()
		else:
			map_viewport.grab_focus()
			_pan_from_direction(direction)
		get_viewport().set_input_as_handled()
		return
	var focused_pin_id := _focused_pin_id(focus_owner)
	if focused_pin_id != &"":
		if direction == &"ui_right" and focused_pin_id == selected_destination_id and _launch_is_enabled():
			_postcard.get_node("LaunchButton").grab_focus()
		else:
			var neighbor_id := _neighbor_pin_id(focused_pin_id, direction)
			if neighbor_id != &"":
				(_pin_nodes[neighbor_id] as Control).grab_focus()
			else:
				map_viewport.grab_focus()
				_pan_from_direction(direction)
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(_postcard) and focus_owner == _postcard.get_node_or_null("LaunchButton"):
		if direction in [&"ui_left", &"ui_up"]:
			_focus_selected_pin()
		else:
			map_viewport.grab_focus()
			_pan_from_direction(direction)
		get_viewport().set_input_as_handled()
		return
	if focus_owner == map_viewport:
		_pan_from_direction(direction)
		get_viewport().set_input_as_handled()


func _focused_pin_id(focus_owner: Control) -> StringName:
	for id in _pin_nodes:
		if _pin_nodes[id] == focus_owner:
			return id
	return &""


func _focus_selected_pin() -> void:
	var pin := _pin_nodes.get(selected_destination_id) as Control
	if pin != null:
		pin.grab_focus()


func _pan_from_direction(action: StringName) -> void:
	if action == &"ui_left":
		_set_map_scroll(_map_scroll_x - MAP_PAN_STEP)
	elif action == &"ui_right":
		_set_map_scroll(_map_scroll_x + MAP_PAN_STEP)


func _set_map_scroll(value: float) -> void:
	_map_scroll_x = clampf(value, MAP_SCROLL_MIN_X, MAP_SCROLL_MAX_X)
	_apply_map_scroll()


func _apply_map_scroll() -> void:
	if is_instance_valid(world_map):
		world_map.position.x = -_map_scroll_x
		landscape.position.x = -_map_scroll_x


func _launch_is_enabled() -> bool:
	if not is_instance_valid(_postcard):
		return false
	var launch_button := _postcard.get_node_or_null("LaunchButton") as BaseButton
	return launch_button != null and not launch_button.disabled and not _selected_scene_path().is_empty()


func _selected_scene_path() -> String:
	var record: Variant = catalog.destinations.get(selected_destination_id)
	if not record is Dictionary:
		return ""
	return CATALOG.launch_scene(record)


func _on_postcard_launch_requested() -> void:
	if not _launch_is_enabled():
		return
	launch_requested.emit(_selected_scene_path())


func _on_back_pressed() -> void:
	back_requested.emit()


func _show_back_focus_ring() -> void:
	back_focus_ring.show()


func _hide_back_focus_ring() -> void:
	back_focus_ring.hide()
