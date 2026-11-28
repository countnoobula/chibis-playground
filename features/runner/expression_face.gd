class_name ChibiExpressionFace
extends Node

## Runtime expression meshes for the twenty approved face studies.
## The body mesh is rebuilt with its original skinning and blend-shape data so
## animation, blink, and dive-bite updates continue to work while a pose is shown.

const POSE_NAMES: Array[String] = [
	"e01", "e02", "e03", "e04", "e05", "e06", "e07", "e08", "e09", "e10",
	"e11", "e12", "e13", "e14", "e15", "sleepy", "scared", "angry", "sad", "crying",
]

const ENSEMBLE_GEOMETRY_PATH := "res://features/runner/expressions/face/ensemble_geometry.json"
const MOODS_GEOMETRY_PATH := "res://features/runner/expressions/face/moods_geometry.json"
const TRANSITION_BLEND_SHAPE: StringName = &"__ExpressionFaceTransition"
const OPEN_MOUTH_POSE_INDICES: Array[int] = [2, 3, 11, 12, 13, 14]
const CLOSED_MOUTH_MIDPOINT_SCALE := 0.12
const SHAPE_BLEND_NAMES: Array[StringName] = [
	&"Expr_Happy", &"Expr_Focused", &"Expr_Effort", &"Expr_Surprised",
]
const MAX_CACHED_POSES := 4
const EYE_SURFACES: Array[String] = [
	"M_Chibi_EyeDark", "M_Chibi_EyeIris", "M_Chibi_EyeIrisLight", "M_Chibi_EyeHighlight",
]
const ENSEMBLE_EYE_WARP := {
	"e01": Vector4(1.02, 1.02, 0.002, 0.0),
	"e02": Vector4(1.02, 0.94, -0.008, 0.0),
	"e03": Vector4(1.02, 0.81, 0.008, 0.0),
	"e04": Vector4(1.02, 1.12, 0.009, 0.0),
	"e05": Vector4(1.02, 1.0, 0.0, 0.0),
	"e06": Vector4(1.02, 1.13, 0.012, 0.0),
	"e07": Vector4(1.02, 0.89, 0.012, 0.0),
	"e08": Vector4(1.02, 0.82, 0.025, 0.0),
	"e09": Vector4(1.02, 0.9, -0.008, 0.0),
	"e10": Vector4(1.02, 1.06, 0.011, 0.0),
	"e11": Vector4(1.02, 1.1, -0.002, 0.0),
	"e12": Vector4(1.02, 1.03, -0.012, 0.0),
	"e13": Vector4(1.02, 1.2, -0.016, 0.0),
	"e14": Vector4(1.02, 0.86, 0.004, 0.0),
	"e15": Vector4(1.02, 1.2, -0.005, 0.0),
}
const MOOD_EYE_WARP := {
	"sleepy": Vector4(1.025, 0.28, -0.008, -0.014),
	"scared": Vector4(1.045, 1.15, -0.007, 0.003),
	"angry": Vector4(1.05, 0.75, 0.031, 0.0),
	"sad": Vector4(1.06, 1.03, -0.028, -0.009),
	"crying": Vector4(1.0, 1.0, 0.0, 0.0),
}
const POSE_BLEND_SHAPES := {
	"scared": {"Expr_Surprised": 0.20},
	"angry": {"Expr_Focused": 0.22, "Expr_Effort": 0.18},
}
const BITE_OVERLAY_HIDE_THRESHOLD := 0.01

var _player: Node3D
var _face: MeshInstance3D
var _skeleton: Skeleton3D
var _juice: ChibiJuice
var _original_mesh: ArrayMesh
var _original_surface_overrides: Array = []
var _mouth_surface_index := -1
var _pose_mesh: ArrayMesh
var _mouth_overlay: MeshInstance3D
var _brow_overlay: MeshInstance3D
var _face_attachment: BoneAttachment3D
var _transparent_face_material: StandardMaterial3D
var _overlay_material: StandardMaterial3D
var _eye_fade_materials: Dictionary = {}
var _eye_surface_indices: Array[int] = []
var _eye_closed_weight := 0.0
var _ensemble_geometry: Dictionary = {}
var _moods_geometry: Dictionary = {}
var _pose_assets_cache: Dictionary = {}
# Keep the landing-critical poses separate from the bounded picker cache.
var _fall_assets: Dictionary = {}
var _fall_face_transitions: Dictionary = {}
var _pose_index := -1
var _setup_complete := false
var _bite_overlays_hidden := false
var _blend_active := false
var _blend_target_index := -1
var _blend_elapsed := 0.0
var _blend_duration := 0.0
var _blend_start_eye_closed := 0.0
var _blend_target_eye_closed := 0.0
var _blend_start_shape_values: Dictionary = {}
var _last_shape_values: Dictionary = {}
var _last_shape_fallbacks: Dictionary = {}
var _blend_target_face_mesh: ArrayMesh
var _blend_target_mouth_mesh: ArrayMesh
var _blend_target_brow_mesh: ArrayMesh
var _blend_mouth_close_mesh: ArrayMesh
var _blend_mouth_open_mesh: ArrayMesh
var _blend_mouth_two_phase := false
var _blend_face_shape_index := -1
var _blend_mouth_shape_index := -1
var _blend_mouth_open_shape_index := -1
var _blend_brow_shape_index := -1


func setup(player: Node3D) -> void:
	if not is_instance_valid(player):
		push_error("ChibiExpressionFace.setup needs the live player node.")
		return
	if _setup_complete and _player == player:
		return
	_release_setup()
	_player = player
	_juice = _find_juice(player)
	if _juice != null:
		_face = _juice.character_mesh
	var rig_binder := _find_rig_binder(player)
	if rig_binder != null:
		if _face == null:
			_face = rig_binder.mesh_inst
		_skeleton = rig_binder.skeleton
	if _face == null:
		_face = _find_face_mesh(player)
	if _skeleton == null:
		_skeleton = _find_skeleton(player)
	if _face == null or _skeleton == null:
		push_error("ChibiExpressionFace could not find Chibi's skinned face mesh and skeleton.")
		return
	_original_mesh = _face.mesh as ArrayMesh
	if _original_mesh == null:
		push_error("ChibiExpressionFace requires the original ArrayMesh face.")
		return
	_original_surface_overrides.clear()
	for surface_index in range(_original_mesh.get_surface_count()):
		_original_surface_overrides.append(_face.get_surface_override_material(surface_index))
		var surface_material := _get_surface_material(_face, surface_index)
		if surface_material != null and surface_material.resource_name in EYE_SURFACES:
			_eye_surface_indices.append(surface_index)
			var eye_material := _original_surface_overrides[surface_index] as StandardMaterial3D
			if eye_material == null:
				eye_material = surface_material as StandardMaterial3D
			if eye_material != null:
				var fade_material := eye_material.duplicate() as StandardMaterial3D
				fade_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				_eye_fade_materials[surface_index] = {
					"material": fade_material,
					"base_alpha": eye_material.albedo_color.a,
				}
		if surface_material != null and surface_material.resource_name.contains("M_Chibi_Mouth"):
			_mouth_surface_index = surface_index
	if _mouth_surface_index < 0:
		push_error("ChibiExpressionFace could not locate the original mouth surface.")
		return

	_transparent_face_material = StandardMaterial3D.new()
	_transparent_face_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_transparent_face_material.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
	_overlay_material = StandardMaterial3D.new()
	_overlay_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay_material.vertex_color_use_as_albedo = true
	_overlay_material.vertex_color_is_srgb = true
	_overlay_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_create_face_overlays()
	if _juice != null:
		_juice.expression_face = self
	_setup_complete = true


