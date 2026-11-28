extends SceneTree

## Runs identical trampoline-to-wind input with the valley provider bound and
## removed, then exercises a loaded-glide fall/retry and both finish choices.
## Optional non-headless captures: CHIBI_FIRST_STEPS_WIND_CAPTURE_DIR=<folder>
## Godot_v4.7.2-stable_win64_console.exe --fixed-fps 60 --headless --path . --script res://tests/test_first_steps_wind.gd

const LEVEL := "res://levels/first_steps/first_steps_valley.tscn"
const MAIN_MENU := "res://ui/menu/main_menu.tscn"
const DRIVER := preload("res://tests/first_steps_wind_driver.gd")
const CAPTURE_ENV := "CHIBI_FIRST_STEPS_WIND_CAPTURE_DIR"

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
	_driver = DRIVER.new()
	if not await _load_valley():
		await _finish()
		return
	var seed_ok := await _seed_wind_checkpoint()
	if not seed_ok:
		await _finish()
		return

	var field := _level.get_node_or_null("WindOverlook/WindField") as Node3D
	var cue := _level.get_node_or_null("WindOverlook/FoliageCue") as Node3D
	var cue_stem := _level.get_node_or_null("WindOverlook/FoliageCue/DownwindStem_00") as Node3D
	var authored_provider: Object = _runner.get("wind_field")
	var field_surface_velocity: Vector3 = field.call("flow_velocity_at", Vector3(44.7, 9.6, -16.0)) \
		if field != null else Vector3.ZERO
	_check(field != null and authored_provider == field
		and bool(field.call("contains_point", Vector3(44.7, 9.6, -16.0)))
		and field_surface_velocity.dot(Vector3.RIGHT) > 7.0,
		"Wind Overlook binds a bounded +X field with authored 8.2 m/s tailwind")
	_check(cue != null and cue.visible and cue_stem != null,
		"The takeoff lane shows the authored downwind foliage cue")
	if cue_stem == null or field == null:
		await _finish()
		return
	var cue_rotation_before := cue_stem.rotation.z
	await _ticks(18)
	var cue_rotation_delta := absf(angle_difference(cue_stem.rotation.z, cue_rotation_before))
	_check(cue_rotation_delta > 0.004,
		"The foliage cue sways over time before the jump (stem Δ %.3f rad)" % cue_rotation_delta)

	var enabled_sample: Dictionary = await _drive({
		"stop_after_field_sample": true,
		"capture_prefix": "enabled_sample",
	})
	_check(bool(enabled_sample.get("field_entered", false))
		and float(enabled_sample.get("max_wind_load", 0.0)) > 0.02
		and float(enabled_sample.get("max_runner_wind_speed", 0.0)) > 0.1,
		"Enabled route carries gust load inside the field (load %.3f, wind %.2f m/s)"
		% [float(enabled_sample.get("max_wind_load", 0.0)),
			float(enabled_sample.get("max_runner_wind_speed", 0.0))])
	if not bool(enabled_sample.get("ok", false)):
		await _finish()
		return

	await _retry_and_check("between enabled and disabled replay")
	var disabled_sample: Dictionary = await _drive({
		"disable_field_for_runner": true,
		"stop_after_field_sample": true,
		"capture_prefix": "disabled_sample",
	})
	var disabled_runner_wind := Vector3(_runner.get("wind_velocity"))
	_check(bool(disabled_sample.get("field_entered", false))
		and float(disabled_sample.get("max_direct_wind_speed", 0.0)) > 0.1
		and float(disabled_sample.get("max_runner_wind_speed", 0.0)) < 0.01
		and disabled_runner_wind.is_zero_approx()
		and _runner.get("wind_field") == null,
		"The disabled repeat crosses the same bounded volume without runner wind or scarf load")
	var enabled_entry: Vector3 = enabled_sample.get("field_entry", Vector3.ZERO)
	var disabled_entry: Vector3 = disabled_sample.get("field_entry", Vector3.ZERO)
	var entry_delta := enabled_entry.distance_to(disabled_entry)
	_check(enabled_entry.x >= 39.7 and disabled_entry.x >= 39.7
		and enabled_entry.x <= 50.0 and disabled_entry.x <= 50.0
		and absf(enabled_entry.z + 16.0) < 2.8 and absf(disabled_entry.z + 16.0) < 2.8
		and entry_delta < 3.0,
		"Enabled and disabled repeats enter the same authored field corridor (Δ %.2f m)" % entry_delta)

	# Restore the authored provider, then cancel the scarf from actual flight.
	_runner.set("wind_field", authored_provider)
	var fall_start := _runner.global_position
	_runner.get("chibi_input").call("set_touch_jump", true)
	await _ticks(1)
	_runner.get("chibi_input").call("set_touch_jump", false)
	var canceled := StringName(_runner.get("scarf_glide_phase")) == &"cancel"
	var canceled_load := float(_runner.get("scarf_wind_load"))
	var min_fall_y := _runner.global_position.y
	var saw_airborne := not _runner.is_on_floor()
	_runner.get("chibi_input").call("set_touch_move", Vector2.ZERO)
	for _tick in 60:
		await _ticks(1)
		min_fall_y = minf(min_fall_y, _runner.global_position.y)
		saw_airborne = saw_airborne or not _runner.is_on_floor()
		if _runner.is_on_floor() or min_fall_y < fall_start.y - 1.0:
			break
	_check(canceled and canceled_load < 0.01 and saw_airborne
		and min_fall_y < fall_start.y - 0.8,
		"Jump cancels the opened scarf and the runner falls under normal gravity (Δy %.2f m, wind load %.3f)"
		% [fall_start.y - min_fall_y, canceled_load])
	await _capture("canceled_glide_fall")
	await _retry_and_check("after canceled glide fall")
	_check(_runner.get("wind_field") == authored_provider
		and Vector3(_runner.get("wind_velocity")).is_zero_approx()
		and float(_runner.get("scarf_wind_load")) < 0.01
		and StringName(_runner.get("scarf_glide_phase")) == &"stowed",
		"Checkpoint retry clears wind carry and scarf state after a field fall")

	# The complete enabled route proves field exit, landing and the grounded finish.
	var completion := await _drive({"capture_prefix": "completed_route"})
	_check(bool(completion.get("ok", false))
		and bool(completion.get("finish_prompt_visible", false)),
		"Enabled tailwind completes the real trampoline → glide → overlook route")
	if not bool(completion.get("finish_prompt_visible", false)):
		await _finish()
		return

	var finish_prompt := _level.get_node_or_null("WindOverlook/ValleyFinish") as CanvasLayer
	var replay_button := finish_prompt.get_node_or_null("ReplayButton") as TextureButton if finish_prompt != null else null
	var level_select_button := finish_prompt.get_node_or_null("LevelSelectButton") as TextureButton if finish_prompt != null else null
	_check(replay_button != null and level_select_button != null
		and (replay_button.get_node_or_null("Label") as Label).text == "Replay"
		and (level_select_button.get_node_or_null("Label") as Label).text == "Level Select"
		and replay_button.focus_mode == Control.FOCUS_ALL
		and level_select_button.focus_mode == Control.FOCUS_ALL,
		"Completion offers focusable Replay and Level Select controls")
	if replay_button == null or level_select_button == null:
		await _finish()
		return

	var replay_requested := [false]
	finish_prompt.connect("replay_requested", func() -> void: replay_requested[0] = true)
	replay_button.pressed.emit()
	var replay_scene_ok := await _wait_for_scene(LEVEL, 180)
	_check(replay_requested[0] and replay_scene_ok,
		"Replay selects a fresh First Steps Valley scene through its completion action")
	if not replay_scene_ok:
		await _finish()
		return
	await _ticks(12)
	var safe_spawn := _level.get_node_or_null("SafeSpawn") as Node3D
	_check(safe_spawn != null and _runner.global_position.distance_to(safe_spawn.global_position) < 0.35
		and String(_runner.get("current_state")) == "Locomotion",
		"Replay returns to the valley trailhead in grounded locomotion")
	await _seed_wind_checkpoint()
	var second_completion := await _drive({"capture_prefix": "level_select_route"})
	_check(bool(second_completion.get("finish_prompt_visible", false)),
		"A fresh run can reach the Wind Overlook completion again")
	if not bool(second_completion.get("finish_prompt_visible", false)):
		await _finish()
		return

	finish_prompt = _level.get_node_or_null("WindOverlook/ValleyFinish") as CanvasLayer
	level_select_button = finish_prompt.get_node_or_null("LevelSelectButton") as TextureButton if finish_prompt != null else null
	if level_select_button == null:
		_check(false, "The second completion retains the Level Select control")
		await _finish()
		return
	var level_select_requested := [false]
	finish_prompt.connect("level_select_requested", func() -> void: level_select_requested[0] = true)
	level_select_button.pressed.emit()
	var menu_loaded := await _wait_for_scene(MAIN_MENU, 180)
	_check(level_select_requested[0] and menu_loaded,
		"Level Select returns to the title menu through the completion action")
	if menu_loaded:
		var preview: Control
		for _tick in 120:
			await process_frame
			preview = (current_scene.get("_atlas_preview") as Control) if current_scene != null else null
			if preview != null and not bool(current_scene.get("_transitioning")):
				break
		var back_button := preview.get_node_or_null("DesignCanvas/BackButton") as Control \
				if preview != null else null
		var focus_owner := root.gui_get_focus_owner()
		_check(preview != null and StringName(preview.get("selected_destination_id")) == &"first_steps"
			and back_button != null and focus_owner == back_button,
			"Atlas returns with First Steps selected and Back focused (selected %s, focus %s)"
			% [StringName(preview.get("selected_destination_id")) if preview != null else &"<missing>",
				str(focus_owner.get_path()) if focus_owner != null else "<none>"])
	else:
		_check(false, "Level Select reaches the main menu before checking the Atlas return")

	await _finish()


