class_name RooftopGymController
extends Node3D

const RunnerWindField3D := preload("res://features/runner/wind_field_3d.gd")

## Handles quick zone teleports (keys 1-5) and fall-out-of-world safety respawn in the gym.

const LevelProgressProvider := preload("res://ui/hud/journal_level_progress_provider.gd")

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
	_journal_progress_provider = LevelProgressProvider.new(journal_area_name)
	for pickup in get_tree().get_nodes_in_group(&"parkour_pickups"):
		_register_strawberry(pickup)
	get_tree().node_added.connect(_register_strawberry)
	_player = get_node_or_null(player_path) as ParkourController
	if _player != null:
		var picker := preload("res://ui/emoji_picker.gd").new()
		picker.name = "EmojiPicker"
		add_child(picker)
		picker.setup(_player)
		_player.wind_field = get_node_or_null("WindTunnel") as RunnerWindField3D
		if _player.touch_hud != null:
			_player.touch_hud.bind_journal_level_progress(_journal_progress_provider)


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
