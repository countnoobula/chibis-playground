extends SceneTree

## Run on either desktop or the --mobile-menu layout, including against an exported pack.
func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var entry: String = ProjectSettings.get_setting("application/run/main_scene")
	if change_scene_to_file(entry) != OK:
		_fail("The configured title scene could not be loaded.")
		return
	await scene_changed
	var controls := current_scene.get_node_or_null("ArtworkCanvas/TitleControls")
	var play := controls.get_node_or_null("PlayButton") as BaseButton if controls != null else null
	if play == null or not play.has_focus():
		_fail("Play should have focus on the title screen.")
		return
	var mobile := OS.get_cmdline_user_args().has("--mobile-menu")
	var play_position := play.get_global_transform_with_canvas() * (play.size * 0.5)
	_click(play_position, mobile)
	_click(play_position, mobile)
	await create_timer(0.5).timeout
	var back := root.gui_get_focus_owner() as BaseButton
	if back == null or back == play or not back.is_visible_in_tree() or back.accessibility_name != "Back":
		_fail("Play should open the atlas and focus Back, including after a double tap.")
		return
	_click(back.get_global_transform_with_canvas() * (back.size * 0.5), mobile)
	await create_timer(0.5).timeout
	if not play.has_focus() or not play.is_visible_in_tree():
		_fail("Atlas Back should restore title Play focus.")
		return
	_gamepad_button(JOY_BUTTON_A)
	await create_timer(0.5).timeout
	back = root.gui_get_focus_owner() as BaseButton
	if back == null or back.accessibility_name != "Back":
		_fail("Confirm should reopen the atlas.")
		return
	_gamepad_button(JOY_BUTTON_B)
	await create_timer(0.5).timeout
	if not play.has_focus():
		_fail("Cancel should return to the focused title Play button.")
		return

	# The next checkpoint will expose the rooftop through the atlas.
	if change_scene_to_file("res://levels/rooftop_gym/rooftop_parkour_gym.tscn") != OK:
		_fail("The rooftop could not be loaded.")
		return
	await scene_changed
	var runner := current_scene.get_node_or_null("ChibiRunner") as ParkourController
	if runner == null or runner.touch_hud == null:
		_fail("The rooftop must provide the playable runner and HUD.")
		return
	var pause_event := InputEventAction.new()
	pause_event.action = &"ui_cancel"
	pause_event.pressed = true
	root.push_input(pause_event)
	await process_frame
	var resume := runner.touch_hud.find_child("ResumeButton", true, false) as BaseButton
	if not paused or resume == null:
		_fail("Pause should open the journal with a Resume button.")
		return
	resume.pressed.emit()
	if paused or runner.touch_hud.menu_open:
		_fail("Resume should return input to the rooftop.")
		return
	unload_current_scene()
	# The audio mixer releases the rooftop wind playback on its own clock.
	var settle_until := Time.get_ticks_msec() + 350
	while Time.get_ticks_msec() < settle_until:
		await process_frame
	print("PASS: Title, Play, atlas, Back and Cancel; direct rooftop, pause journal, and Resume")
	quit(0)


func _click(position: Vector2, touch: bool) -> void:
	for pressed in [true, false]:
		if touch:
			var finger := InputEventScreenTouch.new()
			finger.position = position
			finger.pressed = pressed
			root.push_input(finger, true)
		else:
			var mouse := InputEventMouseButton.new()
			mouse.button_index = MOUSE_BUTTON_LEFT
			mouse.position = position
			mouse.global_position = position
			mouse.pressed = pressed
			root.push_input(mouse, true)


func _gamepad_button(button: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		root.push_input(event)


func _fail(message: String) -> void:
	printerr("FAIL: ", message)
	quit(1)