func _load_valley() -> bool:
	var packed := load(LEVEL) as PackedScene
	if packed == null:
		_check(false, "First Steps Valley scene loads")
		return false
	_level = packed.instantiate() as Node3D
	root.add_child(_level)
	current_scene = _level
	await _ticks(12)
	_runner = _level.get_node_or_null("ChibiRunner") as CharacterBody3D
	_check(_runner != null, "The playable valley provides ChibiRunner")
	return _runner != null


func _seed_wind_checkpoint() -> bool:
	if _level == null or _runner == null or not OS.is_debug_build():
		_check(false, "Wind Overlook regression requires its debug checkpoint start")
		return false
	_level.call("start_at_developer_section", &"debug_zone_4")
	await _ticks(2)
	var spawn := _level.get_node_or_null("WindOverlook/CheckpointArea/Spawn") as Marker3D
	var input := _runner.get("chibi_input") as Node
	if input != null:
		input.call("set_touch_mode", true)
	_check(spawn != null and String(_level.get("active_checkpoint_name")) == "Wind Overlook"
		and _runner.is_on_floor() and spawn != null
		and Vector2(_runner.global_position.x - spawn.global_position.x,
			_runner.global_position.z - spawn.global_position.z).length() < 0.15
		and absf(angle_difference(float(_runner.get("camera_ctrl").get("yaw")), -PI / 2.0)) < 0.05,
		"debug_zone_4 seeds the grounded Wind Overlook spawn facing +X")
	return spawn != null and _runner.is_on_floor()


