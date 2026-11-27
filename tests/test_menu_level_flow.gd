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
	var new_game := controls.get_node_or_null("NewGameButton") as BaseButton if controls != null else null
	if new_game == null or not new_game.has_focus():
		_fail("New Game should have focus on the title screen.")
		return
	new_game.pressed.emit()
	for frame in 60:
		await process_frame
		if current_scene is RooftopGymController:
			break
	if not current_scene is RooftopGymController:
		_fail("New Game did not open the rooftop gym.")
		return
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
	print("PASS: Title, New Game, rooftop runner, pause journal, and Resume")
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL: ", message)
	quit(1)
