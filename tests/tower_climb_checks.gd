extends SceneTree

const TOWER_SCENE := preload("res://levels/rooftop_gym/stations/rooftop_climb_tower.tscn")
const RUNNER_SCENE := preload("res://features/runner/chibi_runner.tscn")
const MOTION := preload("res://features/runner/climbing/wall_climb_motion.gd")

const SUMMIT_INPUT_LIMIT := 1800
const LAP_INPUT_LIMIT := 1800
const LEAP_INPUT_LIMIT := 720
const POSE_CATCH_KEY := -1

var _failures := 0
var _runner: ParkourController
var _tower: Node3D
var _climb_skeleton: Skeleton3D
var _climb_head_bone := -1
var _climb_left_hand_bone := -1
var _climb_right_hand_bone := -1
var _climb_face_axis := Vector3.FORWARD
var _climb_pose_intent := ""
var _climb_pose_metrics: Dictionary = {}
var _climb_pose_last_phase := MOTION.Phase.IDLE


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.physics_ticks_per_second = 60
	var test_root := Node3D.new()
	test_root.name = "TowerClimbTestRoot"
	root.add_child(test_root)
	_add_floor(test_root)
	_tower = TOWER_SCENE.instantiate() as Node3D
	test_root.add_child(_tower)
	_runner = RUNNER_SCENE.instantiate() as ParkourController
	test_root.add_child(_runner)
	await _frames(12)
	_setup_climb_pose_sampler()

	_check(_tower.is_in_group("climbable_wall") and _tower.is_in_group("tower_corner_route"),
		"Tower opts into its own four-face climb route")
	var launch := _tower.get_node_or_null("LaunchMarker") as Marker3D
	_check(launch != null and launch.position.is_equal_approx(Vector3(0.0, 8.0, -1.85)),
		"Launch marker sits at the eight meter roof start")
	_check(_runner.pose_mod != null,
		"Character rig initializes in the headless scene")
	_check_spaced_masonry_geometry()

	await _check_cardinal_mount(Vector3(0.0, 0.035, -3.06), Vector3(0.0, 0.0, 1.0), Vector3.FORWARD, "south")
	await _check_cardinal_mount(Vector3(0.0, 0.035, 3.06), Vector3(0.0, 0.0, -1.0), Vector3.BACK, "north")
	await _check_cardinal_mount(Vector3(3.06, 0.035, 0.0), Vector3(-1.0, 0.0, 0.0), Vector3.RIGHT, "east")
	await _check_cardinal_mount(Vector3(-3.06, 0.035, 0.0), Vector3(1.0, 0.0, 0.0), Vector3.LEFT, "west")
	await _check_climb_camera_orbit()
	await _check_tower_hanging_idle()

	await _check_corner_direction(1.0, "rightward")
	await _check_corner_direction(-1.0, "leftward")
	await _check_vertical_and_lateral_leaps()
	await _check_directional_input_hops()
	await _check_reach_motion_profile()
	await _check_untagged_lateral_no_hop()
	await _check_up_only_topouts()
	await _check_blocked_summit_retry()
	await _check_released_upward_leap_topout()
	_check_climb_pose_replay()

	if _failures == 0:
		print("PASS: rooftop tower climb checks")
	else:
		push_error("%d rooftop tower climb check(s) failed" % _failures)
	test_root.queue_free()
	await _frames(2)
	quit(_failures)


func _check_cardinal_mount(spawn: Vector3, approach: Vector3, expected_normal: Vector3, label: String) -> void:
	_runner.chibi_input.clear_touch_input()
	_runner.reset_for_respawn(spawn)
	_runner.rotation.y = 0.0
	_runner.camera_ctrl.yaw = 0.0
	await _frames(4)
	var mounted := _runner._try_mount_wall(approach, true)
	await _frames(18)
	var held_normal: Vector3 = _runner._wall_climb.frame.z
	_check(mounted and _runner._wall_climb.phase == MOTION.Phase.HOLD and held_normal.dot(expected_normal) > 0.99,
		"Tower mounts its %s face from a direct approach" % label)


func _check_climb_camera_orbit() -> void:
	await _check_cardinal_mount(Vector3(0.0, 0.035, 3.06), Vector3.FORWARD, Vector3.BACK, "north face for camera orbit")
	var view := _runner.camera_ctrl
	var camera := view.active_camera
	view.apply_look(Vector2(0.0, -0.36))
	await _frames(30)
	var aim := view.get_climbing_camera_angles()
	var starting_position := _runner.global_position
	var sphere := SphereShape3D.new()
	sphere.radius = 0.04
	var clearance := PhysicsShapeQueryParameters3D.new()
	clearance.shape = sphere
	clearance.collision_mask = 1
	var overlaps := 0
	var shortest_arm := INF
	var longest_arm := 0.0
	for _step in 24:
		view.apply_look(Vector2(-TAU / 24.0, 0.0))
		for _frame in 7:
			await _frames(1)
			clearance.transform.origin = camera.global_position
			overlaps += int(not camera.get_world_3d().direct_space_state.intersect_shape(clearance, 1).is_empty())
			var arm := camera.global_position.distance_to(starting_position + Vector3.UP * 0.85)
			shortest_arm = minf(shortest_arm, arm)
			longest_arm = maxf(longest_arm, arm)
	var after_orbit := view.get_climbing_camera_angles()
	_check(view.is_climbing_camera_active() and absf(after_orbit.x - aim.x - TAU) < 0.01
		and absf(after_orbit.y - aim.y) < 0.01 and _runner.global_position.distance_to(starting_position) < 0.005,
		"Climbing camera makes a full orbit without disturbing the planted stance")
	_check(overlaps == 0 and shortest_arm < 1.5 and longest_arm > 2.5,
		"Climbing camera retracts before masonry during an orbit (%d overlaps, %.2f to %.2f m)" % [
			overlaps, shortest_arm, longest_arm,
		])


