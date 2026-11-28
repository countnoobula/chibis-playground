class_name FirstStepsValleyController
extends Node3D

## Sends Chibi back to the trailhead if they fall out of the valley.

const LevelProgressProvider := preload("res://ui/hud/journal_level_progress_provider.gd")
const ReliefSurfaceShader := preload("res://levels/first_steps/terrain/materials/relief_surface_shader.gd")

@export var runner_path: NodePath = NodePath("ChibiRunner")
@export var safe_spawn_path: NodePath = NodePath("SafeSpawn")
@export_range(-100.0, 0.0, 0.5) var fall_limit_y: float = -24.0

@export_group("Player-centered terrain relief")
@export var relief_enabled: bool = true
@export_range(1, 6, 1) var relief_tessellation_level: int = 6

var _runner: ParkourController
var _safe_spawn: Marker3D
var _journal_progress_provider: LevelProgressProvider


func _enter_tree() -> void:
	var creek_terrain := get_node_or_null("CreekTerrain")
	if creek_terrain != null:
		creek_terrain.set("collision_mode", Terrain3DCollision.FULL_GAME)


func _ready() -> void:
	_journal_progress_provider = LevelProgressProvider.new("First Steps Valley")
	_runner = get_node_or_null(runner_path) as ParkourController
	_safe_spawn = get_node_or_null(safe_spawn_path) as Marker3D
	if _runner == null:
		push_error("First Steps Valley could not find its ChibiRunner.")
	if _safe_spawn == null:
		push_error("First Steps Valley could not find its SafeSpawn marker.")
	_configure_terrain_relief()
	if _runner != null and _runner.touch_hud != null:
		_runner.touch_hud.bind_journal_level_progress(_journal_progress_provider)


func _configure_terrain_relief() -> void:
	var creek_terrain := get_node_or_null("CreekTerrain") as Terrain3D
	if creek_terrain == null:
		push_error("First Steps Valley could not find its CreekTerrain.")
		return
	if _runner != null:
		creek_terrain.clipmap_target = _runner

	# Keep native displacement off on mobile until it has been checked on devices.
	var is_mobile_device := OS.get_name() in ["Android", "iOS"]
	var use_relief := relief_enabled and not is_mobile_device
	var level := relief_tessellation_level if use_relief else 0
	creek_terrain.tessellation_level = level
	if use_relief:
		var terrain_material := creek_terrain.material as Terrain3DMaterial
		if terrain_material == null:
			push_error("First Steps Valley could not configure terrain relief lighting: CreekTerrain has no Terrain3DMaterial.")
			return
		if ReliefSurfaceShader.install(terrain_material):
			terrain_material.set_shader_param("relief_lighting_strength", 1.0)


func _physics_process(_delta: float) -> void:
	if _runner == null or _safe_spawn == null:
		return
	if _runner.global_position.y > fall_limit_y:
		return
	_runner.reset_for_respawn(_safe_spawn.global_position)
	_runner.global_rotation = _safe_spawn.global_rotation
	if _runner.camera_ctrl != null:
		_runner.camera_ctrl.reset_after_teleport()
