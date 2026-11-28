extends "res://tests/test_first_steps_dry_crossing.gd"

## Continuous configured-title → First Steps → Wind Overlook → atlas → Gym flow.
## Gameplay uses touch-stick/jump input throughout; it never invokes a developer
## checkpoint, retries, resets, or writes the runner transform.

const Roots := preload("res://tests/first_steps_root_ledges_driver.gd")
const Canopy := preload("res://tests/first_steps_canopy_driver.gd")
const Wind := preload("res://tests/first_steps_wind_driver.gd")
const FIRST_STEPS_SCENE := "res://levels/first_steps/first_steps_valley.tscn"
const ROOFTOP_GYM_SCENE := "res://levels/rooftop_gym/rooftop_parkour_gym.tscn"


func _run() -> void:
	Engine.physics_ticks_per_second = 60
	_capture_dir = ""
	var entry_path: String = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if not await _expect(entry_path.ends_with(".tscn"), "Project config supplies a playable title scene"):
		await _abort_run()
		return
	if not await _expect(change_scene_to_file(entry_path) == OK,
			"The configured title scene loads through SceneTree"):
		await _abort_run()
		return
	await scene_changed
	await _ticks(3)
	var title := current_scene
	var play_button := title.get_node_or_null("ArtworkCanvas/TitleControls/PlayButton") as BaseButton
	if not await _expect(title.scene_file_path == entry_path and play_button != null
			and play_button.has_focus(),
			"The configured title opens with Play focused"):
		await _abort_run()
		return

	play_button.pressed.emit()
	await _ticks(24)
	var atlas := title.get_node_or_null("AtlasPreview") as Control
	var atlas_back := atlas.get_node_or_null("DesignCanvas/BackButton") as BaseButton \
		if atlas != null else null
	if not await _expect(atlas != null and atlas.is_visible_in_tree() and atlas_back != null
			and root.gui_get_focus_owner() == atlas_back,
			"Play opens the real atlas with Back focused"):
		await _abort_run()
		return

	atlas_back.pressed.emit()
	await _ticks(24)
	if not await _expect(title.get_node_or_null("AtlasPreview") == null
			and play_button.is_visible_in_tree() and play_button.has_focus(),
			"Atlas Back returns to the title and restores Play focus"):
		await _abort_run()
		return

	play_button.pressed.emit()
	await _ticks(24)
	atlas = title.get_node_or_null("AtlasPreview") as Control
	var postcard := atlas.get_node_or_null("DesignCanvas/Postcard") as Control \
		if atlas != null else null
	var launch_button := postcard.get_node_or_null("LaunchButton") as BaseButton \
		if postcard != null else null
	if not await _expect(atlas != null and atlas.is_visible_in_tree()
			and StringName(atlas.get("selected_destination_id")) == &"first_steps"
			and launch_button != null and not launch_button.disabled,
			"Reopening the atlas selects the playable First Steps postcard"):
		await _abort_run()
		return
	launch_button.pressed.emit()
	if not await _wait_for_scene(FIRST_STEPS_SCENE, 240):
		_check(false, "First Steps postcard launches the valley scene")
		await _abort_run()
		return
	_check(true, "First Steps postcard launches the valley scene")

	var level := current_scene as Node3D
	var player := level.get_node_or_null("ChibiRunner") as ParkourController
	var input := player.chibi_input if player != null else null
	var camera := player.camera_ctrl if player != null else null
	if not await _expect(player != null and input != null and camera != null,
			"The live valley exposes Chibi, touch input, and camera controls"):
		await _abort_run()
		return
	var safe_spawn := level.get_node_or_null("SafeSpawn") as Marker3D
	if not await _expect(safe_spawn != null and player.global_position.distance_to(
			safe_spawn.global_position) < 1.0,
			"The route begins at the authored First Steps trailhead"):
		await _abort_run()
		return
	if not await _exercise_pause_resume(player):
		await _abort_run()
		return
	input.call("set_touch_mode", true)

	for point in APPROACH:
		var waypoint := Vector3(point.x, player.global_position.y, point.y)
		if not await _drive_to_point(player, input, camera, waypoint, 0.9, 1500):
			_check(false, "Continuous touch input reaches the dry crossing approach at %s"
				% str(point))
			await _abort_run()
			return
	_check(true, "Continuous touch input reaches the dry crossing approach")
	camera.yaw = -PI / 2.0
	for point in [Vector3(-22.5, 0.0, -17.6), Vector3(-22.5, 0.0, -14.0),
			Vector3(-22.52, 0.0, -15.72)]:
		var reached_point := false
		for _tick in 500:
			var delta := Vector2(point.x - player.global_position.x,
				point.z - player.global_position.z)
			if delta.length() < 0.14:
				reached_point = true
				break
			input.call("set_touch_move", Vector2(delta.y, -delta.x).normalized()
				* (0.35 if delta.length() < 0.7 else 1.0))
			await _ticks(1)
		if not reached_point:
			_check(false, "Continuous approach reaches the dry crossing staging point %s"
				% str(point))
			await _abort_run()
			return
	input.call("set_touch_move", Vector2.ZERO)
	await _ticks(360)

	var dry_course := level.get_node("DryCrossing") as Node3D
	var dry := await _drive_course(player, input, camera, level.get_node("CreekWater"),
		dry_course.get_node("VaultRoot"), dry_course.get_node("BoulderHopA"),
		dry_course.get_node("BoulderHopB"), dry_course.get_node("BalanceLog"),
		dry_course.get_node("DryExit"), 0, 0, false)
	_check(bool(dry.get("vault", false)), "Continuous dry route enters SpeedVault at the root")
	_check(bool(dry.get("vault_landing", false)), "SpeedVault lands on far-side footing")
	_check(bool(dry.get("boulder_a", false)), "First jump lands on BoulderHopA")
	_check(bool(dry.get("boulder_b", false)), "Second jump lands on BoulderHopB")
	_check(bool(dry.get("beam", false)), "The balance log enters BalanceBeam state")
	_check(bool(dry.get("beam_traversed", false)), "Chibi traverses the balance log")
	_check(bool(dry.get("finish", false)) and player.is_on_floor()
		and player.call("get_active_water") == null,
		"Chibi finishes the dry crossing grounded and out of water")
	_check(not bool(dry.get("miss_swum", false)),
		"The continuous dry route stays out of CreekWater")
	if not bool(dry.get("finish", false)) or not bool(dry.get("beam_traversed", false)):
		await _abort_run()
		return

	for _tick in 300:
		var delta_to_shelf := Vector2(4.0 - player.global_position.x,
			-16.0 - player.global_position.z)
		if delta_to_shelf.length() < 0.04:
			break
		input.call("set_touch_move", Vector2(delta_to_shelf.y, -delta_to_shelf.x).normalized()
			* clampf(delta_to_shelf.length(), 0.08, 0.45))
		await _ticks(1)
	input.call("clear_touch_input")
	await _ticks(360)
	var root_result := await Roots.new().drive_from_dry_exit(self, level, player, _check)
	_check(bool(root_result.get("ok", false)), "Live dry-exit movement completes pole, root climb, and mantle")
	_check(_states_include(root_result.get("states", []), "PolePerch")
		and _states_include(root_result.get("states", []), "Climbing")
		and _states_include(root_result.get("states", []), "MantleUp"),
		"The continuous root route records pole, climbing, and mantle states")
	if not bool(root_result.get("ok", false)):
		await _abort_run()
		return

	var canopy_result := await Canopy.new().drive_from_shelf(self, level, player, _check)
	_check(bool(canopy_result.get("caught", false)), "The shelf run catches the live swing")
	_check(bool(canopy_result.get("released", false)), "Chibi releases the swing with a real jump")
	_check(bool(canopy_result.get("landed", false)), "Swing release lands grounded on the pad")
	_check(bool(canopy_result.get("zip_mounted", false)), "A real jump catches the descending zipline")
	_check(bool(canopy_result.get("zip_dismounted", false)), "The zipline dismounts under its own motion")
	_check(bool(canopy_result.get("finish_grounded", false)),
		"The canopy route finishes grounded after zip dismount")
	if not bool(canopy_result.get("ok", false)):
		await _abort_run()
		return

	var wind_result := await Wind.new().drive_from_zip_exit(self, level, player, _check)
	_check(bool(wind_result.get("field_entered", false)), "The live route enters the bounded wind field")
	_check(bool(wind_result.get("field_exited", false)), "The live route exits the bounded wind field")
	_check(bool(wind_result.get("landed", false))
		and bool(wind_result.get("landing_supported", false)),
		"The scarf glide lands supported on the overlook deck")
	_check(bool(wind_result.get("finish_prompt_visible", false))
		and paused and player.is_on_floor(),
		"Grounded arrival opens the valley completion prompt")
	if not (bool(wind_result.get("ok", false))
			and bool(wind_result.get("finish_prompt_visible", false))):
		await _abort_run()
		return

	var finish_ui := level.get_node_or_null("WindOverlook/ValleyFinish") as CanvasLayer
	var level_select := finish_ui.get_node_or_null("LevelSelectButton") as BaseButton \
		if finish_ui != null else null
	if not await _expect(finish_ui != null and finish_ui.visible and level_select != null,
			"The real valley finish UI offers Level Select"):
		await _abort_run()
		return
	level_select.pressed.emit()
	if not await _wait_for_scene(entry_path, 240):
		_check(false, "Level Select returns to the configured title scene")
		await _abort_run()
		return
	_check(true, "Level Select returns to the configured title scene")
	await _ticks(24)
	title = current_scene
	atlas = title.get_node_or_null("AtlasPreview") as Control
	atlas_back = atlas.get_node_or_null("DesignCanvas/BackButton") as BaseButton \
		if atlas != null else null
	postcard = atlas.get_node_or_null("DesignCanvas/Postcard") as Control \
		if atlas != null else null
	launch_button = postcard.get_node_or_null("LaunchButton") as BaseButton \
		if postcard != null else null
	if not await _expect(atlas != null and atlas.is_visible_in_tree()
			and StringName(atlas.get("selected_destination_id")) == &"first_steps"
			and atlas_back != null and root.gui_get_focus_owner() == atlas_back
			and launch_button != null and not launch_button.disabled,
			"Completion returns to the actual atlas with First Steps selected and Back focused"):
		await _abort_run()
		return

	var world_map := atlas.get_node_or_null("DesignCanvas/MapViewport/WorldMap") as Control
	var gym_pin := world_map.get_node_or_null("RooftopGymPin") as BaseButton \
		if world_map != null else null
	if not await _expect(gym_pin != null, "The returned atlas contains the Rooftop Gym pin"):
		await _abort_run()
		return
	# Exercise the actual pin and postcard buttons, leaving atlas selection and
	# scene transition behavior to the menu's production signal connections.
	gym_pin.pressed.emit()
	await process_frame
	if not await _expect(StringName(atlas.get("selected_destination_id")) == &"rooftop_gym"
			and StringName(postcard.get("current_destination")) == &"rooftop_gym"
			and not launch_button.disabled and current_scene == title,
			"Pressing the real Gym pin selects its available postcard without launching"):
		await _abort_run()
		return
	launch_button.pressed.emit()
	if not await _wait_for_scene(ROOFTOP_GYM_SCENE, 240):
		_check(false, "The Gym postcard launches Rooftop Gym")
		await _abort_run()
		return
	_check(true, "The Gym postcard launches Rooftop Gym")
	var gym_runner := current_scene.get_node_or_null("ChibiRunner") as ParkourController
	if not await _expect(gym_runner != null and gym_runner.touch_hud != null,
			"Rooftop Gym provides the runner and pause HUD"):
		await _abort_run()
		return
	if not await _exercise_pause_resume(gym_runner):
		await _abort_run()
		return

	await _clean_teardown()
	print("=== FULL FIRST STEPS JOURNEY: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _expect(condition: bool, message: String) -> bool:
	_check(condition, message)
	return condition


func _states_include(states: Variant, state_name: String) -> bool:
	if not states is Array:
		return false
	for entry in states as Array:
		if entry is Dictionary and String(entry.get("state", "")) == state_name:
			return true
	return false


func _push_action(action_name: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = pressed
	root.push_input(event)


func _exercise_pause_resume(runner: ParkourController) -> bool:
	if runner.touch_hud == null:
		return _expect(false, "Runner exposes the pause journal")
	_push_action(&"ui_cancel", true)
	_push_action(&"ui_cancel", false)
	await process_frame
	var resume := runner.touch_hud.find_child("ResumeButton", true, false) as BaseButton
	var opened: bool = paused and runner.touch_hud.menu_open and resume != null
	_check(opened, "Pause opens the journal and exposes Resume")
	if not opened:
		if paused:
			paused = false
		return false
	resume.pressed.emit()
	await process_frame
	var resumed: bool = not paused and not runner.touch_hud.menu_open
	_check(resumed, "Resume returns input to active gameplay")
	return resumed


func _wait_for_scene(path: String, max_frames: int) -> bool:
	for _frame in range(max_frames):
		if current_scene != null and current_scene.scene_file_path == path:
			return true
		await process_frame
	return current_scene != null and current_scene.scene_file_path == path


func _clean_teardown() -> void:
	if paused:
		paused = false
	if current_scene != null:
		var runner := current_scene.get_node_or_null("ChibiRunner") as ParkourController
		if runner != null and runner.chibi_input != null:
			runner.chibi_input.clear_touch_input()
		unload_current_scene()
	# Allow playback and scene-owned resources to finish releasing before exit.
	var settle_until := Time.get_ticks_msec() + 350
	while Time.get_ticks_msec() < settle_until:
		await process_frame


func _abort_run() -> void:
	await _clean_teardown()
	print("=== FULL FIRST STEPS JOURNEY: %d passed, %d failed ===" % [_passed, _failed])
	quit(1)