func _check_tower_hanging_idle() -> void:
	var mode = _runner._wall_climb
	var tip_bones := [
		_climb_left_hand_bone, _climb_right_hand_bone,
		_climb_skeleton.find_bone("foot_l"), _climb_skeleton.find_bone("foot_r"),
	]
	_runner.chibi_input.clear_touch_input()
	_runner.reset_for_respawn(Vector3(0.0, 0.08, 3.25))
	_runner.rotation.y = 0.0
	_runner.camera_ctrl.yaw = 0.0
	_runner.camera_ctrl.reset_after_teleport()
	# Start at the first catch, then keep the same run and climb to a braced hold.
	for braced in [false, true]:
		_runner.chibi_input.set_touch_move(Vector2.UP)
		var has_foothold := false
		for frame in 400:
			await _frames(1)
			has_foothold = not mode.contacts[2].is_empty() or not mode.contacts[3].is_empty()
			if mode.phase == MOTION.Phase.HOLD and has_foothold == braced:
				break
		_runner.chibi_input.set_touch_move(Vector2.ZERO)
		var label := "braced" if braced else "unbraced"
		if mode.phase != MOTION.Phase.HOLD or has_foothold != braced:
			_check(false, "Chibi reaches the %s hang for idle verification" % label)
			continue

		var metrics := {
			"time": 0.0, "settled_yaw": INF, "early_turn": 0.0, "lateral_yaw": 0.0,
			"hand_samples": 0, "shoe_samples": 0, "hand_error": 0.0, "shoe_error": 0.0,
		}
		var sample := func() -> void:
			if mode.phase != MOTION.Phase.HOLD:
				return
			var skeleton_world := _climb_skeleton.get_global_transform_interpolated()
			var head_forward := (skeleton_world.basis * _climb_skeleton.get_bone_global_pose(_climb_head_bone).basis
				* _climb_face_axis).normalized()
			var yaw := atan2(head_forward.dot(mode.frame.x), -head_forward.dot(mode.frame.z))
			if metrics.time >= 0.12 and metrics.time <= 0.5:
				if is_inf(metrics.settled_yaw):
					metrics.settled_yaw = yaw
				metrics.early_turn = maxf(metrics.early_turn, rad_to_deg(absf(angle_difference(metrics.settled_yaw, yaw))))
			if metrics.time >= 0.28 and metrics.time <= 0.5:
				metrics.lateral_yaw = maxf(metrics.lateral_yaw, rad_to_deg(absf(yaw)))
			metrics.time += _climb_skeleton.get_process_delta_time()
			for limb in 4:
				var contact: Dictionary = mode.contacts[limb]
				if contact.is_empty():
					continue
				var actual: Vector3 = skeleton_world * _climb_skeleton.get_bone_global_pose(tip_bones[limb]).origin
				var error := actual.distance_to(mode._tip(contact, limb))
				if limb < 2:
					metrics.hand_samples += 1
					metrics.hand_error = maxf(metrics.hand_error, error)
				else:
					metrics.shoe_samples += 1
					metrics.shoe_error = maxf(metrics.shoe_error, error)
		var starting_position := _runner.global_position
		_climb_skeleton.skeleton_updated.connect(sample)
		await _frames(95)
		_climb_skeleton.skeleton_updated.disconnect(sample)
		_check(metrics.early_turn >= 12.0 and metrics.lateral_yaw >= 18.0,
			"%s hang has a readable glance within half a second (%.1f° lateral, %.1f° after settling)" % [
				label.capitalize(), metrics.lateral_yaw, metrics.early_turn,
		])
		_check(metrics.hand_samples > 10 and metrics.hand_error < 0.04 and metrics.shoe_error < 0.04
			and (not braced or metrics.shoe_samples > 10) and _runner.global_position.distance_to(starting_position) < 0.005,
			"%s idle keeps the stance planted (hand %.3f m, shoe %.3f m)" % [
				label.capitalize(), metrics.hand_error, metrics.shoe_error,
			])


func _check_spaced_masonry_geometry() -> void:
	var generated := _tower.get_node_or_null("GeneratedMasonry") as Node3D
	if generated == null:
		_check(false, "Tower generates separate collidable masonry holds")
		return
	var support_count := 0
	var window_sill_count := 0
	var south_projecting_count := 0
	var widest_south_sill := 0.0
	var longest_other_south_hold := 0.0
	var course_sums: Array[float] = []
	var course_counts: Array[int] = []
	for _row in 12:
		course_sums.append(0.0)
		course_counts.append(0)
	for child in generated.get_children():
		if not child is StaticBody3D:
			continue
		var body := child as StaticBody3D
		var label := String(body.name)
		if not (label.begins_with("CornerHold_") or label.begins_with("CornerApproach_")
			or label.begins_with("LedgeHold_") or label.begins_with("WindowSill_")):
			continue
		var collision := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if collision == null or not collision.shape is BoxShape3D:
			continue
		var box := collision.shape as BoxShape3D
		support_count += 1
		if label.begins_with("WindowSill_"):
			window_sill_count += 1
		var top_y := body.position.y + box.size.y * 0.5
		var course_index := int(label.split("_")[1])
		course_sums[course_index] += top_y
		course_counts[course_index] += 1
		if label.contains("_Side_0"):
			if body.position.z < -2.275 and body.position.z > -2.40:
				south_projecting_count += 1
			if label.begins_with("WindowSill_"):
				widest_south_sill = maxf(widest_south_sill, box.size.x)
			else:
				longest_other_south_hold = maxf(longest_other_south_hold, box.size.x)
	var course_tops: Array[float] = []
	for index in 12:
		if course_counts[index] > 0:
			course_tops.append(course_sums[index] / float(course_counts[index]))
	course_tops.sort()
	var has_open_course_gaps := course_tops.size() >= 10
	var has_short_reach_step := false
	var has_wide_leap_gap := false
	var min_course_gap := INF
	var max_course_gap := 0.0
	for index in range(1, course_tops.size()):
		var gap := course_tops[index] - course_tops[index - 1]
		min_course_gap = minf(min_course_gap, gap)
		max_course_gap = maxf(max_course_gap, gap)
		if gap < 0.30 or gap > 1.10:
			has_open_course_gaps = false
		if gap >= 0.30 and gap <= 0.40:
			has_short_reach_step = true
		if gap >= 0.75:
			has_wide_leap_gap = true
	_check(support_count >= 180 and has_open_course_gaps and has_short_reach_step and has_wide_leap_gap,
		"Tower has %d separate collidable holds across %d courses, with %.2f–%.2f m rise gaps" % [
			support_count, course_tops.size(), min_course_gap, max_course_gap,
		])
	_check(window_sill_count == 12 and south_projecting_count >= 45
		and widest_south_sill >= 1.40 and widest_south_sill <= 1.50 and longest_other_south_hold <= 0.90,
		"South face has %d projecting holds, %.2f m window sills, and other holds no longer than %.2f m" % [
			south_projecting_count, widest_south_sill, longest_other_south_hold,
		])


