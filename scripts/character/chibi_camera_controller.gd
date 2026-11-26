class_name ChibiCameraController
extends Node

## Drives Phantom Camera from physics targets with render-frame smoothing.

const CAMERA_WATER_UPPER_TOLERANCE := 0.65
const CAMERA_WATER_FADE_START_DEPTH := -0.45
const CAMERA_WATER_FADE_END_DEPTH := 0.55
const CAMERA_WATER_BLEND_RATE := 7.0
const DEFAULT_UNDERWATER_COLOR := Color(0.10, 0.56, 0.64, 1.0)
const DEFAULT_UNDERWATER_VISIBILITY := 20.0
const UNDERWATER_FOG_DENSITY := 0.28
const TUNNEL_ARM_LENGTH := 1.50
const TUNNEL_CENTER_HEIGHT := 0.53
const TUNNEL_CAMERA_CLEARANCE := 0.22
const CLIMB_CAMERA_PRIORITY := 20
const CLIMB_CAMERA_AUTHORED_PITCH := -0.2443460953 # -14 degrees
const CLIMB_CAMERA_MIN_PITCH := -1.2566370614 # -72 degrees
const CLIMB_CAMERA_MAX_PITCH := 1.0122909662 # 58 degrees
const CLIMB_CAMERA_TURN_RATE := 8.0
const CLIMB_CAMERA_COLLISION_RADIUS := 0.10
const CLIMB_CAMERA_COLLISION_MARGIN := 0.02
const CLIMB_CAMERA_PIVOT_CLEARANCE_STEP := 0.05
const CLIMB_CAMERA_PIVOT_CLEARANCE_STEPS := 16
const CLIMB_CAMERA_ARM_RELEASE_SPEED := 8.0

@export var config: ParkourConfig
@export var parkour_pcam: PhantomCamera3D
@export var climb_pcam: PhantomCamera3D
@export var active_camera: Camera3D

var yaw: float = 0.0
var pitch: float = -0.22
var target_roll_deg: float = 0.0
var current_roll_deg: float = 0.0
var fov_boost_pop: float = 0.0

var _current_fov: float
var _current_arm: float
var _current_offset: Vector3
var _display_yaw: float
var _display_pitch: float
var _climb_yaw: float = 0.0
var _climb_display_yaw: float = 0.0
var _climb_pitch: float = CLIMB_CAMERA_AUTHORED_PITCH
var _climb_display_pitch: float = CLIMB_CAMERA_AUTHORED_PITCH
var _climbing_camera_active: bool = false
var _climb_user_aimed: bool = false
var _climb_wall_normal: Vector3 = Vector3.ZERO
var _climb_collision_sphere: SphereShape3D
var _climb_collision_arm_length: float = -1.0
var _flow: float
var _vertical_velocity: float
var _camera_water: WaterBody3D
var _camera_water_weight: float = 0.0
var _camera_water_color: Color = DEFAULT_UNDERWATER_COLOR
var _camera_water_visibility: float = DEFAULT_UNDERWATER_VISIBILITY
var _presentation_camera: Camera3D
var _original_camera_environment: Environment
var _dry_environment: Environment
var _water_environment: Environment


func _ready() -> void:
	if config == null:
		config = ParkourConfig.new()
	_climb_collision_sphere = SphereShape3D.new()
	_climb_collision_sphere.radius = CLIMB_CAMERA_COLLISION_RADIUS
	process_priority = -10 # Apply the view before PhantomCameraHost evaluates it.
	if parkour_pcam != null:
		if parkour_pcam.camera_3d_resource == null:
			parkour_pcam.camera_3d_resource = Camera3DResource.new()
		parkour_pcam.keep_aspect = Camera3D.KEEP_HEIGHT
		parkour_pcam.follow_damping_value = Vector3(0.06, 0.11, 0.06)
	if climb_pcam != null:
		if climb_pcam.camera_3d_resource == null:
			climb_pcam.camera_3d_resource = Camera3DResource.new()
		climb_pcam.keep_aspect = Camera3D.KEEP_HEIGHT
		climb_pcam.fov = 62.0
	_reset_view()


func _exit_tree() -> void:
	_reset_camera_environment()


