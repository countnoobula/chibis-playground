extends RefCounted

const Motion := preload("res://scripts/climbing/wall_climb_motion.gd")

var _tree: SceneTree
var _runner: ParkourController


func run(tree: SceneTree, runner: ParkourController, wall: Node3D, check: Callable) -> void:
	_tree = tree
	_runner = runner
	_runner.chibi_input.clear_touch_input()
	_runner.reset_for_respawn(wall.to_global(Vector3(-0.74, 0.035, 0.72)))
	_runner.rotation.y = 0.0
	_runner.camera_ctrl.yaw = 0.0
	await _frames(10)

	_key(KEY_E, true)
	await _frames(2)
	_key(KEY_E, false)
	check.call(not _runner.is_wall_climbing(), "The pickup key leaves Chibi on the ground beside a wall")
	await _approach_wall()
	var mode := _runner._wall_climb
	var mounted := mode.phase == Motion.Phase.HOLD and _runner.get_collision_mask_value(1)
	check.call(mounted, "Moving into the collision-based wall mounts with world collision enabled")
	if not mounted:
		return

	var first_stance := _runner.global_position
	_runner.chibi_input.set_touch_move(Vector2.DOWN)
	_runner.chibi_input.set_touch_jump(true)
	await _frames(1)
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	_runner.chibi_input.set_touch_jump(false)
	check.call(mode.phase == Motion.Phase.HOLD and _runner.global_position.is_equal_approx(first_stance),
		"An unreachable direction keeps Chibi on the starting grip")

	var skeleton := _runner.pose_mod.get_skeleton()
	var support_measurement := [0, 0.0]
	var measure_support := func() -> void:
		if mode.phase != Motion.Phase.REACH:
			return
		var progress: float = mode._elapsed / mode._duration
		var side: int = 1 - mode._lead
		if progress < 0.12 or progress > 0.47 or mode.contacts[side].is_empty():
			return
		var bone := skeleton.find_bone("hand_l" if side == 0 else "hand_r")
		var position := skeleton.to_global(skeleton.get_bone_global_pose(bone).origin)
		var expected: Vector3 = mode._tip(mode.contacts[side], side)
		support_measurement[0] += 1
		support_measurement[1] = maxf(support_measurement[1], position.distance_to(expected))
	skeleton.skeleton_updated.connect(measure_support)
	var reached := await _reach(Vector2(0.62, -1.0), 1.19, 85)
	skeleton.skeleton_updated.disconnect(measure_support)
	check.call(reached, "Directional reaches climb the starter lips")
	check.call(support_measurement[0] >= 8 and support_measurement[1] < 0.05,
		"The supporting wrist stays planted while the other hand reaches (peak error %.3f m)" % support_measurement[1])
	if not reached:
		return

	var start := _runner.global_position
	var direction := Vector2(0.66, -1.0)
	var barrier := _make_box(wall.get_parent(), start + Vector3(0.57, 0.86, 0.18), Vector3(0.49, 0.55, 0.34))
	await _frames(2)
	_runner.chibi_input.set_touch_move(direction)
	_runner.chibi_input.set_touch_jump(true)
	await _frames(1)
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	_runner.chibi_input.set_touch_jump(false)
	check.call(mode.phase == Motion.Phase.HOLD and _runner.global_position.distance_to(start) < 0.01,
		"Leap preflight leaves Chibi planted when World geometry blocks the arc")
	barrier.queue_free()
	await _frames(3)

	var pad_jump := InputEventJoypadButton.new()
	pad_jump.button_index = JOY_BUTTON_A
	pad_jump.pressed = true
	_runner.chibi_input.set_touch_move(direction)
	Input.parse_input_event(pad_jump)
	await _frames(2)
	var leapt := mode.phase == Motion.Phase.JUMP
	var pad_release := InputEventJoypadButton.new()
	pad_release.button_index = JOY_BUTTON_A
	Input.parse_input_event(pad_release)
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	await _frames(35)
	var caught: bool = mode.phase == Motion.Phase.HOLD and mode._hand_center().y > 1.85
	check.call(leapt and caught and _runner.global_position.x - start.x > 0.23,
		"Gamepad jump crosses the diagonal gap and catches the new masonry lip")
	if not caught:
		return

	var rose := await _reach(Vector2(0.52, -1.0), 2.10, 54)
	var upper := await _reach(Vector2(-0.56, -1.0), 2.4, 58)
	_runner.chibi_input.set_touch_jump(true)
	await _frames(2)
	var mantling := _runner.current_state == "MantleUp"
	_runner.chibi_input.set_touch_jump(false)
	await _frames(62)
	check.call(rose and upper and mantling and _runner.current_state == "Locomotion"
		and _runner.global_position.y >= 2.74 and _runner.get_collision_mask_value(1),
		"Touch jump mantles onto the rooftop deck and restores locomotion")

	_runner.reset_for_respawn(wall.to_global(Vector3(-0.74, 0.03, 0.72)))
	_runner.rotation.y = 0.0
	await _frames(10)
	await _approach_wall()
	var grabbed := mode.phase == Motion.Phase.HOLD
	_runner.chibi_input.set_touch_slide(true)
	await _frames(2)
	_runner.chibi_input.set_touch_slide(false)
	check.call(grabbed and _runner.current_state == "Locomotion" and not _runner.is_wall_climbing(),
		"Touch Drop releases wall contacts independently of Leap")
	await _frames(27)
	_runner.reset_for_respawn(wall.to_global(Vector3(-0.74, 0.03, 0.72)))
	_runner.rotation.y = 0.0
	await _frames(10)
	await _approach_wall()
	grabbed = _runner.is_wall_climbing()
	_runner.reset_for_respawn(Vector3(10.0, 0.03, 9.0))
	check.call(grabbed and _runner.current_state == "Locomotion" and mode.phase == Motion.Phase.IDLE
		and _runner.pose_mod._wall_pose_blend < 0.001,
		"Respawn clears a wall climb in progress")
	_runner.chibi_input.clear_touch_input()
	await _check_automatic_climb(wall, check)