func _drive(options: Dictionary) -> Dictionary:
	return await _driver.call("drive_from_zip_exit", self, _level, _runner,
		Callable(self, "_check"), _capture_dir, options)


func _retry_and_check(label: String) -> void:
	var spawn := _level.get_node_or_null("WindOverlook/CheckpointArea/Spawn") as Marker3D
	var controller := _level
	controller.call("retry_section")
	await _ticks(2)
	var error := _runner.global_position.distance_to(spawn.global_position) if spawn != null else INF
	_check(spawn != null and String(controller.get("active_checkpoint_name")) == "Wind Overlook"
		and error < 0.15 and String(_runner.get("current_state")) == "Locomotion"
		and _runner.get_collision_mask_value(1),
		"Standard retry after %s restores the Wind Overlook checkpoint (Δ %.3f m)"
		% [label, error])


func _wait_for_scene(path: String, limit: int) -> bool:
	for _tick in limit:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == path:
			_level = current_scene as Node3D if path == LEVEL else null
			if path == LEVEL:
				_runner = _level.get_node_or_null("ChibiRunner") as CharacterBody3D if _level != null else null
			return true
	return false


func _capture(label: String) -> void:
	if _capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		print("CAPTURE skipped for Wind Overlook %s: viewport image empty" % label)
		return
	var error := DirAccess.make_dir_recursive_absolute(_capture_dir)
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_warning("Could not create Wind Overlook capture folder %s" % _capture_dir)
		return
	var destination := _capture_dir.path_join("first_steps_wind_%s.png" % label)
	error = image.save_png(destination)
	if error == OK:
		print("CAPTURE: %s (%s)" % [destination, RenderingServer.get_video_adapter_name()])
	else:
		push_warning("Could not save Wind Overlook capture %s (error %d)" % [destination, error])


func _ticks(count: int) -> void:
	for _tick in count:
		await physics_frame
		await process_frame


func _finish() -> void:
	paused = false
	if current_scene != null and current_scene.is_inside_tree():
		current_scene.queue_free()
		await process_frame
	var audio_release_deadline := Time.get_ticks_msec() + 250
	while Time.get_ticks_msec() < audio_release_deadline:
		await process_frame
	print("=== FIRST STEPS WIND: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("PASS: ", message)
	else:
		_failed += 1
		push_error("FAIL: " + message)