func show_pose(index: int) -> void:
	if not _setup_complete:
		push_warning("Call setup(player) before showing a Chibi face pose.")
		return
	if index < 0 or index >= POSE_NAMES.size():
		push_warning("Chibi face pose index is outside the approved 0–19 order.")
		return
	var interrupted_blend := _blend_active
	_clear_blend_state()
	if _pose_index == index and not interrupted_blend:
		_update_mouth_overlay_for_bite()
		return

	var pose_name: String = POSE_NAMES[index]
	var pose_assets := _get_pose_assets(index)
	var pose_mesh := pose_assets.get("face") as ArrayMesh
	var mouth_mesh := pose_assets.get("mouth") as ArrayMesh
	var brow_mesh := pose_assets.get("brow") as ArrayMesh
	if pose_mesh == null or mouth_mesh == null or brow_mesh == null:
		push_error("ChibiExpressionFace could not build pose '%s' from its preview geometry." % pose_name)
		return

	_pose_index = index
	_pose_mesh = pose_mesh
	_face.mesh = _pose_mesh
	_face.set_surface_override_material(_mouth_surface_index, _transparent_face_material)
	_mouth_overlay.mesh = mouth_mesh
	_brow_overlay.mesh = brow_mesh
	_mouth_overlay.show()
	_brow_overlay.show()
	_bite_overlays_hidden = false
	_set_eye_closed_weight(1.0 if _eyes_are_closed(pose_name) else 0.0)
	_update_mouth_overlay_for_bite()


## Smoothly blends to an approved pose, or back to the unposed face with -1.
## A new request starts from the face currently on screen, even during a blend.
func blend_to_pose(index: int, seconds: float) -> void:
	if not _setup_complete:
		push_warning("Call setup(player) before blending a Chibi face pose.")
		return
	if index < -1 or index >= POSE_NAMES.size():
		push_warning("Chibi face pose index must be -1 or inside the approved 0–19 order.")
		return
	if _blend_active and index == _blend_target_index:
		return
	if not _blend_active and index == _pose_index:
		_update_mouth_overlay_for_bite()
		return

	var blend_duration := maxf(seconds, 0.0) if is_finite(seconds) else 0.0
	if blend_duration <= 0.0001:
		if index < 0:
			clear_pose()
		else:
			show_pose(index)
		return

	var original_shape_values := _capture_original_shape_values()
	var start_shape_values: Dictionary = {}
	for shape_name in SHAPE_BLEND_NAMES:
		start_shape_values[shape_name] = _current_shape_value(shape_name)

	# A cleared face and the neutral e01 study share the same art direction. Enter
	# the neutral study as the transition's source so its mouth and brows remain
	# single meshes instead of overlapping the original face surfaces.
	if _pose_mesh == null:
		var neutral_assets := _get_pose_assets(0)
		_pose_mesh = neutral_assets.get("face") as ArrayMesh
		_face.mesh = _pose_mesh
		_mouth_overlay.mesh = neutral_assets.get("mouth") as ArrayMesh
		_brow_overlay.mesh = neutral_assets.get("brow") as ArrayMesh
		_mouth_overlay.show()
		_brow_overlay.show()
		_face.set_surface_override_material(_mouth_surface_index, _transparent_face_material)
		_set_eye_closed_weight(0.0)
		_apply_original_shape_values(original_shape_values)
		_bite_overlays_hidden = false
		_update_mouth_overlay_for_bite()

	var source_face := _face.mesh as ArrayMesh
	var target_index := 0 if index < 0 else index
	var target_assets := _get_pose_assets(target_index)
	var target_face := target_assets.get("face") as ArrayMesh
	var target_mouth := target_assets.get("mouth") as ArrayMesh
	var target_brow := target_assets.get("brow") as ArrayMesh
	if source_face == null or target_face == null or target_mouth == null or target_brow == null:
		push_error("ChibiExpressionFace could not build the requested blend endpoints.")
		return

	var transition_face: ArrayMesh
	if not _blend_active:
		transition_face = _fall_face_transitions.get(Vector2i(maxi(0, _pose_index), target_index))
	if transition_face == null:
		transition_face = _build_transition_face_mesh(source_face, target_face, _face)
	var transition_mouth: ArrayMesh
	var transition_mouth_open: ArrayMesh
	var neutral_mouth := _get_pose_assets(0).get("mouth") as ArrayMesh
	var mouth_two_phase := not _overlay_topology_matches(_mouth_overlay.mesh as ArrayMesh, target_mouth) \
		and _should_close_mouth_in_two_phases(_mouth_overlay, neutral_mouth, index)
	if mouth_two_phase:
		transition_mouth = _build_mouth_close_transition(_mouth_overlay, neutral_mouth)
		transition_mouth_open = _build_mouth_open_transition(target_mouth, neutral_mouth)
	else:
		transition_mouth = _build_transition_overlay_mesh(_mouth_overlay, target_mouth)
	var transition_brow := _build_transition_overlay_mesh(_brow_overlay, target_brow)
	if transition_face == null or transition_mouth == null or transition_brow == null \
		or (mouth_two_phase and transition_mouth_open == null):
		push_error("ChibiExpressionFace could not build the requested transition meshes.")
		return

	var current_eye_closed := _eye_closed_weight
	var target_eye_closed := 0.0
	if index >= 0 and _eyes_are_closed(POSE_NAMES[index]):
		target_eye_closed = 1.0
	_clear_blend_state()
	_blend_active = true
	_blend_target_index = index
	_blend_elapsed = 0.0
	_blend_duration = blend_duration
	_blend_start_eye_closed = current_eye_closed
	_blend_target_eye_closed = target_eye_closed
	_blend_start_shape_values = start_shape_values
	_blend_target_face_mesh = target_face
	_blend_target_mouth_mesh = target_mouth
	_blend_target_brow_mesh = target_brow
	_blend_mouth_close_mesh = transition_mouth
	_blend_mouth_open_mesh = transition_mouth_open
	_blend_mouth_two_phase = mouth_two_phase
	_face.mesh = transition_face
	_pose_mesh = transition_face
	_mouth_overlay.mesh = transition_mouth
	_brow_overlay.mesh = transition_brow
	_pose_index = index
	_mouth_overlay.show()
	_brow_overlay.show()
	_apply_original_shape_values(original_shape_values)
	_blend_face_shape_index = _find_mesh_blend_shape(transition_face, TRANSITION_BLEND_SHAPE)
	_blend_mouth_shape_index = _find_mesh_blend_shape(transition_mouth, TRANSITION_BLEND_SHAPE)
	_blend_mouth_open_shape_index = _find_mesh_blend_shape(transition_mouth_open, TRANSITION_BLEND_SHAPE)
	_blend_brow_shape_index = _find_mesh_blend_shape(transition_brow, TRANSITION_BLEND_SHAPE)
	_set_transition_weights(0.0)
	_bite_overlays_hidden = false
	_set_eye_closed_weight(current_eye_closed)
	_update_mouth_overlay_for_bite()


