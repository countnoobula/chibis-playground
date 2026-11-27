extends RefCounted

## Input-driven regression coverage for the generated rooftop aerial stations.

const OPEN_DECK := Vector3(4.0, 0.08, 21.0)

var _tree: SceneTree
var _gym: Node3D
var _chibi: ParkourController
var _check: Callable


func run(tree: SceneTree, gym: Node3D, chibi: ParkourController, check: Callable) -> void:
	_tree = tree
	_gym = gym
	_chibi = chibi
	_check = check
	_chibi.chibi_input.clear_touch_input()
	_chibi.rotation.y = 0.0
	_chibi.camera_ctrl.yaw = 0.0

	await _test_trampoline_landings_and_rejections()
	await _test_beam_approaches_and_step_off()
	await _test_first_pole_cap_and_hop()
	await _test_sloth_line_approach_and_block()
	await _test_zip_line_approach_and_side_rejection()
	await _test_swing_approach_and_side_rejection()

	_chibi.chibi_input.clear_touch_input()
	_chibi.reset_for_respawn(OPEN_DECK)
	await _ticks(3)
	_check = Callable()
	_chibi = null
	_gym = null
	_tree = null


func _test_trampoline_landings_and_rejections() -> void:
	var trampoline := _gym.get_node("Zone4_AerialCircuit/Trampoline_01") as ParkourTrampoline
	_reset(trampoline.global_position + Vector3.UP * 2.35)
	for _frame in 70:
		await _ticks(1)
		if _chibi.trampoline_cooldown > 0.20:
			break
	var normal_launch_height := absf(_chibi.global_position.y - ParkourTrampoline.PAD_TOP) <= 0.08
	_check.call(_chibi.trampoline_cooldown > 0.20 and not _chibi.super_bounce_active
		and is_equal_approx(_chibi.last_trampoline_velocity, trampoline.base_bounce_velocity)
		and normal_launch_height,
			"A falling touch-controlled runner gets a normal trampoline bounce")

	_reset(trampoline.global_position + Vector3.UP * 2.35)
	_chibi.chibi_input.set_touch_jump(true)
	for _frame in 75:
		await _ticks(1)
		if _chibi.trampoline_cooldown > 0.20:
			break
	var super_bounce := _chibi.trampoline_cooldown > 0.20 and _chibi.super_bounce_active
	var super_launch_height := absf(_chibi.global_position.y - ParkourTrampoline.PAD_TOP) <= 0.08
	_chibi.chibi_input.set_touch_jump(false)
	_check.call(super_bounce and is_equal_approx(_chibi.velocity.y,
		trampoline.base_bounce_velocity * trampoline.super_bounce_multiplier) and super_launch_height,
		"Holding touch Jump through contact triggers the trampoline super bounce")

	_reset(trampoline.global_position + Vector3.UP * ParkourTrampoline.PAD_TOP)
	_chibi.velocity = Vector3.UP * 2.0
	var rising_rejected := not trampoline.land_on_top(_chibi, _chibi.velocity.y, false)
	var rising_unchanged := _chibi.trampoline_cooldown <= 0.001 and not _chibi.super_bounce_active
	_reset(trampoline.global_position + Vector3(ParkourTrampoline.PAD_RADIUS + _chibi.config.capsule_radius + 0.20,
		ParkourTrampoline.PAD_TOP, 0.0))
	var flyby_rejected := not trampoline.land_on_top(_chibi, -6.0, false)
	_check.call(rising_rejected and rising_unchanged and flyby_rejected,
		"Rising contacts and high-speed edge flybys do not activate the trampoline")


