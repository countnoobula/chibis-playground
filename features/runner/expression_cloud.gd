extends Node3D
class_name RunnerExpressionCloud3D

## Upright thought cloud for runner expressions.
## Add this Node3D below the player and call show_pose(0..19) or clear_pose().

const POSE_TEXTURES: Array[Texture2D] = [
	preload("res://features/runner/expressions/cloud/cloud00.png"),
	preload("res://features/runner/expressions/cloud/cloud01.png"),
	preload("res://features/runner/expressions/cloud/cloud02.png"),
	preload("res://features/runner/expressions/cloud/cloud03.png"),
	preload("res://features/runner/expressions/cloud/cloud04.png"),
	preload("res://features/runner/expressions/cloud/cloud05.png"),
	preload("res://features/runner/expressions/cloud/cloud06.png"),
	preload("res://features/runner/expressions/cloud/cloud07.png"),
	preload("res://features/runner/expressions/cloud/cloud08.png"),
	preload("res://features/runner/expressions/cloud/cloud09.png"),
	preload("res://features/runner/expressions/cloud/cloud10.png"),
	preload("res://features/runner/expressions/cloud/cloud11.png"),
	preload("res://features/runner/expressions/cloud/cloud12.png"),
	preload("res://features/runner/expressions/cloud/cloud13.png"),
	preload("res://features/runner/expressions/cloud/cloud14.png"),
	preload("res://features/runner/expressions/cloud/cloud15.png"),
	preload("res://features/runner/expressions/cloud/cloud16.png"),
	preload("res://features/runner/expressions/cloud/cloud17.png"),
	preload("res://features/runner/expressions/cloud/cloud18.png"),
	preload("res://features/runner/expressions/cloud/cloud19.png"),
]

const FACE_WIDTH := 0.90
const FACE_HEIGHT := 0.99
const CLOUD_SHADER_CODE := """
shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, unshaded;

uniform sampler2D cloud_texture : source_color, filter_linear_mipmap, repeat_disable;

void fragment() {
	vec4 texel = texture(cloud_texture, UV);
	if (texel.a < 0.015) {
		discard;
	}

	ALBEDO = texel.rgb;
	ALPHA = texel.a;
}
"""

@export_range(0.0, 3.0, 0.01, "or_greater") var vertical_offset := 1.67
@export_range(-1.0, 1.0, 0.01) var camera_side_offset := 0.32
@export var follow_parent := true

var _current_pose := -1
var _last_valid_global_yaw := 0.0
var _visual_root: Node3D
var _face_material: ShaderMaterial
var _puffs: MultiMeshInstance3D
var _puff_material: StandardMaterial3D
var _puff_positions: Array[Vector3] = []


func _ready() -> void:
	visible = false
	_last_valid_global_yaw = global_rotation.y
	_build_cloud()
	_update_puff_colors()


func _process(_delta: float) -> void:
	if not visible or not follow_parent:
		return
	var host := get_parent_node_3d()
	if host == null:
		return

	var camera := get_viewport().get_camera_3d()
	var yaw := _last_valid_global_yaw
	var camera_right := Vector3(cos(yaw), 0.0, -sin(yaw))
	if camera != null:
		var toward_camera := camera.global_basis.z.slide(Vector3.UP)
		if toward_camera.length_squared() > 0.000001:
			toward_camera = toward_camera.normalized()
			yaw = atan2(toward_camera.x, toward_camera.z)
			_last_valid_global_yaw = yaw
		var flat_right := camera.global_basis.x.slide(Vector3.UP)
		if flat_right.length_squared() > 0.000001:
			camera_right = flat_right.normalized()

	global_position = host.global_position + Vector3.UP * vertical_offset + camera_right * camera_side_offset
	global_rotation = Vector3(0.0, yaw, 0.0)


## Shows one of the twenty approved face poses (indices 0 through 19).
func show_pose(index: int) -> void:
	if index < 0 or index >= POSE_TEXTURES.size():
		clear_pose()
		return
	_current_pose = index
	_refresh_pose()
	_update_puff_colors()
	visible = true


## Hides the cloud while keeping its meshes and textures ready for reuse.
func clear_pose() -> void:
	_current_pose = -1
	visible = false


func _build_cloud() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "CloudVisual"
	_visual_root.scale = Vector3(1.09, 1.09, 0.48)
	add_child(_visual_root)

	_puff_material = StandardMaterial3D.new()
	_puff_material.vertex_color_use_as_albedo = true
	_puff_material.roughness = 0.86
	_puff_material.emission_enabled = true
	_puff_material.emission = Color(0.10, 0.08, 0.08)
	_puff_material.emission_energy_multiplier = 0.18

	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 14
	sphere.rings = 8
	sphere.material = _puff_material

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = sphere
	multimesh.instance_count = 11
	_puffs = MultiMeshInstance3D.new()
	_puffs.name = "CloudVolume"
	_puffs.multimesh = multimesh
	_puffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual_root.add_child(_puffs)

	for i in range(9):
		var angle := TAU * float(i) / 9.0
		var radius := 0.150 + 0.012 * cos(angle * 3.0)
		_add_puff(multimesh, Vector3(0.207 * cos(angle), 0.198 * sin(angle), 0.0), Vector3(radius, radius, 0.105))
	_add_puff(multimesh, Vector3(-0.125, -0.373, 0.0), Vector3.ONE * 0.054)
	_add_puff(multimesh, Vector3(-0.182, -0.456, 0.0), Vector3.ONE * 0.027)

	var face := MeshInstance3D.new()
	face.name = "FaceTexture"
	var quad := QuadMesh.new()
	quad.size = Vector2(FACE_WIDTH, FACE_HEIGHT)
	face.mesh = quad
	face.position.z = 0.17
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_face_material = ShaderMaterial.new()
	_face_material.shader = Shader.new()
	_face_material.shader.code = CLOUD_SHADER_CODE
	face.material_override = _face_material
	_visual_root.add_child(face)


func _add_puff(multimesh: MultiMesh, origin: Vector3, radii: Vector3) -> void:
	var puff_transform := Transform3D(Basis.from_scale(radii), origin)
	multimesh.set_instance_transform(_puff_positions.size(), puff_transform)
	_puff_positions.append(origin)


func _refresh_pose() -> void:
	if _face_material == null or _current_pose < 0:
		return
	_face_material.set_shader_parameter("cloud_texture", POSE_TEXTURES[_current_pose])


func _update_puff_colors() -> void:
	if _puffs == null or _puffs.multimesh == null:
		return
	for i in range(_puff_positions.size()):
		_puffs.multimesh.set_instance_color(i, _puff_color(_puff_positions[i]))


func _puff_color(point: Vector3) -> Color:
	var height := clampf(inverse_lerp(-0.30, 0.26, point.y), 0.0, 1.0)
	match _current_pose:
		17:
			return Color("d74f62").lerp(Color("ffcfbd"), height)
		18:
			return Color("a6cde5").lerp(Color("fff2ef"), height)
		19:
			return Color("7386bb").lerp(Color("cce6f7"), height)
	return Color("fff1eb")
