class_name RooftopGymController
extends Node3D

## Handles quick zone teleports (keys 1-5) and fall-out-of-world safety respawn in the gym.

@export var player_path: NodePath = NodePath("ChibiRunner")
@export var zone_spawns: Array[Vector3] = [
	Vector3(0.0, 0.1, 6.0),     # Zone 1: Flow, Vaults & Slide Gates
	Vector3(-18.0, 0.1, 2.0),   # Zone 2: Wall-Run Corridor & Beveled Ledge Tower
	Vector3(13.74, 0.1, 1.0),   # Zone 3: Approach to the first wall grip
	Vector3(0.0, 0.1, -22.0),   # Zone 4: Aerial Apparatus Circuit
	Vector3(24.0, 0.35, -16.0), # Zone 5: Dry approach to the basin
]

var _player: ParkourController
var _pending_zone := -1


func _ready() -> void:
	_player = get_node_or_null(player_path) as ParkourController
	if _player != null:
		_player.wind_tunnel = get_node_or_null("WindTunnel") as RooftopWindTunnel


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