func _test_beam_approaches_and_step_off() -> void:
	var beam := _gym.get_node("Zone4_AerialCircuit/BalanceBeam_01") as ParkourBalanceBeam
	var start_pad := _gym.get_node("Zone4_AerialCircuit/BeamStartPad") as StaticBody3D
	var end_pad := _gym.get_node("Zone4_AerialCircuit/BeamEndPad") as StaticBody3D

	_reset(start_pad.global_position + Vector3(0.0, 0.80, -1.08))
	_chibi.chibi_input.set_touch_move(Vector2.UP)
	var mounted_from_start := await _move_until_state("BalanceBeam", 75)
	_chibi.chibi_input.set_touch_move(Vector2.ZERO)
	if mounted_from_start:
		_chibi.chibi_input.set_touch_move(Vector2.UP)
		for _frame in 340:
			await _ticks(1)
			if _chibi.current_state == "Locomotion" and _chibi.global_position.z < beam.global_position.z - beam.beam_length + 0.18:
				break
		var stepped_off_end := _chibi.current_state == "Locomotion" \
			and _chibi.global_position.z < beam.global_position.z - beam.beam_length + 0.35
		_chibi.chibi_input.set_touch_move(Vector2.ZERO)
		_check.call(stepped_off_end,
			"Walking from the start pad crosses the beam and steps onto the end pad")
	else:
		_check.call(false, "Walking from the start pad mounts the balance beam")

	_reset(end_pad.global_position + Vector3(0.0, 0.80, 1.08))
	_chibi.chibi_input.set_touch_move(Vector2.DOWN)
	var mounted_from_end := await _move_until_state("BalanceBeam", 75)
	_chibi.chibi_input.set_touch_move(Vector2.ZERO)
	if mounted_from_end:
		_chibi.chibi_input.set_touch_move(Vector2.DOWN)
		for _frame in 340:
			await _ticks(1)
			if _chibi.current_state == "Locomotion" and _chibi.global_position.z > beam.global_position.z + 0.18:
				break
		var stepped_off_start := _chibi.current_state == "Locomotion" \
			and _chibi.global_position.z > beam.global_position.z - 0.35
		_chibi.chibi_input.set_touch_move(Vector2.ZERO)
		_check.call(stepped_off_start,
			"Walking from the end pad crosses the beam and steps onto the start pad")
	else:
		_check.call(false, "Walking from the end pad mounts the balance beam")

	_reset(start_pad.global_position + Vector3(0.88, 0.80, -1.08))
	_chibi.chibi_input.set_touch_move(Vector2.UP)
	await _ticks(90)
	var side_flyby_rejected := _chibi.current_state != "BalanceBeam"
	_chibi.chibi_input.set_touch_move(Vector2.ZERO)
	_check.call(side_flyby_rejected,
		"A parallel approach outside the beam rails cannot mount from a flyby")


func _test_first_pole_cap_and_hop() -> void:
	var pole_1 := _gym.get_node("Zone4_AerialCircuit/ParkourPole_01") as ParkourPole
	var pole_2 := _gym.get_node("Zone4_AerialCircuit/ParkourPole_02") as ParkourPole
	_reset(Vector3(0.0, 0.64, -22.40))
	await _ticks(10)
	_chibi.chibi_input.set_touch_move(Vector2.UP)
	for _frame in 35:
		if _chibi.global_position.z <= -22.75:
			break
		await _ticks(1)
	var reached_takeoff := _chibi.global_position.z <= -22.75 and _chibi.is_on_floor()
	_chibi.chibi_input.set_touch_jump(true)
	await _ticks(1)
	_chibi.chibi_input.set_touch_jump(false)
	var landed_on_first_cap := await _move_until_state("PolePerch", 55)
	_check.call(reached_takeoff and landed_on_first_cap
		and _chibi.global_position.distance_to(pole_1.get_top_world_position()) < 0.12,
		"A run-up jump from the 0.60 m starter step lands on the first pole cap")
	if landed_on_first_cap:
		_chibi.chibi_input.set_touch_jump(true)
		await _ticks(1)
		_chibi.chibi_input.set_touch_jump(false)
		var hopped_to_second := await _move_until_position(pole_2.get_top_world_position(), 50)
		_check.call(hopped_to_second and _chibi.current_state == "PolePerch",
			"Touch Jump hops from the first pole to the next pole cap")
	else:
		_check.call(false, "Touch Jump hops from the first pole to the next pole cap")


