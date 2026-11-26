class_name ChibiScarfGlider
extends Node

## Keeps one lightweight canopy attached to the final IK hand poses, and crossfades
## only the runner's separately surfaced M_Chibi_ScarfPeach material during the toss.

const CANOPY_SCENE: PackedScene = preload("res://assets/characters/chibi_scarf_canopy.glb")
const PRINT_TEXTURE: Texture2D = preload("res://assets/characters/chibi_scarf_print.png")
const WEAVE_TEXTURE: Texture2D = preload("res://assets/characters/chibi_scarf_weave.png")
const LAYOUT: ChibiScarfLayout = preload("res://assets/characters/chibi_scarf_layout.tres")
const SHADER: Shader = preload("res://shaders/character/scarf_glider.gdshader")
const COLLAPSE_CENTER := Vector3(0.0, 0.56, -0.09)

var _visual_root: Node3D
var _runner_mesh: MeshInstance3D
var _skeleton: Skeleton3D
var _canopy_root: Node3D
var _canopy_mesh: MeshInstance3D
var _canopy_material: ShaderMaterial
var _body_scarf_material: StandardMaterial3D
var _body_scarf_surface := -1
var _body_scarf_color := Color.WHITE
var _source_pin_points := PackedVector3Array()
var _hand_pin_offsets := PackedVector3Array()
var _hand_bones := PackedInt32Array([-1, -1])
var _toss_side_model_x := Vector3.LEFT
var _collapse_center := COLLAPSE_CENTER
var _layout_valid := false
var _deployment := 0.0
var _gust_phase := 0.0
var _opacity := 0.0


func attach_to(visual_root: Node3D, skeleton: Skeleton3D, body_mesh: MeshInstance3D) -> bool:
	if visual_root == null or skeleton == null or body_mesh == null:
		return false
	_visual_root = visual_root
	_skeleton = skeleton
	_runner_mesh = body_mesh
	_hand_bones[0] = skeleton.find_bone("hand_l")
	_hand_bones[1] = skeleton.find_bone("hand_r")
	if _hand_bones[0] < 0 or _hand_bones[1] < 0 or not _load_layout():
		return false
	var hand_r_in_model := visual_root.global_transform.affine_inverse() \
		* skeleton.global_transform * skeleton.get_bone_global_rest(_hand_bones[1])
	if not is_zero_approx(hand_r_in_model.origin.x):
		_toss_side_model_x = Vector3(signf(hand_r_in_model.origin.x), 0.0, 0.0)

	_canopy_root = CANOPY_SCENE.instantiate() as Node3D
	if _canopy_root == null:
		return false
	_canopy_root.name = "ScarfCanopy"
	_visual_root.add_child(_canopy_root)
	_canopy_mesh = _find_mesh(_canopy_root)
	if _canopy_mesh == null or _canopy_mesh.mesh == null:
		_canopy_root.queue_free()
		_canopy_root = null
		return false

	_canopy_material = ShaderMaterial.new()
	_canopy_material.shader = SHADER
	_canopy_material.set_shader_parameter("chibi_scarf_print", PRINT_TEXTURE)
	_canopy_material.set_shader_parameter("chibi_scarf_weave", WEAVE_TEXTURE)
	_canopy_material.set_shader_parameter("collapse_center", _collapse_center)
	_canopy_material.set_shader_parameter("deploy_amount", 0.0)
	_canopy_material.set_shader_parameter("canopy_alpha", 0.0)
	_canopy_mesh.material_override = _canopy_material
	_canopy_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_canopy_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_canopy_root.visible = false

	if not _bind_body_scarf():
		_canopy_root.queue_free()
		_canopy_root = null
		return false
	_layout_valid = true
	return true


