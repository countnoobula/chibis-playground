extends SceneTree

## Drives the First Steps Canopy Gap from its live shelf checkpoint. The route
## helper uses continuous touch-stick movement and real jump presses only.
## Optional non-headless captures: CHIBI_CANOPY_CAPTURE_DIR=<folder>
## Godot_v4.7.2-stable_win64_console.exe --fixed-fps 60 --headless --path . --script res://tests/test_first_steps_canopy.gd

const LEVEL := "res://levels/first_steps/first_steps_valley.tscn"
const DRIVER := preload("res://tests/first_steps_canopy_driver.gd")
const CAPTURE_ENV := "CHIBI_CANOPY_CAPTURE_DIR"

var _passed := 0
var _failed := 0
var _capture_dir := ""
var _level: Node3D
var _runner: CharacterBody3D
var _controller: Node
var _input: Node
var _driver: RefCounted
var _spawn: Marker3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.physics_ticks_per_second = 60
	_capture_dir = OS.get_environment(CAPTURE_ENV).strip_edges()
	var packed := load(LEVEL) as PackedScene
	if packed == null:
		_check(false, "First Steps Valley loads for the Canopy Gap route")
		quit(1)
		return
	_level = packed.instantiate() as Node3D
	root.add_child(_level)
	await _ticks(12)
	_runner = _level.get_node_or_null("ChibiRunner") as CharacterBody3D
	_controller = _level
	_spawn = _level.get_node_or_null("CanopyGap/CheckpointArea/Spawn") as Marker3D
	_driver = DRIVER.new()
	_input = _runner.get("chibi_input") as Node if _runner != null else null
	var camera := _runner.get("camera_ctrl") as Node if _runner != null else null
	var developer_start := _level.get_node_or_null("CanopyGap/DeveloperStart") as Marker3D
	var swing := _level.get_node_or_null("CanopyGap/Swing") as Node3D
	var landing := _level.get_node_or_null("CanopyGap/ReleaseLanding") as Marker3D
	var zip_line := _level.get_node_or_null("CanopyGap/ZipLine") as Node3D
	var finish := _level.get_node_or_null("CanopyGap/CanopyGapFinish") as Marker3D
	if _runner == null or _input == null or camera == null or _spawn == null \
			or developer_start == null or swing == null or landing == null \
			or zip_line == null or finish == null:
		_check(false, "Valley exposes the runner, shelf checkpoint, swing, landing, zipline, and finish markers")
		await _finish()
		return
	_input.call("set_touch_mode", true)
	if not OS.is_debug_build():
		_check(false, "Canopy Gap regression requires a debug build for its authored checkpoint seed")
		await _finish()
		return
	_controller.call("start_at_developer_section", &"debug_zone_3")
	await _ticks(2)
	var checkpoint_error := _runner.global_position.distance_to(_spawn.global_position)
	var camera_yaw_error := absf(angle_difference(float(camera.get("yaw")), -PI / 2.0))
	_check(String(_controller.get("active_checkpoint_name")) == "Canopy Gap"
		and checkpoint_error < 0.15
		and _runner.is_on_floor()
		and camera_yaw_error < 0.05,
		"Standalone seed starts grounded at x=13.05 on the mantle shelf with the +X camera (pos Δ %.3f m, yaw Δ %.3f rad)"
		% [checkpoint_error, camera_yaw_error])
	if checkpoint_error >= 0.15 or not _runner.is_on_floor():
		await _finish()
		return

	# Exercise the edge of the swing's forgiving entry envelope, release almost
	# immediately, settle below the gap, and verify a real Canopy Gap retry.
	var early_edge: Dictionary = await _driver.call("drive_from_shelf", self, _level, _runner,
		Callable(self, "_check"), _capture_dir,
		{"approach_lateral": 0.42, "release_after_swing_ticks": 4,
		"stop_after_release": true, "capture_prefix": "early_edge"})
	_check(bool(early_edge.get("caught", false))
		and absf(float(early_edge.get("approach_z_offset", 0.0))) >= 0.30,
		"An edge-biased run still enters the rope catch volume (offset %.2f m)"
		% float(early_edge.get("approach_z_offset", 0.0)))
	_check(bool(early_edge.get("released", false))
		and int(early_edge.get("swing_ticks", 0)) == 4,
		"The early test uses a real jump release after four swing ticks")
	_input.call("clear_touch_input")
	var early_recovered := false
	for _tick in 150:
		await _ticks(1)
		if String(_runner.get("current_state")) == "Locomotion" \
				and _runner.is_on_floor():
			early_recovered = true
			break
	_check(early_recovered or _runner.global_position.y < -4.0,
		"Early release reaches a grounded recovery surface or the valley retry boundary (pos %s)"
		% str(_runner.global_position))
	_controller.call("retry_section")
	await _ticks(2)
	var retry_error := _runner.global_position.distance_to(_spawn.global_position)
	_check(String(_controller.get("active_checkpoint_name")) == "Canopy Gap"
		and retry_error < 0.15
		and String(_runner.get("current_state")) == "Locomotion"
		and _runner.get("_active_swing") == null,
		"Canopy Gap retry restores the shelf spawn and clears the early swing attachment (Δ %.3f m)"
		% retry_error)

	# Sweep a later release window after retry. This leaves the full route start
	# deterministic and verifies the route helper's early/late release controls.
	var late_release: Dictionary = await _driver.call("drive_from_shelf", self, _level, _runner,
		Callable(self, "_check"), _capture_dir,
		{"release_after_swing_ticks": 22, "stop_after_release": true,
		"capture_prefix": "late_release"})
	_check(bool(late_release.get("caught", false)) and bool(late_release.get("released", false))
		and int(late_release.get("swing_ticks", 0)) == 22,
		"A late timing window releases from the same live swing after 22 ticks (angle %.3f rad)"
		% float(late_release.get("release_angle", 0.0)))
	_input.call("clear_touch_input")
	_controller.call("retry_section")
	await _ticks(2)

	# The reusable default covers center approach, the intended swing landing,
	# the second jump, automatic descending zip dismount, and grounded finish.
	var full_route: Dictionary = await _driver.call("drive_from_shelf", self, _level, _runner,
		Callable(self, "_check"), _capture_dir,
		{"release_after_swing_ticks": 16, "capture_prefix": "center_route"})
	_check(bool(full_route.get("ok", false)),
		"Continuous shelf input completes RopeSwing → landing → ZipLine → grounded finish (states %s, finish %s)"
		% [str(full_route.get("states", [])), str(full_route.get("finish", _runner.global_position))])
	_check(float(full_route.get("approach_z_offset", INF)) <= 0.25,
		"The intended route approaches the swing through the center of its catch volume (offset %.2f m)"
		% float(full_route.get("approach_z_offset", INF)))
	_check(_runner.get("_active_swing") == null and _runner.get("_active_line") == null,
		"The completed route leaves no rope or zip attachment active")
	_input.call("clear_touch_input")
	await _finish()


func _ticks(count: int) -> void:
	for _tick in count:
		await physics_frame
		await process_frame


func _finish() -> void:
	if _level != null and is_instance_valid(_level):
		_level.queue_free()
		await process_frame
	var audio_release_deadline := Time.get_ticks_msec() + 250
	while Time.get_ticks_msec() < audio_release_deadline:
		await process_frame
	print("=== FIRST STEPS CANOPY GAP: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("PASS: ", message)
	else:
		_failed += 1
		push_error("FAIL: " + message)
