class_name ChibiSwimController
extends RefCounted

## Owns Chibi's water movement and water-to-parkour state transitions.

const WORLD_MASK := 1
const SWIM_START_FLOOR_DEPTH := 1.00
const SWIM_EXIT_FLOOR_DEPTH := 0.81
const SWIM_START_WET_DEPTH := 0.92
const MAX_SWIM_SPEED := 2.30
const MAX_VERTICAL_SWIM_SPEED := 1.65
const SWIM_ACCELERATION := 8.6
const SWIM_TURN_BRAKE := 19.5
const SWIM_LATERAL_DRAG := 11.0
const SWIM_COAST_DRAG := 5.0
const SWIM_COAST_SPEED_DRAG := 1.35
const SWIM_DIVE_KICK_TIME := 0.26
const SWIM_YAW_LIMIT := 8.6
const WADING_SPEED := 1.70
const SURFACE_UPPER_TOLERANCE := 0.10
const BANK_CONTACT_TOLERANCE := 0.045
const MAX_ENTRY_SINK_SPEED := 2.8

var _player: ParkourController
var _swimming := false
var _surface_swimming := false
var _surface_weight := 0.0
var _tread_weight := 0.0
var _dive_kick_time := 0.0
var _swim_pitch := 0.0
var _swim_yaw_rate := 0.0
var _dive_pose := 0.0
var _rise_pose := 0.0
var _glide_pose := 0.0
var _ripple_clock := 0.0
var _bubble_clock := 0.0
var _foot_idx := -1
var _wade_hand_side := 0
var _wet_depth := 0.0
var _floor_depth := 0.0
var _wading_weight := 0.0
var _occupant_skeleton: Skeleton3D
var _bone_foot_l := -1
var _bone_foot_r := -1
var _bone_hand_l := -1
var _bone_hand_r := -1


func setup(player: ParkourController) -> void:
	_player = player


func get_active_water() -> WaterBody3D:
	if _player == null:
		return null
	return _player.get_active_water()


func get_wade_pose_weight() -> float:
	if _swimming or not is_instance_valid(get_active_water()):
		return 0.0
	return smoothstep(0.20, 0.55, _wet_depth)


## Select a single water body and prepare caps/transitions before locomotion runs.
func prepare_physics() -> void:
	if _player == null:
		return

	var previous := get_active_water()
	var body := WaterBody3D.find_at(
		_player,
		_player.global_position,
		previous,
		SURFACE_UPPER_TOLERANCE
	) as WaterBody3D
	if body != previous:
		_switch_water_body(body)

	if not is_instance_valid(body):
		if _swimming:
			_end_swimming(false)
		_player.external_walk_speed_cap = 99.0
		return

	_player.set_active_water_body(body)
	var surface_y := body.get_surface_height()
	_wet_depth = surface_y - _player.global_position.y
	_floor_depth = _probe_floor_depth(body, surface_y)

	if _swimming and _player.current_state != "PoolSwim":
		_swimming = false
	if _swimming and _floor_depth < SWIM_EXIT_FLOOR_DEPTH \
		and (_player.is_on_floor() or _floor_depth - _wet_depth <= BANK_CONTACT_TOLERANCE):
		_end_swimming(true)
	elif not _swimming and _player.current_state == "Locomotion":
		if _floor_depth >= SWIM_START_FLOOR_DEPTH and _wet_depth >= SWIM_START_WET_DEPTH:
			_begin_swimming(body, surface_y)

	if _swimming:
		_player.external_walk_speed_cap = 99.0
	else:
		_wading_weight = smoothstep(0.12, 0.80, _wet_depth)
		var dry_speed := lerpf(_player.config.base_run_speed, _player.config.max_flow_speed, _player.flow_level)
		_player.external_walk_speed_cap = lerpf(dry_speed, minf(dry_speed, WADING_SPEED), _wading_weight) if _wading_weight > 0.001 else 99.0


