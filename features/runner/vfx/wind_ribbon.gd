class_name WindRibbon
extends MeshInstance3D

## Lightweight Mobile-friendly ribbon trail (replaces Unreal NS_Chibi_WindRibbon).

@export var max_points: int = 18
@export var ribbon_width: float = 0.18
@export var sample_interval: float = 0.02

var _emitting: bool = false
var _points: Array[Vector3] = []
var _timer: float = 0.0
var _head := Vector3.ZERO
var _has_head := false
var _anchor: Node3D
var _imm: ImmediateMesh


func _ready() -> void:
	_anchor = get_parent() as Node3D
	top_level = true
	# ImmediateMesh vertices are already in world space.
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_imm = ImmediateMesh.new()
	mesh = _imm
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.85, 0.98, 1.0, 0.65)
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func set_emitting(enabled: bool) -> void:
	_emitting = enabled


func clear_trail() -> void:
	_emitting = false
	_has_head = false
	_timer = 0.0
	_points.clear()
	if _imm != null:
		_imm.clear_surfaces()


func _process(delta: float) -> void:
	if _anchor == null or (not _emitting and not _has_head):
		return
	if _emitting and not _has_head:
		_head = _anchor.get_global_transform_interpolated().origin
		_has_head = true
		_points.push_front(_head)
	else:
		_advance_trail(delta)

	_imm.clear_surfaces()
	if _points.is_empty():
		return
	_imm.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in _points.size() + 1:
		var t := 1.0 - float(i) / float(_points.size())
		var half_w := ribbon_width * 0.5 * t
		var p := _head if i == 0 else _points[i - 1]
		_imm.surface_set_color(Color(0.85, 0.98, 1.0, t * 0.65))
		_imm.surface_add_vertex(p + Vector3(0.0, half_w, 0.0))
		_imm.surface_set_color(Color(0.85, 0.98, 1.0, t * 0.65))
		_imm.surface_add_vertex(p - Vector3(0.0, half_w, 0.0))
	_imm.surface_end()


func _advance_trail(delta: float) -> void:
	var interval := maxf(sample_interval, 0.001)
	var history_limit := maxi(max_points - 1, 1)
	_timer += delta
	var elapsed_samples := floori(_timer / interval)
	_timer -= elapsed_samples * interval
	if _emitting:
		var current := _anchor.get_global_transform_interpolated().origin
		# Retain the sub-frame remainder so trail length holds at different render rates.
		for i in range(mini(elapsed_samples, history_limit) - 1, -1, -1):
			var age := _timer + i * interval
			var weight := clampf(age / maxf(delta, 0.001), 0.0, 1.0)
			_points.push_front(current.lerp(_head, weight))
		_points.resize(mini(_points.size(), history_limit))
		_head = current
	elif elapsed_samples > 0:
		_points.resize(maxi(0, _points.size() - elapsed_samples))
		if _points.is_empty():
			_has_head = false
			_timer = 0.0