func update_pose(
	phase: StringName,
	progress: float,
	stow_open: float,
	bank: float,
	delta: float,
	local_velocity: Vector3 = Vector3.ZERO
) -> void:
	if not _layout_valid or _canopy_material == null or (phase == &"stowed" and _deployment == 0.0):
		return
	_gust_phase += maxf(delta, 0.0) * 0.74
	var eased_progress := clampf(progress, 0.0, 1.0)
	var eased_stow_open := smoothstep(0.0, 1.0, clampf(stow_open, 0.0, 1.0))
	var cloth_tension := 0.0
	var airflow_fade := 0.0
	var deployment_catch := 0.0
	match phase:
		&"deploy":
			_deployment = smoothstep(0.0, 1.0, eased_progress)
			cloth_tension = smoothstep(0.025, 0.62, _deployment)
			airflow_fade = smoothstep(0.10, 0.82, _deployment)
			deployment_catch = sin(PI * eased_progress)
		&"glide":
			_deployment = 1.0
			cloth_tension = 1.0
			airflow_fade = 1.0
		&"stow", &"cancel":
			_deployment = eased_stow_open * (
				1.0 - smoothstep(0.0, 1.0, eased_progress)
			)
			if phase == &"cancel":
				var spill := 1.0 - smoothstep(0.0, 0.65, eased_progress)
				cloth_tension = smoothstep(0.025, 0.62, eased_stow_open) * spill
				airflow_fade = smoothstep(0.10, 0.82, eased_stow_open) * spill
				deployment_catch = sin(PI * stow_open) * spill
			else:
				cloth_tension = eased_stow_open * (1.0 - smoothstep(0.45, 1.0, eased_progress))
				airflow_fade = eased_stow_open * (1.0 - smoothstep(0.0, 0.95, eased_progress))
		_:
			_deployment = 0.0
	_deployment = clampf(_deployment, 0.0, 1.0)
	var toss_handoff := 0.0
	if phase == &"stow":
		# Only a near-full dry stow gathers the last visible fold toward the right collar.
		# Hand_r's authored rest offset supplies the local X sign despite the model's 180° turn.
		toss_handoff = smoothstep(0.86, 1.0, eased_stow_open) \
			* smoothstep(0.42, 0.72, eased_progress)
	var toss_center_model := COLLAPSE_CENTER \
		+ _toss_side_model_x * 0.12 + Vector3.UP * 0.08
	var toss_center_world := _visual_root.global_transform * toss_center_model
	var toss_center_canopy := _canopy_mesh.global_transform.affine_inverse() * toss_center_world
	_collapse_center = COLLAPSE_CENTER.lerp(toss_center_canopy, toss_handoff)
	var planar_speed := Vector2(local_velocity.x, local_velocity.z).length()
	var planar_airflow := clampf(planar_speed / 4.4, 0.0, 1.0) * airflow_fade
	var descent_airflow := clampf(maxf(-local_velocity.y, 0.0) / 5.8, 0.0, 1.0) * airflow_fade
	var airflow_side := clampf(local_velocity.x / 4.4, -1.0, 1.0) * airflow_fade
	_opacity = smoothstep(0.025, 0.22, _deployment)
	_canopy_root.visible = _deployment > 0.001
	_canopy_material.set_shader_parameter("deploy_amount", _deployment)
	_canopy_material.set_shader_parameter("collapse_center", _collapse_center)
	_canopy_material.set_shader_parameter("canopy_alpha", _opacity)
	_canopy_material.set_shader_parameter("bank", clampf(bank, -1.0, 1.0))
	_canopy_material.set_shader_parameter("gust", _gust_phase)
	_canopy_material.set_shader_parameter("planar_airflow", planar_airflow)
	_canopy_material.set_shader_parameter("descent_airflow", descent_airflow)
	_canopy_material.set_shader_parameter("airflow_side", airflow_side)
	_canopy_material.set_shader_parameter("cloth_tension", cloth_tension)
	_canopy_material.set_shader_parameter("deployment_catch", deployment_catch)
	_set_body_scarf_alpha(1.0 - _opacity)


func update_hand_pins() -> void:
	if not _layout_valid or _canopy_material == null or _skeleton == null or _opacity <= 0.0:
		return
	var skeleton_to_canopy := _canopy_mesh.global_transform.affine_inverse() * _skeleton.global_transform
	var deltas := PackedVector3Array()
	for i in 4:
		var hand_index := 0 if i < 2 else 1
		var pose := _skeleton.get_bone_global_pose(_hand_bones[hand_index])
		var target_canopy := skeleton_to_canopy * pose * _hand_pin_offsets[i]
		var collapsed_source := _collapse_center.lerp(_source_pin_points[i], _deployment)
		deltas.append(target_canopy - collapsed_source)
	_canopy_material.set_shader_parameter("scarf_pin_delta", deltas)


## World-space positions of the four cloth corners in left-inner, left-outer,
## right-inner, right-outer order. These are also the live shader pin targets.
func get_corner_targets() -> PackedVector3Array:
	var targets := PackedVector3Array()
	if not _layout_valid or _skeleton == null:
		return targets
	for i in 4:
		var hand_index := 0 if i < 2 else 1
		var pose := _skeleton.get_bone_global_pose(_hand_bones[hand_index])
		targets.append(_skeleton.global_transform * pose * _hand_pin_offsets[i])
	return targets


func _load_layout() -> bool:
	if LAYOUT == null:
		push_error("Scarf pin layout is missing.")
		return false
	if LAYOUT.source_pin_points.size() != 4 or LAYOUT.bone_local_offsets.size() != 4:
		push_error("Scarf pin layout must contain four points and hand offsets.")
		return false
	if LAYOUT.pin_bones.size() != 4:
		return false
	for i in 4:
		var expected_bone := "hand_l" if i < 2 else "hand_r"
		if LAYOUT.pin_bones[i] != expected_bone:
			push_error("Scarf pin %d is not bound to %s." % [i, expected_bone])
			return false
	_source_pin_points = LAYOUT.source_pin_points
	_hand_pin_offsets = LAYOUT.bone_local_offsets
	return true


func _bind_body_scarf() -> bool:
	if _runner_mesh.mesh == null:
		return false
	for surface in _runner_mesh.mesh.get_surface_count():
		var material := _runner_mesh.mesh.surface_get_material(surface) as StandardMaterial3D
		if material == null:
			continue
		var material_name := String(material.resource_name)
		if material_name != "M_Chibi_ScarfPeach" and not material_name.contains("M_Chibi_ScarfPeach"):
			continue
		_body_scarf_surface = surface
		_body_scarf_material = material.duplicate(true) as StandardMaterial3D
		_body_scarf_color = _body_scarf_material.albedo_color
		_body_scarf_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_runner_mesh.set_surface_override_material(surface, _body_scarf_material)
		return true
	push_error("Could not find the separate M_Chibi_ScarfPeach mesh surface.")
	return false


func _set_body_scarf_alpha(amount: float) -> void:
	if _body_scarf_material == null:
		return
	var tint := _body_scarf_color
	tint.a = _body_scarf_color.a * clampf(amount, 0.0, 1.0)
	_body_scarf_material.albedo_color = tint


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null