## Run exactly once from ParkourController's PoolSwim state branch.
func swim_physics(delta: float) -> void:
	var player := _player
	var body := get_active_water()
	if player == null or not is_instance_valid(body) or not _swimming:
		return

	var move_in := player.chibi_input.move_vec if player.chibi_input != null else Vector2.ZERO
	var cam_fwd := player.camera_ctrl.get_forward_xz() if player.camera_ctrl != null else -player.global_transform.basis.z
	var cam_right := player.camera_ctrl.get_right_xz() if player.camera_ctrl != null else player.global_transform.basis.x
	var wish := cam_right * move_in.x - cam_fwd * move_in.y
	if wish.length() > 1.0:
		wish = wish.normalized()

	var rise := player.chibi_input.rise_held if player.chibi_input != null else false
	var dive := not rise and player.chibi_input != null and player.chibi_input.dive_held
	var open_water := body.ceiling_below_surface <= 0.0
	var surface_h := body.get_surface_height() - 0.04
	var center_y := player.get_capsule_center().y

	if not open_water:
		_surface_swimming = false
	elif dive and _surface_swimming:
		_surface_swimming = false
		_dive_kick_time = SWIM_DIVE_KICK_TIME
	if rise:
		_dive_kick_time = 0.0
		if open_water and center_y >= surface_h - 0.16:
			_surface_swimming = true
	var kick := _dive_kick_time / SWIM_DIVE_KICK_TIME
	var horizontal := _steer_swim(wish, delta)
	var vertical_speed := _swim_vertical_target(body, surface_h, center_y, rise, dive, kick)
	_dive_kick_time = maxf(0.0, _dive_kick_time - delta)
	var vertical_response := 11.0 if rise or _surface_swimming else 8.5
	player.velocity = Vector3(horizontal.x, lerpf(player.velocity.y, vertical_speed, 1.0 - exp(-vertical_response * delta)), horizontal.z)
	player.move_and_slide()
	var resolved := player.get_real_velocity()
	_update_swim_heading(wish, Vector3(resolved.x, 0.0, resolved.z), delta)

	if rise and open_water and player.try_climb_out_of_pool():
		_swimming = false
		_player.set_active_water_body(null)
		player.external_walk_speed_cap = 99.0
		_reset_swim_visual_state()
		return

	_update_swim_pose(body, resolved, wish.length(), rise, dive, kick, delta)


func _steer_swim(wish: Vector3, delta: float) -> Vector3:
	var horizontal := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	var speed := horizontal.length()
	var input_strength := wish.length()
	if input_strength <= 0.05:
		var drag := SWIM_COAST_DRAG + speed * SWIM_COAST_SPEED_DRAG
		return horizontal.move_toward(Vector3.ZERO, drag * delta)

	# Keep lateral carry through a turn and brake before pushing in the opposite direction.
	var direction := wish / input_strength
	var forward_speed := horizontal.dot(direction)
	var lateral := horizontal - direction * forward_speed
	var target_speed := input_strength * MAX_SWIM_SPEED
	var drive_rate := SWIM_TURN_BRAKE if forward_speed < 0.0 else SWIM_ACCELERATION
	# Give a reversal its normal acceleration once braking has used its share of the tick.
	if forward_speed < 0.0 and -forward_speed < SWIM_TURN_BRAKE * delta:
		var remaining := delta + forward_speed / SWIM_TURN_BRAKE
		forward_speed = minf(target_speed, SWIM_ACCELERATION * remaining)
	else:
		forward_speed = move_toward(forward_speed, target_speed, drive_rate * delta)
	lateral = lateral.move_toward(Vector3.ZERO, SWIM_LATERAL_DRAG * delta)
	return (direction * forward_speed + lateral).limit_length(maxf(speed, MAX_SWIM_SPEED))


