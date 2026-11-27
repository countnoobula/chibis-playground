class_name JournalScarfPreview
extends Control

## Renders the in-game Chibi model as a transparent journal portrait. The peach
## scarf is the actual M_Chibi_ScarfPeach surface on the skinned runner mesh.

const CHIBI_MODEL: PackedScene = preload("res://assets/characters/chibi_runner.glb")
const IDLE_ANIMATION: StringName = &"Anim_Chibi_Idle"
const DIVE_GEAR_SCRIPT: Script = preload("res://scripts/character/chibi_dive_gear.gd")

const PREVIEW_MARGIN := 1.24
const MIN_PREVIEW_SIZE := Vector2(140.0, 190.0)
const CAMERA_FOV_DEGREES := 34.0
const MODEL_YAW_DEGREES := -8.0

var _preview_container: SubViewportContainer
var _preview_viewport: SubViewport
var _preview_camera: Camera3D
var _chibi_model: Node3D
var _dive_gear: Node3D
var _lantern_attachment: BoneAttachment3D
var _lantern_preview: Node3D
var _selected_item := 0
var _model_width := 0.64
var _model_height := 1.2
var _model_center_y := 0.62


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = MIN_PREVIEW_SIZE
	_create_preview_viewport()
	_create_preview_world()
	_create_chibi()
	resized.connect(_sync_preview_size)
	visibility_changed.connect(_sync_render_mode)
	_sync_preview_size()
	_sync_render_mode()
	set_selected_item(_selected_item)


func _create_preview_viewport() -> void:
	_preview_container = SubViewportContainer.new()
	_preview_container.name = "TransparentPreview"
	_preview_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Match the SubViewport size to this Control in _sync_preview_size; leaving
	# stretch off avoids Godot's redundant stretch-resize warning.
	_preview_container.stretch = false
	add_child(_preview_container)
	_preview_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_preview_viewport = SubViewport.new()
	_preview_viewport.name = "ChibiViewport"
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
	environment.ambient_light_energy = 0.72
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	world_root.add_child(world_environment)

	var key_light := DirectionalLight3D.new()
	key_light.name = "WarmKeyLight"
	key_light.light_color = Color("#fff0df")
	key_light.light_energy = 1.05
	key_light.rotation_degrees = Vector3(-34.0, -26.0, 0.0)
	key_light.shadow_enabled = false
	world_root.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.name = "PeachFillLight"
	fill_light.light_color = Color("#dfeefa")
	fill_light.light_energy = 0.42
	fill_light.rotation_degrees = Vector3(-15.0, 145.0, 0.0)
	fill_light.shadow_enabled = false
	world_root.add_child(fill_light)

	_preview_camera = Camera3D.new()
	_preview_camera.name = "PortraitCamera"
	_preview_camera.fov = CAMERA_FOV_DEGREES
	_preview_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_preview_camera.near = 0.05
	_preview_camera.far = 20.0
	_preview_camera.current = true
	world_root.add_child(_preview_camera)


func _create_chibi() -> void:
	_chibi_model = CHIBI_MODEL.instantiate() as Node3D
	if _chibi_model == null:
		push_error("Journal scarf preview could not instantiate the Chibi runner model.")
		return
	_chibi_model.name = "ChibiWearingPeachScarf"
	_chibi_model.rotation_degrees.y = MODEL_YAW_DEGREES
	_preview_viewport.get_node("PreviewWorld").add_child(_chibi_model)

	var mesh := _find_mesh(_chibi_model)
	if mesh != null and mesh.mesh != null:
		var bounds := mesh.get_aabb()
		_model_width = maxf(bounds.size.x, 0.3)
		_model_height = maxf(bounds.size.y, 0.8)
		_model_center_y = bounds.position.y + bounds.size.y * 0.53
		var scarf_surface_found := false
		for surface_index in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface_index)
			if material != null and String(material.resource_name).contains("ScarfPeach"):
				scarf_surface_found = true
				break
		if not scarf_surface_found:
			push_warning("The Chibi runner mesh does not expose its Peach Scarf material surface.")

	var skeleton := _find_skeleton(_chibi_model)
	if skeleton != null:
		var dive_gear := DIVE_GEAR_SCRIPT.new() as Node3D
		if dive_gear != null and bool(dive_gear.call("attach_to", skeleton)):
			_dive_gear = dive_gear
		else:
			if dive_gear != null:
				dive_gear.free()
			push_warning("The journal Chibi preview could not attach its gameplay dive goggles.")
		_create_lantern_preview(skeleton)
	else:
		push_warning("The journal Chibi preview model has no skeleton for gear attachments.")

	var animation_player := _find_animation_player(_chibi_model)
	if animation_player != null and animation_player.has_animation(IDLE_ANIMATION):
		animation_player.speed_scale = 0.58
		animation_player.play(IDLE_ANIMATION)
	else:
		push_warning("The Chibi runner model has no idle animation for the journal preview.")
	set_selected_item(_selected_item)


