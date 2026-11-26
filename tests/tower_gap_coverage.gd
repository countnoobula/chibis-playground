extends SceneTree

## Direction-only tower gap audit. Run directly with the project's Godot console:
## Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/tower_gap_coverage.gd

const TOWER_SCENE := preload("res://scenes/stations/rooftop_climb_tower.tscn")
const RUNNER_SCENE := preload("res://scenes/character/chibi_runner.tscn")
const MOTION := preload("res://scripts/climbing/wall_climb_motion.gd")

const ROUTE_FRAME_LIMIT := 1800
const SIDE_ROUTE_FRAME_LIMIT := 900
const HIGH_SPAWN_Y := 7.30

var _failures := 0
var _passes := 0
var _runner: ParkourController
var _tower: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.physics_ticks_per_second = 60
	var test_root := Node3D.new()
	test_root.name = "TowerGapCoverageRoot"
	root.add_child(test_root)
	_add_floor(test_root)
	_tower = TOWER_SCENE.instantiate() as Node3D
	test_root.add_child(_tower)
	_runner = RUNNER_SCENE.instantiate() as ParkourController
	test_root.add_child(_runner)
	await _frames(12)
	_release_actions()

	_check_authored_paired_courses()
	for face in _faces():
		await _check_full_up(face)
		await _check_full_descent(face)
		await _check_outward_and_return_lane(face, -1)
		await _check_outward_and_return_lane(face, 1)

	await _check_upper_paired_course_laps()

	print("=== TOWER GAP COVERAGE: %d passed, %d failed ===" % [_passes, _failures])
	test_root.queue_free()
	await _frames(2)
	quit(0 if _failures == 0 else 1)


func _check_authored_paired_courses() -> void:
	var generated := _tower.get_node_or_null("GeneratedMasonry") as Node3D
	var complete := generated != null
	for row in [0, 6]:
		for side in 4:
			for end_label in ["Negative", "Positive"]:
				complete = complete and generated.get_node_or_null("CornerHold_%02d_Side_%d_%s" % [row, side, end_label]) != null
				complete = complete and generated.get_node_or_null("CornerApproach_%02d_Side_%d_%s" % [row, side, end_label]) != null
	_check(complete, "Both authored paired courses expose matching approach and corner holds on all four faces")


func _check_full_up(face: Dictionary) -> void:
	_release_actions()
	_runner.chibi_input.clear_touch_input()
	_runner.reset_for_respawn(face["spawn"])
	_runner.rotation.y = face["yaw"]
	_runner.camera_ctrl.yaw = face["yaw"]
	_runner.velocity = Vector3.ZERO
	await _frames(5)
	var mounted := _runner._try_mount_wall(face["approach"], true)
	await _frames(18)
	var mode = _runner._wall_climb
	if not mounted or mode.phase != MOTION.Phase.HOLD:
		_check(false, "Up route mounts the %s face" % face["label"])
		return

	var visited_rows: Dictionary = {}
	var handoffs := 0
	var max_hand_y := mode._hand_center().y
	var saw_mantle := false
	var landed_ticks := 0
	var delivered_input := false
	var movement_consistent := true
	var no_jump := true
	var previous_phase: int = mode.phase
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	Input.action_press(&"move_forward")
	for _tick in ROUTE_FRAME_LIMIT:
		await _frames(1)
		var move: Vector2 = _runner.chibi_input.move_vec
		delivered_input = delivered_input or move.is_equal_approx(Vector2.UP)
		movement_consistent = movement_consistent and move.is_equal_approx(Vector2.UP)
		no_jump = no_jump and not _jump_is_active()
		if _runner.current_state == "Climbing":
			mode = _runner._wall_climb
			_record_rows(visited_rows, mode.contacts)
			if previous_phase == MOTION.Phase.HOLD and mode.phase in [MOTION.Phase.REACH, MOTION.Phase.JUMP]:
				handoffs += 1
			if mode.phase == MOTION.Phase.HOLD:
				max_hand_y = maxf(max_hand_y, mode._hand_center().y)
			elif mode.phase == MOTION.Phase.REACH or mode.phase == MOTION.Phase.JUMP:
				max_hand_y = maxf(max_hand_y, _planned_hand_y(mode))
				_record_rows(visited_rows, mode._planned)
			previous_phase = mode.phase
		elif _runner.current_state == "MantleUp":
			saw_mantle = true
		elif saw_mantle and _runner.current_state == "Locomotion" and _runner.global_position.y >= 7.98:
			landed_ticks += 1
			if landed_ticks >= 2:
				break
		else:
			landed_ticks = 0

	Input.action_release(&"move_forward")
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	await _frames(2)
	var reached_summit := max_hand_y >= 7.55 or _runner.global_position.y >= 7.98
	var course_count := visited_rows.size()
	var passed := delivered_input and movement_consistent and no_jump and handoffs >= 8 and reached_summit and saw_mantle \
		and landed_ticks >= 2 and course_count == 12
	_check(passed, "Repeated Up alone crosses the %s face from the base through the summit (courses %d/12, handoffs %d, max hand %.2f m)" % [
		face["label"], course_count, handoffs, max_hand_y,
	])
	if not passed:
		print("GAP-DEBUG up face=%s rows=%s handoffs=%d mantle=%s landed=%d input=%s no_jump=%s state=%s phase=%s runner=%s hand=%s" % [
			face["label"], str(visited_rows.keys()), handoffs, str(saw_mantle), landed_ticks,
			str(delivered_input and movement_consistent), str(no_jump), _runner.current_state, str(_runner._wall_climb.phase),
			str(_runner.global_position), _current_hand_text(),
		])