func _update_swim_heading(wish: Vector3, horizontal: Vector3, delta: float) -> void:
	var yaw_goal := _player.rotation.y
	if wish.length_squared() > 0.0025:
		yaw_goal = atan2(-wish.x, -wish.z)
		var speed := horizontal.length()
		if speed > 0.12:
			var course := atan2(-horizontal.x, -horizontal.z)
			var turn := angle_difference(course, yaw_goal)
			var follow_course := smoothstep(0.12, 1.75, speed) * (1.0 - smoothstep(1.1, 2.55, absf(turn)))
			yaw_goal -= turn * (0.62 * follow_course)
	elif horizontal.length_squared() > 0.09:
		var course := atan2(-horizontal.x, -horizontal.z)
		# Finish the glide facing into its travel without winding around after release.
		yaw_goal += clampf(angle_difference(yaw_goal, course), -0.64, 0.64)

	var yaw_error := angle_difference(_player.rotation.y, yaw_goal)
	var rate := clampf(yaw_error * 13.0, -SWIM_YAW_LIMIT, SWIM_YAW_LIMIT)
	_swim_yaw_rate = lerpf(_swim_yaw_rate, rate, 1.0 - exp(-20.0 * delta))
	_player.rotation.y = wrapf(_player.rotation.y + _swim_yaw_rate * delta, -PI, PI)


func _swim_vertical_target(body: WaterBody3D, surface_h: float, center_y: float, rise: bool, dive: bool, kick: float) -> float:
	var target := 0.0
	if body.ceiling_below_surface > 0.0 and rise:
		var half_height := center_y - _player.global_position.y
		var headroom := body.get_volume_ceiling_height() - (center_y + half_height) - 0.04
		target = clampf(headroom * 5.0, -0.65, MAX_VERTICAL_SWIM_SPEED)
	elif _surface_swimming or rise:
		target = clampf((surface_h - center_y) * 4.8, -0.75, MAX_VERTICAL_SWIM_SPEED)
	elif dive:
		target = -MAX_VERTICAL_SWIM_SPEED
	elif kick > 0.0:
		target = -MAX_VERTICAL_SWIM_SPEED * smoothstep(0.0, 1.0, kick)

	if _floor_depth < SWIM_EXIT_FLOOR_DEPTH and not dive and kick <= 0.0:
		# Let buoyancy ease off over the bank so the feet can meet the ground.
		var shallows := 1.0 - smoothstep(0.58, SWIM_EXIT_FLOOR_DEPTH, _floor_depth)
		target = lerpf(target, -0.60, shallows)
	return target


func _update_swim_pose(body: WaterBody3D, resolved: Vector3, input_strength: float, rise: bool, dive: bool, kick: float, delta: float) -> void:
	var surface_y := body.get_surface_height()
	var center_depth := surface_y - _player.get_capsule_center().y
	var near_surface := 1.0 - smoothstep(0.14, 0.52, center_depth)
	var open_water := body.ceiling_below_surface <= 0.0
	var surface_target := 0.0
	if open_water and (_surface_swimming or rise):
		surface_target = near_surface
	elif open_water and (dive or kick > 0.0):
		surface_target = near_surface * (1.0 - _dive_pose)
	_surface_weight = lerpf(_surface_weight, surface_target, 1.0 - exp(-8.0 * delta))

	var horizontal_speed := Vector2(resolved.x, resolved.z).length()
	var travel_speed := resolved.length()
	var drive := maxf(input_strength, maxf(1.0 if (rise or dive) else 0.0, kick))
	var effort := maxf(travel_speed, maxf(input_strength, kick) * 0.38)
	var idle_target := 1.0 - smoothstep(0.10, 1.13, effort)
	_tread_weight = lerpf(_tread_weight, idle_target, 1.0 - exp(-8.0 * delta))
	var glide_target := smoothstep(0.17, 1.10, travel_speed) * (1.0 - smoothstep(0.05, 0.40, drive))
	var gesture_blend := 1.0 - exp(-11.0 * delta)
	_glide_pose = lerpf(_glide_pose, glide_target, gesture_blend)
	var dive_target := maxf(kick, 0.54 if dive else 0.0)
	var rise_target := smoothstep(0.12, 1.04, resolved.y) if rise else 0.0
	_dive_pose = lerpf(_dive_pose, dive_target, gesture_blend)
	_rise_pose = lerpf(_rise_pose, rise_target, gesture_blend)

	var travel_pitch := rad_to_deg(atan2(resolved.y, maxf(0.65, horizontal_speed)))
	var submerged_pitch := clampf(travel_pitch - 15.0 * _dive_pose, -58.0, 49.0)
	var surface_lean := -lerpf(13.0, 19.0, _glide_pose) * smoothstep(0.14, 1.25, horizontal_speed)
	var pitch_target := lerpf(submerged_pitch, surface_lean, _surface_weight)
	_swim_pitch = lerpf(_swim_pitch, pitch_target, 1.0 - exp(-9.0 * delta))
	_player.update_pool_swim_visuals(surface_y, _surface_weight, _tread_weight, _swim_pitch, travel_speed / MAX_SWIM_SPEED,
		_swim_yaw_rate / SWIM_YAW_LIMIT, _dive_pose, _rise_pose, _glide_pose)
	_tick_swim_effects(delta, body, horizontal_speed)