func clear_pose() -> void:
	_clear_blend_state()
	if _face != null and is_instance_valid(_face) and _original_mesh != null:
		_face.mesh = _original_mesh
		for surface_index in range(_original_surface_overrides.size()):
			_face.set_surface_override_material(surface_index, _original_surface_overrides[surface_index])
	if _mouth_overlay != null and is_instance_valid(_mouth_overlay):
		_mouth_overlay.hide()
		_mouth_overlay.mesh = null
	if _brow_overlay != null and is_instance_valid(_brow_overlay):
		_brow_overlay.hide()
		_brow_overlay.mesh = null
	_pose_mesh = null
	_pose_index = -1
	_eye_closed_weight = 0.0
	_bite_overlays_hidden = false


## ChibiJuice is the only per-frame blend-shape writer. Active poses provide
## their approved baseline weights through this hook; blink and bite stay live.
func get_pose_blend_shape_value(shape_name: StringName, fallback: float) -> float:
	_last_shape_fallbacks[shape_name] = fallback
	var value := fallback
	if _blend_active:
		var start_value := float(_blend_start_shape_values.get(shape_name, fallback))
		var target_value := fallback if _blend_target_index < 0 \
			else _get_pose_shape_value(_blend_target_index, shape_name)
		value = lerpf(start_value, target_value, _blend_eased_weight())
	elif _pose_index >= 0:
		value = _get_pose_shape_value(_pose_index, shape_name)
	_last_shape_values[shape_name] = value
	return value


func get_pose_name(index: int) -> String:
	if index < 0 or index >= POSE_NAMES.size():
		return ""
	return POSE_NAMES[index]


func _process(_delta: float) -> void:
	if _blend_active:
		_blend_elapsed = minf(_blend_duration, _blend_elapsed + _delta)
		var blend_weight := _blend_eased_weight()
		_set_transition_weights(blend_weight)
		_update_mouth_transition_weight()
		_set_eye_closed_weight(lerpf(_blend_start_eye_closed, _blend_target_eye_closed, blend_weight))
		_update_mouth_overlay_for_bite()
		if _blend_elapsed >= _blend_duration:
			_finish_blend()
	elif _pose_mesh != null:
		_update_mouth_overlay_for_bite()


func _exit_tree() -> void:
	_release_setup()


func _release_setup() -> void:
	clear_pose()
	if _juice != null and is_instance_valid(_juice) and _juice.expression_face == self:
		_juice.expression_face = null
	if _face_attachment != null and is_instance_valid(_face_attachment):
		_face_attachment.free()
	_player = null
	_face = null
	_skeleton = null
	_juice = null
	_original_mesh = null
	_original_surface_overrides.clear()
	_eye_fade_materials.clear()
	_eye_surface_indices.clear()
	_mouth_surface_index = -1
	_pose_mesh = null
	_face_attachment = null
	_mouth_overlay = null
	_brow_overlay = null
	_transparent_face_material = null
	_overlay_material = null
	_ensemble_geometry.clear()
	_moods_geometry.clear()
	_pose_assets_cache.clear()
	_fall_assets.clear()
	_fall_face_transitions.clear()
	_pose_index = -1
	_setup_complete = false
	_bite_overlays_hidden = false
	_eye_closed_weight = 0.0
	_last_shape_values.clear()
	_last_shape_fallbacks.clear()


## Build the common drop/catch skinned morphs before the first rooftop frame.
## Interruptions still sample and blend from their actual in-between geometry.
func warm_up_fall() -> void:
	if not _setup_complete or not _fall_assets.is_empty():
		return
	for index in [0, 11, 14, 9]:
		_fall_assets[index] = _get_pose_assets(index)
		_pose_assets_cache.erase(index)
	var source := MeshInstance3D.new()
	for pair: Vector2i in [Vector2i(0, 11), Vector2i(11, 14), Vector2i(14, 9), Vector2i(11, 9), Vector2i(9, 0), Vector2i(14, 0)]:
		source.mesh = _fall_assets[pair.x].face
		_fall_face_transitions[pair] = _build_transition_face_mesh(source.mesh, _fall_assets[pair.y].face, source)
	source.free()


func _get_pose_assets(index: int) -> Dictionary:
	if _fall_assets.has(index):
		return _fall_assets[index]
	if _pose_assets_cache.has(index):
		return _pose_assets_cache[index]
	var pose_name: String = POSE_NAMES[index]
	var mood_pose := index >= 15
	var assets := {
		"face": _build_pose_mesh(pose_name, mood_pose),
		"mouth": _build_overlay_mesh(pose_name, mood_pose),
		"brow": _build_overlay_mesh("brow-" + pose_name, mood_pose),
	}
	if _pose_assets_cache.size() >= MAX_CACHED_POSES:
		_pose_assets_cache.erase(_pose_assets_cache.keys()[0])
	_pose_assets_cache[index] = assets
	return assets


func _build_transition_face_mesh(source_mesh: ArrayMesh, target_mesh: ArrayMesh, source_instance: MeshInstance3D) -> ArrayMesh:
	if source_instance.mesh != source_mesh or _find_mesh_blend_shape(target_mesh, TRANSITION_BLEND_SHAPE) >= 0:
		return null
	var transition_mesh := ArrayMesh.new()
	transition_mesh.blend_shape_mode = target_mesh.blend_shape_mode
	for blend_shape_index in range(target_mesh.get_blend_shape_count()):
		transition_mesh.add_blend_shape(target_mesh.get_blend_shape_name(blend_shape_index))
	transition_mesh.add_blend_shape(TRANSITION_BLEND_SHAPE)
	for surface_index in range(target_mesh.get_surface_count()):
		var target_arrays: Array = target_mesh.surface_get_arrays(surface_index)
		var source_arrays := _get_effective_surface_arrays(source_instance, surface_index)
		if source_arrays.is_empty():
			return null
		var source_vertices: PackedVector3Array = source_arrays[Mesh.ARRAY_VERTEX]
		var target_vertices: PackedVector3Array = target_arrays[Mesh.ARRAY_VERTEX]
		if source_vertices.size() != target_vertices.size():
			push_error("Chibi face blend endpoints have different skin vertex counts.")
			return null
		var base_arrays: Array = target_arrays.duplicate(true)
		base_arrays[Mesh.ARRAY_VERTEX] = source_vertices
		var source_normals: Variant = source_arrays[Mesh.ARRAY_NORMAL]
		var target_normals: Variant = target_arrays[Mesh.ARRAY_NORMAL]
		if source_normals is PackedVector3Array and target_normals is PackedVector3Array \
			and source_normals.size() == target_normals.size():
			base_arrays[Mesh.ARRAY_NORMAL] = source_normals
		var source_tangents: Variant = source_arrays[Mesh.ARRAY_TANGENT]
		var target_tangents: Variant = target_arrays[Mesh.ARRAY_TANGENT]
		if source_tangents is PackedFloat32Array and target_tangents is PackedFloat32Array \
			and source_tangents.size() == target_tangents.size():
			base_arrays[Mesh.ARRAY_TANGENT] = source_tangents
		var source_index_value: Variant = source_arrays[Mesh.ARRAY_INDEX]
		if source_index_value is PackedInt32Array and not source_index_value.is_empty():
			var source_indices: PackedInt32Array = source_index_value
			base_arrays[Mesh.ARRAY_INDEX] = source_indices

		var transition_shape := _make_transition_shape_arrays(
			base_arrays, target_arrays, target_mesh.blend_shape_mode
		)
		var blend_shapes: Array = target_mesh.surface_get_blend_shape_arrays(surface_index)
		blend_shapes.append(transition_shape)
		transition_mesh.add_surface_from_arrays(
			target_mesh.surface_get_primitive_type(surface_index),
			base_arrays,
			blend_shapes,
			{},
			target_mesh.surface_get_format(surface_index) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		)
		transition_mesh.surface_set_material(surface_index, target_mesh.surface_get_material(surface_index))
	return transition_mesh


