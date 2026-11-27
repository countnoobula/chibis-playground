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
var _ensemble_geometry: Dictionary = {}
var _moods_geometry: Dictionary = {}
var _pose_index := -1
var _setup_complete := false
var _bite_overlays_hidden := false


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
	if _pose_index == index:
		_update_mouth_overlay_for_bite()
		return

	var pose_name: String = POSE_NAMES[index]
	var pose_mesh := _build_pose_mesh(pose_name, index >= 15)
	var mouth_mesh := _build_overlay_mesh(pose_name, index >= 15)
	var brow_mesh := _build_overlay_mesh("brow-" + pose_name, index >= 15)
	if pose_mesh == null or mouth_mesh == null or brow_mesh == null:
		push_error("ChibiExpressionFace could not build pose '%s' from its preview geometry." % pose_name)
		return

	_pose_index = index
	_pose_mesh = pose_mesh
	_face.mesh = _pose_mesh
	for surface_index in range(_original_mesh.get_surface_count()):
		var surface_material := _get_surface_material(_face, surface_index)
		if surface_material != null and surface_material.resource_name in EYE_SURFACES:
			_face.set_surface_override_material(
				surface_index,
				_transparent_face_material if _eyes_are_closed(pose_name) else _original_surface_overrides[surface_index]
			)
	_face.set_surface_override_material(_mouth_surface_index, _transparent_face_material)
	_mouth_overlay.mesh = mouth_mesh
	_brow_overlay.mesh = brow_mesh
	_mouth_overlay.show()
	_brow_overlay.show()
	_bite_overlays_hidden = false
	_update_mouth_overlay_for_bite()


func clear_pose() -> void:
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
	_bite_overlays_hidden = false


## ChibiJuice is the only per-frame blend-shape writer. Active poses provide
## their approved baseline weights through this hook; blink and bite stay live.
func get_pose_blend_shape_value(shape_name: StringName, fallback: float) -> float:
	if _pose_index < 0:
		return fallback
	var pose_name: String = POSE_NAMES[_pose_index]
	var overrides: Dictionary = POSE_BLEND_SHAPES.get(pose_name, {})
	return float(overrides.get(String(shape_name), 0.0))


func get_pose_name(index: int) -> String:
	if index < 0 or index >= POSE_NAMES.size():
		return ""
	return POSE_NAMES[index]


func _process(_delta: float) -> void:
	if _pose_index >= 0:
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
	_mouth_surface_index = -1
	_pose_mesh = null
	_face_attachment = null
	_mouth_overlay = null
	_brow_overlay = null
	_transparent_face_material = null
	_overlay_material = null
	_ensemble_geometry.clear()
	_moods_geometry.clear()
	_pose_index = -1
	_setup_complete = false
	_bite_overlays_hidden = false


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
	if _mouth_overlay == null or _face == null or _pose_index < 0:
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
