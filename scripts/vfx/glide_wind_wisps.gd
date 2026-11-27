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
var _skeleton: Skeleton3D
var _hand_r_bone: int = -1
var _foot_bones := PackedInt32Array([-1, -1])
var _cached_hand_r_local := Vector3.ZERO
var _cached_feet_local := PackedVector3Array()
var _cached_canopy_corners_local := PackedVector3Array()
var _has_cached_skeleton_pose: bool = false
var _has_cached_canopy_corners: bool = false
var _vfx_elapsed: float = 0.0
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
	_skeleton = _find_skeleton(controller)
	_cache_contact_bones()


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
	if _skeleton == null and is_instance_valid(_controller):
		_skeleton = _find_skeleton(_controller)
	_cache_contact_bones()


func _process(delta: float) -> void:
	if not is_instance_valid(_controller):
		_clear_trail()
		return
	var safe_delta := maxf(delta, 0.0)
	_vfx_elapsed += safe_delta
	if not is_instance_valid(_skeleton):
		_skeleton = _find_skeleton(_controller)
		_cache_contact_bones()

	var phase: StringName = _controller.scarf_glide_phase
	var in_locomotion := _controller.current_state == "Locomotion"
	var on_floor := _controller.is_on_floor()
	var glide_phase := phase in [&"deploy", &"glide"]
	var can_emit := in_locomotion and glide_phase and not on_floor
	var closing_fade := in_locomotion and _has_history \
		and (phase == &"cancel" or (on_floor and phase == &"stow"))
	var body_transform := _controller.get_global_transform_interpolated()
	var origin := body_transform.origin
	if _has_actor_origin and origin.distance_squared_to(_previous_actor_origin) > 1.0:
		# A large discontinuity is a zone teleport or respawn. Never connect it to
		# the previous flight, then seed fresh history on the next rendered frame.
		_clear_glide_trail()
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
			_age_samples(safe_delta)
			_sample_render_interval(safe_delta, left, right)
			_previous_left = left
			_previous_right = right
			_head_left = left
			_head_right = right
			_head_age = 0.0
			_has_history = not _ages.is_empty()
		_emitting = true
		_visibility_weight = move_toward(_visibility_weight, 1.0, safe_delta * 8.0)
		_update_motion_weight(body_transform, safe_delta)
	elif closing_fade:
		# Let the existing wisps feather away when the cloth closes.
		_emitting = false
		_age_samples(safe_delta)
		_head_age += safe_delta
		_visibility_weight = move_toward(_visibility_weight, 0.0, safe_delta * 5.5)
		_has_history = not _ages.is_empty()
		if not _has_history or _head_age >= TRAIL_LIFETIME:
			_clear_glide_trail()
	else:
		_clear_glide_trail()

	_render_ribbons(phase, body_transform)


func _find_skeleton(root_node: Node) -> Skeleton3D:
	if root_node == null:
		return null
	if root_node is Skeleton3D:
		return root_node as Skeleton3D
	for child: Node in root_node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _cache_contact_bones() -> void:
	if _skeleton == null:
		return
	_hand_r_bone = _skeleton.find_bone(&"hand_r")
	_foot_bones[0] = _skeleton.find_bone(&"foot_l")
	_foot_bones[1] = _skeleton.find_bone(&"foot_r")
	if not _skeleton.skeleton_updated.is_connected(_cache_live_skeleton_pose):
		_skeleton.skeleton_updated.connect(_cache_live_skeleton_pose)