func _test_sloth_line_approach_and_block() -> void:
	var line := _gym.get_node("Zone4_AerialCircuit/SlothLine_01") as ParkourLine
	var rope_point := line.get_rope_world_pos_at_t(0.5)
	var target_feet := rope_point - Vector3.UP * 0.616
	_reset(Vector3(12.0, 2.20, -22.85))
	await _ticks(10)
	_chibi.chibi_input.set_touch_move(Vector2.UP)
	for _frame in 100:
		if _chibi.global_position.z <= -25.00:
			break
		await _ticks(1)
	_chibi.chibi_input.set_touch_jump(true)
	await _ticks(1)
	_chibi.chibi_input.set_touch_jump(false)
	var mounted := await _move_until_state("RopeLine", 40)
	_check.call(mounted and _chibi._active_line == line and line._has_rider,
		"A run-up jump from the sloth tower catches the crawl line")

	# Keep the area capture active but block the short body sweep from an offset approach.
	_reset(target_feet + Vector3(0.55, 0.0, 0.0))
	var blocker := _test_collision_box(_gym, target_feet + Vector3(0.25, 0.55, 0.0), Vector3(0.10, 1.05, 0.55))
	_chibi.chibi_input.set_touch_move(Vector2.LEFT * 0.2)
	await _ticks(8)
	var blocked := _chibi.current_state == "Locomotion" and _chibi._active_line == null
	blocker.queue_free()
	_chibi.chibi_input.set_touch_move(Vector2.ZERO)
	_check.call(blocked, "A side approach blocked by a collider cannot snap onto the sloth line")


func _test_zip_line_approach_and_side_rejection() -> void:
	var line := _gym.get_node("Zone4_AerialCircuit/ZipLine_01") as ParkourLine
	var t := 0.45
	var rope_point := line.get_rope_world_pos_at_t(t)
	var forward := Vector3(line.get_line_direction().x, 0.0, line.get_line_direction().z).normalized()
	var target_feet := rope_point - forward * 0.29 - Vector3.UP * 1.325
	_reset(Vector3(16.5, 2.90, -22.65))
	await _ticks(10)
	_chibi.chibi_input.set_touch_move(Vector2.UP)
	for _frame in 100:
		if _chibi.global_position.z <= -25.20:
			break
		await _ticks(1)
	_chibi.chibi_input.set_touch_jump(true)
	await _ticks(1)
	_chibi.chibi_input.set_touch_jump(false)
	var mounted := await _move_until_state("ZipLine", 40)
	_check.call(mounted and _chibi._active_line == line and line._has_rider,
		"A run-up jump from the zip tower connects to the handle and pulley")
	if mounted:
		var zip_start_distance := _chibi._line_distance
		await _ticks(12)
		_check.call(_chibi.current_state == "ZipLine" and _chibi._active_line == line
			and line._has_rider and _chibi._line_distance > zip_start_distance + 0.50,
			"A mounted zip rider travels down the line during the first 12 physics ticks")
	else:
		_check.call(false, "A mounted zip rider travels down the line during the first 12 physics ticks")

	_reset(target_feet + Vector3.RIGHT * 1.40)
	_chibi.velocity = Vector3.DOWN * 0.3
	_chibi.chibi_input.set_touch_move(Vector2.RIGHT * 0.10)
	await _ticks(12)
	var side_rejected := _chibi.current_state != "ZipLine" and _chibi._active_line == null
	_chibi.chibi_input.set_touch_move(Vector2.ZERO)
	_check.call(side_rejected, "A side flyby outside the zip handle reach cannot attach")