func _check_corner_direction(lateral: float, label: String) -> void:
	_reset_runner()
	await _frames(4)
	var mounted := _runner._try_mount_wall(Vector3(0.0, 0.0, 1.0), true)
	await _frames(18)
	var mode = _runner._wall_climb
	_check(mounted and mode.phase == MOTION.Phase.HOLD,
		"Tower mounts from the south face before the %s corner run" % label)
	if not mounted or mode.phase != MOTION.Phase.HOLD:
		return
	var initial_normal: Vector3 = mode.frame.z
	_start_climb_pose_capture("right" if lateral > 0.0 else "left")
	_runner.chibi_input.set_touch_move(Vector2(lateral, 0.0))
	var route_normals: Array[Vector3] = [initial_normal]
	var turns := 0
	for _frame in LAP_INPUT_LIMIT:
		await _frames(1)
		if mode.phase == MOTION.Phase.HOLD and route_normals.back().dot(mode.frame.z) < 0.20:
			turns += 1
			route_normals.append(mode.frame.z)
			if turns >= 4:
				break
		if mode.phase == MOTION.Phase.IDLE:
			break
	_stop_climb_pose_capture()
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	await _frames(2)
	var valid_lap: bool = turns == 4 and mode.phase == MOTION.Phase.HOLD and _runner.get_collision_mask_value(1)
	if route_normals.size() == 5:
		for index in range(1, route_normals.size()):
			if absf(route_normals[index - 1].dot(route_normals[index])) > 0.20:
				valid_lap = false
		if route_normals[0].dot(route_normals[4]) < 0.99:
			valid_lap = false
	_check(valid_lap,
		"Held %s input completes a four-corner lap and returns to the starting face" % label)
	if not valid_lap:
		print("DEBUG: %s lap stopped after %d turns at state=%s phase=%s position=%s hand=%s normal=%s" % [
			label, turns, _runner.current_state, str(mode.phase), str(_runner.global_position),
			str(mode._hand_center()) if mode.phase != MOTION.Phase.IDLE else "none",
			str(mode.frame.z),
		])


func _check_vertical_and_lateral_leaps() -> void:
	await _check_real_leap(Vector2.UP, "vertical")
	await _check_real_leap(Vector2.RIGHT, "rightward lateral")
	await _check_real_leap(Vector2.LEFT, "leftward lateral")


func _check_real_leap(direction: Vector2, label: String) -> void:
	_reset_runner()
	await _frames(4)
	var mounted := _runner._try_mount_wall(Vector3(0.0, 0.0, 1.0), true)
	await _frames(18)
	var mode = _runner._wall_climb
	_check(mounted and mode.phase == MOTION.Phase.HOLD,
		"Tower mounts before the %s leap input" % label)
	if not mounted or mode.phase != MOTION.Phase.HOLD:
		return
	var start_position: Vector3 = _runner.global_position
	var saw_jump := false
	var minimum_weight := 1.0
	var caught := false
	var finish_position := start_position
	_runner.chibi_input.set_touch_move(direction)
	for _frame in LEAP_INPUT_LIMIT:
		await _frames(1)
		if mode.phase == MOTION.Phase.JUMP:
			saw_jump = true
			minimum_weight = minf(minimum_weight, mode.body_weight)
		elif saw_jump and mode.phase == MOTION.Phase.HOLD:
			finish_position = _runner.global_position
			if finish_position.distance_to(start_position) > 0.08:
				caught = true
				break
		if mode.phase == MOTION.Phase.IDLE or _runner.current_state != "Climbing":
			break
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	await _frames(2)
	var displacement := finish_position - start_position
	var requested_world_direction: Vector3 = Vector3.UP if direction.y < -0.5 else mode.frame.x * signf(direction.x)
	var moved_in_direction: bool = displacement.dot(requested_world_direction) > 0.12
	_check(saw_jump and caught and moved_in_direction and minimum_weight < 0.96,
		"Real %s steering enters a weighted JUMP phase, catches a higher or farther hold, and moves in the requested direction" % label)
	if not saw_jump or not caught or not moved_in_direction or minimum_weight >= 0.96:
		print("DEBUG: %s leap saw=%s caught=%s weight=%.3f start=%s finish=%s state=%s phase=%s hand=%s" % [
			label, str(saw_jump), str(caught), minimum_weight, str(start_position), str(finish_position),
			_runner.current_state, str(mode.phase),
			str(mode._hand_center()) if mode.phase != MOTION.Phase.IDLE else "none",
		])


func _check_directional_input_hops() -> void:
	await _check_directional_input_hop(&"move_left", -1.0, "Left")
	await _check_directional_input_hop(&"move_right", 1.0, "Right")


