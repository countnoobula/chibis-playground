extends RefCounted

var _max_plant_error := 0.0
var _max_drift := 0.0
var _samples := 0
var _two_foot_samples := 0
var _no_support_samples := 0
var _turn_samples := 0
var _turn_two_foot_samples := 0
var _previous_targets := [Vector3.ZERO, Vector3.ZERO]
var _previous_soles := [Vector3.ZERO, Vector3.ZERO]
var _previous_planted := [false, false]


func run(tree: SceneTree, check: Callable, gym: Node3D, runner: ParkourController, skel: Skeleton3D) -> void:
	var beam := gym.get_node("Zone4_AerialCircuit/BalanceBeam_01") as ParkourBalanceBeam
	runner.chibi_input.set_touch_move(Vector2.ZERO)
	runner.camera_ctrl.yaw = 0.0
	runner.rotation.y = 0.0
	runner.reset_for_respawn(beam.to_global(Vector3(0.0, 0.24, -3.2)))
	await _steps(tree, 18)
	var sample := _sample.bind(runner, beam, skel)
	skel.skeleton_updated.connect(sample)
	await _steps(tree, 18)
	check.call(runner.has_balance_footing() and _samples >= 8 and _two_foot_samples == _samples and _max_plant_error <= 0.02,
		"Both soles meet the rounded balance beam at idle (error %.3f m across %d samples)" % [_max_plant_error, _samples])

	_reset_samples()
	var forward_start := runner.global_position.z
	runner.chibi_input.set_touch_move(Vector2.UP)
	await _steps(tree, 52)
	check.call(runner.global_position.z < forward_start - 0.75 and _samples >= 24
		and _max_plant_error <= 0.02 and _max_drift <= 0.025 and _no_support_samples == 0,
		"Balance walk holds the supporting sole while the other foot swings (error %.3f m, drift %.3f m)" % [_max_plant_error, _max_drift])

	_reset_samples()
	var reverse_start := runner.global_position.z
	runner.chibi_input.set_touch_move(Vector2.DOWN * 0.65)
	await _steps(tree, 110)
	check.call(runner.has_balance_footing() and runner.global_position.z > reverse_start + 0.70
		and absf(angle_difference(runner.rotation.y, PI)) < 0.03 and _turn_samples >= 8
		and _turn_two_foot_samples == _turn_samples and _samples >= 40
		and _no_support_samples == 0 and _max_plant_error <= 0.02 and _max_drift <= 0.025,
		"Balance reversal plants both feet for the pivot and resumes at partial speed (error %.3f m, drift %.3f m)" % [_max_plant_error, _max_drift])

	skel.skeleton_updated.disconnect(sample)
	runner.chibi_input.set_touch_move(Vector2.ZERO)
	runner.request_jump()
	await _steps(tree, 4)
	check.call(not runner.has_balance_footing() and runner.current_state == "Locomotion" and runner.velocity.y > 1.0,
		"Jumping off the balance beam releases the foot placement and restores airborne motion")


func _sample(runner: ParkourController, beam: ParkourBalanceBeam, skel: Skeleton3D) -> void:
	if not runner.has_balance_footing():
		return
	_samples += 1
	var planted_feet := 0
	for side in 2:
		var target := runner.get_balance_foot_target(side).origin
		var point := beam.to_local(target)
		var surface_y := sqrt(maxf(0.0, beam.beam_radius * beam.beam_radius - point.x * point.x))
		var planted := absf(point.y - surface_y) < 0.002
		if planted:
			planted_feet += 1
			var ball := skel.find_bone("ball_l" if side == 0 else "ball_r")
			var sole := skel.get_global_transform_interpolated() * skel.get_bone_global_pose(ball).origin
			sole -= Vector3.UP * 0.022
			_max_plant_error = maxf(_max_plant_error, sole.distance_to(target))
			if _previous_planted[side] and target.distance_to(_previous_targets[side]) < 0.001:
				_max_drift = maxf(_max_drift, sole.distance_to(_previous_soles[side]))
			_previous_soles[side] = sole
		_previous_planted[side] = planted
		_previous_targets[side] = target
	if planted_feet == 2:
		_two_foot_samples += 1
	elif planted_feet == 0:
		_no_support_samples += 1
	var yaw := absf(wrapf(runner.rotation.y, -PI, PI))
	if yaw > 0.2 and yaw < PI - 0.2:
		_turn_samples += 1
		if planted_feet == 2:
			_turn_two_foot_samples += 1


func _reset_samples() -> void:
	_max_plant_error = 0.0
	_max_drift = 0.0
	_samples = 0
	_two_foot_samples = 0
	_no_support_samples = 0
	_turn_samples = 0
	_turn_two_foot_samples = 0
	_previous_planted = [false, false]


func _steps(tree: SceneTree, count: int) -> void:
	for i in count:
		await tree.physics_frame
		await tree.process_frame
