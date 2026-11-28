extends SceneTree

## Run with Godot --headless --path . --script res://tests/test_first_steps_station_starts.gd
## Add -- --mobile-menu to repeat the checkpoint button check with touch controls shown.

const VALLEY := preload("res://levels/first_steps/first_steps_valley.tscn")
const SECTION_CASES := [
	{"key": KEY_1, "action": &"debug_zone_1", "path": "DryCrossing", "name": "Dry Crossing"},
	{"key": KEY_2, "action": &"debug_zone_2", "path": "RootLedges", "name": "Root Ledges"},
	{"key": KEY_3, "action": &"debug_zone_3", "path": "CanopyGap", "name": "Canopy Gap"},
	{"key": KEY_4, "action": &"debug_zone_4", "path": "WindOverlook", "name": "Wind Overlook"},
]

var _passed := 0
var _failed := 0
var _level: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.physics_ticks_per_second = 60
	_level = VALLEY.instantiate() as Node3D
	root.add_child(_level)
	await _ticks(12)
	var level := _level
	var controller := level as FirstStepsValleyController
	var runner := level.get_node_or_null("ChibiRunner") as ParkourController
	var camera := runner.camera_ctrl if runner != null else null
	var input := runner.chibi_input if runner != null else null
	var field := level.get_node_or_null("WindOverlook/WindField") as RunnerWindField3D
	if controller == null or runner == null or camera == null or input == null:
		_check(false, "First Steps Valley exposes the controller, runner, input, and camera")
		await _finish(level)
		return
	if not OS.is_debug_build():
		_check(false, "Numeric station starts require the debug build")
		await _finish(level)
		return
	_check(field != null and runner.wind_field == field,
		"The live valley assigns the authored Wind Overlook provider once for checkpoint state checks")

	for section in SECTION_CASES:
		var path := String(section["path"])
		var action := StringName(section["action"])
		var keycode := int(section["key"])
		var area := level.get_node_or_null(path + "/CheckpointArea") as Area3D
		var developer_start := level.get_node_or_null(path + "/DeveloperStart") as Marker3D
		var spawn := level.get_node_or_null(path + "/CheckpointArea/Spawn") as Marker3D
		if area == null or developer_start == null or spawn == null:
			_check(false, "%s exposes its grouped checkpoint, Spawn, and DeveloperStart" % section["name"])
			continue
		_check(InputMap.has_action(action)
			and StringName(area.get_meta("developer_action", "")) == action
			and String(area.get_meta("section_name", "Dry Crossing")) == String(section["name"]),
			"Key %d is bound to the %s checkpoint contract" % [keycode - KEY_0, section["name"]])

		input.call("clear_touch_input")
		await _tap_key(keycode, 4)
		await _ticks(4)
		var expected_transform := developer_start.global_transform
		var position_error := runner.global_position.distance_to(developer_start.global_position)
		var runner_yaw_error := absf(angle_difference(runner.global_rotation.y, developer_start.global_rotation.y))
		var camera_yaw_error := absf(angle_difference(camera.yaw, developer_start.global_rotation.y))
		var expected_pitch := float(area.get_meta("camera_pitch", -0.56))
		var active_transform: Transform3D = controller.active_checkpoint_transform
		_check(String(controller.active_checkpoint_name) == String(section["name"])
			and active_transform.is_equal_approx(expected_transform)
			and position_error < 0.18
			and runner_yaw_error < 0.035 and camera_yaw_error < 0.035
			and absf(camera.pitch - expected_pitch) < 0.035
			and String(runner.current_state) == "Locomotion" and runner.is_on_floor(),
			"Physical key %d starts %s at its authored marker with grounded locomotion and camera (Δ %.3f m, yaw %.3f/%.3f, pitch %.3f/%.3f)"
			% [keycode - KEY_0, section["name"], position_error, runner_yaw_error,
				camera_yaw_error, camera.pitch, expected_pitch])

		# Move away under the ordinary keyboard mapping, then retry with R through
		# the HUD's unhandled key path. This intentionally exercises the live input
		# path instead of calling retry_section() directly.
		var before_move := runner.global_position
		await _hold_key(KEY_W, 14)
		var moved_distance := Vector2(runner.global_position.x - before_move.x,
			runner.global_position.z - before_move.z).length()
		_check(moved_distance > 0.35 and String(runner.current_state) == "Locomotion",
			"W moves Chibi away from %s before retry (%.2f m)" % [section["name"], moved_distance])
		await _tap_key(KEY_R)
		await _ticks(4)
		var retry_error := runner.global_position.distance_to(spawn.global_position)
		var retry_yaw_error := absf(angle_difference(runner.global_rotation.y, spawn.global_rotation.y))
		var retry_camera_yaw_error := absf(angle_difference(camera.yaw, spawn.global_rotation.y))
		var inactive_attachment: bool = runner.get("_active_line") == null \
			and runner.get("_active_swing") == null and runner.get("_beam") == null \
			and not bool(runner.get("_wall_mantle_active")) and not runner.call("is_wall_climbing")
		var cleared_wind: bool = runner.wind_velocity.is_zero_approx() \
			and float(runner.scarf_wind_load) < 0.001 \
			and StringName(runner.scarf_glide_phase) == &"stowed" \
			and not bool(runner.get("_wind_field_inside"))
		_check(String(controller.active_checkpoint_name) == String(section["name"])
			and controller.active_checkpoint_transform.is_equal_approx(spawn.global_transform)
			and retry_error < 0.18 and retry_yaw_error < 0.035
			and retry_camera_yaw_error < 0.035
			and absf(camera.pitch - expected_pitch) < 0.035
			and String(runner.current_state) == "Locomotion" and runner.is_on_floor()
			and runner.call("get_active_water") == null and inactive_attachment and cleared_wind,
			"R retries %s to its Spawn, restores camera and clears water, attachments, and wind (Δ %.3f m, state %s)"
			% [section["name"], retry_error, String(runner.current_state)])

	if OS.get_cmdline_user_args().has("--mobile-menu"):
		await _test_touch_retry(runner)

	input.call("clear_touch_input")
	await _finish(level)