func _check_directional_input_hop(action: StringName, lateral: float, label: String) -> void:
	_release_movement_actions()
	_reset_runner()
	await _frames(4)
	var mounted := _runner._try_mount_wall(Vector3(0.0, 0.0, 1.0), true)
	await _frames(18)
	var mode = _runner._wall_climb
	_check(mounted and mode.phase == MOTION.Phase.HOLD,
		"Tower mounts before the native %s-only hop input" % label)
	if not mounted or mode.phase != MOTION.Phase.HOLD:
		return

	var saw_directional_input := false
	var saw_jump_phase := false
	var caught := false
	var jump_action_seen := false
	var vertical_or_diagonal_seen := false
	var jump_start := Vector3.ZERO
	var jump_finish := Vector3.ZERO
	var jump_axis := Vector3.ZERO
	var jump_hand_origin := Vector3.ZERO
	var jump_goal := Vector3.ZERO
	var goal_collider: StaticBody3D
	var goal_point := Vector3.ZERO
	var jump_lead := -1
	var jump_positions: Array[Vector3] = []
	var peak_lift := 0.0
	var source_contacts: Array[Dictionary] = []
	var finished_contacts: Array[Dictionary] = []

	Input.action_press(action)
	for _frame in LEAP_INPUT_LIMIT:
		await _frames(1)
		var move: Vector2 = _runner.chibi_input.move_vec
		if move.x * lateral > 0.90 and absf(move.y) < 0.05:
			saw_directional_input = true
		if absf(move.y) > 0.05 or Input.is_action_pressed("move_forward") or Input.is_action_pressed("move_back"):
			vertical_or_diagonal_seen = true
		if Input.is_action_pressed("jump") or _runner.chibi_input.jump_held or _runner.chibi_input.jump_just_pressed:
			jump_action_seen = true

		if mode.phase == MOTION.Phase.JUMP:
			if not saw_jump_phase:
				saw_jump_phase = true
				jump_start = _runner.global_position
				jump_finish = mode._finish
				jump_axis = mode.frame.x * lateral
				jump_hand_origin = mode._hand_center()
				jump_lead = mode._lead
				var planned: Dictionary = mode._planned[jump_lead]
				goal_collider = planned.get("collider") as StaticBody3D
				goal_point = planned.get("point", Vector3.ZERO)
				jump_goal = goal_point
				source_contacts = mode.contacts.duplicate()
				jump_positions.append(jump_start)
			else:
				var current_position := _runner.global_position
				jump_positions.append(current_position)
				peak_lift = maxf(peak_lift, current_position.y - jump_start.y)
		elif saw_jump_phase and mode.phase == MOTION.Phase.HOLD:
			jump_finish = _runner.global_position
			finished_contacts = mode.contacts.duplicate()
			caught = true
			break
		elif saw_jump_phase and (mode.phase == MOTION.Phase.CORNER or mode.phase == MOTION.Phase.IDLE):
			break

	Input.action_release(action)
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	await _frames(2)
	if caught:
		jump_finish = _runner.global_position
		finished_contacts = mode.contacts.duplicate()

	var lateral_travel: float = (jump_finish - jump_start).dot(jump_axis) if saw_jump_phase else 0.0
	var target_delta: Vector3 = jump_goal - jump_hand_origin
	var target_stride: float = target_delta.dot(jump_axis)
	var target_face_delta: Vector3 = target_delta - mode.frame.z * target_delta.dot(mode.frame.z)
	var target_side_offset: float = (target_face_delta - jump_axis * target_stride).length()
	var target_is_nearby: bool = target_stride >= 0.28 and target_stride <= 0.92 and target_side_offset <= 0.48
	var target_is_distinct: bool = goal_collider != null
	for contact in source_contacts:
		if not contact.is_empty() and contact.get("collider") == goal_collider:
			target_is_distinct = false
	var landed_on_goal: bool = false
	if jump_lead >= 0 and jump_lead < finished_contacts.size() and not finished_contacts[jump_lead].is_empty():
		var landed_contact: Dictionary = finished_contacts[jump_lead]
		landed_on_goal = landed_contact.get("collider") == goal_collider \
			and (landed_contact.get("point", Vector3.ZERO) as Vector3).distance_to(goal_point) <= 0.08
	var goal_is_collidable_tower_hold: bool = goal_collider != null and goal_collider.is_inside_tree() \
		and goal_collider.get_collision_layer_value(1) and goal_collider.get_parent().name == "GeneratedMasonry"
	var max_still_ticks: int = _max_still_motion_ticks(jump_positions, 0.002)
	var arc_is_low: bool = peak_lift >= 0.055 and peak_lift <= 0.18
	var hop_is_short: bool = lateral_travel >= 0.28 and lateral_travel <= 0.72
	var passed: bool = saw_directional_input and saw_jump_phase and caught and not jump_action_seen \
		and not vertical_or_diagonal_seen and hop_is_short and arc_is_low and target_is_nearby \
		and target_is_distinct and landed_on_goal and goal_is_collidable_tower_hold and max_still_ticks <= 5
	_check(passed,
		"Native %s alone makes a short low-arc hop to a nearby distinct masonry hold with no Jump input" % label)
	if not passed:
		print("DEBUG: %s input-hop input=%s jump=%s caught=%s travel=%.3f arc=%.3f target_stride=%.3f target_side=%.3f distinct=%s landed=%s tower_hold=%s still=%d state=%s phase=%s start=%s finish=%s target=%s" % [
			label, str(saw_directional_input), str(saw_jump_phase), str(caught), lateral_travel, peak_lift,
			target_stride, target_side_offset, str(target_is_distinct), str(landed_on_goal),
			str(goal_is_collidable_tower_hold), max_still_ticks, _runner.current_state, str(mode.phase),
			str(jump_start), str(jump_finish), str(goal_point),
		])


func _check_reach_motion_profile() -> void:
	_reset_runner()
	await _frames(4)
	var mounted := _runner._try_mount_wall(Vector3(0.0, 0.0, 1.0), true)
	await _frames(18)
	var mode = _runner._wall_climb
	_check(mounted and mode.phase == MOTION.Phase.HOLD,
		"Tower mounts before sampling a staged upward reach")
	if not mounted or mode.phase != MOTION.Phase.HOLD:
		return

	_runner.chibi_input.set_touch_move(Vector2.UP)
	var saw_reach := false
	var reach_start := Vector3.ZERO
	var reach_finish := Vector3.ZERO
	var reach_axis := Vector3.ZERO
	var reach_completed := false
	var samples: Array[Vector3] = []
	for _frame in LEAP_INPUT_LIMIT:
		await _frames(1)
		if mode.phase == MOTION.Phase.REACH:
			saw_reach = true
			reach_start = mode._start
			reach_finish = mode._finish
			reach_axis = (reach_finish - reach_start).normalized()
			samples.append(_runner.global_position)
			break
		if mode.phase == MOTION.Phase.JUMP or mode.phase == MOTION.Phase.IDLE:
			break
	if saw_reach:
		for _frame in LEAP_INPUT_LIMIT:
			await _frames(1)
			samples.append(_runner.global_position)
			if mode.phase != MOTION.Phase.REACH:
				reach_finish = _runner.global_position
				reach_completed = true
				break
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	await _frames(2)

	var net_progress: float = (reach_finish - reach_start).dot(reach_axis) if saw_reach else 0.0
	var mid_progress: float = 0.0
	if samples.size() >= 6 and saw_reach:
		var mid_start_index := clampi(int(floor(float(samples.size() - 1) * 0.38)), 0, samples.size() - 1)
		var mid_end_index := clampi(int(ceil(float(samples.size() - 1) * 0.62)), 0, samples.size() - 1)
		mid_progress = (samples[mid_end_index] - samples[mid_start_index]).dot(reach_axis)
	var max_still_ticks: int = _max_still_motion_ticks(samples, 0.002)
	var midpoint_has_motion: bool = mid_progress > maxf(0.012, net_progress * 0.06)
	var passed: bool = saw_reach and reach_completed and net_progress > 0.12 and midpoint_has_motion and max_still_ticks <= 5
	_check(passed,
		"Reach keeps real body motion through its midpoint without a fixed multi-tick pause (net %.3f m, mid %.3f m, still %d ticks)" % [
			net_progress, mid_progress, max_still_ticks,
		])
	if not passed:
		print("DEBUG: reach profile saw=%s net=%.3f midpoint=%.3f still=%d samples=%d state=%s phase=%s" % [
			str(saw_reach), net_progress, mid_progress, max_still_ticks, samples.size(),
			_runner.current_state, str(mode.phase),
		])