func _check_full_descent(face: Dictionary) -> void:
	if not await _mount_at_height(face, HIGH_SPAWN_Y, 0.0):
		_check(false, "High-grip setup mounts the %s face for descent" % face["label"])
		return
	var mode = _runner._wall_climb
	var start_hand := mode._hand_center()
	var start_y := start_hand.y
	var visited_rows: Dictionary = {}
	var handoffs := 0
	var min_hand_y := start_y
	var delivered_input := false
	var no_jump := true
	var dropped := false
	var previous_phase: int = mode.phase
	_record_rows(visited_rows, mode.contacts)
	Input.action_press(&"move_back")
	for _tick in ROUTE_FRAME_LIMIT:
		await _frames(1)
		var move: Vector2 = _runner.chibi_input.move_vec
		delivered_input = delivered_input or move.is_equal_approx(Vector2.DOWN)
		no_jump = no_jump and move.is_equal_approx(Vector2.DOWN) and not _jump_is_active()
		if _runner.current_state != "Climbing" or mode.phase == MOTION.Phase.IDLE:
			dropped = true
			break
		if mode.phase == MOTION.Phase.HOLD:
			min_hand_y = minf(min_hand_y, mode._hand_center().y)
			_record_rows(visited_rows, mode.contacts)
			if mode._hand_center().y <= 0.82:
				break
		elif mode.phase == MOTION.Phase.REACH or mode.phase == MOTION.Phase.JUMP:
			min_hand_y = minf(min_hand_y, _planned_hand_y(mode))
			_record_rows(visited_rows, mode._planned)
		if previous_phase == MOTION.Phase.HOLD and mode.phase in [MOTION.Phase.REACH, MOTION.Phase.JUMP]:
			handoffs += 1
		previous_phase = mode.phase
	Input.action_release(&"move_back")
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	await _frames(2)
	var low_course_reached := min_hand_y <= 0.82
	var passed: bool = start_y >= 7.55 and delivered_input and no_jump and not dropped \
		and low_course_reached and handoffs >= 8 and visited_rows.has(11) and visited_rows.has(0) \
		and _runner.current_state == "Climbing"
	_check(passed, "Repeated Down alone descends the %s face from upper grip %.2f m to the base courses (min %.2f m, courses %d, handoffs %d)" % [
		face["label"], start_y, min_hand_y, visited_rows.size(), handoffs,
	])
	if not passed:
		print("GAP-DEBUG down face=%s start=%.3f min=%.3f dropped=%s rows=%s handoffs=%d state=%s phase=%s pos=%s hand=%s holds=%s" % [
			face["label"], start_y, min_hand_y, str(dropped), str(visited_rows.keys()), handoffs,
			_runner.current_state, str(mode.phase), str(_runner.global_position), _current_hand_text(), str(_contact_names(mode.contacts)),
		])