## Emit shallow-water ripples after the normal locomotion move has completed.
func finish_physics(delta: float) -> void:
	if _player == null or _swimming:
		return
	var body := get_active_water()
	if not is_instance_valid(body):
		return
	_tick_wading_effects(delta, body)


func reset_for_respawn() -> void:
	if _player == null:
		return
	if _swimming or _player.current_state == "PoolSwim":
		_end_swimming(false)
	_player.set_active_water_body(null)
	_player.external_walk_speed_cap = 99.0
	_clear_skeleton()
	_reset_swim_visual_state()
	_wet_depth = 0.0
	_floor_depth = 0.0
	_wading_weight = 0.0
	_wade_hand_side = 0


func _switch_water_body(body: WaterBody3D) -> void:
	_player.set_active_water_body(body)
	_ripple_clock = 0.0
	_foot_idx = -1
	if is_instance_valid(body):
		_cache_occupant_skeleton()
	else:
		_clear_skeleton()
		_ripple_clock = 0.0
		_bubble_clock = 0.0
		_wading_weight = 0.0
		if _swimming:
			_end_swimming(false)


func _probe_floor_depth(body: WaterBody3D, surface_y: float) -> float:
	var world := _player.get_world_3d()
	if world == null:
		return body.max_depth
	# Start near Chibi's feet so submerged shelves above the swimmer don't masquerade as the floor.
	var ray_start_y := minf(surface_y - 0.03, _player.global_position.y + 0.08)
	var origin := Vector3(_player.global_position.x, ray_start_y, _player.global_position.z)
	var end := Vector3(origin.x, surface_y - body.max_depth - 0.10, origin.z)
	var query := PhysicsRayQueryParameters3D.create(origin, end, WORLD_MASK, [_player.get_rid()])
	query.hit_from_inside = true
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return body.max_depth
	var hit_position: Vector3 = hit.get("position", origin)
	if not body.contains_horizontal(hit_position):
		return body.max_depth
	return clampf(surface_y - hit_position.y, 0.0, body.max_depth)


func _begin_swimming(body: WaterBody3D, surface_y: float) -> void:
	var center_y := _player.get_capsule_center().y
	_surface_swimming = body.ceiling_below_surface <= 0.0 and center_y > surface_y - 0.55
	_surface_weight = 1.0 - smoothstep(0.14, 0.52, surface_y - center_y) if _surface_swimming else 0.0
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	_tread_weight = 1.0 - smoothstep(0.10, 1.15, speed)
	_dive_kick_time = 0.0
	_swim_pitch = 0.0
	_swim_yaw_rate = 0.0
	_dive_pose = 0.0
	_rise_pose = 0.0
	_glide_pose = 0.0
	_bubble_clock = 0.0
	_swimming = true
	body.emit_ripple(_player.get_capsule_center(), 0.85)
	if _player.juice != null and _player.velocity.y < -2.0:
		_player.juice.play_sfx("Slide", 0.08)
	_player.velocity.y = maxf(_player.velocity.y, -MAX_ENTRY_SINK_SPEED)
	_player.enter_pool_swim(body, surface_y)


func _end_swimming(keep_water: bool) -> void:
	var was_swimming := _swimming or (_player != null and _player.current_state == "PoolSwim")
	_swimming = false
	_reset_swim_visual_state()
	if not was_swimming or _player == null:
		return
	_player.exit_pool_swim(not keep_water)