func _check_untagged_lateral_no_hop() -> void:
	_release_movement_actions()
	_tower.remove_from_group("tower_corner_route")
	_reset_runner()
	await _frames(4)
	var mounted := _runner._try_mount_wall(Vector3(0.0, 0.0, 1.0), true)
	await _frames(18)
	var mode = _runner._wall_climb
	var saw_jump := false
	if mounted and mode.phase == MOTION.Phase.HOLD:
		Input.action_press(&"move_right")
		for _frame in 120:
			await _frames(1)
			if mode.phase == MOTION.Phase.JUMP:
				saw_jump = true
				break
	Input.action_release(&"move_right")
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	await _frames(2)
	_tower.add_to_group("tower_corner_route")
	var stayed_attached: bool = _runner.current_state == "Climbing" and mode.phase != MOTION.Phase.IDLE
	_check(mounted and stayed_attached and not saw_jump and not Input.is_action_pressed("jump"),
		"An untagged ordinary climb wall keeps lateral steering from starting tower-only hops")
	if not mounted or not stayed_attached or saw_jump:
		print("DEBUG: untagged lateral route mounted=%s attached=%s jump=%s state=%s phase=%s" % [
			str(mounted), str(stayed_attached), str(saw_jump), _runner.current_state, str(mode.phase),
		])


func _max_still_motion_ticks(samples: Array[Vector3], threshold: float) -> int:
	var current_run := 0
	var longest_run := 0
	for index in range(1, samples.size()):
		if samples[index].distance_to(samples[index - 1]) <= threshold:
			current_run += 1
			longest_run = maxi(longest_run, current_run)
		else:
			current_run = 0
	return longest_run


func _release_movement_actions() -> void:
	for action in [&"move_left", &"move_right", &"move_forward", &"move_back", &"jump"]:
		Input.action_release(action)


func _check_up_only_topouts() -> void:
	for face in _faces():
		_runner.chibi_input.clear_touch_input()
		_runner.reset_for_respawn(face["spawn"])
		_runner.rotation.y = face["yaw"]
		_runner.camera_ctrl.yaw = face["yaw"]
		_runner.velocity = Vector3.ZERO
		await _frames(5)
		_start_climb_pose_capture("up")
		var result: Dictionary = await _hold_up_to_roof(SUMMIT_INPUT_LIMIT)
		_stop_climb_pose_capture()
		_check(result["mounted"], "Grounded Up input attaches to the %s face" % face["label"])
		_check(result["saw_reach"] and result["saw_jump"] and result["minimum_reach_weight"] > 0.98,
			"Held Up keeps full support weight during real REACHes and enters JUMPs on the %s face" % face["label"])
		_check(result["mantled"] and result["landed"] and result["no_jump"],
			"Holding Up alone tops out from the %s face onto the roof" % face["label"])
		if not result["mounted"] or not result["mantled"] or not result["landed"]:
			print("DEBUG: %s topout result=%s state=%s phase=%s position=%s hand=%s" % [
				face["label"], str(result), _runner.current_state, str(_runner._wall_climb.phase),
				str(_runner.global_position),
				str(_runner._wall_climb._hand_center()) if _runner._wall_climb.phase != MOTION.Phase.IDLE else "none",
			])


func _check_blocked_summit_retry() -> void:
	var south := _faces()[0]
	_runner.chibi_input.clear_touch_input()
	_runner.reset_for_respawn(south["spawn"])
	_runner.rotation.y = south["yaw"]
	_runner.camera_ctrl.yaw = south["yaw"]
	_runner.velocity = Vector3.ZERO
	await _frames(5)
	var blocker := _make_box(_tower.get_parent(), Vector3(0.0, 8.58, -1.80), Vector3(4.60, 1.16, 0.36))
	_runner.chibi_input.set_touch_move(Vector2.UP)
	var remained_attached := false
	var saw_mount := false
	var reached_summit_hold := false
	var unexpected_mantle := false
	var unexpected_fall := false
	for _frame in SUMMIT_INPUT_LIMIT:
		await _frames(1)
		if _runner.current_state == "Climbing":
			saw_mount = true
			if _runner._wall_climb.phase == MOTION.Phase.HOLD:
				remained_attached = true
				if _runner._wall_climb._hand_center().y >= 7.15:
					reached_summit_hold = true
		elif saw_mount and _runner.current_state == "MantleUp":
			unexpected_mantle = true
			break
		elif saw_mount and _runner.current_state == "Locomotion":
			unexpected_fall = true
			break
	var mode = _runner._wall_climb
	var was_blocked: bool = reached_summit_hold and not unexpected_mantle and not unexpected_fall \
		and _runner.current_state == "Climbing" and mode.phase == MOTION.Phase.HOLD
	_check(was_blocked and not _runner.chibi_input.jump_held and not _runner.chibi_input.jump_just_pressed
		and not Input.is_action_pressed("jump"),
		"Grounded Up input reaches the obstruction and keeps Chibi attached without a jump press")
	if not was_blocked:
		print("DEBUG: blocked summit attached_seen=%s summit_hold=%s mantle=%s fall=%s state=%s phase=%s position=%s hand=%s" % [
			str(remained_attached), str(reached_summit_hold), str(unexpected_mantle), str(unexpected_fall),
			_runner.current_state, str(mode.phase), str(_runner.global_position),
			str(mode._hand_center()) if mode.phase != MOTION.Phase.IDLE else "none",
		])
	blocker.queue_free()
	await _frames(3)
	if not was_blocked:
		return
	var result: Dictionary = await _hold_up_to_roof(SUMMIT_INPUT_LIMIT)
	_check(result["mantled"] and result["landed"] and result["no_jump"],
		"Removing the summit obstruction lets held Up mantle onto the roof without pressing Jump")
	if not result["mantled"] or not result["landed"]:
		print("DEBUG: retry topout result=%s state=%s phase=%s position=%s" % [
			str(result), _runner.current_state, str(_runner._wall_climb.phase), str(_runner.global_position),
		])