## Show the selected gameplay gear on the same runner model used in the game.
func set_selected_item(item_index: int) -> void:
	_selected_item = clampi(item_index, 0, 2)
	if _dive_gear != null:
		_dive_gear.visible = _selected_item == 1
	if _lantern_preview != null:
		_lantern_preview.visible = _selected_item == 2
	if _preview_viewport != null and _preview_viewport.size.x > 0:
		_fit_camera_to_preview(_preview_viewport.size)


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
	var model_height := _model_height + (0.18 if _selected_item == 2 else 0.0)
	var model_width := _model_width + (0.24 if _selected_item == 2 else 0.0)
	var height_distance := model_height * PREVIEW_MARGIN / (2.0 * tan(vertical_half_angle))
	var width_distance := model_width * PREVIEW_MARGIN / (2.0 * tan(horizontal_half_angle))
	var distance := maxf(height_distance, width_distance)
	var target := Vector3(0.0, _model_center_y, 0.0)
	_preview_camera.position = target + Vector3(0.16, 0.035, distance)
	_preview_camera.look_at(target, Vector3.UP)


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


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _create_lantern_preview(skeleton: Skeleton3D) -> void:
	var hand_bone := skeleton.find_bone("hand_r")
	if hand_bone < 0:
		push_warning("The journal Chibi preview has no right-hand bone for the petal lantern.")
		return
	_lantern_attachment = BoneAttachment3D.new()
	_lantern_attachment.name = "LanternHandAttachment"
	_lantern_attachment.bone_name = skeleton.get_bone_name(hand_bone)
	skeleton.add_child(_lantern_attachment)
	_lantern_preview = _build_lantern()
	_lantern_preview.position = Vector3(0.0, -0.075, 0.025)
	_lantern_preview.rotation_degrees = Vector3(7.0, 8.0, -12.0)
	_lantern_attachment.add_child(_lantern_preview)


func _build_lantern() -> Node3D:
	var lantern := Node3D.new()
	lantern.name = "PetalLanternPreview"

	var brass := _preview_material(Color("#99613f"), 0.32, false)
	var leaf_green := _preview_material(Color("#78943c"), 0.74, false)
	var petal_peach := _preview_material(Color("#ffb15b"), 0.44, false)
	var petal_gold := _preview_material(Color("#ffcf69"), 0.38, false)
	var glowing_core := _preview_material(Color("#ffe48a"), 0.3, true)

	var hook := MeshInstance3D.new()
	hook.name = "HandleLoop"
	var loop_mesh := TorusMesh.new()
	loop_mesh.inner_radius = 0.032
	loop_mesh.outer_radius = 0.041
	hook.mesh = loop_mesh
	hook.position = Vector3(0.0, 0.105, 0.0)
	hook.material_override = brass
	hook.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lantern.add_child(hook)

	var cap := MeshInstance3D.new()
	cap.name = "LeafCalyx"
	var cap_mesh := SphereMesh.new()
	cap_mesh.radius = 0.037
	cap_mesh.height = 0.036
	cap.mesh = cap_mesh
	cap.position = Vector3(0.0, 0.052, 0.0)
	cap.scale = Vector3(1.15, 0.55, 1.15)
	cap.material_override = leaf_green
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lantern.add_child(cap)

	for index in 5:
		var angle := TAU * float(index) / 5.0
		var leaf := MeshInstance3D.new()
		leaf.name = "Leaf%d" % index
		var leaf_mesh := SphereMesh.new()
		leaf_mesh.radius = 0.032
		leaf_mesh.height = 0.075
		leaf.mesh = leaf_mesh
		leaf.position = Vector3(cos(angle) * 0.025, 0.045, sin(angle) * 0.025)
		leaf.rotation_degrees.z = -22.0
		leaf.scale = Vector3(0.72, 0.78, 0.43)
		leaf.material_override = leaf_green
		leaf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lantern.add_child(leaf)

	var center := MeshInstance3D.new()
	center.name = "GlowingCenter"
	var center_mesh := SphereMesh.new()
	center_mesh.radius = 0.044
	center_mesh.height = 0.105
	center.mesh = center_mesh
	center.position = Vector3(0.0, -0.006, 0.0)
	center.material_override = glowing_core
	center.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lantern.add_child(center)

	for index in 6:
		var angle := TAU * float(index) / 6.0
		var petal := MeshInstance3D.new()
		petal.name = "Petal%d" % index
		var petal_mesh := SphereMesh.new()
		petal_mesh.radius = 0.036
		petal_mesh.height = 0.103
		petal.mesh = petal_mesh
		petal.position = Vector3(cos(angle) * 0.032, -0.009, sin(angle) * 0.032)
		petal.rotation_degrees.y = rad_to_deg(angle)
		petal.scale = Vector3(0.72, 0.78, 0.56)
		petal.material_override = petal_peach if index % 2 == 0 else petal_gold
		petal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lantern.add_child(petal)

	var stem := MeshInstance3D.new()
	stem.name = "LanternStem"
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.014
	stem_mesh.bottom_radius = 0.014
	stem_mesh.height = 0.034
	stem.mesh = stem_mesh
	stem.position = Vector3(0.0, 0.082, 0.0)
	stem.material_override = brass
	stem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lantern.add_child(stem)

	var glow := OmniLight3D.new()
	glow.name = "LanternGlow"
	glow.light_color = Color("#ffd77a")
	glow.light_energy = 0.35
	glow.omni_range = 0.28
	glow.shadow_enabled = false
	glow.position = Vector3(0.0, -0.005, 0.0)
	lantern.add_child(glow)
	return lantern


func _preview_material(color: Color, roughness: float, emissive: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emissive:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.2
	return material