func _build_transition_overlay_mesh(source_instance: MeshInstance3D, target_mesh: ArrayMesh) -> ArrayMesh:
	var source_mesh := source_instance.mesh as ArrayMesh
	if source_mesh == null:
		return null
	var source_surfaces: Array[Array] = []
	for surface_index in range(source_mesh.get_surface_count()):
		source_surfaces.append(_get_effective_surface_arrays(source_instance, surface_index))
	var target_surface_count := target_mesh.get_surface_count()
	var source_surface_count := source_surfaces.size()
	var source_center := _overlay_mesh_center(source_surfaces)
	var target_center := _overlay_mesh_center_from_mesh(target_mesh)
	var transition_mesh := ArrayMesh.new()
	transition_mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	transition_mesh.add_blend_shape(TRANSITION_BLEND_SHAPE)
	var total_surfaces := maxi(source_surface_count, target_surface_count)
	for surface_index in range(total_surfaces):
		var base_arrays: Array
		var target_vertices: PackedVector3Array
		var primitive := Mesh.PRIMITIVE_TRIANGLES
		if surface_index < target_surface_count:
			var target_arrays: Array = target_mesh.surface_get_arrays(surface_index)
			var destination_vertices: PackedVector3Array = target_arrays[Mesh.ARRAY_VERTEX]
			base_arrays = target_arrays.duplicate(true)
			primitive = target_mesh.surface_get_primitive_type(surface_index)
			if surface_index < source_surface_count:
				var source_arrays: Array = source_surfaces[surface_index]
				var source_vertices: PackedVector3Array = source_arrays[Mesh.ARRAY_VERTEX]
				var map := _map_overlay_vertices(source_vertices, destination_vertices, source_arrays, target_arrays)
				base_arrays[Mesh.ARRAY_VERTEX] = _mapped_positions(source_vertices, map)
				var source_colors: PackedColorArray = source_arrays[Mesh.ARRAY_COLOR]
				if not source_colors.is_empty():
					base_arrays[Mesh.ARRAY_COLOR] = _mapped_colors(source_colors, map)
			else:
				base_arrays[Mesh.ARRAY_VERTEX] = _repeat_point(source_center, destination_vertices.size())
			target_vertices = destination_vertices
		else:
			var source_arrays: Array = source_surfaces[surface_index]
			var source_vertices: PackedVector3Array = source_arrays[Mesh.ARRAY_VERTEX]
			base_arrays = source_arrays.duplicate(true)
			target_vertices = _repeat_point(target_center, source_vertices.size())
		var transition_shape := _overlay_transition_shape(base_arrays, target_vertices)
		transition_mesh.add_surface_from_arrays(
			primitive,
			base_arrays,
			[transition_shape]
		)
		transition_mesh.surface_set_material(surface_index, _overlay_material)
	return transition_mesh


func _overlay_topology_matches(source_mesh: ArrayMesh, target_mesh: ArrayMesh) -> bool:
	if source_mesh == null or target_mesh == null \
		or source_mesh.get_surface_count() != target_mesh.get_surface_count():
		return false
	for surface_index in range(source_mesh.get_surface_count()):
		var source_arrays: Array = source_mesh.surface_get_arrays(surface_index)
		var target_arrays: Array = target_mesh.surface_get_arrays(surface_index)
		var source_vertices: PackedVector3Array = source_arrays[Mesh.ARRAY_VERTEX]
		var target_vertices: PackedVector3Array = target_arrays[Mesh.ARRAY_VERTEX]
		if source_vertices.size() != target_vertices.size():
			return false
		var source_indices: Variant = source_arrays[Mesh.ARRAY_INDEX]
		var target_indices: Variant = target_arrays[Mesh.ARRAY_INDEX]
		if source_indices != target_indices:
			return false
	return true


func _should_close_mouth_in_two_phases(source_instance: MeshInstance3D, neutral_mesh: ArrayMesh, target_index: int) -> bool:
	if target_index in OPEN_MOUTH_POSE_INDICES or source_instance == null or neutral_mesh == null:
		return false
	var source_arrays := _get_effective_surface_arrays(source_instance, 0)
	if source_arrays.is_empty() or neutral_mesh.get_surface_count() == 0:
		return false
	var source_vertices: PackedVector3Array = source_arrays[Mesh.ARRAY_VERTEX]
	var neutral_arrays: Array = neutral_mesh.surface_get_arrays(0)
	var neutral_vertices: PackedVector3Array = neutral_arrays[Mesh.ARRAY_VERTEX]
	var source_height := _overlay_vertical_span(source_vertices)
	var neutral_height := _overlay_vertical_span(neutral_vertices)
	return source_height > maxf(neutral_height * 1.45, neutral_height + 0.008)


func _overlay_vertical_span(vertices: PackedVector3Array) -> float:
	if vertices.is_empty():
		return 0.0
	var min_y := INF
	var max_y := -INF
	for vertex in vertices:
		min_y = minf(min_y, vertex.y)
		max_y = maxf(max_y, vertex.y)
	return max_y - min_y