func _test_swing_approach_and_side_rejection() -> void:
	var swing := _gym.get_node("Zone4_AerialCircuit/RopeSwing_01") as ParkourRopeSwing
	var connector := swing.global_position + Vector3.DOWN * swing.rope_length
	_reset(Vector3(-11.5, 2.24, -23.25))
	_chibi.chibi_input.set_touch_move(Vector2.UP)
	for _frame in 100:
		if _chibi.global_position.z <= -25.97:
			break
		await _ticks(1)
	var reached_jump_point := _chibi.global_position.z <= -25.97
	_chibi.chibi_input.set_touch_jump(true)
	await _ticks(1)
	_chibi.chibi_input.set_touch_jump(false)
	var mounted := await _move_until_state("RopeSwing", 45)
	_check.call(reached_jump_point and mounted and _chibi._active_swing == swing and swing.is_ridden,
		"A jump from the swing pad catches the low rope connector at base Flow")
	if mounted:
		await _test_swing_grip_contact(swing)
		var settled_on_swing := _chibi.current_state == "RopeSwing" and swing.is_ridden
		_chibi.chibi_input.set_touch_jump(true)
		await _ticks(1)
		_chibi.chibi_input.set_touch_jump(false)
		await _ticks(1)
		_check.call(settled_on_swing and _chibi.current_state == "Locomotion" and _chibi._active_swing == null
			and not swing.is_ridden,
			"Touch Jump releases the settled swing and clears its rider state")
	else:
		_check.call(false, "The swing keeps both hands on its grips and the head clear of the rope")
		_check.call(false, "Touch Jump releases the settled swing and clears its rider state")
	_chibi.chibi_input.set_touch_move(Vector2.ZERO)

	_reset(connector + Vector3.RIGHT * 1.40)
	_chibi.velocity = Vector3.DOWN * 0.3
	_chibi.chibi_input.set_touch_move(Vector2.RIGHT * 0.10)
	await _ticks(12)
	var side_rejected := _chibi.current_state != "RopeSwing" and _chibi._active_swing == null
	_chibi.chibi_input.set_touch_move(Vector2.ZERO)
	_check.call(side_rejected, "A side flyby beyond connector reach cannot attach to the swing")


func _test_swing_grip_contact(swing: ParkourRopeSwing) -> void:
	var skeleton := _chibi.pose_mod.get_skeleton()
	var hands := [skeleton.find_bone(&"hand_l"), skeleton.find_bone(&"hand_r")]
	var head_bone := skeleton.find_bone(&"head")
	var rope_pivot := swing.get_node("RopePivot") as Node3D
	var samples := [0, 0.0, INF]
	var sample_contact := func():
		if _chibi.get_rope_swing_grip_weight() < 0.999:
			return
		var world := skeleton.global_transform
		for side in 2:
			var wrist := (world * skeleton.get_bone_global_pose(hands[side])).origin
			samples[1] = maxf(samples[1], wrist.distance_to(swing.get_hand_grip_world(side)))
		var head := (world * skeleton.get_bone_global_pose(head_bone)).origin
		var rope_end := rope_pivot.get_global_transform_interpolated() * (Vector3.DOWN * swing.rope_length)
		var rope_point := Geometry3D.get_closest_point_to_segment(head, rope_end, swing.global_position)
		samples[2] = minf(samples[2], head.distance_to(rope_point))
		samples[0] += 1
	skeleton.skeleton_updated.connect(sample_contact)
	await _ticks(22)
	skeleton.skeleton_updated.disconnect(sample_contact)
	_check.call(samples[0] > 0 and samples[1] < 0.035 and samples[2] > 0.23,
		"The swing keeps both hands on its grips and the head clear of the rope (hand %.3f m, head %.3f m)" % [samples[1], samples[2]])


func _move_until_state(state: String, frame_limit: int) -> bool:
	for _frame in frame_limit:
		if _chibi.current_state == state:
			return true
		await _ticks(1)
	return _chibi.current_state == state


func _move_until_position(target: Vector3, frame_limit: int) -> bool:
	for _frame in frame_limit:
		if _chibi.current_state == "PolePerch" and _chibi.global_position.distance_to(target) < 0.12:
			return true
		await _ticks(1)
	return _chibi.current_state == "PolePerch" and _chibi.global_position.distance_to(target) < 0.12


func _reset(position: Vector3) -> void:
	_chibi.chibi_input.clear_touch_input()
	_chibi.reset_for_respawn(position)
	_chibi.rotation.y = 0.0
	_chibi.camera_ctrl.yaw = 0.0


func _ticks(count: int) -> void:
	for _frame in count:
		await _tree.physics_frame


func _test_collision_box(parent: Node3D, center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	body.global_position = center
	return body
