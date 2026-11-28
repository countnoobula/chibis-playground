class_name FirstStepsValleyController
extends Node3D

## Sends Chibi back to the trailhead if they fall out of the valley.

const LevelProgressProvider := preload("res://ui/hud/journal_level_progress_provider.gd")
const ReliefSurfaceShader := preload("res://levels/first_steps/terrain/materials/relief_surface_shader.gd")
const WaterCausticSurfaceShader := preload("res://levels/first_steps/terrain/materials/water_caustic_surface_shader.gd")
const WATER_CAUSTIC_RECEIVER_GROUP: StringName = &"water_caustic_receivers"

@export var runner_path: NodePath = NodePath("ChibiRunner")
@export var safe_spawn_path: NodePath = NodePath("SafeSpawn")
@export_range(-100.0, 0.0, 0.5) var fall_limit_y: float = -24.0
@export_group("Water caustics")
@export var water_body_path: NodePath = NodePath("CreekWater")

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
	# The playable valley uses physics for ground queries. Terrain3D's 2×2
	# mouse-picking viewport cannot render the creek's screen-space refraction.
	var mouse_viewport := get_node_or_null("CreekTerrain/MouseViewport") as SubViewport
	if mouse_viewport != null:
		mouse_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_journal_progress_provider = LevelProgressProvider.new("First Steps Valley")
	_runner = get_node_or_null(runner_path) as ParkourController
	_safe_spawn = get_node_or_null(safe_spawn_path) as Marker3D
	if _runner == null:
		push_error("First Steps Valley could not find its ChibiRunner.")
	if _safe_spawn == null:
		push_error("First Steps Valley could not find its SafeSpawn marker.")
	_configure_terrain_relief()
	_configure_water_caustics()
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


func _configure_water_caustics() -> void:
	var creek_terrain := get_node_or_null("CreekTerrain") as Terrain3D
	if creek_terrain == null:
		push_error("First Steps Valley could not find its CreekTerrain for water caustics.")
		return
	var water := get_node_or_null(water_body_path) as WaterBody3D
	if water == null:
		push_error("First Steps Valley could not find its CreekWater body for water caustics.")
		return
	var terrain_material := creek_terrain.material as Terrain3DMaterial
	if terrain_material == null:
		push_error("First Steps Valley CreekTerrain has no Terrain3DMaterial for water caustics.")
		return
	if not WaterCausticSurfaceShader.install(terrain_material):
		return

	# WaterBody3D owns the shared outline, depth, bounds, and profile uniforms. Registering
	# Terrain3DMaterial through the same receiver API keeps them in sync if the body moves.
	water.register_caustic_receiver(terrain_material)
	var configured_mesh_ids: Dictionary = {}
	for receiver_root in get_tree().get_nodes_in_group(WATER_CAUSTIC_RECEIVER_GROUP):
		if not is_ancestor_of(receiver_root):
			continue
		_configure_caustic_meshes(receiver_root, water, configured_mesh_ids)


func _configure_caustic_meshes(node: Node, water: WaterBody3D, configured_mesh_ids: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var instance_id := mesh_instance.get_instance_id()
		if not configured_mesh_ids.has(instance_id):
			configured_mesh_ids[instance_id] = true
			var existing_material := mesh_instance.material_override
			if existing_material == null and mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 0:
				existing_material = mesh_instance.get_surface_override_material(0)
				if existing_material == null:
					existing_material = mesh_instance.mesh.surface_get_material(0)
			var already_uses_water_caustics := false
			if existing_material is ShaderMaterial:
				var existing_shader := (existing_material as ShaderMaterial).shader
				already_uses_water_caustics = existing_shader != null and existing_shader.code.contains("water_caustic_light(")
			if already_uses_water_caustics:
				water.register_caustic_receiver(existing_material)
			else:
				water.configure_caustic_receiver(mesh_instance)
	for child in node.get_children():
		_configure_caustic_meshes(child, water, configured_mesh_ids)


func _physics_process(_delta: float) -> void:
	if _runner == null or _safe_spawn == null:
		return
	if _runner.global_position.y > fall_limit_y:
		return
	_runner.reset_for_respawn(_safe_spawn.global_position)
	_runner.global_rotation = _safe_spawn.global_rotation
	if _runner.camera_ctrl != null:
		_runner.camera_ctrl.reset_after_teleport()