func _build_mouth_close_transition(source_instance: MeshInstance3D, neutral_mesh: ArrayMesh) -> ArrayMesh:
	var source_mesh := source_instance.mesh as ArrayMesh
	if source_mesh == null or neutral_mesh == null:
		return null
	var source_surfaces: Array[Array] = []
	for surface_index in range(source_mesh.get_surface_count()):
		source_surfaces.append(_get_effective_surface_arrays(source_instance, surface_index))
	var neutral_center := _overlay_mesh_center_from_mesh(neutral_mesh)
	var transition_mesh := ArrayMesh.new()
	transition_mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	transition_mesh.add_blend_shape(TRANSITION_BLEND_SHAPE)
	for surface_index in range(source_surfaces.size()):
		var source_arrays: Array = source_surfaces[surface_index]
		var source_vertices: PackedVector3Array = source_arrays[Mesh.ARRAY_VERTEX]
		var closed_vertices: PackedVector3Array
		if surface_index < neutral_mesh.get_surface_count():
			var neutral_arrays: Array = neutral_mesh.surface_get_arrays(surface_index)
			var neutral_vertices: PackedVector3Array = neutral_arrays[Mesh.ARRAY_VERTEX]
			var map := _map_overlay_vertices(neutral_vertices, source_vertices, neutral_arrays, source_arrays)
			closed_vertices = _mapped_positions(neutral_vertices, map)
			closed_vertices = _scale_vertices_around(neutral_center, closed_vertices, CLOSED_MOUTH_MIDPOINT_SCALE)
		else:
			closed_vertices = _repeat_point(neutral_center, source_vertices.size())
		var base_arrays: Array = source_arrays.duplicate(true)
		transition_mesh.add_surface_from_arrays(
			source_mesh.surface_get_primitive_type(surface_index),
			base_arrays,
			[_overlay_transition_shape(base_arrays, closed_vertices)]
		)
		var material := source_mesh.surface_get_material(surface_index)
		transition_mesh.surface_set_material(surface_index, _overlay_material if material == null else material)
	return transition_mesh


func _build_mouth_open_transition(target_mesh: ArrayMesh, neutral_mesh: ArrayMesh) -> ArrayMesh:
	if target_mesh == null or neutral_mesh == null:
		return null
	var neutral_center := _overlay_mesh_center_from_mesh(neutral_mesh)
	var transition_mesh := ArrayMesh.new()
	transition_mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	transition_mesh.add_blend_shape(TRANSITION_BLEND_SHAPE)
	for surface_index in range(target_mesh.get_surface_count()):
		var target_arrays: Array = target_mesh.surface_get_arrays(surface_index)
		var target_vertices: PackedVector3Array = target_arrays[Mesh.ARRAY_VERTEX]
		var closed_vertices: PackedVector3Array
		if surface_index < neutral_mesh.get_surface_count():
			var neutral_arrays: Array = neutral_mesh.surface_get_arrays(surface_index)
			var neutral_vertices: PackedVector3Array = neutral_arrays[Mesh.ARRAY_VERTEX]
			var map := _map_overlay_vertices(neutral_vertices, target_vertices, neutral_arrays, target_arrays)
			closed_vertices = _mapped_positions(neutral_vertices, map)
			closed_vertices = _scale_vertices_around(neutral_center, closed_vertices, CLOSED_MOUTH_MIDPOINT_SCALE)
		else:
			closed_vertices = _repeat_point(neutral_center, target_vertices.size())
		var base_arrays: Array = target_arrays.duplicate(true)
		base_arrays[Mesh.ARRAY_VERTEX] = closed_vertices
		transition_mesh.add_surface_from_arrays(
			target_mesh.surface_get_primitive_type(surface_index),
			base_arrays,
			[_overlay_transition_shape(base_arrays, target_vertices)]
		)
		transition_mesh.surface_set_material(surface_index, target_mesh.surface_get_material(surface_index))
	return transition_mesh


func _get_effective_surface_arrays(mesh_instance: MeshInstance3D, surface_index: int) -> Array:
	if mesh_instance == null or not is_instance_valid(mesh_instance):
		return []
	var mesh := mesh_instance.mesh as ArrayMesh
	if mesh == null or surface_index < 0 or surface_index >= mesh.get_surface_count():
		return []
	var arrays: Array = mesh.surface_get_arrays(surface_index).duplicate(true)
	var transition_shape_index: int = _find_mesh_blend_shape(mesh, TRANSITION_BLEND_SHAPE)
	if transition_shape_index < 0:
		return arrays
	var blend_shape_arrays: Array = mesh.surface_get_blend_shape_arrays(surface_index)
	if transition_shape_index >= blend_shape_arrays.size():
		return arrays
	var transition_shape: Array = blend_shape_arrays[transition_shape_index]
	var weight := mesh_instance.get_blend_shape_value(transition_shape_index)
	if weight <= 0.0:
		return arrays
	var relative := mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_RELATIVE
	for attribute in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL]:
		var base_value: Variant = arrays[attribute]
		var shape_value: Variant = transition_shape[attribute]
		if not base_value is PackedVector3Array or not shape_value is PackedVector3Array:
			continue
		var base_values: PackedVector3Array = base_value
		var shape_values: PackedVector3Array = shape_value
		if base_values.is_empty() or shape_values.size() != base_values.size():
			continue
		arrays[attribute] = _apply_vector_shape(base_values, shape_values, weight, relative)
	var base_tangent_value: Variant = arrays[Mesh.ARRAY_TANGENT]
	var shape_tangent_value: Variant = transition_shape[Mesh.ARRAY_TANGENT]
	if base_tangent_value is PackedFloat32Array and shape_tangent_value is PackedFloat32Array:
		var base_tangents: PackedFloat32Array = base_tangent_value
		var shape_tangents: PackedFloat32Array = shape_tangent_value
		if not base_tangents.is_empty() and shape_tangents.size() == base_tangents.size():
			arrays[Mesh.ARRAY_TANGENT] = _apply_float_shape(base_tangents, shape_tangents, weight, relative)
	return arrays


func _make_transition_shape_arrays(base_arrays: Array, target_arrays: Array, mode: int) -> Array:
	var result: Array = []
	result.resize(Mesh.ARRAY_MAX)
	var relative := mode == Mesh.BLEND_SHAPE_MODE_RELATIVE
	for attribute in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL]:
		var base_value: Variant = base_arrays[attribute]
		var target_value: Variant = target_arrays[attribute]
		if not target_value is PackedVector3Array:
			continue
		var target_values: PackedVector3Array = target_value
		var base_values: PackedVector3Array = base_value if base_value is PackedVector3Array else PackedVector3Array()
		if target_values.is_empty():
			continue
		if relative and base_values.size() == target_values.size():
			var difference := PackedVector3Array()
			difference.resize(target_values.size())
			for vertex_index in range(target_values.size()):
				difference[vertex_index] = target_values[vertex_index] - base_values[vertex_index]
			result[attribute] = difference
		else:
			result[attribute] = target_values
	var base_tangent_value: Variant = base_arrays[Mesh.ARRAY_TANGENT]
	var target_tangent_value: Variant = target_arrays[Mesh.ARRAY_TANGENT]
	if target_tangent_value is PackedFloat32Array:
		var target_tangents: PackedFloat32Array = target_tangent_value
		var base_tangents: PackedFloat32Array = base_tangent_value if base_tangent_value is PackedFloat32Array else PackedFloat32Array()
		if relative and base_tangents.size() == target_tangents.size():
			var difference := PackedFloat32Array()
			difference.resize(target_tangents.size())
			for value_index in range(target_tangents.size()):
				difference[value_index] = target_tangents[value_index] - base_tangents[value_index]
			result[Mesh.ARRAY_TANGENT] = difference
		else:
			result[Mesh.ARRAY_TANGENT] = target_tangents
	return result


