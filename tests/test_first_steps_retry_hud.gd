extends SceneTree

## Run with Godot --headless --path . --script res://tests/test_first_steps_retry_hud.gd
## Exercises the checkpoint retry HUD through desktop and touch input in a loaded valley.

const VALLEY_SCENE := preload("res://levels/first_steps/first_steps_valley.tscn")

var _passed := 0
var _failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var level := VALLEY_SCENE.instantiate() as Node3D
	root.add_child(level)
	await process_frame
	await process_frame

	var controller := level as FirstStepsValleyController
	var runner := level.get_node_or_null("ChibiRunner") as ParkourController
	if controller == null or runner == null or runner.touch_hud == null:
		_assert(false, "First Steps Valley exposes its controller, runner, and HUD")
		await _finish(level)
		return

	var checkpoint_area := level.get_node_or_null("DryCrossing/CheckpointArea") as Area3D
	var checkpoint_spawn := checkpoint_area.get_node_or_null("Spawn") as Marker3D if checkpoint_area != null else null
	if checkpoint_area != null and checkpoint_spawn != null:
		checkpoint_area.body_entered.emit(runner)
		_assert(controller.active_checkpoint_name == "Dry Crossing"
			and controller.active_checkpoint_transform.is_equal_approx(checkpoint_spawn.global_transform),
			"The grouped checkpoint Area3D binds its Spawn marker as the active retry transform")
	else:
		_assert(false, "Dry Crossing provides the checkpoint Area3D and Spawn marker")

	var hud := runner.touch_hud
	var mobile_mode := OS.get_cmdline_user_args().has("--mobile-menu")
	var prompt := hud.get_node_or_null("HUDRoot/SectionRetryPrompt") as Control
	var retry_button := prompt.find_child("RetryButton", true, false) as Button if prompt != null else null
	if prompt == null or retry_button == null:
		_assert(false, "The section retry prompt and button are attached to the main HUD")
		await _finish(level)
		return

	runner.set_physics_process(false)
	var retry_button_activations := [0]
	retry_button.pressed.connect(func() -> void: retry_button_activations[0] += 1)
	var developer_start := level.get_node_or_null("DryCrossing/DeveloperStart") as Marker3D
	if developer_start != null and OS.is_debug_build():
		controller.start_at_developer_section()
		_assert(controller.active_checkpoint_name == "Dry Crossing"
			and runner.global_position.is_equal_approx(developer_start.global_position)
			and is_equal_approx(runner.global_rotation.y, developer_start.global_rotation.y)
			and is_equal_approx(runner.camera_ctrl.yaw, developer_start.global_rotation.y)
			and is_equal_approx(runner.camera_ctrl.pitch, -0.56),
			"The debug section start resets runner heading and the higher section camera framing")
	else:
		print("[SKIP] Developer section start requires the debug build and authored marker")

	var checkpoint := checkpoint_spawn.global_transform
	await process_frame
	_assert(prompt.visible and hud.touch_visible == mobile_mode,
		"The retry prompt remains visible with the active desktop or touch controls")
	_assert(retry_button.focus_mode == Control.FOCUS_ALL and retry_button.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND,
		"The retry button supports keyboard focus and shows a pointing cursor")
	retry_button.grab_focus()
	_assert(root.gui_get_focus_owner() == retry_button, "The retry button accepts keyboard focus")

	# Desktop keyboard activation should route through the prompt's R shortcut.
	runner.global_position = Vector3(10.0, 24.0, 10.0)
	_push_key(KEY_R, true)
	await process_frame
	_push_key(KEY_R, false)
	await process_frame
	_assert(runner.global_position.is_equal_approx(checkpoint.origin)
		and is_equal_approx(runner.global_rotation.y, -PI / 2.0)
		and is_equal_approx(runner.camera_ctrl.yaw, -PI / 2.0)
		and is_equal_approx(runner.camera_ctrl.pitch, -0.56),
		"Desktop R retries to the checkpoint with runner and camera heading restored")

	# Opening the pause journal must hide the retry control and prevent its shortcut.
	runner.global_position = Vector3(10.0, 24.0, 10.0)
	hud.set_menu_open(true)
	await process_frame
	_assert(not prompt.visible, "The retry prompt hides while the pause journal is open")
	_push_key(KEY_R, true)
	await process_frame
	_push_key(KEY_R, false)
	await process_frame
	_assert(runner.global_position.is_equal_approx(Vector3(10.0, 24.0, 10.0)),
		"R does not retry while the pause journal is open")
	hud.set_menu_open(false)
	await process_frame
	_assert(prompt.visible, "The retry prompt returns when gameplay resumes")

	# The same button remains reachable when touch controls are active. Screen-touch
	# input should pass through the HUD's joystick router and activate the button.
	hud.set_touch_visible(true)
	await process_frame
	var touch_point := retry_button.get_global_transform_with_canvas() * (retry_button.size * 0.5)
	var activations_before_touch: int = retry_button_activations[0]
	runner.global_position = Vector3(10.0, 24.0, 10.0)
	_push_touch(1, touch_point, true)
	await process_frame
	_push_touch(1, touch_point, false)
	await process_frame
	_assert(retry_button_activations[0] == activations_before_touch + 1
		and runner.global_position.is_equal_approx(checkpoint.origin),
		"Touching Retry activates the button and restores the authored checkpoint")

	await _finish(level)


func _push_key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	root.get_viewport().push_input(event)


func _push_touch(index: int, point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.device = 0
	event.position = point
	event.pressed = pressed
	root.push_input(event, true)


func _assert(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
		print("[PASS] ", description)
	else:
		_failed += 1
		printerr("[FAIL] ", description)


func _finish(level: Node) -> void:
	root.get_viewport().gui_release_focus()
	level.queue_free()
	await process_frame
	print("=== First Steps retry HUD: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