func _test_touch_retry(runner: ParkourController) -> void:
	var hud := runner.touch_hud
	var prompt := hud.get_node_or_null("HUDRoot/SectionRetryPrompt") as Control if hud != null else null
	var retry_button := prompt.find_child("RetryButton", true, false) as BaseButton if prompt != null else null
	var spawn := _level.get_node_or_null("WindOverlook/CheckpointArea/Spawn") as Marker3D
	if hud == null or prompt == null or retry_button == null or spawn == null:
		_check(false, "Touch retry exposes the active Wind Overlook checkpoint button")
		return
	hud.set_touch_visible(true)
	await _ticks(2)
	var before_move := runner.global_position
	await _hold_key(KEY_W, 12)
	var moved_distance := Vector2(runner.global_position.x - before_move.x,
		runner.global_position.z - before_move.z).length()
	var point := retry_button.get_global_transform_with_canvas() * (retry_button.size * 0.5)
	await _push_touch(1, point, true)
	await process_frame
	await _push_touch(1, point, false)
	await _ticks(4)
	_check(moved_distance > 0.35
		and runner.global_position.distance_to(spawn.global_position) < 0.18
		and String(runner.current_state) == "Locomotion" and runner.is_on_floor(),
		"Touch Retry restores the Wind Overlook spawn after moving away (walk %.2f m)" % moved_distance)
	hud.set_touch_visible(false)


func _tap_key(keycode: int, hold_ticks: int = 1) -> void:
	_push_key(keycode, true)
	await _ticks(maxi(1, hold_ticks))
	_push_key(keycode, false)
	await _ticks(1)


func _hold_key(keycode: int, ticks: int) -> void:
	_push_key(keycode, true)
	await _ticks(ticks)
	_push_key(keycode, false)
	await _ticks(2)


func _push_key(keycode: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _push_touch(index: int, point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.device = 0
	event.position = point
	event.pressed = pressed
	root.push_input(event, true)


func _ticks(count: int) -> void:
	for _tick in count:
		await physics_frame
		await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("[PASS] ", message)
	else:
		_failed += 1
		printerr("[FAIL] ", message)


func _finish(level: Node) -> void:
	level.queue_free()
	await process_frame
	print("=== First Steps station starts: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