func _reset_swim_visual_state() -> void:
	_surface_swimming = false
	_surface_weight = 0.0
	_tread_weight = 0.0
	_dive_kick_time = 0.0
	_swim_pitch = 0.0
	_swim_yaw_rate = 0.0
	_dive_pose = 0.0
	_rise_pose = 0.0
	_glide_pose = 0.0
	_bubble_clock = 0.0
	_ripple_clock = 0.0


func _tick_wading_effects(delta: float, body: WaterBody3D) -> void:
	var player := _player
	var planar_speed := Vector2(player.velocity.x, player.velocity.z).length()
	_ripple_clock -= delta
	if not player.is_on_floor() or _ripple_clock > 0.0:
		return
	if planar_speed <= 0.15:
		if _wet_depth > 0.35:
			_emit_wade_hand_ripple(body, 0.22)
			_ripple_clock = 0.48
		return

	var left_foot := _get_bone_world(_bone_foot_l, player.global_position)
	var right_foot := _get_bone_world(_bone_foot_r, player.global_position)
	var low_foot := 1 if right_foot.y < left_foot.y else 0
	var boot := right_foot if low_foot == 1 else left_foot
	var shallow := _wet_depth < 0.18
	if not shallow or (low_foot != _foot_idx and boot.y - 0.08 < body.get_surface_height() + 0.02):
		body.emit_ripple(boot, lerpf(0.26, 0.49, _wading_weight))
		_foot_idx = low_foot
	if _wet_depth > 0.28:
		body.emit_ripple(player.get_capsule_center(), lerpf(0.45, 0.96, _wading_weight))
	if _wet_depth > 0.38:
		_emit_wade_hand_ripple(body, 0.33)
	_ripple_clock = 0.025 if shallow else clampf(0.65 / planar_speed, 0.15, 0.45)


func _emit_wade_hand_ripple(body: WaterBody3D, diameter: float) -> void:
	if _player.pose_mod == null:
		return
	var wrist := _player.pose_mod.get_wade_wrist_world(_wade_hand_side)
	_wade_hand_side = 1 - _wade_hand_side
	if wrist.is_finite() and absf(wrist.y - body.get_surface_height()) < 0.07:
		body.emit_ripple(wrist, diameter)


func _tick_swim_effects(delta: float, body: WaterBody3D, speed_2d: float) -> void:
	var player := _player
	_ripple_clock -= delta
	_bubble_clock -= delta
	if _surface_weight > 0.5 and _ripple_clock <= 0.0 and speed_2d > 0.15:
		_foot_idx = 0 if _foot_idx == 1 else 1
		var hand_bone := _bone_hand_l if _foot_idx == 1 else _bone_hand_r
		body.emit_ripple(_get_bone_world(hand_bone, player.get_capsule_center()), 0.55)
		_ripple_clock = 0.35
	if _bubble_clock <= 0.0 and _surface_weight < 0.5 and player.pose_mod != null:
		var gear := player.pose_mod.dive_gear
		if gear != null:
			var outlet := gear.get_snorkel_outlet_world()
			if outlet.is_finite() and body.emit_bubble(outlet):
				_bubble_clock = lerpf(0.65, 0.18, clampf(player.velocity.length() / MAX_SWIM_SPEED, 0.0, 1.0))


func _cache_occupant_skeleton() -> void:
	_clear_skeleton()
	var binder := _player.get_node_or_null("ChibiRigBinder") as ChibiRigBinder
	if binder == null or binder.skeleton == null:
		return
	_occupant_skeleton = binder.skeleton
	_bone_foot_l = _occupant_skeleton.find_bone("foot_l")
	_bone_foot_r = _occupant_skeleton.find_bone("foot_r")
	_bone_hand_l = _occupant_skeleton.find_bone("hand_l")
	_bone_hand_r = _occupant_skeleton.find_bone("hand_r")


func _clear_skeleton() -> void:
	_occupant_skeleton = null
	_bone_foot_l = -1
	_bone_foot_r = -1
	_bone_hand_l = -1
	_bone_hand_r = -1


func _get_bone_world(bone_index: int, fallback: Vector3) -> Vector3:
	if is_instance_valid(_occupant_skeleton) and bone_index >= 0:
		return (_occupant_skeleton.global_transform * _occupant_skeleton.get_bone_global_pose(bone_index)).origin
	return fallback
