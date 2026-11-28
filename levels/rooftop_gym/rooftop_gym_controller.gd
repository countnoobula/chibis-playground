class_name RooftopGymController
extends Node3D

const RunnerWindField3D := preload("res://features/runner/wind_field_3d.gd")

## Handles quick zone teleports (keys 1-5) and fall-out-of-world safety respawn in the gym.

const LevelProgressProvider := preload("res://ui/hud/journal_level_progress_provider.gd")
const CLOUD_DRIFT_PERIOD_SECONDS := 300.0

@export var player_path: NodePath = NodePath("ChibiRunner")
@export var journal_area_name := "Rooftop Parkour Gym"
@export var zone_spawns: Array[Vector3] = [
	Vector3(0.0, 0.1, 6.0),     # Zone 1: Flow, Vaults & Slide Gates
	Vector3(-18.0, 0.1, 2.0),   # Zone 2: Wall-Run Corridor & Beveled Ledge Tower
	Vector3(13.74, 0.1, 1.0),   # Zone 3: Approach to the first wall grip
	Vector3(0.0, 0.1, -22.0),   # Zone 4: Aerial Apparatus Circuit
	Vector3(24.0, 0.35, -16.0), # Zone 5: Dry approach to the basin
]

var strawberries_collected: int:
	get:
		return _journal_progress_provider.get_berry_progress().x if _journal_progress_provider != null else 0
var strawberries_total: int:
	get:
		return _journal_progress_provider.get_berry_progress().y if _journal_progress_provider != null else 0

var _player: ParkourController
var _pending_zone := -1
var _journal_progress_provider: LevelProgressProvider


func _ready() -> void:
	_update_cloud_phase()
	get_tree().process_frame.connect(_update_cloud_phase)
	_journal_progress_provider = LevelProgressProvider.new(journal_area_name)
	for pickup in get_tree().get_nodes_in_group(&"parkour_pickups"):
		_register_strawberry(pickup)
	get_tree().node_added.connect(_register_strawberry)
	_player = get_node_or_null(player_path) as ParkourController
	if _player != null:
		var reactions := preload("res://features/runner/rooftop_reactions.gd").new()
		reactions.name = "RooftopReactions"
		add_child(reactions)
		reactions.setup(_player)
		_player.expression_director.requests_cleared.connect(reactions.reset)
		var picker := preload("res://ui/emoji_picker.gd").new()
		picker.name = "EmojiPicker"
		add_child(picker)
		picker.setup(_player)
		_player.wind_field = get_node_or_null("WindTunnel") as RunnerWindField3D
		if _player.touch_hud != null:
			_player.touch_hud.bind_journal_level_progress(_journal_progress_provider)
		if OS.get_cmdline_user_args().has("--debug-menu"):
			_add_sky_preview()


func _add_sky_preview() -> void:
	var lighting := preload("res://levels/rooftop_gym/rooftop_celestial_lighting.gd").new()
	lighting.name = "CelestialLighting"
	lighting.setup($WorldEnvironment, $SunLight, $SkyFill, _player.camera_ctrl)
	add_child(lighting)
	var preview := preload("res://levels/rooftop_gym/rooftop_sky_preview.gd").new()
	preview.name = "SkyPreview"
	preview.setup(lighting, _player)
	add_child(preview)


func _update_cloud_phase() -> void:
	# A global float animates the visible sky without dirtying its static radiance.
	var elapsed := Time.get_ticks_msec() * 0.001
	var phase := fposmod(elapsed, CLOUD_DRIFT_PERIOD_SECONDS) * TAU / CLOUD_DRIFT_PERIOD_SECONDS
	RenderingServer.global_shader_parameter_set(&"rooftop_cloud_phase", phase)


func _register_strawberry(node: Node) -> void:
	if node.scene_file_path != "res://features/items/strawberry_pickup.tscn" or not is_ancestor_of(node):
		return
	if not node.is_connected(&"picked_up", _on_strawberry_picked_up):
		_journal_progress_provider.register_strawberry()
		node.connect(&"picked_up", _on_strawberry_picked_up, CONNECT_ONE_SHOT)


func _on_strawberry_picked_up(_picker: PhysicsBody3D) -> void:
	_journal_progress_provider.collect_strawberry()


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	for i in mini(5, zone_spawns.size()):
		if Input.is_action_just_pressed("debug_zone_%d" % (i + 1)):
			_pending_zone = i
	if _pending_zone < 0 and _player.global_position.y < -10.0 and not zone_spawns.is_empty():
		_pending_zone = 0
	if _pending_zone >= 0:
		var index := _pending_zone
		_pending_zone = -1
		_player.reset_for_respawn(to_global(zone_spawns[index]))
		var fall_meter := get_node_or_null("TowerFallMeter")
		if fall_meter != null:
			fall_meter.call("reset_measurement")
		if _player.camera_ctrl != null:
			_player.camera_ctrl.reset_after_teleport()


func teleport_to_zone(index: int) -> void:
	if _player == null or index < 0 or index >= zone_spawns.size():
		return
	_pending_zone = index
