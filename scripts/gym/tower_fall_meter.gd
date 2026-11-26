extends Node

const SETTLE_TICKS := 4
const DEPTH_EPSILON := 0.003

enum Phase { WAITING, READY, FALLING, SUBMERGING }

@export var player_path: NodePath
@export var launch_marker_path: NodePath
@export var drop_water_path: NodePath
@export var launch_half_size := Vector2(1.1, 0.95)

var last_measurement: Dictionary = {}
var _phase := Phase.WAITING
var _player: ParkourController
var _launch_marker: Node3D
var _drop_water: WaterBody3D
var _previous_feet: Vector3
var _apex_y: float
var _lowest_y: float
var _entry_y: float
var _settle_ticks := 0
var _panel: PanelContainer
var _label: Label


func _ready() -> void:
	process_physics_priority = 40
	_player = get_node_or_null(player_path) as ParkourController
	_launch_marker = get_node_or_null(launch_marker_path) as Node3D
	_drop_water = get_node_or_null(drop_water_path) as WaterBody3D
	_build_readout()
	reset_measurement()


func reset_measurement() -> void:
	_phase = Phase.WAITING
	last_measurement.clear()
	if is_instance_valid(_player):
		_previous_feet = _player.global_position
	_show_readout("")


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_launch_marker) or not is_instance_valid(_drop_water):
		return
	var feet := _player.global_position
	var grounded := _player.is_on_floor()
	match _phase:
		Phase.WAITING, Phase.READY:
			_check_launch(feet, grounded)
		Phase.FALLING:
			_sample_fall(feet, grounded)
		Phase.SUBMERGING:
			_sample_entry(feet, grounded)
	_previous_feet = feet


func _check_launch(feet: Vector3, grounded: bool) -> void:
	if grounded:
		var local_feet := _launch_marker.to_local(feet)
		if absf(local_feet.y) < 0.12 and absf(local_feet.x) <= launch_half_size.x and absf(local_feet.z) <= launch_half_size.y:
			if _phase == Phase.WAITING:
				last_measurement.clear()
				_phase = Phase.READY
				_show_readout("Jump toward the drop pool")
		elif _phase == Phase.READY:
			reset_measurement()
	elif _phase == Phase.READY:
		_phase = Phase.FALLING
		_apex_y = maxf(feet.y, _previous_feet.y)
		_show_readout("")


func _sample_fall(feet: Vector3, grounded: bool) -> void:
	_apex_y = maxf(_apex_y, feet.y)
	var surface := _drop_water.get_surface_height()
	if _previous_feet.y > surface and feet.y <= surface:
		var crossing := _previous_feet.lerp(feet, inverse_lerp(_previous_feet.y, feet.y, surface))
		if not _drop_water.contains_horizontal(crossing):
			reset_measurement()
			return
		_entry_y = surface
		_lowest_y = feet.y
		_settle_ticks = 0
		_phase = Phase.SUBMERGING
	elif grounded:
		reset_measurement()


func _sample_entry(feet: Vector3, grounded: bool) -> void:
	var wants_dive := _player.current_state == "PoolSwim" and _player.chibi_input != null and _player.chibi_input.dive_held
	if wants_dive or not _drop_water.contains_horizontal(feet):
		_publish_result()
		return
	_lowest_y = minf(_lowest_y, feet.y)
	if grounded or feet.y > _previous_feet.y + DEPTH_EPSILON:
		_publish_result()
	elif _previous_feet.y - feet.y <= DEPTH_EPSILON:
		_settle_ticks += 1
		if _settle_ticks >= SETTLE_TICKS:
			_publish_result()
	else:
		_settle_ticks = 0


func _publish_result() -> void:
	var air := maxf(0.0, _apex_y - _entry_y)
	var depth := maxf(0.0, _entry_y - _lowest_y)
	last_measurement = {"air_fall_m": air, "entry_depth_m": depth, "total_fall_m": air + depth}
	_phase = Phase.WAITING
	_show_readout("Air fall %.2f m    •    Entry depth %.2f m    •    Total %.2f m" % [air, depth, air + depth])


func _show_readout(message: String) -> void:
	if is_instance_valid(_panel):
		_panel.visible = not message.is_empty()
		_label.text = message


func _build_readout() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 15
	add_child(layer)
	var anchor := CenterContainer.new()
	layer.add_child(anchor)
	anchor.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	anchor.offset_top = 18.0
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(_panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f5ede5ed")
	style.set_corner_radius_all(14)
	style.content_margin_left = 15
	style.content_margin_right = 15
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", style)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 17)
	_label.add_theme_color_override("font_color", Color("453c49"))
	_panel.add_child(_label)
