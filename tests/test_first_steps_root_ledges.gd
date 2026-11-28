extends SceneTree

## Plays the Root Ledges transfer with continuous virtual-stick input, drops
## from the exposed shelf edge, retries through the valley checkpoint, and
## repeats the same route without reloading the scene.
## Optional non-headless captures: CHIBI_ROOT_LEDGES_CAPTURE_DIR=<folder>
## Godot_v4.7.2-stable_win64_console.exe --fixed-fps 60 --headless --path . --script res://tests/test_first_steps_root_ledges.gd

const LEVEL := "res://levels/first_steps/first_steps_valley.tscn"
const DRIVER := preload("res://tests/first_steps_root_ledges_driver.gd")
const CAPTURE_ENV := "CHIBI_ROOT_LEDGES_CAPTURE_DIR"
const FORWARD_STICK := Vector2(0.0, -1.0)

var _passed := 0
var _failed := 0
var _capture_dir := ""
var _level: Node3D
var _runner: CharacterBody3D
var _driver: RefCounted


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.physics_ticks_per_second = 60
	_capture_dir = OS.get_environment(CAPTURE_ENV).strip_edges()
	var packed := load(LEVEL) as PackedScene
	if packed == null:
		_check(false, "First Steps Valley loads for the Root Ledges traversal")
		quit(1)
		return
	_level = packed.instantiate() as Node3D
	root.add_child(_level)
	await _ticks(12)
	_runner = _level.get_node_or_null("ChibiRunner") as CharacterBody3D
	_driver = DRIVER.new()
	var spawn := _level.get_node_or_null("RootLedges/CheckpointArea/Spawn") as Marker3D
	var shelf := _level.get_node_or_null("RootLedges/MantleShelf") as StaticBody3D
	var camera := _runner.get("camera_ctrl") as Node if _runner != null else null
	var input := _runner.get("chibi_input") as Node if _runner != null else null
	if _runner == null or spawn == null or shelf == null or camera == null or input == null:
		_check(false, "Valley exposes runner, touch input, camera, root shelf, and checkpoint spawn")
		await _finish()
		return
	input.call("set_touch_mode", true)
	var controller := _level
	if OS.is_debug_build():
		controller.call("start_at_developer_section", &"debug_zone_2")
		await _ticks(2)
		_check(String(controller.get("active_checkpoint_name")) == "Root Ledges"
			and Vector2(_runner.global_position.x - spawn.global_position.x,
				_runner.global_position.z - spawn.global_position.z).length() < 0.15,
			"Standalone route uses the authored Root Ledges checkpoint start")
	else:
		_check(false, "Root Ledges regression requires a debug build for its section seed")
		await _finish()
		return

	var first: Dictionary = await _driver.call("drive_from_dry_exit",
		self, _level, _runner, Callable(self, "_check"), _capture_dir)
	_check(bool(first.get("ok", false)), "The reusable DryExit driver completes its first traversal")
	if not bool(first.get("ok", false)):
		await _finish()
		return
	_check(String(controller.get("active_checkpoint_name")) == "Root Ledges"
		and controller.get("active_checkpoint_transform") is Transform3D,
		"The live valley keeps Root Ledges as the retry checkpoint through the transfer")

	var edge_x := shelf.global_position.x + 2.7
	var collision := shelf.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision != null and collision.shape is BoxShape3D:
		edge_x = shelf.global_position.x + (collision.shape as BoxShape3D).size.x * 0.5 + 0.45
	var top_y := shelf.global_position.y + 0.13
	input.call("clear_touch_input")
	input.call("set_touch_move", FORWARD_STICK)
	var walked_off := false
	var drop_min_y := _runner.global_position.y
	for _tick in 170:
		await _ticks(1)
		drop_min_y = minf(drop_min_y, _runner.global_position.y)
		if _runner.global_position.x > edge_x and _runner.global_position.y < top_y - 0.45:
			walked_off = true
			break
		if String(_runner.get("current_state")) == "Locomotion" and _runner.is_on_floor() \
				and _runner.global_position.x <= edge_x and _runner.global_position.x > shelf.global_position.x:
			continue
	input.call("set_touch_move", Vector2.ZERO)
	_check(walked_off,
		"Holding forward walks off the shelf’s exposed +X edge before retry (edge x %.2f, min y %.2f, final %s)"
		% [edge_x, drop_min_y, str(_runner.global_position)])
	await _capture("drop_from_shelf")
	if not walked_off:
		await _finish()
		return

	controller.call("retry_section")
	await _ticks(2)
	var position_error := Vector2(_runner.global_position.x - spawn.global_position.x,
		_runner.global_position.z - spawn.global_position.z).length()
	var yaw_error := absf(angle_difference(_runner.global_rotation.y, spawn.global_rotation.y))
	var camera_yaw_error := absf(angle_difference(float(camera.get("yaw")), spawn.global_rotation.y))
	var expected_pitch := float(_level.get_node("RootLedges/CheckpointArea").get_meta("camera_pitch", -0.18))
	_check(String(controller.get("active_checkpoint_name")) == "Root Ledges"
		and position_error < 0.12 and yaw_error < 0.03
		and camera_yaw_error < 0.03
		and absf(float(camera.get("pitch")) - expected_pitch) < 0.03
		and String(_runner.get("current_state")) == "Locomotion" and _runner.get_collision_mask_value(1),
		"Standard retry restores checkpoint position, heading, camera framing, and locomotion (pos Δ %.3f, yaw Δ %.3f, camera Δ %.3f, pitch %.3f/%.3f)"
		% [position_error, yaw_error, camera_yaw_error, float(camera.get("pitch")), expected_pitch])
	await _capture("retry_spawn")

	var second: Dictionary = await _driver.call("drive_from_dry_exit",
		self, _level, _runner, Callable(self, "_check"), _capture_dir)
	_check(bool(second.get("ok", false)), "The same loaded valley replays pole → root → mantle after retry")
	input.call("clear_touch_input")
	await _finish()


func _capture(label: String) -> void:
	if _capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		print("CAPTURE skipped for Root Ledges %s: viewport image empty" % label)
		return
	var error := DirAccess.make_dir_recursive_absolute(_capture_dir)
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_warning("Could not create Root Ledges capture folder %s" % _capture_dir)
		return
	var destination := _capture_dir.path_join("root_ledges_%s.png" % label)
	error = image.save_png(destination)
	if error == OK:
		print("CAPTURE: %s (%s)" % [destination, RenderingServer.get_video_adapter_name()])
	else:
		push_warning("Could not save Root Ledges capture %s (error %d)" % [destination, error])


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
	print("=== FIRST STEPS ROOT LEDGES: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("PASS: ", message)
	else:
		_failed += 1
		push_error("FAIL: " + message)