func _cache_live_skeleton_pose() -> void:
	if _skeleton == null or not is_instance_valid(_controller):
		return
	if _hand_r_bone >= 0:
		_cached_hand_r_local = _skeleton.get_bone_global_pose(_hand_r_bone).origin
	_cached_feet_local.resize(2)
	for foot_side in 2:
		if _foot_bones[foot_side] >= 0:
			_cached_feet_local[foot_side] = _skeleton.get_bone_global_pose(_foot_bones[foot_side]).origin
	_has_cached_skeleton_pose = _hand_r_bone >= 0
	_has_cached_canopy_corners = false
	if _controller.pose_mod != null and _controller.pose_mod.scarf_glider != null:
		var corners: PackedVector3Array = _controller.pose_mod.scarf_glider.get_corner_targets()
		if corners.size() == 4:
			var skeleton_inverse := _skeleton.global_transform.affine_inverse()
			_cached_canopy_corners_local.resize(4)
			for corner_index in 4:
				_cached_canopy_corners_local[corner_index] = skeleton_inverse * corners[corner_index]
			_has_cached_canopy_corners = true


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


func _render_ribbons(phase: StringName, body_transform: Transform3D) -> void:
	if _immediate_mesh == null:
		return
	_immediate_mesh.clear_surfaces()
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		visible = false
		return
	var camera_position := camera.get_global_transform_interpolated().origin
	var rendered_any := false
	if _has_history and _visibility_weight > 0.001:
		var open_weight := clampf(_controller.scarf_glide_progress, 0.0, 1.0) if phase == &"deploy" else 1.0
		var visibility := _visibility_weight * _motion_weight * open_weight
		if not _emitting:
			visibility = _visibility_weight * _motion_weight
		if visibility > 0.001:
			var left_path: Array[Vector3] = [_head_left]
			var right_path: Array[Vector3] = [_head_right]
			var path_ages: Array[float] = [_head_age]
			for index in _ages.size():
				left_path.append(_left_points[index])
				right_path.append(_right_points[index])
				path_ages.append(_ages[index])
			if left_path.size() >= 2:
				# Preserve the soft dry glide trails: two ivory strands and two
				# lavender feather passes, independent of tunnel wind.
				_draw_wisp(left_path, path_ages, camera_position, visibility, true)
				_draw_wisp(left_path, path_ages, camera_position, visibility, false)
				_draw_wisp(right_path, path_ages, camera_position, visibility, true)
				_draw_wisp(right_path, path_ages, camera_position, visibility, false)
				rendered_any = true

	if _draw_brace_vfx(camera_position, body_transform):
		rendered_any = true
	if _draw_canopy_vfx(camera_position, body_transform, phase):
		rendered_any = true
	visible = rendered_any


func _bone_world_position(bone_index: int) -> Vector3:
	if _skeleton == null or bone_index < 0:
		return Vector3.ZERO
	var interpolated_skeleton := _skeleton.get_global_transform_interpolated()
	if _has_cached_skeleton_pose:
		if bone_index == _hand_r_bone:
			return interpolated_skeleton * _cached_hand_r_local
		for foot_side in 2:
			if bone_index == _foot_bones[foot_side] and _cached_feet_local.size() > foot_side:
				return interpolated_skeleton * _cached_feet_local[foot_side]
	return interpolated_skeleton * _skeleton.get_bone_global_pose(bone_index).origin