func apply_look(look_delta: Vector2) -> void:
	if look_delta == Vector2.ZERO:
		return
	yaw = wrapf(yaw - look_delta.x, -PI, PI)
	pitch = clampf(pitch - look_delta.y, deg_to_rad(-72.0), deg_to_rad(58.0))
	if _climbing_camera_active:
		# Climb camera aim is world-relative and can make full turns. It does not
		# feed into the wall-relative hand placement or movement steering.
		_climb_yaw -= look_delta.x
		_climb_pitch = clampf(_climb_pitch - look_delta.y, CLIMB_CAMERA_MIN_PITCH, CLIMB_CAMERA_MAX_PITCH)
		_climb_user_aimed = true


func pop_fov(amount: float = 2.6) -> void:
	fov_boost_pop = clampf(fov_boost_pop + amount * 0.55, 0.0, 2.2)


func set_climbing_camera(active: bool, wall_normal_world: Vector3 = Vector3.ZERO, view_angle_deg: float = 0.0) -> void:
	if climb_pcam == null or parkour_pcam == null:
		return
	if active:
		var entering := not _climbing_camera_active
		_climbing_camera_active = true
		if entering:
			_climb_wall_normal = Vector3.ZERO
			_climb_collision_arm_length = -1.0
		if wall_normal_world.length_squared() > 0.01:
			_climb_wall_normal = wall_normal_world.normalized()
		if entering:
			_climb_user_aimed = false
			# Start from the currently visible view while the two Phantom Cameras
			# blend. The authored wall framing then eases in without a mount snap.
			_climb_display_yaw = _display_yaw
			_climb_display_pitch = _display_pitch
			if wall_normal_world.length_squared() <= 0.01:
				_climb_yaw = _display_yaw
				_climb_pitch = _display_pitch
			else:
				_climb_pitch = CLIMB_CAMERA_AUTHORED_PITCH
		if wall_normal_world.length_squared() > 0.01 and (entering or not _climb_user_aimed):
			_climb_yaw = _get_authored_climb_yaw(wall_normal_world, view_angle_deg)
		if entering:
			_apply_climbing_view()
			climb_pcam.priority = CLIMB_CAMERA_PRIORITY
	elif _climbing_camera_active or climb_pcam.priority != 0:
		if _climbing_camera_active:
			if _climb_user_aimed:
				# Carry user-controlled aim into the parkour camera without a snap.
				# Preserve the requested target as well as the current display angle,
				# so a just-finished look movement can complete after the handoff.
				yaw = wrapf(_climb_yaw, -PI, PI)
				pitch = _climb_pitch
				_display_yaw = wrapf(_climb_display_yaw, -PI, PI)
				_display_pitch = _climb_display_pitch
			# Without user aim, leave parkour yaw and pitch untouched. Authored
			# wall framing should not replace the ground camera's movement basis.
			_climbing_camera_active = false
			_climb_user_aimed = false
			_climb_wall_normal = Vector3.ZERO
			_climb_collision_arm_length = -1.0
			_apply_parkour_view()
		climb_pcam.priority = 0


func is_climbing_camera_active() -> bool:
	return _climbing_camera_active


func get_climbing_camera_angles() -> Vector2:
	# Radians; x is the unwrapped world yaw target and y is the bounded pitch.
	return Vector2(_climb_yaw, _climb_pitch)


func update_camera(_delta: float, flow_level: float, vertical_vel: float, _pool_surface_y: float, _underwater_weight: float) -> void:
	_flow = flow_level
	_vertical_velocity = vertical_vel


func reset_after_teleport() -> void:
	_flow = 0.0
	_vertical_velocity = 0.0
	reset_water_presentation()
	fov_boost_pop = 0.0
	target_roll_deg = 0.0
	current_roll_deg = 0.0
	set_climbing_camera(false)
	_reset_view()
	if parkour_pcam != null:
		parkour_pcam.teleport_position()


func get_camera_water() -> WaterBody3D:
	return _camera_water if is_instance_valid(_camera_water) else null


func reset_water_presentation() -> void:
	_camera_water = null
	_camera_water_weight = 0.0
	_camera_water_color = DEFAULT_UNDERWATER_COLOR
	_camera_water_visibility = DEFAULT_UNDERWATER_VISIBILITY
	_reset_camera_environment()


func _reset_view() -> void:
	_display_yaw = yaw
	_display_pitch = pitch
	_current_fov = config.base_fov
	_current_arm = config.base_arm_length
	_current_offset = Vector3(config.base_shoulder_offset_x, config.base_socket_offset_y, 0.0)
	if parkour_pcam != null:
		_apply_parkour_view()