func _approach_wall() -> void:
	_runner.chibi_input.set_touch_move(Vector2.UP)
	for _i in 35:
		await _frames(1)
		if _runner.is_wall_climbing():
			break
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	await _frames(17)


func _check_automatic_climb(wall: Node3D, check: Callable) -> void:
	var mode := _runner._wall_climb
	var gym := wall.get_parent().get_parent() as RooftopGymController
	gym.teleport_to_zone(2)
	_runner.rotation.y = 0.0
	_runner.camera_ctrl.yaw = 0.0
	await _frames(10)
	_key(KEY_W, true)
	for _i in 100:
		await _frames(1)
		if _runner.is_wall_climbing():
			break
	_key(KEY_W, false)
	await _frames(17)
	var engaged := mode.phase == Motion.Phase.HOLD
	check.call(engaged and _runner.get_collision_mask_value(1),
		"Running straight into the roof wall attaches with movement alone")
	if engaged:
		var original_x := _runner.global_position.x
		var grip_height := mode._hand_center().y
		var went_right := await _shimmy(1.0)
		var went_left := await _shimmy(-1.0)
		check.call(went_right and went_left and absf(_runner.global_position.x - original_x) < 0.12
			and absf(mode._hand_center().y - grip_height) < 0.05,
			"Left and right input move Chibi along the same bar")

		var gap_leap := false
		var landed := false
		_runner.chibi_input.set_touch_move(Vector2.UP)
		for _i in 190:
			await _frames(1)
			if mode.phase == Motion.Phase.JUMP and absf(mode._hand_center().y - 1.30) < 0.05:
				gap_leap = true
			if mode.phase == Motion.Phase.HOLD and mode._hand_center().y >= 1.85:
				landed = true
				break
		_runner.chibi_input.set_touch_move(Vector2.ZERO)
		check.call(gap_leap and landed, "Holding Up automatically leaps across the halfway gap")

	_runner.reset_for_respawn(wall.to_global(Vector3(-0.76, 0.04, 1.20)))
	_runner.rotation.y = 0.0
	await _frames(10)
	_runner.chibi_input.set_touch_move(Vector2.UP)
	await _frames(10)
	_runner.chibi_input.set_touch_jump(true)
	await _frames(6)
	_runner.chibi_input.set_touch_jump(false)
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	await _frames(38)
	check.call(mode.phase == Motion.Phase.HOLD,
		"Jumping toward the wall still catches after the stick is released")
	await _check_immediate_released_jump(wall, check)
	await _check_steering_away_overrides_wall_approach(wall, check)
	_runner.reset_for_respawn(Vector3(10.0, 0.03, 9.0))