func _draw_brace_vfx(camera_position: Vector3, body_transform: Transform3D) -> bool:
	if _controller.current_state != "Locomotion" or not _controller.is_on_floor() \
		or _skeleton == null or _hand_r_bone < 0:
		return false
	var brace := clampf(_controller.wind_brace_weight, 0.0, 1.0)
	if brace < 0.05:
		return false
	var wind_velocity := _controller.wind_velocity
	if wind_velocity.length_squared() <= 0.0001:
		return false
	var flow_direction := wind_velocity.normalized()
	var body_basis := body_transform.basis.orthonormalized()
	var right := body_basis.x
	var up := body_basis.y
	var hand := _bone_world_position(_hand_r_bone)
	var recoil := clampf(_controller.wind_recoil_weight, 0.0, 1.0)
	var alpha := 0.20 + brace * 0.22 + recoil * 0.16
	var width := 0.013 + recoil * 0.010
	var ivory := Color(1.0, 0.96, 0.88)
	var mint := Color(0.72, 0.92, 0.83)
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for side_sign: float in [-1.0, 1.0]:
		var palm_split: Array[Vector3] = [
			hand - flow_direction * 0.28 + right * (side_sign * 0.095),
			hand - flow_direction * 0.10 + right * (side_sign * 0.075) + up * 0.035,
			hand + flow_direction * 0.08 + right * (side_sign * 0.12) + up * 0.025,
			hand + flow_direction * 0.34 + right * (side_sign * 0.19) + up * 0.045,
		]
		_append_wind_curve(palm_split, camera_position, width, alpha, ivory, mint)

	for foot_side in 2:
		var foot_bone := _foot_bones[foot_side]
		if foot_bone < 0:
			continue
		var foot := _bone_world_position(foot_bone) - up * 0.045
		var side_sign := -1.0 if foot_side == 0 else 1.0
		var shoe_sweep: Array[Vector3] = [
			foot - flow_direction * 0.10 + right * (side_sign * 0.045) + up * 0.025,
			foot + flow_direction * 0.015 + right * (side_sign * 0.07) + up * 0.040,
			foot + flow_direction * 0.16 + right * (side_sign * 0.105) + up * 0.025,
		]
		_append_wind_curve(shoe_sweep, camera_position, width * 0.62, alpha * 0.65, ivory, mint)
	_immediate_mesh.surface_end()
	return true


func _draw_canopy_vfx(camera_position: Vector3, body_transform: Transform3D, phase: StringName) -> bool:
	if phase not in [&"deploy", &"glide"] or _controller.current_state != "Locomotion":
		return false
	var wind_load := clampf(_controller.scarf_wind_load, 0.0, 1.0)
	if wind_load <= 0.015 or _controller.pose_mod == null \
		or _controller.pose_mod.scarf_glider == null or not _has_cached_canopy_corners:
		return false
	var flow_velocity := _controller.scarf_wind_velocity
	if flow_velocity.length_squared() <= 0.0001:
		return false
	var flow_direction := flow_velocity.normalized()
	var body_basis := body_transform.basis.orthonormalized()
	var actor_right := body_basis.x
	var actor_up := body_basis.y
	var open_weight := clampf(_controller.scarf_glide_progress, 0.0, 1.0) if phase == &"deploy" else 1.0
	var canopy_offset := actor_up * (1.00 * open_weight) + (-body_basis.z) * (0.06 * open_weight)
	var interpolated_skeleton := _skeleton.get_global_transform_interpolated()
	var left_leading: Vector3 = interpolated_skeleton * _cached_canopy_corners_local[0] + canopy_offset
	var left_trailing: Vector3 = interpolated_skeleton * _cached_canopy_corners_local[1] + canopy_offset
	if left_leading.dot(flow_direction) > left_trailing.dot(flow_direction):
		var swap_left := left_leading
		left_leading = left_trailing
		left_trailing = swap_left
	var right_leading: Vector3 = interpolated_skeleton * _cached_canopy_corners_local[2] + canopy_offset
	var right_trailing: Vector3 = interpolated_skeleton * _cached_canopy_corners_local[3] + canopy_offset
	if right_leading.dot(flow_direction) > right_trailing.dot(flow_direction):
		var swap_right := right_leading
		right_leading = right_trailing
		right_trailing = swap_right
	var canopy_center := (left_leading + left_trailing + right_leading + right_trailing) * 0.25
	var left_sign := -1.0 if (left_leading - canopy_center).dot(actor_right) < 0.0 else 1.0
	var right_sign := -left_sign
	var ivory := Color(1.0, 0.96, 0.88)
	var mint := Color(0.72, 0.92, 0.83)
	var alpha := lerpf(0.18, 0.46, wind_load)
	var width := lerpf(0.012, 0.030, wind_load)
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var left_arc: Array[Vector3] = [
		left_leading - flow_direction * 0.22 + actor_up * 0.035,
		left_leading + flow_direction * 0.03 + actor_right * (left_sign * 0.12) + actor_up * (0.08 + sin(_vfx_elapsed * 5.1) * 0.025),
		left_trailing + flow_direction * 0.29 + actor_right * (left_sign * 0.18) + actor_up * (0.04 + sin(_vfx_elapsed * 4.3 + 0.9) * 0.025),
		left_trailing + flow_direction * 0.68 + actor_right * (left_sign * 0.26) + actor_up * 0.025,
	]
	var right_arc: Array[Vector3] = [
		right_leading - flow_direction * 0.22 + actor_up * 0.035,
		right_leading + flow_direction * 0.03 + actor_right * (right_sign * 0.12) + actor_up * (0.08 + sin(_vfx_elapsed * 5.1 + 1.4) * 0.025),
		right_trailing + flow_direction * 0.29 + actor_right * (right_sign * 0.18) + actor_up * (0.04 + sin(_vfx_elapsed * 4.3 + 2.0) * 0.025),
		right_trailing + flow_direction * 0.68 + actor_right * (right_sign * 0.26) + actor_up * 0.025,
	]
	_append_wind_curve(left_arc, camera_position, width, alpha, ivory, mint)
	_append_wind_curve(right_arc, camera_position, width, alpha, ivory, mint)
	_immediate_mesh.surface_end()
	return true


