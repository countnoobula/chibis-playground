extends RefCounted

## Reusable continuous-input transfer from the live CP9 zip exit to the Wind
## Overlook finish. The helper consumes the current runner state only; it never
## reloads, teleports, or retries. Set options.disable_field_for_runner to
## repeat the same physical route without a wind provider.

const FORWARD_STICK := Vector2(0.0, -1.0)
const STEER_STICK := Vector2.RIGHT
const APPROACH_JUMP_OFFSET := 2.3
const APPROACH_LIMIT_TICKS := 160
const BOUNCE_LIMIT_TICKS := 100
const DEPLOY_LIMIT_TICKS := 150
const FLIGHT_LIMIT_TICKS := 250
const STEER_TICKS := 8


func drive_from_zip_exit(
		tree: SceneTree,
		level: Node3D,
		runner: CharacterBody3D,
		check: Callable,
		capture_dir: String = "",
		options: Dictionary = {}
) -> Dictionary:
	var result := {
		"ok": false,
		"start": Vector3.ZERO,
		"approach_jump": Vector3.ZERO,
		"bounce": Vector3.ZERO,
		"bounce_velocity_y": 0.0,
		"glide_deploy": Vector3.ZERO,
		"field_entry": Vector3.ZERO,
		"field_exit": Vector3.ZERO,
		"landing": Vector3.ZERO,
		"finish": Vector3.ZERO,
		"field_entered": false,
		"field_exited": false,
		"landed": false,
		"landing_supported": false,
		"finish_prompt_visible": false,
		"finish_recovered_from_edge": false,
		"max_wind_load": 0.0,
		"max_runner_wind_speed": 0.0,
		"max_direct_wind_speed": 0.0,
		"wind_after_exit": Vector3.ZERO,
		"max_bank": 0.0,
		"steer_offset_z": 0.0,
		"field_ticks": 0,
		"field_provider_bound": false,
		"direct_wind_after_exit": Vector3.ZERO,
		"states": [],
	}
	var course := level.get_node_or_null("WindOverlook") as Node3D
	var trampoline := level.get_node_or_null("WindOverlook/Trampoline") as Node3D
	var field := level.get_node_or_null("WindOverlook/WindField") as Node3D
	var cue := level.get_node_or_null("WindOverlook/FoliageCue") as Node3D
	var landing := level.get_node_or_null("WindOverlook/GlideLanding") as Node3D
	var landing_pad := level.get_node_or_null("WindOverlook/LandingRootPad") as StaticBody3D
	var finish_area := level.get_node_or_null("WindOverlook/FinishArea") as Area3D
	var finish_marker := level.get_node_or_null("WindOverlook/Finish") as Node3D
	var finish_prompt := level.get_node_or_null("WindOverlook/ValleyFinish") as CanvasLayer
	var input := runner.get("chibi_input") as Node
	var camera := runner.get("camera_ctrl") as Node
	if course == null or trampoline == null or field == null or cue == null \
			or landing == null or landing_pad == null or finish_area == null or finish_marker == null \
			or finish_prompt == null or input == null or camera == null:
		check.call(false, "Wind Overlook driver finds the trampoline, bounded field, cue, landing, and finish UI")
		return result
	if not field.has_method("contains_point") or not field.has_method("flow_velocity_at"):
		check.call(false, "Wind Overlook field exposes the RunnerWindField3D query contract")
		return result

	var start := runner.global_position
	result["start"] = start
	var zip_finish := level.get_node_or_null("CanopyGap/CanopyGapFinish") as Node3D
	var developer_start := level.get_node_or_null("WindOverlook/DeveloperStart") as Node3D
	var section_start := course.get_node_or_null("SectionStart") as Node3D
	var at_zip_exit := zip_finish != null and start.distance_to(zip_finish.global_position) < 1.55
	var at_wind_checkpoint := developer_start != null and start.distance_to(developer_start.global_position) < 1.10
	var at_section_start := section_start != null and start.distance_to(section_start.global_position) < 1.10
	var yaw_error := absf(angle_difference(float(camera.get("yaw")), -PI / 2.0))
	check.call((at_zip_exit or at_wind_checkpoint or at_section_start)
		and String(runner.get("current_state")) == "Locomotion" and runner.is_on_floor(),
		"Wind route starts grounded at the live ZipExit or Wind Overlook spawn (pos %s)" % str(start))
	check.call(yaw_error < 0.42,
		"The runner camera faces the authored +X wind route (yaw %.3f, error %.3f rad)"
		% [float(camera.get("yaw")), yaw_error])
	if not (at_zip_exit or at_wind_checkpoint or at_section_start) or yaw_error >= 0.42:
		return result

	var authored_provider: Object = runner.get("wind_field")
	var disable_field := bool(options.get("disable_field_for_runner", false))
	if disable_field:
		runner.set("wind_field", null)
	else:
		result["field_provider_bound"] = authored_provider == field
		check.call(authored_provider == field,
			"The live valley binds its authored Wind Overlook provider to Chibi")
	input.call("set_touch_mode", true)
	input.call("clear_touch_input")
	await _ticks(tree, int(options.get("settle_ticks", 16)))
	var jump_x := trampoline.global_position.x - APPROACH_JUMP_OFFSET
	input.call("set_touch_move", FORWARD_STICK)
	var approach_jump_sent := false
	for _tick in APPROACH_LIMIT_TICKS:
		if not approach_jump_sent and runner.global_position.x >= jump_x:
			result["approach_jump"] = runner.global_position
			await _tap_jump(tree, input)
			approach_jump_sent = true
			(result["states"] as Array).append({"state": "ApproachJump", "position": runner.global_position})
		if float(runner.get("trampoline_cooldown")) > 0.02 \
				and float(runner.get("bounce_anim_timer")) > 0.25 \
				and runner.velocity.y > 7.5:
			break
		await _ticks(tree, 1)
		if runner.global_position.y < -3.0:
			break
	var bounced := float(runner.get("trampoline_cooldown")) > 0.02 \
		and float(runner.get("bounce_anim_timer")) > 0.25 and runner.velocity.y > 7.5
	if bounced:
		result["bounce"] = runner.global_position
		result["bounce_velocity_y"] = runner.velocity.y
		(result["states"] as Array).append({"state": "TrampolineBounce", "position": runner.global_position})
	await _capture(tree, capture_dir, _capture_name(options, "trampoline_bounce"))
	check.call(approach_jump_sent and bounced
		and float(runner.get("last_trampoline_velocity")) > 7.5,
		"A real approach jump lands on the shared trampoline and launches upward (jump %s, bounce %s, vy %.2f)"
		% [str(result["approach_jump"]), str(result["bounce"]), float(result["bounce_velocity_y"])])
	if not bounced:
		input.call("clear_touch_input")
		result["finish"] = runner.global_position
		return result

	var can_deploy := false
	for _tick in DEPLOY_LIMIT_TICKS:
		await _ticks(tree, 1)
		if runner.call("can_deploy_scarf"):
			can_deploy = true
			break
		if runner.global_position.y < -3.0:
			break
	if can_deploy:
		result["glide_deploy"] = runner.global_position
		await _tap_jump(tree, input)
	var deployed := StringName(runner.get("scarf_glide_phase")) in [&"deploy", &"glide"]
	(result["states"] as Array).append({"state": "GlideDeploy" if deployed else "NoGlide",
		"position": runner.global_position})
	await _capture(tree, capture_dir, _capture_name(options, "glide_deploy"))
	check.call(can_deploy and deployed,
		"Jump deploys the scarf only on a descending trampoline bounce (x %.2f, y %.2f, vy %.2f)"
		% [runner.global_position.x, runner.global_position.y, runner.velocity.y])
	if not deployed:
		input.call("clear_touch_input")
		result["finish"] = runner.global_position
		return result

	var direct_wind_peak := 0.0
	var runner_wind_peak := 0.0
	var load_peak := 0.0
	var bank_peak := 0.0
	var field_ticks := 0
	var entered := false
	var exited := false
	var steer_started := false
	var steer_ticks := 0
	var steer_start_z := runner.global_position.z
	var steer_end_z := runner.global_position.z
	var capture_prefix := str(options.get("capture_prefix", "wind"))
	var stop_after_field := bool(options.get("stop_after_field_sample", false))
	input.call("set_touch_move", FORWARD_STICK)
	for _tick in FLIGHT_LIMIT_TICKS:
		var in_field_before_tick := bool(field.call("contains_point", runner.call("get_capsule_center")))
		if not steer_started and in_field_before_tick \
				and StringName(runner.get("scarf_glide_phase")) == &"glide":
			steer_started = true
			steer_start_z = runner.global_position.z
			input.call("set_touch_move", STEER_STICK)
			await _capture(tree, capture_dir, capture_prefix + "_field_entry")
		await _ticks(tree, 1)
		var capsule_center: Vector3 = runner.call("get_capsule_center")
		var in_field := bool(field.call("contains_point", capsule_center))
		var direct_velocity: Vector3 = field.call("flow_velocity_at", capsule_center)
		var runner_wind_readout: Vector3 = runner.get("wind_velocity")
		direct_wind_peak = maxf(direct_wind_peak, direct_velocity.length())
		runner_wind_peak = maxf(runner_wind_peak, runner_wind_readout.length())
		load_peak = maxf(load_peak, float(runner.get("scarf_wind_load")))
		bank_peak = maxf(bank_peak, absf(float(runner.get("scarf_glide_bank"))))
		if in_field:
			field_ticks += 1
			if not entered:
				entered = true
				result["field_entry"] = runner.global_position
				(result["states"] as Array).append({"state": "WindField", "position": runner.global_position})
				await _capture(tree, capture_dir, capture_prefix + "_inside_wind")
		else:
			if entered and not exited:
				exited = true
				result["field_exit"] = runner.global_position
				await _ticks(tree, 1)
				result["wind_after_exit"] = runner.get("wind_velocity")
				result["direct_wind_after_exit"] = field.call("flow_velocity_at",
					runner.call("get_capsule_center"))
				await _capture(tree, capture_dir, capture_prefix + "_wind_exit")
		if steer_started and steer_ticks < STEER_TICKS:
			steer_ticks += 1
			if steer_ticks == STEER_TICKS:
				steer_end_z = runner.global_position.z
				input.call("set_touch_move", FORWARD_STICK)
		if stop_after_field and entered and steer_ticks >= STEER_TICKS:
			break
		if not stop_after_field and String(runner.get("current_state")) == "Locomotion" \
				and runner.is_on_floor() and deployed:
			result["landed"] = true
			result["landing"] = runner.global_position
			(result["states"] as Array).append({"state": "Landing", "position": runner.global_position})
			await _capture(tree, capture_dir, capture_prefix + "_landing")
			break
		if runner.global_position.y < -5.0:
			break

	input.call("set_touch_move", Vector2.ZERO)
	input.call("set_touch_jump", false)
	result["finish"] = runner.global_position
	result["field_entered"] = entered
	result["field_exited"] = exited
	result["field_ticks"] = field_ticks
	result["max_direct_wind_speed"] = direct_wind_peak
	result["max_runner_wind_speed"] = runner_wind_peak
	result["max_wind_load"] = load_peak
	result["max_bank"] = bank_peak
	result["steer_offset_z"] = steer_end_z - steer_start_z
	var field_is_disabled := disable_field
	if field_is_disabled:
		check.call(field_ticks > 0 and direct_wind_peak > 0.1
			and runner_wind_peak < 0.01 and load_peak < 0.01,
			"Disabled repeat crosses the live wind volume with no runner carry/load (direct %.2f m/s, runner %.2f, load %.3f)"
			% [direct_wind_peak, runner_wind_peak, load_peak])
	else:
		check.call(entered and field_ticks > 0 and direct_wind_peak > 0.1
			and runner_wind_peak > 0.1 and load_peak > 0.02,
			"The opened scarf samples positive airflow inside the authored field (direct %.2f, runner %.2f m/s, load %.3f)"
			% [direct_wind_peak, runner_wind_peak, load_peak])
	check.call(steer_started and bank_peak > 0.08 and absf(steer_end_z - steer_start_z) > 0.02,
		"A lateral stick input visibly steers and banks the in-flight scarf (bank %.2f, Δz %.2f m)"
		% [bank_peak, steer_end_z - steer_start_z])
	if stop_after_field:
		result["ok"] = bounced and deployed and entered and steer_ticks >= STEER_TICKS
		return result

	var landing_pos: Vector3 = result["landing"]
	var landing_error := landing_pos.distance_to(landing.global_position) \
		if bool(result["landed"]) else INF
	var supported_landing := _inside_landing_collider(landing_pos, landing_pad, landing.global_position, runner)
	result["landing_supported"] = supported_landing
	var wind_after_flight: Vector3 = runner.get("wind_velocity")
	check.call(bool(result["landed"]) and supported_landing,
		"Glide clears the field and lands supported by the Wind Overlook deck (landing %s, marker Δ %.2f m)"
		% [str(landing_pos), landing_error])
	var direct_exit_wind: Vector3 = result["direct_wind_after_exit"]
	check.call(exited and wind_after_flight.is_zero_approx() and direct_exit_wind.is_zero_approx(),
		"Leaving the bounded field clears both direct and runner wind readouts (exit %s, direct %s, runner %s)"
		% [str(result["field_exit"]), str(direct_exit_wind), str(wind_after_flight)])
	if bool(result["landed"]):
		await _ticks(tree, 3)
		if not finish_prompt.visible:
			var recovered := await _walk_into_finish_area(tree, runner, input, camera,
				finish_area, finish_marker, finish_prompt)
			result["finish_recovered_from_edge"] = recovered
		result["finish_prompt_visible"] = finish_prompt.visible
		check.call(finish_prompt.visible and finish_area.monitoring,
			"Grounded feet inside FinishArea open the completion prompt (edge recovery %s, pos %s)"
			% [str(result["finish_recovered_from_edge"]), str(runner.global_position)])
		await _capture(tree, capture_dir, capture_prefix + "_finish")
	result["ok"] = bounced and deployed and entered and exited and bool(result["landed"]) and supported_landing
	return result