func _process(delta: float) -> void:
	# Deferred calls run after regular process callbacks, including the
	# PhantomCameraHost at priority 300. The headless runner also reaches this path.
	call_deferred("_update_water_presentation_after_host", delta)
	if parkour_pcam == null or config == null:
		return
	var look_weight := 1.0 - exp(-32.0 * delta)
	_display_yaw = lerp_angle(_display_yaw, yaw, look_weight)
	_display_pitch = lerpf(_display_pitch, pitch, look_weight)
	if climb_pcam != null and _climbing_camera_active:
		var climb_look_weight := 1.0 - exp(-CLIMB_CAMERA_TURN_RATE * delta)
		_climb_display_yaw = lerp_angle(_climb_display_yaw, _climb_yaw, climb_look_weight)
		_climb_display_pitch = lerpf(_climb_display_pitch, _climb_pitch, climb_look_weight)
		_apply_climbing_view()

	fov_boost_pop = maxf(0.0, fov_boost_pop - delta * 5.0)
	var target_fov := lerpf(config.base_fov, config.max_flow_fov, _flow) + fov_boost_pop
	_current_fov = lerpf(_current_fov, target_fov, 1.0 - exp(-6.0 * delta))

	var fall_alpha := clampf(inverse_lerp(-2.4, -5.5, _vertical_velocity), 0.0, 1.0)
	var flow_arm := lerpf(config.base_arm_length, config.max_flow_arm_length, _flow)
	var target_arm := lerpf(flow_arm, config.fall_arm_length, fall_alpha)
	var target_offset := Vector3(
		config.base_shoulder_offset_x,
		config.base_socket_offset_y,
		0.0
	)
	var follow := parkour_pcam.follow_target
	var tunnel := _find_enclosed_water_at_follow_target(follow)
	var view_rate := 8.0
	if tunnel != null:
		target_arm = TUNNEL_ARM_LENGTH
		target_offset.x = 0.0
		target_offset.y = TUNNEL_CENTER_HEIGHT
		view_rate = 15.0
	_current_arm = lerpf(_current_arm, target_arm, 1.0 - exp(-(view_rate * 0.5) * delta))
	_current_offset = _current_offset.lerp(target_offset, 1.0 - exp(-view_rate * delta))
	if tunnel != null:
		# Keep the cast origin clear when a rising swimmer reaches the ceiling.
		var ceiling := tunnel.get_volume_ceiling_height()
		var follow_y := follow.get_global_transform_interpolated().origin.y
		_current_offset.y = minf(_current_offset.y, ceiling - follow_y - TUNNEL_CAMERA_CLEARANCE)
	current_roll_deg = lerpf(current_roll_deg, target_roll_deg, 1.0 - exp(-6.0 * delta))
	_apply_parkour_view()


func _apply_climbing_view() -> void:
	climb_pcam.set_third_person_rotation(Vector3(_climb_display_pitch, _climb_display_yaw, 0.0))


func _get_authored_climb_yaw(wall_normal_world: Vector3, view_angle_deg: float) -> float:
	var normal := wall_normal_world.normalized()
	return atan2(normal.x, normal.z) + deg_to_rad(view_angle_deg)


func _find_enclosed_water_at_follow_target(follow: Node3D) -> WaterBody3D:
	if not is_instance_valid(follow):
		return null
	var water := WaterBody3D.find_at(follow, follow.global_position + Vector3.UP * 0.42)
	return water if _is_enclosed_water(water) else null


func _is_enclosed_water(water: WaterBody3D) -> bool:
	return water != null and water.ceiling_below_surface > 0.0