func _check_released_upward_leap_topout() -> void:
	var south := _faces()[0]
	_runner.chibi_input.clear_touch_input()
	_runner.reset_for_respawn(south["spawn"])
	_runner.rotation.y = south["yaw"]
	_runner.camera_ctrl.yaw = south["yaw"]
	_runner.velocity = Vector3.ZERO
	await _frames(5)
	var mode = _runner._wall_climb
	var mounted := false
	var saw_final_leap := false
	var mantled_after_release := false
	_runner.chibi_input.set_touch_move(Vector2.UP)
	for _frame in SUMMIT_INPUT_LIMIT:
		await _frames(1)
		if _runner.current_state == "Climbing":
			mounted = true
		if mode.phase == MOTION.Phase.JUMP and mode._planned[mode._lead]["point"].y >= 7.67:
			saw_final_leap = true
			_runner.chibi_input.set_touch_move(Vector2.ZERO)
		if saw_final_leap and _runner.current_state == "MantleUp":
			mantled_after_release = true
			break
		if _runner.current_state == "MantleUp":
			# If this route has no summit leap, the held-Up test covers the mantle
			# itself. Do not manufacture a jump state to make this assertion pass.
			break
		if mode.phase == MOTION.Phase.IDLE or _runner.current_state == "Locomotion":
			if mounted:
				break
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	await _frames(62)
	_check(mounted and saw_final_leap and mantled_after_release and _runner.current_state == "Locomotion"
		and _runner.global_position.y >= 7.98 and not _runner.chibi_input.jump_held
		and not _runner.chibi_input.jump_just_pressed and not Input.is_action_pressed("jump"),
		"Finishing the final upward leap after releasing Up still carries Chibi onto the roof")
	if not mounted or not saw_final_leap or not mantled_after_release:
		print("DEBUG: released leap mounted=%s saw=%s mantled=%s state=%s phase=%s position=%s hand=%s" % [
			str(mounted), str(saw_final_leap), str(mantled_after_release), _runner.current_state, str(mode.phase),
			str(_runner.global_position),
			str(mode._hand_center()) if mode.phase != MOTION.Phase.IDLE else "none",
		])


func _hold_up_to_roof(limit: int) -> Dictionary:
	var mounted := false
	var saw_reach := false
	var saw_jump := false
	var minimum_reach_weight := 1.0
	var saw_mantle := false
	var landed := false
	var locomotion_ticks := 0
	_runner.chibi_input.set_touch_move(Vector2.UP)
	for _frame in limit:
		await _frames(1)
		if _runner.current_state == "Climbing" and _runner._wall_climb.phase != MOTION.Phase.IDLE:
			mounted = true
			if _runner._wall_climb.phase == MOTION.Phase.REACH:
				saw_reach = true
				minimum_reach_weight = minf(minimum_reach_weight, _runner._wall_climb.body_weight)
			elif _runner._wall_climb.phase == MOTION.Phase.JUMP:
				saw_jump = true
		if _runner.current_state == "MantleUp":
			saw_mantle = true
		elif saw_mantle and _runner.current_state == "Locomotion" and _runner.global_position.y >= 7.98:
			locomotion_ticks += 1
			if locomotion_ticks >= 2:
				landed = _runner.get_collision_mask_value(1) and _runner.is_on_floor()
				break
		elif _runner.current_state != "MantleUp":
			locomotion_ticks = 0
		if mounted and _runner.current_state == "Locomotion" and not saw_mantle:
			break
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	await _frames(2)
	return {
		"mounted": mounted,
		"saw_reach": saw_reach,
		"saw_jump": saw_jump,
		"minimum_reach_weight": minimum_reach_weight,
		"mantled": saw_mantle,
		"landed": landed,
		"no_jump": not _runner.chibi_input.jump_held and not _runner.chibi_input.jump_just_pressed
			and not Input.is_action_pressed("jump"),
	}


func _faces() -> Array[Dictionary]:
	return [
		{"label": "south", "spawn": Vector3(0.0, 0.035, -3.25), "yaw": PI},
		{"label": "north", "spawn": Vector3(0.0, 0.035, 3.25), "yaw": 0.0},
		{"label": "east", "spawn": Vector3(3.25, 0.035, 0.0), "yaw": PI * 0.5},
		{"label": "west", "spawn": Vector3(-3.25, 0.035, 0.0), "yaw": -PI * 0.5},
	]


func _setup_climb_pose_sampler() -> void:
	if _runner.pose_mod == null:
		return
	_climb_skeleton = _runner.pose_mod.get_skeleton() as Skeleton3D
	if _climb_skeleton == null:
		return
	_climb_head_bone = _climb_skeleton.find_bone("head")
	if _climb_head_bone < 0:
		_climb_head_bone = _climb_skeleton.find_bone("neck_01")
	_climb_left_hand_bone = _climb_skeleton.find_bone("hand_l")
	_climb_right_hand_bone = _climb_skeleton.find_bone("hand_r")
	if _climb_head_bone >= 0:
		# Express the runner's forward direction in the head's rest frame so the
		# measurement follows the rendered rig even if its authored face axis changes.
		_climb_face_axis = _climb_skeleton.get_bone_global_rest(_climb_head_bone).basis.inverse() * (
			_climb_skeleton.global_basis.inverse() * (_runner.global_basis * Vector3.FORWARD)
		)
	_climb_skeleton.skeleton_updated.connect(_sample_climb_pose)


