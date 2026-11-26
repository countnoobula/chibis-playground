extends SceneTree

const GYM_SCENE := "res://scenes/gym/rooftop_parkour_gym.tscn"

var _gym: RooftopGymController
var _runner: ParkourController
var _launch: Marker3D
var _water: WaterBody3D
var _meter: Node
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_gym = (load(GYM_SCENE) as PackedScene).instantiate() as RooftopGymController
	root.add_child(_gym)
	_runner = _gym.get_node("ChibiRunner") as ParkourController
	_launch = _gym.get_node_or_null("ClimbTower/LaunchMarker") as Marker3D
	_water = _gym.get_node_or_null("TowerDropCourse/DropWater") as WaterBody3D
	_meter = _gym.get_node_or_null("TowerFallMeter")
	if _launch == null or _water == null or _meter == null:
		printerr("Tower launch, drop water, or fall meter missing")
		quit(1)
		return
	await _ticks(4)
	_check(absf(_launch.global_position.y - _water.get_surface_height() - 6.55) < 0.08, "Deck-to-waterline drop is 6.55 m")
	_check(absf(_water.max_depth - 3.60) < 0.01, "Drop well is 3.60 m deep")
	await _jump_into_well(0.0)
	await _jump_into_well(1.0)
	_gym.teleport_to_zone(4)
	await _ticks(4)
	_check((_meter.get("last_measurement") as Dictionary).is_empty(), "Gym respawn clears the readout")
	await _missed_jump()
	await _climb_out_of_well()
	_gym.queue_free()
	await process_frame
	await process_frame
	print("Tower drop failures: ", _failures)
	quit(0 if _failures == 0 else 1)


func _jump_into_well(flow: float) -> void:
	await _spawn_at(_launch.global_position + Vector3(0.0, 0.08, 1.3))
	_runner.flow_level = flow
	_runner.chibi_input.set_touch_move(Vector2.UP)
	for _i in range(36):
		await _ticks(1)
		if _runner.global_position.z <= _launch.global_position.z + 0.16:
			break
	var apex := _runner.global_position.y
	_runner.chibi_input.set_touch_jump(true)
	await _ticks(1)
	_runner.chibi_input.set_touch_jump(false)
	var wet := false
	var lowest := INF
	for _i in range(160):
		await _ticks(1)
		var feet := _runner.global_position
		apex = maxf(apex, feet.y)
		if _water.contains_horizontal(feet) and feet.y <= _water.get_surface_height():
			wet = true
			lowest = minf(lowest, feet.y)
			_runner.chibi_input.set_touch_move(Vector2.ZERO)
		if not (_meter.get("last_measurement") as Dictionary).is_empty():
			break
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	await _ticks(8)
	var measured: Dictionary = _meter.get("last_measurement")
	_check(wet and _runner.get_active_water() == _water and _runner.current_state == "PoolSwim",
		"Tower jump enters the drop well at initial Flow %.1f (%s)" % [flow, _runner.global_position])
	if measured.is_empty():
		_check(false, "Tower jump publishes a fall measurement at Flow %.1f" % flow)
		return
	var air: float = measured["air_fall_m"]
	var depth: float = measured["entry_depth_m"]
	var total: float = measured["total_fall_m"]
	_check(absf(air - (apex - _water.get_surface_height())) <= 0.03 and air > 6.8,
		"Air fall matches the sampled apex above the water (%.2f m)" % air)
	_check(absf(depth - (_water.get_surface_height() - lowest)) <= 0.04 and is_equal_approx(total, air + depth),
		"Entry depth and total match the recorded fall (%.2f m, %.2f m)" % [depth, total])
	_runner.chibi_input.set_touch_slide(true)
	await _ticks(30)
	_runner.chibi_input.set_touch_slide(false)
	_check(is_equal_approx((_meter.get("last_measurement") as Dictionary).get("entry_depth_m", -1.0), depth),
		"Diving after the plunge leaves the result fixed")


func _missed_jump() -> void:
	await _spawn_at(_launch.global_position + Vector3(0.0, 0.08, 0.25))
	_runner.chibi_input.set_touch_jump(true)
	await _ticks(1)
	_runner.chibi_input.set_touch_jump(false)
	await _ticks(75)
	_check(_runner.is_on_floor() and _runner.global_position.y > 7.9 and (_meter.get("last_measurement") as Dictionary).is_empty(),
		"A jump that lands back on the tower leaves no drop result")


func _climb_out_of_well() -> void:
	await _spawn_at(Vector3(38.5, 0.42, -35.10))
	_runner.camera_ctrl.yaw = PI
	_runner.rotation.y = PI
	_runner.chibi_input.set_touch_move(Vector2.UP)
	_runner.chibi_input.set_touch_jump(true)
	var mantled := false
	for _i in range(100):
		await _ticks(1)
		if _runner.current_state == "MantleUp":
			mantled = true
			_runner.chibi_input.set_touch_move(Vector2.ZERO)
			_runner.chibi_input.set_touch_jump(false)
		elif mantled and _runner.current_state == "Locomotion":
			break
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	_runner.chibi_input.set_touch_jump(false)
	_check(mantled and _runner.current_state == "Locomotion" and _runner.global_position.y > _water.get_surface_height(),
		"Held Rise climbs onto the drop well's peach rim (%s)" % _runner.global_position)


func _spawn_at(point: Vector3) -> void:
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	_runner.chibi_input.set_touch_jump(false)
	_runner.chibi_input.set_touch_slide(false)
	await physics_frame
	_runner.reset_for_respawn(point)
	_runner.camera_ctrl.yaw = 0.0
	_runner.camera_ctrl.reset_after_teleport()
	await _ticks(16)


func _ticks(count: int) -> void:
	for _i in count:
		await physics_frame
		await process_frame


func _check(passed: bool, message: String) -> void:
	if passed:
		print("[PASS] ", message)
	else:
		_failures += 1
		printerr("[FAIL] ", message)