func _check_outward_and_return_lane(face: Dictionary, direction: int) -> void:
	var label := "Right" if direction > 0 else "Left"
	if not await _reach_mid_hold(face):
		_check(false, "%s route reaches a natural mid-height grip on the %s face" % [label, face["label"]])
		return
	var mode = _runner._wall_climb
	var start_hand_y := mode._hand_center().y
	var start_position := _runner.global_position
	var start_contacts := _contact_names(mode.contacts)
	var outward_vector := Vector2.RIGHT if direction > 0 else Vector2.LEFT
	var outward_action: StringName = &"move_right" if direction > 0 else &"move_left"
	var delivered_outward := false
	var no_jump := true
	var corner_caught := false
	var corner_name := ""
	var previous_phase: int = mode.phase
	Input.action_press(outward_action)
	for _tick in SIDE_ROUTE_FRAME_LIMIT:
		await _frames(1)
		var move: Vector2 = _runner.chibi_input.move_vec
		delivered_outward = delivered_outward or move.is_equal_approx(outward_vector)
		no_jump = no_jump and move.is_equal_approx(outward_vector) and not _jump_is_active()
		if _runner.current_state != "Climbing" or mode.phase == MOTION.Phase.IDLE:
			break
		if mode.phase == MOTION.Phase.HOLD and previous_phase in [MOTION.Phase.REACH, MOTION.Phase.JUMP, MOTION.Phase.CORNER]:
			corner_name = _new_contact_name(mode.contacts, "CornerHold_", start_contacts)
			if not corner_name.is_empty():
				corner_caught = true
				break
		previous_phase = mode.phase
	Input.action_release(outward_action)
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	await _frames(2)
	var corner_hand := mode._hand_center() if mode.phase != MOTION.Phase.IDLE else Vector3.ZERO
	var corner_contacts := _contact_names(mode.contacts)
	var corner_stable: bool = corner_caught and _runner.current_state == "Climbing" \
		and mode.phase == MOTION.Phase.HOLD and not _new_contact_name(mode.contacts, "CornerHold_", start_contacts).is_empty()

	var return_direction := -direction
	var return_vector := Vector2.RIGHT if return_direction > 0 else Vector2.LEFT
	var return_action: StringName = &"move_right" if return_direction > 0 else &"move_left"
	var delivered_return := false
	var returned_to_inner := false
	var return_delta := 0.0
	var return_handoffs := 0
	var previous_return_phase: int = mode.phase
	Input.action_press(return_action)
	for _tick in SIDE_ROUTE_FRAME_LIMIT:
		await _frames(1)
		var move: Vector2 = _runner.chibi_input.move_vec
		delivered_return = delivered_return or move.is_equal_approx(return_vector)
		no_jump = no_jump and move.is_equal_approx(return_vector) and not _jump_is_active()
		if _runner.current_state != "Climbing" or mode.phase == MOTION.Phase.IDLE:
			break
		if previous_return_phase in [MOTION.Phase.REACH, MOTION.Phase.JUMP, MOTION.Phase.CORNER] \
			and mode.phase == MOTION.Phase.HOLD:
			return_handoffs += 1
		if mode.phase == MOTION.Phase.HOLD:
			var has_inner := _has_contact_prefix(mode.contacts, ["LedgeHold_", "WindowSill_"])
			return_delta = mode._hand_center().distance_to(corner_hand)
			if has_inner and return_handoffs > 0 and return_delta > 0.12:
				returned_to_inner = true
				break
		previous_return_phase = mode.phase
	Input.action_release(return_action)
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	await _frames(2)
	var passed: bool = start_hand_y >= 4.50 and start_hand_y <= 4.90 and delivered_outward \
		and delivered_return and no_jump and corner_stable and returned_to_inner \
		and _runner.current_state == "Climbing" and mode.phase == MOTION.Phase.HOLD
	_check(passed, "%s outward and reverse input carries the %s mid-height route from a CornerHold back to an inner hold (%.2f m)" % [
		label, face["label"], return_delta,
	])
	if not passed:
		print("GAP-DEBUG side face=%s dir=%s hand_y=%.3f start=%s start_holds=%s corner=%s corner_holds=%s return=%.3f inner=%s end_state=%s end_phase=%s end=%s end_holds=%s" % [
			face["label"], label, start_hand_y, str(start_position), str(start_contacts), corner_name,
			str(corner_contacts), return_delta, str(returned_to_inner), _runner.current_state,
			str(mode.phase), str(_runner.global_position), str(_contact_names(mode.contacts)),
		])