func _start_climb_pose_capture(intent: String) -> void:
	_climb_pose_intent = intent
	_climb_pose_last_phase = MOTION.Phase.IDLE


func _stop_climb_pose_capture() -> void:
	_climb_pose_intent = ""
	_climb_pose_last_phase = MOTION.Phase.IDLE


func _sample_climb_pose() -> void:
	if _climb_pose_intent.is_empty() or _climb_skeleton == null or _climb_head_bone < 0:
		return
	var mode = _runner._wall_climb
	if _runner.current_state != "Climbing" or mode.phase < MOTION.Phase.HOLD:
		_climb_pose_last_phase = mode.phase
		return

	var skeleton_world := _climb_skeleton.get_global_transform_interpolated()
	var head_forward := (skeleton_world.basis * _climb_skeleton.get_bone_global_pose(_climb_head_bone).basis
		* _climb_face_axis).normalized()
	var pitch := rad_to_deg(asin(clampf(head_forward.y, -1.0, 1.0)))
	var travel := Vector3.UP
	if _climb_pose_intent != "up":
		var shown_normal: Vector3 = mode.get_presentation_normal()
		var tangent := Vector3.UP.cross(shown_normal).normalized()
		if tangent.length_squared() > 0.5:
			travel = tangent * (-1.0 if _climb_pose_intent == "left" else 1.0)
	var gaze_alignment := head_forward.dot(travel)
	var phase: int = mode.phase
	var row := _climb_pose_row_for_write(_climb_pose_intent, phase)
	row[0] += 1
	row[1] += gaze_alignment
	row[2] += pitch

	if _climb_pose_intent != "up":
		if phase == MOTION.Phase.REACH and mode._elapsed / maxf(mode._duration, 0.001) >= 0.12 \
			and mode._elapsed / maxf(mode._duration, 0.001) <= 0.48:
			var support_side: int = 1 - mode._lead
			var support_contact: Dictionary = mode.contacts[support_side]
			if not support_contact.is_empty():
				var hand_bone: int = _climb_left_hand_bone if support_side == 0 else _climb_right_hand_bone
				var expected_hand: Vector3 = mode._tip(support_contact, support_side)
				var actual_hand: Vector3 = (skeleton_world * _climb_skeleton.get_bone_global_pose(hand_bone)).origin
				var hand_error := actual_hand.distance_to(expected_hand)
				row[6] += 1
				row[7] = maxf(row[7], hand_error)
				if _is_real_tower_hold(support_contact):
					row[8] += 1

		if phase == MOTION.Phase.REACH or phase == MOTION.Phase.CORNER:
			for side in 2:
				var limb := 2 + side
				var source: Dictionary = mode.contacts[limb]
				var planned: Dictionary = mode._planned[limb]
				var free_leg := source.is_empty() or planned.is_empty()
				if not free_leg:
					free_leg = source.get("collider") != planned.get("collider") \
						or (source.get("point", Vector3.ZERO) as Vector3).distance_to(
							planned.get("point", Vector3.ZERO) as Vector3
						) > 0.025
				if free_leg:
					var suffix := "_l" if side == 0 else "_r"
					var hip_bone := _climb_skeleton.find_bone("thigh" + suffix)
					var knee_bone := _climb_skeleton.find_bone("calf" + suffix)
					var ankle_bone := _climb_skeleton.find_bone("foot" + suffix)
					if hip_bone >= 0 and knee_bone >= 0 and ankle_bone >= 0:
						var hip := _climb_skeleton.get_bone_global_pose(hip_bone).origin
						var knee := _climb_skeleton.get_bone_global_pose(knee_bone).origin
						var ankle := _climb_skeleton.get_bone_global_pose(ankle_bone).origin
						var flexion := rad_to_deg((knee - hip).angle_to(ankle - knee))
						row[3] += flexion
						row[4] += 1
						row[5] = maxf(row[5], flexion)

	if phase == MOTION.Phase.REACH or phase == MOTION.Phase.HOLD or phase == MOTION.Phase.CORNER:
		var foot_contacts := 0
		var all_footholds_real := true
		for side in 2:
			var limb := 2 + side
			var source: Dictionary = mode.contacts[limb]
			if source.is_empty():
				continue
			foot_contacts += 1
			if not _is_real_tower_hold(source):
				all_footholds_real = false
			var planned: Dictionary = mode._planned[limb]
			var same_hold: bool = not planned.is_empty() \
				and source.get("collider") == planned.get("collider") \
				and (source.get("point", Vector3.ZERO) as Vector3).distance_to(
					planned.get("point", Vector3.ZERO) as Vector3
				) <= 0.025
			var weight: float = _runner.pose_mod._wall_weights[limb]
			if same_hold and weight >= 0.72 and _is_real_tower_hold(source):
				var foot_bone := _climb_skeleton.find_bone("foot_l" if side == 0 else "foot_r")
				if foot_bone >= 0:
					var actual_foot := (skeleton_world * _climb_skeleton.get_bone_global_pose(foot_bone)).origin
					var target_foot: Vector3 = mode._tip(source, limb)
					row[9] += 1
					row[10] = maxf(row[10], actual_foot.distance_to(target_foot))
		if foot_contacts > 0:
			if all_footholds_real:
				row[11] += 1
			else:
				row[12] += 1

	if phase == MOTION.Phase.HOLD and _climb_pose_last_phase in [MOTION.Phase.REACH, MOTION.Phase.JUMP, MOTION.Phase.CORNER]:
		var catch_row := _climb_pose_row_for_write(_climb_pose_intent, POSE_CATCH_KEY)
		catch_row[0] += 1
		catch_row[1] += gaze_alignment
	_climb_pose_last_phase = phase


func _climb_pose_row_for_write(intent: String, phase: int) -> Array:
	var route_rows: Dictionary = _climb_pose_metrics.get(intent, {})
	var row: Array = route_rows.get(phase, [0, 0.0, 0.0, 0.0, 0, 0.0, 0, 0.0, 0, 0, 0.0, 0, 0, 0, 0.0])
	route_rows[phase] = row
	_climb_pose_metrics[intent] = route_rows
	return row