func _overlay_transition_shape(base_arrays: Array, target_vertices: PackedVector3Array) -> Array:
	var result: Array = []
	result.resize(Mesh.ARRAY_MAX)
	result[Mesh.ARRAY_VERTEX] = target_vertices
	return result


func _find_mesh_blend_shape(mesh: ArrayMesh, shape_name: StringName) -> int:
	if mesh == null:
		return -1
	for blend_shape_index in range(mesh.get_blend_shape_count()):
		if mesh.get_blend_shape_name(blend_shape_index) == shape_name:
			return blend_shape_index
	return -1


func _map_overlay_vertices(source_vertices: PackedVector3Array, target_vertices: PackedVector3Array, source_arrays: Array, target_arrays: Array) -> PackedInt32Array:
	if source_vertices.size() == target_vertices.size():
		var source_indices: PackedInt32Array = source_arrays[Mesh.ARRAY_INDEX]
		var target_indices: PackedInt32Array = target_arrays[Mesh.ARRAY_INDEX]
		if source_indices == target_indices:
			var identity := PackedInt32Array()
			identity.resize(target_vertices.size())
			for vertex_index in range(identity.size()):
				identity[vertex_index] = vertex_index
			return identity
	var map := PackedInt32Array()
	map.resize(target_vertices.size())
	for target_index in range(target_vertices.size()):
		var nearest_index := 0
		var nearest_distance := INF
		for source_index in range(source_vertices.size()):
			var distance := target_vertices[target_index].distance_squared_to(source_vertices[source_index])
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_index = source_index
		map[target_index] = nearest_index
	return map