func _append_wind_curve(
	points: Array[Vector3], camera_position: Vector3, half_width: float, opacity: float,
	start_tint: Color, end_tint: Color
) -> void:
	if points.size() < 2:
		return
	for index in points.size() - 1:
		var t0 := float(index) / float(points.size() - 1)
		var t1 := float(index + 1) / float(points.size() - 1)
		var a: Vector3 = points[index]
		var b: Vector3 = points[index + 1]
		var tangent := (b - a).normalized()
		var toward_camera := (camera_position - (a + b) * 0.5).normalized()
		var side := tangent.cross(toward_camera)
		if side.length_squared() < 0.000001:
			side = tangent.cross(Vector3.UP)
		if side.length_squared() < 0.000001:
			side = Vector3.RIGHT
		side = side.normalized()
		var fade0 := (0.25 + 0.75 * sin(PI * t0)) * (1.0 - t0 * 0.30)
		var fade1 := (0.25 + 0.75 * sin(PI * t1)) * (1.0 - t1 * 0.30)
		var color_a := start_tint.lerp(end_tint, t0)
		var color_b := start_tint.lerp(end_tint, t1)
		color_a.a = opacity * fade0
		color_b.a = opacity * fade1
		var width_a := half_width * (1.0 - t0 * 0.60)
		var width_b := half_width * (1.0 - t1 * 0.60)
		_immediate_mesh.surface_set_color(color_a)
		_immediate_mesh.surface_add_vertex(a - side * width_a)
		_immediate_mesh.surface_set_color(color_a)
		_immediate_mesh.surface_add_vertex(a + side * width_a)
		_immediate_mesh.surface_set_color(color_b)
		_immediate_mesh.surface_add_vertex(b - side * width_b)
		_immediate_mesh.surface_set_color(color_a)
		_immediate_mesh.surface_add_vertex(a + side * width_a)
		_immediate_mesh.surface_set_color(color_b)
		_immediate_mesh.surface_add_vertex(b + side * width_b)
		_immediate_mesh.surface_set_color(color_b)
		_immediate_mesh.surface_add_vertex(b - side * width_b)


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
	_clear_glide_trail()
	_has_actor_origin = false
	_has_previous_yaw = false
	_has_cached_skeleton_pose = false
	_has_cached_canopy_corners = false
	if _immediate_mesh != null:
		_immediate_mesh.clear_surfaces()
	visible = false


func _clear_glide_trail() -> void:
	_left_points.clear()
	_right_points.clear()
	_ages.clear()
	_sample_remainder = 0.0
	_has_previous = false
	_has_history = false
	_emitting = false
	_visibility_weight = 0.0
	_head_age = 0.0
	_has_previous_yaw = false