func _climb_pose_row(intent: String, phase: int) -> Array:
	var route_rows: Dictionary = _climb_pose_metrics.get(intent, {})
	return route_rows.get(phase, [])


func _climb_pose_combine(intent: String, phases: Array[int]) -> Array:
	var combined: Array = [0, 0.0, 0.0, 0.0, 0, 0.0, 0, 0.0, 0, 0, 0.0, 0, 0, 0, 0.0]
	for phase in phases:
		var row := _climb_pose_row(intent, phase)
		if row.is_empty():
			continue
		for index in [0, 1, 2, 3, 4, 6, 8, 9, 11, 12, 13, 14]:
			combined[index] += row[index]
		for index in [5, 7, 10]:
			combined[index] = maxf(combined[index], row[index])
	return combined


func _is_real_tower_hold(contact: Dictionary) -> bool:
	var collider := contact.get("collider") as StaticBody3D
	var generated := _tower.get_node_or_null("GeneratedMasonry")
	return collider != null and collider.is_inside_tree() and collider.get_parent() == generated \
		and collider.get_collision_layer_value(1)


func _check_climb_pose_replay() -> void:
	if _climb_skeleton != null and _climb_skeleton.skeleton_updated.is_connected(_sample_climb_pose):
		_climb_skeleton.skeleton_updated.disconnect(_sample_climb_pose)
	var up_reaches := _climb_pose_row("up", MOTION.Phase.REACH)
	var up_pitch: float = 0.0 if up_reaches.is_empty() else float(up_reaches[2]) / float(up_reaches[0])
	var up_alignment: float = 0.0 if up_reaches.is_empty() else float(up_reaches[1]) / float(up_reaches[0])
	_check(up_reaches.size() > 0 and up_reaches[0] >= 12 and up_pitch > 5.0 and up_alignment > 0.08,
		"Rendered gaze rises along the route during held-Up reaches (%.1f° pitch, %.2f alignment)" % [up_pitch, up_alignment])

	var free_knee_samples := 0
	var free_knee_sum := 0.0
	var free_knee_peak := 0.0
	var all_side_gaze := true
	var all_side_catches := true
	var all_side_hands := true
	var up_footholds := _climb_pose_combine("up", [MOTION.Phase.REACH, MOTION.Phase.HOLD])
	var up_hold_footholds := _climb_pose_row("up", MOTION.Phase.HOLD)
	var up_footholds_ok: bool = up_footholds[11] >= 8 and up_footholds[12] == 0 \
		and up_footholds[9] >= 8 and up_footholds[10] < 0.08 \
		and not up_hold_footholds.is_empty() and up_hold_footholds[11] >= 4
	for intent in ["left", "right"]:
		var active := _climb_pose_combine(intent, [MOTION.Phase.REACH, MOTION.Phase.JUMP, MOTION.Phase.CORNER])
		var reaches := _climb_pose_row(intent, MOTION.Phase.REACH)
		var corners := _climb_pose_row(intent, MOTION.Phase.CORNER)
		var catches := _climb_pose_row(intent, POSE_CATCH_KEY)
		var mean_alignment: float = float(active[1]) / maxf(float(active[0]), 1.0)
		var catch_alignment: float = 0.0 if catches.is_empty() else float(catches[1]) / float(catches[0])
		free_knee_samples += active[4]
		free_knee_sum += active[3]
		free_knee_peak = maxf(free_knee_peak, active[5])
		var gaze_ok: bool = not reaches.is_empty() and not corners.is_empty() \
			and reaches[0] >= 8 and corners[0] >= 8 and mean_alignment > 0.10
		var catches_ok: bool = not catches.is_empty() and catches[0] >= 2 and catch_alignment > 0.02
		var hands_ok: bool = reaches.size() > 0 and reaches[6] >= 8 and reaches[8] == reaches[6] and reaches[7] < 0.055
		all_side_gaze = all_side_gaze and gaze_ok
		all_side_catches = all_side_catches and catches_ok
		all_side_hands = all_side_hands and hands_ok
		print("INFO: %s climb pose gaze=%.2f reach=%d corner=%d catches=%.2f/%d support=%.3f/%d knees=%.1f°/%d" % [
			intent, mean_alignment, 0 if reaches.is_empty() else reaches[0], 0 if corners.is_empty() else corners[0],
			catch_alignment, 0 if catches.is_empty() else catches[0],
			0.0 if reaches.is_empty() else reaches[7], 0 if reaches.is_empty() else reaches[6],
			active[3] / maxf(float(active[4]), 1.0), active[4],
		])
	_check(all_side_gaze,
		"Rendered gaze follows held Left and Right input through reaches and corner turns")
	_check(all_side_catches,
		"Rendered gaze carries the held Left and Right focus through catches")
	_check(free_knee_samples >= 12 and free_knee_sum / maxf(float(free_knee_samples), 1.0) > 5.0
		and free_knee_peak > 10.0,
		"Free knees stay visibly flexed during sideways reaches and corners (%.1f° mean, %.1f° peak)" % [
			free_knee_sum / maxf(float(free_knee_samples), 1.0), free_knee_peak,
		])
	_check(all_side_hands,
		"The support hand stays planted on its real masonry hold during sideways reaches")
	_check(up_footholds_ok,
		"Rendered shoes stay planted on real masonry footholds during the upward ascent and catches (%.3f m, %d contacts)" % [
			up_footholds[10], up_footholds[11],
		])


func _reset_runner() -> void:
	_runner.chibi_input.clear_touch_input()
	_runner.reset_for_respawn(Vector3(0.0, 0.035, -3.06))
	_runner.rotation.y = 0.0
	_runner.camera_ctrl.yaw = 0.0
	_runner.velocity = Vector3.ZERO


func _add_floor(parent: Node3D) -> void:
	var floor := StaticBody3D.new()
	floor.name = "TestGround"
	floor.collision_layer = 1
	var shape := BoxShape3D.new()
	shape.size = Vector3(80.0, 0.20, 80.0)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	floor.add_child(collision)
	floor.position.y = -0.10
	parent.add_child(floor)


func _make_box(parent: Node3D, center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	body.global_position = center
	return body


func _frames(count: int) -> void:
	for _frame in count:
		await physics_frame
		await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		_failures += 1
		push_error("FAIL: %s" % message)
