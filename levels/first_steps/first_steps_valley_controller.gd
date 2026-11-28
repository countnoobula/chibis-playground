class_name FirstStepsValleyController
extends Node3D

## Sends Chibi back to the latest safe valley checkpoint if they fall out.

const LevelProgressProvider := preload("res://ui/hud/journal_level_progress_provider.gd")
const SectionRetryPrompt := preload("res://ui/hud/section_retry_prompt.gd")
const ReliefSurfaceShader := preload("res://levels/first_steps/terrain/materials/relief_surface_shader.gd")
const WaterCausticSurfaceShader := preload("res://levels/first_steps/terrain/materials/water_caustic_surface_shader.gd")
const WATER_CAUSTIC_RECEIVER_GROUP: StringName = &"water_caustic_receivers"
const SECTION_CHECKPOINT_GROUP: StringName = &"first_steps_section_checkpoints"
const DEFAULT_CAMERA_PITCH := -0.22
const SECTION_CAMERA_PITCH := -0.56

@export var runner_path: NodePath = NodePath("ChibiRunner")
@export var safe_spawn_path: NodePath = NodePath("SafeSpawn")
@export_range(-100.0, 0.0, 0.5) var fall_limit_y: float = -24.0
@export_group("Section retry")
@export var section_checkpoint_group: StringName = SECTION_CHECKPOINT_GROUP
@export var developer_section_start_path: NodePath = NodePath("DryCrossing/DeveloperStart")
@export var developer_section_start_enabled: bool = true
@export_group("Water caustics")
@export var water_body_path: NodePath = NodePath("CreekWater")

@export_group("Player-centered terrain relief")
@export var relief_enabled: bool = true
@export_range(1, 6, 1) var relief_tessellation_level: int = 6

var _runner: ParkourController
var _safe_spawn: Marker3D
var _developer_section_start: Node3D
var _active_checkpoint_transform := Transform3D.IDENTITY
var _active_checkpoint_name := "Trailhead"
var _active_checkpoint_camera_pitch := DEFAULT_CAMERA_PITCH
var _retry_prompt: SectionRetryPrompt
var _journal_progress_provider: LevelProgressProvider
var active_checkpoint_name: String:
	get:
		return _active_checkpoint_name
var active_checkpoint_transform: Transform3D:
	get:
		return _active_checkpoint_transform


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
	_developer_section_start = get_node_or_null(developer_section_start_path) as Node3D
	if _runner == null:
		push_error("First Steps Valley could not find its ChibiRunner.")
	if _safe_spawn == null:
		push_error("First Steps Valley could not find its SafeSpawn marker.")
	else:
		_active_checkpoint_transform = _safe_spawn.global_transform
	_bind_section_checkpoints()
	_build_retry_prompt()
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
	if OS.is_debug_build() and developer_section_start_enabled and Input.is_action_just_pressed(&"debug_zone_1"):
		start_at_developer_section()
	if _runner.global_position.y > fall_limit_y:
		return
	retry_section()


## Teleport to the current section checkpoint and clear movement, traversal, and camera state.
func retry_section() -> void:
	if _runner == null:
		return
	_teleport_runner(_active_checkpoint_transform, _active_checkpoint_camera_pitch)


## Developer-only shortcut used to inspect the dry crossing from its authored start marker.
func start_at_developer_section() -> void:
	if not developer_section_start_enabled or not OS.is_debug_build() or _runner == null:
		return
	if _developer_section_start == null:
		_developer_section_start = get_node_or_null(developer_section_start_path) as Node3D
	if _developer_section_start == null:
		return
	_activate_section_checkpoint(_developer_section_start.global_transform, "Dry Crossing", SECTION_CAMERA_PITCH)
	_teleport_runner(_active_checkpoint_transform, _active_checkpoint_camera_pitch)


func _bind_section_checkpoints() -> void:
	for node in get_tree().get_nodes_in_group(section_checkpoint_group):
		if not (node is Area3D) or not is_ancestor_of(node):
			continue
		var checkpoint_area := node as Area3D
		checkpoint_area.body_entered.connect(_on_section_checkpoint_body_entered.bind(checkpoint_area))


func _on_section_checkpoint_body_entered(body: Node3D, checkpoint_area: Area3D) -> void:
	if body != _runner:
		return
	var spawn := checkpoint_area.get_node_or_null("Spawn") as Node3D
	var spawn_node: Node3D = spawn if spawn != null else checkpoint_area
	var section_name := str(checkpoint_area.get_meta("section_name", "Dry Crossing")).strip_edges()
	if section_name.is_empty():
		section_name = "Dry Crossing"
	_activate_section_checkpoint(spawn_node.global_transform, section_name, SECTION_CAMERA_PITCH)


func _activate_section_checkpoint(
		spawn_transform: Transform3D,
		section_name: String,
		camera_pitch: float = SECTION_CAMERA_PITCH
) -> void:
	_active_checkpoint_transform = spawn_transform
	_active_checkpoint_name = section_name
	_active_checkpoint_camera_pitch = camera_pitch
	if _retry_prompt != null:
		_retry_prompt.show_checkpoint(section_name)


func _teleport_runner(spawn_transform: Transform3D, camera_pitch: float) -> void:
	_runner.reset_for_respawn(spawn_transform.origin)
	var spawn_rotation := spawn_transform.basis.get_euler()
	_runner.global_rotation = spawn_rotation
	_runner.reset_physics_interpolation()
	if _runner.camera_ctrl != null:
		_runner.camera_ctrl.yaw = spawn_rotation.y
		_runner.camera_ctrl.pitch = camera_pitch
		_runner.camera_ctrl.reset_after_teleport()


func _build_retry_prompt() -> void:
	if _runner == null or _runner.touch_hud == null:
		return
	# Keep this in the main HUD so it works with either desktop or touch controls.
	# Place it just behind the pause journal, which covers it while the game is paused.
	var hud_root := _runner.touch_hud.get_node_or_null("HUDRoot") as Control
	if hud_root == null:
		return
	_retry_prompt = SectionRetryPrompt.new()
	_retry_prompt.name = "SectionRetryPrompt"
	hud_root.add_child(_retry_prompt)
	var pause_menu := hud_root.get_node_or_null("PauseMenu")
	if pause_menu != null:
		hud_root.move_child(_retry_prompt, pause_menu.get_index())
	_retry_prompt.retry_requested.connect(retry_section)
