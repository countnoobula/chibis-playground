class_name JournalScarfIconPreview
extends Control

## Transparent 3D thumbnail of the actual in-game scarf canopy and fabric shader.

const CANOPY_SCENE: PackedScene = preload("res://assets/characters/chibi_scarf_canopy.glb")
const SCARF_SHADER: Shader = preload("res://shaders/character/scarf_glider.gdshader")
const PRINT_TEXTURE: Texture2D = preload("res://assets/characters/chibi_scarf_print.png")
const WEAVE_TEXTURE: Texture2D = preload("res://assets/characters/chibi_scarf_weave.png")

const PREVIEW_MARGIN := 1.12
const MIN_PREVIEW_SIZE := Vector2(88.0, 72.0)
const CAMERA_FOV_DEGREES := 38.0

var _preview_container: SubViewportContainer
var _preview_viewport: SubViewport
var _preview_camera: Camera3D
var _canopy_root: Node3D
var _canopy_mesh: MeshInstance3D
var _canopy_width := 2.24
var _canopy_depth := 1.26


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = MIN_PREVIEW_SIZE
	_create_preview_viewport()
	_create_preview_world()
	_create_canopy()
	resized.connect(_sync_preview_size)
	visibility_changed.connect(_sync_render_mode)
	_sync_preview_size()
	_sync_render_mode()


func _create_preview_viewport() -> void:
	_preview_container = SubViewportContainer.new()
	_preview_container.name = "TransparentScarfThumbnail"
	_preview_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Match the SubViewport size to this Control in _sync_preview_size; leaving
	# stretch off avoids Godot's redundant stretch-resize warning.
	_preview_container.stretch = false
	add_child(_preview_container)
	_preview_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_preview_viewport = SubViewport.new()
	_preview_viewport.name = "ScarfViewport"
	_preview_viewport.transparent_bg = true
	_preview_viewport.own_world_3d = true
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_viewport.msaa_3d = Viewport.MSAA_2X
	_preview_container.add_child(_preview_viewport)


func _create_preview_world() -> void:
	var world_root := Node3D.new()
	world_root.name = "PreviewWorld"
	_preview_viewport.add_child(world_root)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#fff0df")
	environment.ambient_light_energy = 0.78
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	world_root.add_child(world_environment)

	var key_light := DirectionalLight3D.new()
	key_light.name = "WarmKeyLight"
	key_light.light_color = Color("#fff0df")
	key_light.light_energy = 1.0
	key_light.rotation_degrees = Vector3(-38.0, -28.0, 0.0)
	key_light.shadow_enabled = false
	world_root.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.name = "CreamFillLight"
	fill_light.light_color = Color("#e7f1f5")
	fill_light.light_energy = 0.38
	fill_light.rotation_degrees = Vector3(-18.0, 145.0, 0.0)
	fill_light.shadow_enabled = false
	world_root.add_child(fill_light)

	_preview_camera = Camera3D.new()
	_preview_camera.name = "ScarfCamera"
	_preview_camera.fov = CAMERA_FOV_DEGREES
	_preview_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_preview_camera.near = 0.05
	_preview_camera.far = 16.0
	_preview_camera.current = true
	world_root.add_child(_preview_camera)


func _create_canopy() -> void:
	_canopy_root = CANOPY_SCENE.instantiate() as Node3D
	if _canopy_root == null:
		push_error("Journal scarf icon could not instantiate the in-game canopy.")
		return
	_canopy_root.name = "InGamePeachScarf"
	_canopy_root.rotation_degrees = Vector3(-4.0, -8.0, -3.0)
	_preview_viewport.get_node("PreviewWorld").add_child(_canopy_root)
	_canopy_mesh = _find_mesh(_canopy_root)
	if _canopy_mesh == null or _canopy_mesh.mesh == null:
		push_error("Journal scarf icon canopy has no mesh.")
		return

	var bounds := _canopy_mesh.get_aabb()
	_canopy_width = maxf(bounds.size.x, 0.5)
	_canopy_depth = maxf(bounds.size.z, 0.5)
	_canopy_mesh.position -= bounds.get_center()
	_canopy_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_canopy_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

	var material := ShaderMaterial.new()
	material.shader = SCARF_SHADER
	material.set_shader_parameter("chibi_scarf_print", PRINT_TEXTURE)
	material.set_shader_parameter("chibi_scarf_weave", WEAVE_TEXTURE)
	material.set_shader_parameter("deploy_amount", 1.0)
	material.set_shader_parameter("canopy_alpha", 1.0)
	material.set_shader_parameter("cloth_tension", 0.22)
	_canopy_mesh.material_override = material


func _sync_preview_size() -> void:
	if _preview_viewport == null or _preview_camera == null:
		return
	var pixel_size := Vector2i(
		maxi(roundi(size.x), 1),
		maxi(roundi(size.y), 1)
	)
	_preview_viewport.size = pixel_size
	_fit_camera_to_preview(pixel_size)


func _fit_camera_to_preview(pixel_size: Vector2i) -> void:
	var aspect := float(pixel_size.x) / maxf(float(pixel_size.y), 1.0)
	var vertical_half_angle := deg_to_rad(_preview_camera.fov * 0.5)
	var horizontal_half_angle := atan(tan(vertical_half_angle) * aspect)
	var height_distance := _canopy_depth * PREVIEW_MARGIN / (2.0 * tan(vertical_half_angle))
	var width_distance := _canopy_width * PREVIEW_MARGIN / (2.0 * tan(horizontal_half_angle))
	var distance := maxf(height_distance, width_distance)
	var target := Vector3(0.0, 0.0, 0.0)
	_preview_camera.position = target + Vector3(0.0, distance, 0.05)
	_preview_camera.look_at(target, Vector3(0.0, 0.0, -1.0))


func _sync_render_mode() -> void:
	if _preview_viewport == null:
		return
	_preview_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	)


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null