func _update_water_presentation_after_host(delta: float) -> void:
	# Run after PhantomCameraHost so the water test sees the final camera transform.
	var camera := _get_render_camera()
	if camera != _presentation_camera:
		_set_presentation_camera(camera)
	if camera == null:
		return
	_resolve_climbing_camera_collision(camera, delta)

	var previous_water: WaterBody3D = _camera_water if is_instance_valid(_camera_water) else null
	_camera_water = WaterBody3D.find_at(camera, camera.global_position, previous_water, CAMERA_WATER_UPPER_TOLERANCE)
	var target_weight := 0.0
	if _camera_water != null:
		var depth_below_surface := _camera_water.get_surface_height() - camera.global_position.y
		target_weight = smoothstep(CAMERA_WATER_FADE_START_DEPTH, CAMERA_WATER_FADE_END_DEPTH, depth_below_surface)
		if _is_enclosed_water(_camera_water):
			target_weight = 1.0
		_update_camera_water_profile(_camera_water, delta)

	_camera_water_weight = lerpf(_camera_water_weight, target_weight, 1.0 - exp(-CAMERA_WATER_BLEND_RATE * delta))
	if _camera_water_weight <= 0.001:
		_restore_camera_environment()
		return
	_apply_camera_water_environment()


func _resolve_climbing_camera_collision(camera: Camera3D, delta: float) -> void:
	if not _climbing_camera_active or climb_pcam == null:
		_climb_collision_arm_length = -1.0
		return
	# This controller owns the exported gameplay camera. Leave an independently
	# selected debug/photo camera alone even if climbing is still active.
	if not is_instance_valid(active_camera) or camera != active_camera:
		return
	if _climb_collision_sphere == null or not is_instance_valid(camera):
		return
	var follow := climb_pcam.follow_target
	if not is_instance_valid(follow):
		return
	var world := camera.get_world_3d()
	if world == null:
		return

	# Use the same world-space follow anchor as Phantom Camera, not the rendered
	# endpoint. The anchor is clear on the tower; move it outward only if a hold
	# or nearby wall actually overlaps the camera-sized sphere.
	var pivot := follow.get_global_transform_interpolated().origin + climb_pcam.follow_offset
	var cast_vector := camera.global_position - pivot
	var cast_length := cast_vector.length()
	if cast_length <= 0.001:
		return
	var cast_direction := cast_vector / cast_length
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _climb_collision_sphere
	query.collision_mask = climb_pcam.collision_mask
	query.margin = CLIMB_CAMERA_COLLISION_MARGIN
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var follow_body := follow as CollisionObject3D
	if follow_body != null:
		query.exclude = [follow_body.get_rid()]

	var space := world.direct_space_state
	query.transform = Transform3D(Basis.IDENTITY, pivot)
	if not space.intersect_shape(query, 1).is_empty():
		var outward := _climb_wall_normal
		if outward.length_squared() <= 0.01:
			outward = cast_direction
		else:
			outward = outward.normalized()
		for _step in range(CLIMB_CAMERA_PIVOT_CLEARANCE_STEPS):
			pivot += outward * CLIMB_CAMERA_PIVOT_CLEARANCE_STEP
			query.transform = Transform3D(Basis.IDENTITY, pivot)
			if space.intersect_shape(query, 1).is_empty():
				break
		cast_vector = camera.global_position - pivot
		cast_length = cast_vector.length()
		if cast_length <= 0.001:
			return
		cast_direction = cast_vector / cast_length

	# Phantom Camera's own frustum cast can finish inside a wall. A smaller
	# sphere cast gives the actual lens center a dependable buffer while keeping
	# the authored 2.85 m open arm and the user's chosen orbit direction.
	query.transform = Transform3D(Basis.IDENTITY, pivot)
	query.motion = cast_vector
	var cast_fractions := space.cast_motion(query)
	var safe_fraction := 1.0
	if cast_fractions.size() >= 2:
		safe_fraction = clampf(cast_fractions[0], 0.0, 1.0)
	var safe_arm_length := cast_length * safe_fraction
	if _climb_collision_arm_length < 0.0 or safe_arm_length < _climb_collision_arm_length:
		# Retract immediately when a turn brings masonry between the player and
		# camera. Releasing is eased below to avoid a spring-out on clear views.
		_climb_collision_arm_length = safe_arm_length
	else:
		_climb_collision_arm_length = minf(
			safe_arm_length,
			_climb_collision_arm_length + CLIMB_CAMERA_ARM_RELEASE_SPEED * maxf(delta, 0.0)
		)

	var resolved_arm_length := minf(_climb_collision_arm_length, cast_length)
	if resolved_arm_length < cast_length - 0.001:
		camera.global_position = pivot + cast_direction * resolved_arm_length


func _get_render_camera() -> Camera3D:
	if get_viewport() != null:
		var viewport_camera := get_viewport().get_camera_3d()
		if is_instance_valid(viewport_camera):
			return viewport_camera
	if is_instance_valid(active_camera) and active_camera.is_inside_tree():
		return active_camera
	return null