func _check_immediate_released_jump(wall: Node3D, check: Callable) -> void:
	var mode := _runner._wall_climb
	_runner.chibi_input.clear_touch_input()
	_runner.reset_for_respawn(wall.to_global(Vector3(-0.76, 0.04, 1.20)))
	_runner.rotation.y = 0.0
	_runner.camera_ctrl.yaw = 0.0
	await _frames(10)
	_runner.chibi_input.set_touch_move(Vector2.UP)
	await _frames(10)
	_runner.chibi_input.set_touch_jump(true)
	await _frames(1)
	_runner.chibi_input.set_touch_jump(false)
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	var released_before_catch := (
		mode.phase == Motion.Phase.IDLE and _runner.current_state == "Locomotion"
		and _runner.velocity.y > 0.0 and wall.to_local(_runner.global_position).z > 0.72
	)
	var caught := false
	for _i in 44:
		await _frames(1)
		if mode.phase == Motion.Phase.HOLD:
			caught = true
			break
	check.call(released_before_catch and caught,
		"Jump catches the Zone 3 wall after the stick is released on its first physics tick")


func _check_steering_away_overrides_wall_approach(wall: Node3D, check: Callable) -> void:
	var mode := _runner._wall_climb
	_runner.chibi_input.clear_touch_input()
	_runner.reset_for_respawn(wall.to_global(Vector3(-0.76, 0.04, 1.20)))
	_runner.rotation.y = 0.0
	_runner.camera_ctrl.yaw = 0.0
	await _frames(10)
	_runner.chibi_input.set_touch_move(Vector2.UP)
	await _frames(10)
	_runner.chibi_input.set_touch_jump(true)
	await _frames(1)
	_runner.chibi_input.set_touch_jump(false)
	_runner.chibi_input.set_touch_move(Vector2.DOWN)
	await _frames(1)
	var steering_start_z := wall.to_local(_runner.global_position).z
	var still_out_of_reach := steering_start_z > 0.72
	var stayed_free := mode.phase == Motion.Phase.IDLE
	for _i in 44:
		await _frames(1)
		if mode.phase != Motion.Phase.IDLE:
			stayed_free = false
			break
	var moved_away := wall.to_local(_runner.global_position).z > steering_start_z + 0.15
	check.call(still_out_of_reach and stayed_free and moved_away and _runner.current_state == "Locomotion",
		"Steering away while still out of reach overrides the saved wall approach")
	_runner.chibi_input.clear_touch_input()


func _shimmy(direction: float) -> bool:
	var start_x := _runner.global_position.x
	_runner.chibi_input.set_touch_move(Vector2(direction, 0.0))
	for _i in 55:
		await _frames(1)
		if _runner._wall_climb.phase == Motion.Phase.HOLD and (_runner.global_position.x - start_x) * direction > 0.12:
			_runner.chibi_input.set_touch_move(Vector2.ZERO)
			return true
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	return false


func _reach(direction: Vector2, height: float, limit: int) -> bool:
	var mode := _runner._wall_climb
	_runner.chibi_input.set_touch_move(direction)
	for _i in limit:
		await _frames(1)
		if mode.phase == Motion.Phase.HOLD and mode._hand_center().y >= height:
			_runner.chibi_input.set_touch_move(Vector2.ZERO)
			return true
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	return false


func _frames(count: int) -> void:
	for _i in count:
		await _tree.physics_frame
		await _tree.process_frame


func _key(code: Key, pressed: bool) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = code
	key.pressed = pressed
	Input.parse_input_event(key)


func _make_box(parent: Node3D, center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	parent.add_child(body)
	body.global_position = center
	return body
