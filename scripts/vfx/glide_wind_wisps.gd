class_name GlideWindWisps
extends MeshInstance3D

## Small world-space ribbons that catch the latest rendered glide path beside
## Chibi's shoulders. Kept separate from the running wind ribbon.

const SAMPLE_INTERVAL := 0.02
const TRAIL_LIFETIME := 0.21
const MAX_SAMPLES := 14
const SHOULDER_HEIGHT := 0.66
const SHOULDER_SIDE := 0.33
const SHOULDER_BACK := 0.16
const LIFT_AT_TAIL := 0.035

var _controller: ParkourController
var _immediate_mesh: ImmediateMesh
var _material: StandardMaterial3D
var _left_points: Array[Vector3] = []
var _right_points: Array[Vector3] = []
var _ages: Array[float] = []
var _sample_remainder := 0.0
var _previous_left := Vector3.ZERO
var _previous_right := Vector3.ZERO
var _head_left := Vector3.ZERO
var _head_right := Vector3.ZERO
var _head_age := 0.0
var _has_previous := false
var _has_history := false
var _emitting := false
var _visibility_weight := 0.0
var _motion_weight := 0.72
var _previous_actor_origin := Vector3.ZERO
var _has_actor_origin := false
var _previous_yaw := 0.0
var _has_previous_yaw := false


func bind_controller(controller: ParkourController) -> void:
	_controller = controller


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	global_transform = Transform3D.IDENTITY
	process_priority = 100
	_immediate_mesh = ImmediateMesh.new()
	mesh = _immediate_mesh
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.vertex_color_use_as_albedo = true
	_material.albedo_color = Color.WHITE
	_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	visible = false


func _process(delta: float) -> void:
	if not is_instance_valid(_controller):
		_clear_trail()
		return

	var phase: StringName = _controller.scarf_glide_phase
	var in_locomotion := _controller.current_state == "Locomotion"
	var on_floor := _controller.is_on_floor()
	var glide_phase := phase in [&"deploy", &"glide"]
	var can_emit := in_locomotion and glide_phase and not on_floor
	var closing_fade := in_locomotion and _has_history \
		and (phase == &"cancel" or (on_floor and phase == &"stow"))
	if not can_emit and not closing_fade:
		if not _has_history and not _emitting and _visibility_weight <= 0.0 and not visible:
			return
		_clear_trail()
		return

	var body_transform := _controller.get_global_transform_interpolated()
	var origin := body_transform.origin
	if _has_actor_origin and origin.distance_squared_to(_previous_actor_origin) > 1.0:
		# A large discontinuity is a zone teleport or respawn. Never connect it to
		# the previous flight, then seed fresh history on the next rendered frame.
		_clear_trail()
		_previous_actor_origin = origin
		_has_actor_origin = true
		return
	_previous_actor_origin = origin
	_has_actor_origin = true

	if can_emit:
		var anchors := _get_shoulder_anchors(body_transform)
		var left: Vector3 = anchors[0]
		var right: Vector3 = anchors[1]
		if not _has_previous:
			_previous_left = left
			_previous_right = right
			_head_left = left
			_head_right = right
			_push_sample(left, right, 0.0)
			_has_previous = true
		else:
			_age_samples(delta)
			_sample_render_interval(delta, left, right)
			_previous_left = left
			_previous_right = right
			_head_left = left
			_head_right = right
			_head_age = 0.0
			_has_history = not _ages.is_empty()
		_emitting = true
		_visibility_weight = move_toward(_visibility_weight, 1.0, maxf(delta, 0.0) * 8.0)
		_update_motion_weight(body_transform, delta)
	else:
		# Let the existing wisps feather away when the cloth closes.
		_emitting = false
		_age_samples(delta)
		_head_age += maxf(delta, 0.0)
		_visibility_weight = move_toward(_visibility_weight, 0.0, maxf(delta, 0.0) * 5.5)
		_has_history = not _ages.is_empty()
		if not _has_history or _head_age >= TRAIL_LIFETIME:
			_clear_trail()
			return

	_render_ribbons(phase)


func _get_shoulder_anchors(body_transform: Transform3D) -> Array[Vector3]:
	var frame := body_transform.basis.orthonormalized()
	var center := body_transform.origin + frame.y * SHOULDER_HEIGHT + frame.z * SHOULDER_BACK
	return [center - frame.x * SHOULDER_SIDE, center + frame.x * SHOULDER_SIDE]


func _sample_render_interval(delta: float, left: Vector3, right: Vector3) -> void:
	var frame_delta := maxf(delta, 0.0)
	if frame_delta <= 0.0:
		return
	var first_offset := SAMPLE_INTERVAL - _sample_remainder
	var accumulated := _sample_remainder + frame_delta
	while first_offset <= frame_delta + 0.000001:
		var fraction := clampf(first_offset / frame_delta, 0.0, 1.0)
		_push_sample(
			_previous_left.lerp(left, fraction),
			_previous_right.lerp(right, fraction),
			frame_delta - first_offset
		)
		first_offset += SAMPLE_INTERVAL
	_sample_remainder = fmod(accumulated, SAMPLE_INTERVAL)