func _set_presentation_camera(camera: Camera3D) -> void:
	_reset_camera_environment()
	_presentation_camera = camera
	_original_camera_environment = null
	_dry_environment = null
	_water_environment = null
	_camera_water = null
	_camera_water_weight = 0.0
	_camera_water_color = DEFAULT_UNDERWATER_COLOR
	_camera_water_visibility = DEFAULT_UNDERWATER_VISIBILITY
	if camera == null:
		return

	_original_camera_environment = camera.environment
	_dry_environment = camera.environment
	if _dry_environment == null:
		var camera_world := camera.get_world_3d()
		if camera_world != null:
			_dry_environment = camera_world.environment
			if _dry_environment == null:
				_dry_environment = camera_world.fallback_environment
	if _dry_environment == null and get_tree().current_scene != null:
		var world_environment := get_tree().current_scene.find_child("WorldEnvironment", true, false) as WorldEnvironment
		if world_environment != null:
			_dry_environment = world_environment.environment
	if _dry_environment == null:
		_dry_environment = Environment.new()
	_water_environment = _dry_environment.duplicate() as Environment


func _update_camera_water_profile(water: WaterBody3D, delta: float) -> void:
	var target_color := DEFAULT_UNDERWATER_COLOR
	var target_visibility := DEFAULT_UNDERWATER_VISIBILITY
	var profile: Variant = water.profile
	if profile == null and water.has_method("get_profile"):
		profile = water.call("get_profile")
	if profile == null and water.has_method("_get_profile"):
		profile = water.call("_get_profile")
	if profile != null:
		var color_value: Variant = profile.get("underwater_color")
		var visibility_value: Variant = profile.get("visibility_distance")
		if color_value is Color:
			target_color = color_value
		if visibility_value is float or visibility_value is int:
			target_visibility = maxf(float(visibility_value), 4.0)
	var blend := 1.0 - exp(-5.0 * delta)
	_camera_water_color = _camera_water_color.lerp(target_color, blend)
	_camera_water_visibility = lerpf(_camera_water_visibility, target_visibility, blend)


func _apply_camera_water_environment() -> void:
	if not is_instance_valid(_presentation_camera) or _water_environment == null or _dry_environment == null:
		return
	var weight := clampf(_camera_water_weight, 0.0, 1.0)
	_water_environment.fog_enabled = _dry_environment.fog_enabled or weight > 0.001
	_water_environment.fog_mode = Environment.FOG_MODE_DEPTH
	_water_environment.fog_density = lerpf(_dry_environment.fog_density, UNDERWATER_FOG_DENSITY, weight)
	_water_environment.fog_light_color = _dry_environment.fog_light_color.lerp(_camera_water_color, weight)
	_water_environment.fog_depth_begin = lerpf(_dry_environment.fog_depth_begin, 0.0, weight)
	_water_environment.fog_depth_end = lerpf(_dry_environment.fog_depth_end, _camera_water_visibility, weight)
	_water_environment.fog_depth_curve = lerpf(_dry_environment.fog_depth_curve, 1.0, weight)
	_water_environment.fog_sky_affect = lerpf(_dry_environment.fog_sky_affect, 1.0, weight)
	if _presentation_camera.environment != _water_environment:
		_presentation_camera.environment = _water_environment


func _reset_camera_environment() -> void:
	_restore_camera_environment()
	_presentation_camera = null
	_original_camera_environment = null
	_dry_environment = null
	_water_environment = null


func _restore_camera_environment() -> void:
	if is_instance_valid(_presentation_camera) and _presentation_camera.environment == _water_environment:
		_presentation_camera.environment = _original_camera_environment


func _apply_parkour_view() -> void:
	parkour_pcam.spring_length = _current_arm
	parkour_pcam.follow_offset = _current_offset
	parkour_pcam.set_third_person_rotation(Vector3(_display_pitch, _display_yaw, deg_to_rad(current_roll_deg)))
	if not is_equal_approx(parkour_pcam.fov, _current_fov):
		parkour_pcam.fov = _current_fov


func get_planar_basis() -> Basis:
	return Basis(Vector3.UP, yaw)


func get_forward_xz() -> Vector3:
	return -get_planar_basis().z


func get_right_xz() -> Vector3:
	return get_planar_basis().x