func _reach_mid_hold(face: Dictionary) -> bool:
	_release_actions()
	_runner.chibi_input.clear_touch_input()
	_runner.reset_for_respawn(face["spawn"])
	_runner.rotation.y = face["yaw"]
	_runner.camera_ctrl.yaw = face["yaw"]
	_runner.velocity = Vector3.ZERO
	await _frames(5)
	var mounted := _runner._try_mount_wall(face["approach"], true)
	await _frames(18)
	if not mounted or _runner._wall_climb.phase != MOTION.Phase.HOLD:
		return false
	Input.action_press(&"move_forward")
	var reached := false
	var no_jump := true
	for _tick in ROUTE_FRAME_LIMIT:
		await _frames(1)
		no_jump = no_jump and _runner.chibi_input.move_vec.is_equal_approx(Vector2.UP) and not _jump_is_active()
		if _runner.current_state != "Climbing":
			break
		var mode = _runner._wall_climb
		if mode.phase == MOTION.Phase.HOLD and mode._hand_center().y >= 4.55:
			reached = true
			break
	Input.action_release(&"move_forward")
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	await _frames(2)
	var mode = _runner._wall_climb
	return reached and _runner.current_state == "Climbing" and mode.phase == MOTION.Phase.HOLD \
		and mode._hand_center().y >= 4.50 and mode._hand_center().y <= 4.90 and no_jump and not _jump_is_active()


func _contact_names(contacts: Array[Dictionary]) -> Array[String]:
	var names: Array[String] = []
	for index in mini(2, contacts.size()):
		if contacts[index].is_empty():
			continue
		var collider := contacts[index].get("collider") as Node
		if collider != null:
			names.append(String(collider.name))
	return names


func _new_contact_name(contacts: Array[Dictionary], prefix: String, previous_names: Array[String]) -> String:
	for index in mini(2, contacts.size()):
		if contacts[index].is_empty():
			continue
		var collider := contacts[index].get("collider") as Node
		if collider != null and String(collider.name).begins_with(prefix) and not previous_names.has(String(collider.name)):
			return String(collider.name)
	return ""


func _has_contact_prefix(contacts: Array[Dictionary], prefixes: Array[String]) -> bool:
	for index in mini(2, contacts.size()):
		if contacts[index].is_empty():
			continue
		var collider := contacts[index].get("collider") as Node
		if collider == null:
			continue
		for prefix in prefixes:
			if String(collider.name).begins_with(prefix):
				return true
	return false


func _check_upper_paired_course_laps() -> void:
	var face: Dictionary = _faces()[0]
	for direction in [-1, 1]:
		var label := "Left" if direction < 0 else "Right"
		if not await _reach_mid_hold(face):
			_check(false, "%s upper-lap setup reaches a natural south-face hold" % label)
			continue
		var mode = _runner._wall_climb
		var route_normals: Array[Vector3] = [mode.frame.z]
		var start_hand_y := mode._hand_center().y
		var handoffs := 0
		var no_jump := true
		var movement_consistent := true
		var delivered_input := false
		var previous_phase: int = mode.phase
		var action: StringName = &"move_right" if direction > 0 else &"move_left"
		Input.action_press(action)
		for _tick in ROUTE_FRAME_LIMIT:
			await _frames(1)
			var move: Vector2 = _runner.chibi_input.move_vec
			delivered_input = delivered_input or move.is_equal_approx(Vector2.RIGHT if direction > 0 else Vector2.LEFT)
			movement_consistent = movement_consistent and move.is_equal_approx(Vector2.RIGHT if direction > 0 else Vector2.LEFT)
			no_jump = no_jump and not _jump_is_active()
			if _runner.current_state != "Climbing" or mode.phase == MOTION.Phase.IDLE:
				break
			if previous_phase == MOTION.Phase.HOLD and mode.phase in [MOTION.Phase.REACH, MOTION.Phase.JUMP, MOTION.Phase.CORNER]:
				handoffs += 1
			if mode.phase == MOTION.Phase.HOLD and route_normals.back().dot(mode.frame.z) < 0.20:
				route_normals.append(mode.frame.z)
			previous_phase = mode.phase
			if route_normals.size() == 5 and mode.phase == MOTION.Phase.HOLD:
				break
		Input.action_release(action)
		_runner.chibi_input.set_touch_move(Vector2.ZERO)
		await _frames(2)
		var returned: bool = route_normals.size() == 5 and route_normals.front().dot(route_normals.back()) > 0.99
		var passed: bool = start_hand_y >= 4.50 and start_hand_y <= 4.90 and delivered_input \
			and movement_consistent and no_jump and returned and handoffs >= 4 \
			and _runner.current_state == "Climbing" and mode.phase == MOTION.Phase.HOLD
		_check(passed, "%s alone completes the upper paired-course lap from a natural %.2f m grip across all four faces (%d handoffs)" % [label, start_hand_y, handoffs])
		if not passed:
			print("GAP-DEBUG upper-lap dir=%s start_hand_y=%.3f turns=%d handoffs=%d input=%s no_jump=%s state=%s phase=%s position=%s hand=%s holds=%s" % [
			label, start_hand_y, route_normals.size() - 1, handoffs, str(delivered_input), str(no_jump),
			_runner.current_state, str(mode.phase), str(_runner.global_position), _current_hand_text(), str(_contact_names(mode.contacts)),
		])