func _inside_landing_collider(position: Vector3, pad: StaticBody3D,
		marker_position: Vector3, runner: CharacterBody3D) -> bool:
	var collision := pad.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or not collision.shape is BoxShape3D:
		return position.distance_to(marker_position) < 1.6
	var box := collision.shape as BoxShape3D
	var local_position := collision.to_local(position)
	var radius := float(runner.get("config").get("capsule_radius")) if runner.get("config") != null else 0.36
	var supported_top := box.size.y * 0.5
	return absf(local_position.x) <= box.size.x * 0.5 + radius \
		and absf(local_position.z) <= box.size.z * 0.5 + radius \
		and absf(local_position.y - supported_top) <= 0.34


func _walk_into_finish_area(tree: SceneTree, runner: CharacterBody3D, input: Node,
		camera: Node, finish_area: Area3D, finish_marker: Node3D,
		finish_prompt: CanvasLayer) -> bool:
	if input == null or camera == null:
		return false
	var walked := false
	for _tick in 120:
		if finish_prompt.visible:
			break
		if not runner.is_on_floor() or String(runner.get("current_state")) != "Locomotion":
			break
		if _finish_feet_inside_area(runner.global_position, finish_area):
			input.call("set_touch_move", Vector2.ZERO)
			await _ticks(tree, 2)
			if finish_prompt.visible:
				break
		var delta := finish_marker.global_position - runner.global_position
		delta.y = 0.0
		if delta.length() <= 0.20:
			input.call("set_touch_move", Vector2.ZERO)
			await _ticks(tree, 2)
			if finish_prompt.visible:
				break
		var planar := delta.normalized()
		var basis := Basis(Vector3.UP, float(camera.get("yaw")))
		var camera_forward := -basis.z
		var camera_right := basis.x
		input.call("set_touch_move", Vector2(planar.dot(camera_right), -planar.dot(camera_forward)))
		walked = true
		await _ticks(tree, 1)
	input.call("set_touch_move", Vector2.ZERO)
	if not finish_prompt.visible:
		await _ticks(tree, 4)
	return finish_prompt.visible and walked