func _mapped_positions(source_vertices: PackedVector3Array, map: PackedInt32Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	result.resize(map.size())
	for vertex_index in range(map.size()):
		result[vertex_index] = source_vertices[map[vertex_index]]
	return result


func _mapped_colors(source_colors: PackedColorArray, map: PackedInt32Array) -> PackedColorArray:
	var result := PackedColorArray()
	result.resize(map.size())
	for vertex_index in range(map.size()):
		result[vertex_index] = source_colors[map[vertex_index]]
	return result


func _repeat_point(point: Vector3, count: int) -> PackedVector3Array:
	var result := PackedVector3Array()
	result.resize(count)
	for vertex_index in range(count):
		result[vertex_index] = point
	return result


func _scale_vertices_around(center: Vector3, vertices: PackedVector3Array, scale: float) -> PackedVector3Array:
	var result := PackedVector3Array()
	result.resize(vertices.size())
	for vertex_index in range(vertices.size()):
		result[vertex_index] = center + (vertices[vertex_index] - center) * scale
	return result


func _overlay_mesh_center(arrays: Array[Array]) -> Vector3:
	if arrays.is_empty():
		return Vector3.ZERO
	var vertices: PackedVector3Array = arrays[0][Mesh.ARRAY_VERTEX]
	return _average_vertex_position(vertices)


func _overlay_mesh_center_from_mesh(mesh: ArrayMesh) -> Vector3:
	if mesh == null or mesh.get_surface_count() == 0:
		return Vector3.ZERO
	var arrays: Array = mesh.surface_get_arrays(0)
	return _average_vertex_position(arrays[Mesh.ARRAY_VERTEX])


func _average_vertex_position(vertices: PackedVector3Array) -> Vector3:
	if vertices.is_empty():
		return Vector3.ZERO
	var total := Vector3.ZERO
	for vertex in vertices:
		total += vertex
	return total / float(vertices.size())


func _apply_vector_shape(base_values: PackedVector3Array, shape_values: PackedVector3Array, weight: float, relative: bool) -> PackedVector3Array:
	var result := PackedVector3Array()
	result.resize(base_values.size())
	for vertex_index in range(base_values.size()):
		result[vertex_index] = base_values[vertex_index] + shape_values[vertex_index] * weight \
			if relative else base_values[vertex_index].lerp(shape_values[vertex_index], weight)
	return result


func _apply_float_shape(base_values: PackedFloat32Array, shape_values: PackedFloat32Array, weight: float, relative: bool) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(base_values.size())
	for value_index in range(base_values.size()):
		result[value_index] = base_values[value_index] + shape_values[value_index] * weight \
			if relative else lerpf(base_values[value_index], shape_values[value_index], weight)
	return result


func _set_transition_weights(weight: float) -> void:
	if _face != null and _blend_face_shape_index >= 0:
		_face.set_blend_shape_value(_blend_face_shape_index, weight)
	if not _blend_mouth_two_phase and _mouth_overlay != null and _blend_mouth_shape_index >= 0:
		_mouth_overlay.set_blend_shape_value(_blend_mouth_shape_index, weight)
	if _brow_overlay != null and _blend_brow_shape_index >= 0:
		_brow_overlay.set_blend_shape_value(_blend_brow_shape_index, weight)


func _update_mouth_transition_weight() -> void:
	if _mouth_overlay == null or not _blend_active:
		return
	var weight := _blend_eased_weight()
	if not _blend_mouth_two_phase:
		if _blend_mouth_shape_index >= 0:
			_mouth_overlay.set_blend_shape_value(_blend_mouth_shape_index, weight)
		return
	var linear_weight := clampf(_blend_elapsed / _blend_duration, 0.0, 1.0)
	if linear_weight <= 0.5:
		if _mouth_overlay.mesh != _blend_mouth_close_mesh:
			_mouth_overlay.mesh = _blend_mouth_close_mesh
			_blend_mouth_shape_index = _find_mesh_blend_shape(_blend_mouth_close_mesh, TRANSITION_BLEND_SHAPE)
			if _blend_mouth_shape_index >= 0:
				_mouth_overlay.set_blend_shape_value(_blend_mouth_shape_index, 0.0)
		var phase_weight := linear_weight * 2.0
		phase_weight = phase_weight * phase_weight * (3.0 - 2.0 * phase_weight)
		if _blend_mouth_shape_index >= 0:
			_mouth_overlay.set_blend_shape_value(_blend_mouth_shape_index, phase_weight)
	else:
		if _mouth_overlay.mesh != _blend_mouth_open_mesh:
			_mouth_overlay.mesh = _blend_mouth_open_mesh
			_blend_mouth_shape_index = _blend_mouth_open_shape_index
			if _blend_mouth_shape_index >= 0:
				_mouth_overlay.set_blend_shape_value(_blend_mouth_shape_index, 0.0)
		var phase_weight := (linear_weight - 0.5) * 2.0
		phase_weight = phase_weight * phase_weight * (3.0 - 2.0 * phase_weight)
		if _blend_mouth_shape_index >= 0:
			_mouth_overlay.set_blend_shape_value(_blend_mouth_shape_index, phase_weight)


func _finish_blend() -> void:
	var target_index := _blend_target_index
	var target_face := _blend_target_face_mesh
	var target_mouth := _blend_target_mouth_mesh
	var target_brow := _blend_target_brow_mesh
	var target_closed_weight := _blend_target_eye_closed
	var original_shape_values := _capture_original_shape_values()
	_clear_blend_state()
	if target_index < 0:
		clear_pose()
		return
	_face.mesh = target_face
	_pose_mesh = target_face
	_pose_index = target_index
	_mouth_overlay.mesh = target_mouth
	_brow_overlay.mesh = target_brow
	_mouth_overlay.show()
	_brow_overlay.show()
	_face.set_surface_override_material(_mouth_surface_index, _transparent_face_material)
	_apply_original_shape_values(original_shape_values)
	_set_eye_closed_weight(target_closed_weight)
	_bite_overlays_hidden = false
	_update_mouth_overlay_for_bite()


func _clear_blend_state() -> void:
	_blend_active = false
	_blend_target_index = -1
	_blend_elapsed = 0.0
	_blend_duration = 0.0
	_blend_start_eye_closed = 0.0
	_blend_target_eye_closed = 0.0
	_blend_start_shape_values.clear()
	_blend_target_face_mesh = null
	_blend_target_mouth_mesh = null
	_blend_target_brow_mesh = null
	_blend_mouth_close_mesh = null
	_blend_mouth_open_mesh = null
	_blend_mouth_two_phase = false
	_blend_face_shape_index = -1
	_blend_mouth_shape_index = -1
	_blend_mouth_open_shape_index = -1
	_blend_brow_shape_index = -1


func _blend_eased_weight() -> float:
	if _blend_duration <= 0.0:
		return 1.0
	var weight := clampf(_blend_elapsed / _blend_duration, 0.0, 1.0)
	return weight * weight * (3.0 - 2.0 * weight)


func _capture_original_shape_values() -> Dictionary:
	var values: Dictionary = {}
	if _face == null or not is_instance_valid(_face) or _original_mesh == null:
		return values
	for blend_shape_index in range(_original_mesh.get_blend_shape_count()):
		var shape_name := _original_mesh.get_blend_shape_name(blend_shape_index)
		if blend_shape_index < _face.get_blend_shape_count():
			values[shape_name] = _face.get_blend_shape_value(blend_shape_index)
	return values


func _apply_original_shape_values(values: Dictionary) -> void:
	if _face == null or not is_instance_valid(_face):
		return
	for shape_name in values:
		var shape_index := _face.find_blend_shape_by_name(shape_name)
		if shape_index >= 0:
			_face.set_blend_shape_value(shape_index, float(values[shape_name]))


func _current_shape_value(shape_name: StringName) -> float:
	var fallback := float(_last_shape_fallbacks.get(shape_name, _juice_shape_fallback(shape_name)))
	if _blend_active:
		var start_value := float(_blend_start_shape_values.get(shape_name, fallback))
		var target_value := fallback if _blend_target_index < 0 \
			else _get_pose_shape_value(_blend_target_index, shape_name)
		return lerpf(start_value, target_value, _blend_eased_weight())
	if _pose_index < 0:
		return fallback
	return _get_pose_shape_value(_pose_index, shape_name)


func _juice_shape_fallback(shape_name: StringName) -> float:
	if _juice == null or not is_instance_valid(_juice):
		return 0.0
	match shape_name:
		&"Expr_Happy": return _juice.morph_happy
		&"Expr_Focused": return _juice.morph_focused
		&"Expr_Effort": return _juice.morph_effort
		&"Expr_Surprised": return _juice.morph_surprised
	return 0.0


func _get_pose_shape_value(index: int, shape_name: StringName) -> float:
	var pose_name: String = POSE_NAMES[index]
	var overrides: Dictionary = POSE_BLEND_SHAPES.get(pose_name, {})
	return float(overrides.get(String(shape_name), 0.0))


func _set_eye_closed_weight(weight: float) -> void:
	_eye_closed_weight = clampf(weight, 0.0, 1.0)
	if _face == null or not is_instance_valid(_face):
		return
	for surface_index in _eye_surface_indices:
		if _eye_closed_weight <= 0.001:
			_face.set_surface_override_material(surface_index, _original_surface_overrides[surface_index])
		elif _eye_closed_weight >= 0.999:
			_face.set_surface_override_material(surface_index, _transparent_face_material)
		elif _eye_fade_materials.has(surface_index):
			var fade: Dictionary = _eye_fade_materials[surface_index]
			var material := fade.material as StandardMaterial3D
			var color := material.albedo_color
			color.a = float(fade.base_alpha) * (1.0 - _eye_closed_weight)
			material.albedo_color = color
			_face.set_surface_override_material(surface_index, material)
		else:
			_face.set_surface_override_material(
				surface_index,
				_transparent_face_material if _eye_closed_weight >= 0.5 else _original_surface_overrides[surface_index]
			)


func _create_face_overlays() -> void:
	var head_bone := _skeleton.find_bone("head")
	if head_bone < 0:
		push_error("ChibiExpressionFace could not locate the head bone.")
		return
	_face_attachment = BoneAttachment3D.new()
	_face_attachment.name = "ExpressionFaceAttachment"
	_face_attachment.bone_name = &"head"
	_skeleton.add_child(_face_attachment)
	var overlay_transform := _skeleton.get_bone_global_rest(head_bone).affine_inverse()
	_mouth_overlay = MeshInstance3D.new()
	_mouth_overlay.name = "ExpressionMouth"
	_mouth_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mouth_overlay.transform = overlay_transform
	_face_attachment.add_child(_mouth_overlay)
	_brow_overlay = MeshInstance3D.new()
	_brow_overlay.name = "ExpressionBrows"
	_brow_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_brow_overlay.transform = overlay_transform
	_face_attachment.add_child(_brow_overlay)


func _update_mouth_overlay_for_bite() -> void:
	if _mouth_overlay == null or _face == null or _pose_mesh == null:
		return
	var bite_weight := 0.0
	if _juice != null and is_instance_valid(_juice) and _juice.dive_gear != null:
		bite_weight = _juice.dive_gear.mouthpiece_weight
	var hide_mouth := bite_weight >= BITE_OVERLAY_HIDE_THRESHOLD
	if hide_mouth == _bite_overlays_hidden:
		return
	_bite_overlays_hidden = hide_mouth
	if hide_mouth:
		_mouth_overlay.hide()
		_face.set_surface_override_material(
			_mouth_surface_index,
			_original_surface_overrides[_mouth_surface_index]
		)
	else:
		_face.set_surface_override_material(_mouth_surface_index, _transparent_face_material)
		_mouth_overlay.show()


func _eyes_are_closed(pose_name: String) -> bool:
	return pose_name == "e05" or pose_name == "crying"


func _build_pose_mesh(pose_name: String, mood_pose: bool) -> ArrayMesh:
	var body := ArrayMesh.new()
	body.blend_shape_mode = _original_mesh.blend_shape_mode
	for blend_shape_index in range(_original_mesh.get_blend_shape_count()):
		body.add_blend_shape(_original_mesh.get_blend_shape_name(blend_shape_index))
	var stretch: Vector4 = MOOD_EYE_WARP.get(pose_name, Vector4(1.0, 1.0, 0.0, 0.0)) if mood_pose \
		else ENSEMBLE_EYE_WARP.get(pose_name, Vector4(1.0, 1.0, 0.0, 0.0))
	for surface_index in range(_original_mesh.get_surface_count()):
		var arrays: Array = _original_mesh.surface_get_arrays(surface_index)
		var surface_material := _original_mesh.surface_get_material(surface_index)
		if surface_material != null:
			var material_name: String = surface_material.resource_name
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if material_name in EYE_SURFACES:
				for vertex_index in range(vertices.size()):
					var point := vertices[vertex_index]
					var side := signf(point.x)
					var local_x := absf(point.x) - 0.105
					var iris_scale := 1.0
					if material_name != "M_Chibi_EyeDark":
						if pose_name == "gasp" or pose_name == "squeal":
							iris_scale = 0.946
						if pose_name == "scared":
							iris_scale = 0.73 if mood_pose else 0.83
					var abs_x := local_x * stretch.x * iris_scale + 0.105
					var pos_y := (point.y - 0.754) * stretch.y * iris_scale + 0.754 \
						+ stretch.z * local_x / 0.065 + stretch.w
					if pose_name == "e14" and side < 0.0:
						pos_y = 0.749 + (pos_y - 0.754) * 0.43
					if pose_name == "sleepy" and side < 0.0:
						pos_y = 0.74 + (pos_y - 0.74) * 0.20
					if pose_name == "scared" and side < 0.0:
						pos_y = 0.75 + (pos_y - 0.75) * 0.87
					var pos_z := point.z + (pos_y - point.y) * 0.26 - (abs_x - absf(point.x)) * 0.29 + 0.002
					vertices[vertex_index] = Vector3(abs_x * side, pos_y, pos_z)
				arrays[Mesh.ARRAY_VERTEX] = vertices
				if pose_name == "e06":
					arrays[Mesh.ARRAY_INDEX] = _filter_triangles(
						arrays[Mesh.ARRAY_INDEX], vertices,
						func(point_in_triangle: Vector3) -> bool: return point_in_triangle.x > 0.0
					)
			elif material_name == "M_Chibi_Blush" and pose_name == "angry":
				for vertex_index in range(vertices.size()):
					var point := vertices[vertex_index]
					var pivot := Vector3(signf(point.x) * 0.168, 0.675, point.z)
					vertices[vertex_index] = pivot + (point - pivot) * Vector3(1.10, 1.13, 1.0)
				arrays[Mesh.ARRAY_VERTEX] = vertices
			elif material_name == "M_Chibi_Hair":
				arrays[Mesh.ARRAY_INDEX] = _filter_triangles(
					arrays[Mesh.ARRAY_INDEX], vertices, _is_original_brow
				)
		var flags := _original_mesh.surface_get_format(surface_index) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		body.add_surface_from_arrays(
			_original_mesh.surface_get_primitive_type(surface_index),
			arrays,
			_original_mesh.surface_get_blend_shape_arrays(surface_index),
			{},
			flags
		)
		body.surface_set_material(surface_index, surface_material)
	return body


func _build_overlay_mesh(shape_name: String, mood_pose: bool) -> ArrayMesh:
	var geometry: Dictionary = _get_geometry_library(mood_pose)
	var layers: Variant = geometry.get(shape_name, null)
	if not layers is Array:
		return null
	var mesh := ArrayMesh.new()
	for layer_value in layers:
		if not layer_value is Dictionary:
			continue
		var layer: Dictionary = layer_value
		var vertices: Array = layer.get("vertices", [])
		var triangles: Array = layer.get("triangles", [])
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_material(_overlay_material)
		for row_value in vertices:
			var row: Array = row_value
			if row.size() < 6:
				continue
			surface.set_color(Color(float(row[3]), float(row[4]), float(row[5])))
			surface.add_vertex(Vector3(float(row[0]), float(row[1]), float(row[2])))
		for triangle_index in triangles:
			surface.add_index(int(triangle_index))
		surface.commit(mesh)
	return mesh if mesh.get_surface_count() > 0 else null


func _get_geometry_library(mood_pose: bool) -> Dictionary:
	if mood_pose:
		if _moods_geometry.is_empty():
			_moods_geometry = _load_geometry(MOODS_GEOMETRY_PATH)
		return _moods_geometry
	if _ensemble_geometry.is_empty():
		_ensemble_geometry = _load_geometry(ENSEMBLE_GEOMETRY_PATH)
	return _ensemble_geometry


func _load_geometry(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Chibi face geometry file is missing: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Chibi face geometry file could not be opened: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Chibi face geometry file is not a JSON object: %s" % path)
		return {}
	return parsed


func _get_surface_material(mesh_instance: MeshInstance3D, surface_index: int) -> Material:
	# Read the immutable mesh material first. Surface overrides change during pose
	# swaps (closed eyes use a transparent override) and must not affect classification.
	var material: Material
	if mesh_instance.mesh != null:
		material = mesh_instance.mesh.surface_get_material(surface_index)
	if material == null:
		material = mesh_instance.get_surface_override_material(surface_index)
	return material


func _find_face_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh is ArrayMesh:
			var has_eyes := false
			var has_mouth := false
			for surface_index in range(mesh_instance.mesh.get_surface_count()):
				var material := _get_surface_material(mesh_instance, surface_index)
				if material == null:
					continue
				has_eyes = has_eyes or material.resource_name in EYE_SURFACES
				has_mouth = has_mouth or material.resource_name.contains("M_Chibi_Mouth")
			if has_eyes and has_mouth:
				return mesh_instance
	for child in node.get_children():
		var result := _find_face_mesh(child)
		if result != null:
			return result
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var result := _find_skeleton(child)
		if result != null:
			return result
	return null


func _find_juice(node: Node) -> ChibiJuice:
	if node is ChibiJuice:
		return node as ChibiJuice
	for child in node.get_children():
		var result := _find_juice(child)
		if result != null:
			return result
	return null


func _find_rig_binder(node: Node) -> ChibiRigBinder:
	if node is ChibiRigBinder:
		return node as ChibiRigBinder
	for child in node.get_children():
		var result := _find_rig_binder(child)
		if result != null:
			return result
	return null


func _is_original_brow(point: Vector3) -> bool:
	return point.y >= 0.850 and point.y <= 0.860 and absf(point.x) >= 0.073 \
		and absf(point.x) <= 0.139 and point.z >= 0.228


func _filter_triangles(
	indices: PackedInt32Array,
	vertices: PackedVector3Array,
	exclude: Callable
) -> PackedInt32Array:
	var visible := PackedInt32Array()
	for triangle_start in range(0, indices.size(), 3):
		var a := indices[triangle_start]
		var b := indices[triangle_start + 1]
		var c := indices[triangle_start + 2]
		if exclude.call(vertices[a]) and exclude.call(vertices[b]) and exclude.call(vertices[c]):
			continue
		visible.append(a)
		visible.append(b)
		visible.append(c)
	return visible