func _mount_at_height(face: Dictionary, runner_y: float, lane_offset: float) -> bool:
	_release_actions()
	_runner.chibi_input.clear_touch_input()
	var frame := Basis(Vector3.UP.cross(face["normal"]).normalized(), Vector3.UP, face["normal"]).orthonormalized()
	var spawn: Vector3 = face["normal"] * 3.06 + frame.x * lane_offset + Vector3.UP * runner_y
	_runner.reset_for_respawn(spawn)
	_runner.rotation.y = face["yaw"]
	_runner.camera_ctrl.yaw = face["yaw"]
	_runner.velocity = Vector3.ZERO
	await _frames(5)
	var mounted := _runner._try_mount_wall(face["approach"], true)
	await _frames(18)
	return mounted and _runner.current_state == "Climbing" and _runner._wall_climb.phase == MOTION.Phase.HOLD


func _record_rows(rows: Dictionary, contacts: Array[Dictionary]) -> void:
	for contact in contacts:
		if contact.is_empty():
			continue
		var collider := contact.get("collider") as Node
		if collider == null:
			continue
		var parts := String(collider.name).split("_")
		if parts.size() >= 2 and parts[0] in ["CornerHold", "CornerApproach", "LedgeHold", "WindowSill"]:
			rows[int(parts[1])] = true


func _planned_hand_y(mode) -> float:
	if mode._lead >= 0 and mode._lead < mode._planned.size() and not mode._planned[mode._lead].is_empty():
		return (mode._planned[mode._lead]["point"] as Vector3).y
	return mode._hand_center().y


func _current_hand_text() -> String:
	if _runner == null or _runner._wall_climb.phase == MOTION.Phase.IDLE:
		return "none"
	return str(_runner._wall_climb._hand_center())


func _jump_is_active() -> bool:
	return Input.is_action_pressed(&"jump") or _runner.chibi_input.jump_held \
		or _runner.chibi_input.jump_just_pressed


func _faces() -> Array[Dictionary]:
	return [
		{"label": "south", "spawn": Vector3(0.0, 0.035, -3.06), "normal": Vector3.FORWARD, "approach": Vector3.BACK, "yaw": PI},
		{"label": "north", "spawn": Vector3(0.0, 0.035, 3.06), "normal": Vector3.BACK, "approach": Vector3.FORWARD, "yaw": 0.0},
		{"label": "east", "spawn": Vector3(3.06, 0.035, 0.0), "normal": Vector3.RIGHT, "approach": Vector3.LEFT, "yaw": PI * 0.5},
		{"label": "west", "spawn": Vector3(-3.06, 0.035, 0.0), "normal": Vector3.LEFT, "approach": Vector3.RIGHT, "yaw": -PI * 0.5},
	]


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


func _release_actions() -> void:
	for action in [&"move_left", &"move_right", &"move_forward", &"move_back", &"jump"]:
		Input.action_release(action)
	if _runner != null and _runner.chibi_input != null:
		_runner.chibi_input.set_touch_move(Vector2.ZERO)


func _frames(count: int) -> void:
	for _tick in count:
		await physics_frame
		await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		_passes += 1
		print("PASS: %s" % message)
	else:
		_failures += 1
		push_error("FAIL: %s" % message)