func _finish_feet_inside_area(feet_position: Vector3, finish_area: Area3D) -> bool:
	var collision := finish_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or not collision.shape is BoxShape3D:
		return false
	var box := collision.shape as BoxShape3D
	var local_position := collision.to_local(feet_position)
	var half_size := box.size * 0.5
	return absf(local_position.x) <= half_size.x \
		and absf(local_position.y) <= half_size.y \
		and absf(local_position.z) <= half_size.z


func _tap_jump(tree: SceneTree, input: Node) -> void:
	input.call("set_touch_jump", true)
	await _ticks(tree, 1)
	input.call("set_touch_jump", false)


func _ticks(tree: SceneTree, count: int) -> void:
	for _tick in count:
		await tree.physics_frame
		await tree.process_frame


func _capture(tree: SceneTree, capture_dir: String, label: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := tree.root.get_texture().get_image()
	if image == null or image.is_empty():
		print("CAPTURE skipped for Wind Overlook %s: viewport image empty" % label)
		return
	var error := DirAccess.make_dir_recursive_absolute(capture_dir)
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_warning("Could not create Wind Overlook capture folder %s" % capture_dir)
		return
	var destination := capture_dir.path_join("first_steps_%s.png" % label)
	error = image.save_png(destination)
	if error == OK:
		print("CAPTURE: %s (%s)" % [destination, RenderingServer.get_video_adapter_name()])
	else:
		push_warning("Could not save Wind Overlook capture %s (error %d)" % [destination, error])


func _capture_name(options: Dictionary, suffix: String) -> String:
	return str(options.get("capture_prefix", "wind")) + "_" + suffix