func _push_sample(left: Vector3, right: Vector3, age: float) -> void:
	_left_points.push_front(left)
	_right_points.push_front(right)
	_ages.push_front(age)
	while _ages.size() > MAX_SAMPLES:
		_left_points.pop_back()
		_right_points.pop_back()
		_ages.pop_back()
	_has_history = not _ages.is_empty()


func _age_samples(delta: float) -> void:
	for index in _ages.size():
		_ages[index] += maxf(delta, 0.0)
	while not _ages.is_empty() and _ages.back() > TRAIL_LIFETIME:
		_left_points.pop_back()
		_right_points.pop_back()
		_ages.pop_back()
	_has_history = not _ages.is_empty()


func _update_motion_weight(body_transform: Transform3D, delta: float) -> void:
	var speed_down := clampf(-_controller.velocity.y / 5.8, 0.0, 1.0)
	var yaw := body_transform.basis.get_euler().y
	var turn := absf(_controller.scarf_glide_bank) * 0.65
	if _has_previous_yaw and delta > 0.0001:
		var yaw_rate := absf(wrapf(yaw - _previous_yaw, -PI, PI)) / delta
		turn = maxf(turn, clampf(yaw_rate / 4.5, 0.0, 1.0) * 0.55)
	_previous_yaw = yaw
	_has_previous_yaw = true
	var target := 0.72 + speed_down * 0.16 + turn * 0.10
	_motion_weight = lerpf(_motion_weight, target, 1.0 - exp(-6.0 * maxf(delta, 0.0)))


func _render_ribbons(phase: StringName) -> void:
	if _immediate_mesh == null:
		return
	_immediate_mesh.clear_surfaces()
	if not _has_history or _visibility_weight <= 0.001:
		visible = false
		return

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		visible = false
		return
	var open_weight := clampf(_controller.scarf_glide_progress, 0.0, 1.0) if phase == &"deploy" else 1.0
	var visibility := _visibility_weight * _motion_weight * open_weight
	if not _emitting:
		visibility = _visibility_weight * _motion_weight
	if visibility <= 0.001:
		visible = false
		return

	var left_path: Array[Vector3] = [_head_left]
	var right_path: Array[Vector3] = [_head_right]
	var path_ages: Array[float] = [_head_age]
	for index in _ages.size():
		left_path.append(_left_points[index])
		right_path.append(_right_points[index])
		path_ages.append(_ages[index])
	if left_path.size() < 2:
		visible = false
		return

	var camera_position := camera.get_global_transform_interpolated().origin
	_draw_wisp(left_path, path_ages, camera_position, visibility, true)
	_draw_wisp(left_path, path_ages, camera_position, visibility, false)
	_draw_wisp(right_path, path_ages, camera_position, visibility, true)
	_draw_wisp(right_path, path_ages, camera_position, visibility, false)
	visible = true


func _draw_wisp(
	points: Array[Vector3], ages: Array[float], camera_position: Vector3,
	visibility: float, feather: bool
) -> void:
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for index in points.size():
		var age_ratio := clampf(ages[index] / TRAIL_LIFETIME, 0.0, 1.0)
		var taper := pow(1.0 - age_ratio, 0.82)
		var lead_fade := smoothstep(0.0, 0.17, age_ratio)
		var center := points[index] + Vector3.UP * (LIFT_AT_TAIL * age_ratio)
		var tangent: Vector3
		if index == 0:
			tangent = points[0] - points[1]
		elif index == points.size() - 1:
			tangent = points[index - 1] - points[index]
		else:
			tangent = points[index - 1] - points[index + 1]
		if tangent.length_squared() < 0.000001:
			tangent = Vector3.FORWARD
		else:
			tangent = tangent.normalized()
		var toward_camera := (camera_position - center).normalized()
		var side := tangent.cross(toward_camera)
		if side.length_squared() < 0.000001:
			side = tangent.cross(Vector3.UP)
		if side.length_squared() < 0.000001:
			side = Vector3.RIGHT
		side = side.normalized()
		var max_half_width := 0.034 if feather else 0.010
		var half_width := max_half_width * taper
		var rgb := Color(0.69, 0.65, 0.75) if feather else Color(1.0, 0.94, 0.81)
		var alpha := (0.18 if feather else 0.72) * lead_fade * taper * visibility
		var color := Color(rgb.r, rgb.g, rgb.b, alpha)
		_immediate_mesh.surface_set_color(color)
		_immediate_mesh.surface_add_vertex(center + side * half_width)
		_immediate_mesh.surface_set_color(color)
		_immediate_mesh.surface_add_vertex(center - side * half_width)
	_immediate_mesh.surface_end()


func _clear_trail() -> void:
	if not _has_history and not _emitting and _visibility_weight <= 0.0 and not visible:
		return
	_left_points.clear()
	_right_points.clear()
	_ages.clear()
	_sample_remainder = 0.0
	_has_previous = false
	_has_history = false
	_emitting = false
	_visibility_weight = 0.0
	_head_age = 0.0
	_has_actor_origin = false
	_has_previous_yaw = false
	if _immediate_mesh != null:
		_immediate_mesh.clear_surfaces()
	visible = false
