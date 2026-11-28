extends RefCounted

## Continuous virtual-stick route from the Canopy Gap shelf checkpoint.
## The caller seeds the live checkpoint; this driver never teleports or retries.

const FORWARD_STICK := Vector2(0.0, -1.0)
const JUMP_START_OFFSET := 1.85
const ZIP_JUMP_START_OFFSET := 0.30
const APPROACH_LIMIT_TICKS := 140
const SWING_RELEASE_LIMIT_TICKS := 150
const LANDING_LIMIT_TICKS := 180
const ZIP_MOUNT_LIMIT_TICKS := 110
const ZIP_RIDE_LIMIT_TICKS := 180
const FINISH_LIMIT_TICKS := 160


func drive_from_shelf(
		tree: SceneTree,
		level: Node3D,
		runner: CharacterBody3D,
		check: Callable,
		capture_dir: String = "",
		options: Dictionary = {}
) -> Dictionary:
	var result := {
		"ok": false,
		"caught": false,
		"released": false,
		"landed": false,
		"zip_mounted": false,
		"zip_dismounted": false,
		"finish_grounded": false,
		"start": Vector3.ZERO,
		"approach_z_offset": 0.0,
		"swing_catch": Vector3.ZERO,
		"swing_release": Vector3.ZERO,
		"release_angle": 0.0,
		"release_ang_vel": 0.0,
		"swing_ticks": 0,
		"landing": Vector3.ZERO,
		"zip_catch": Vector3.ZERO,
		"zip_progress": 0.0,
		"zip_dismount": Vector3.ZERO,
		"finish": Vector3.ZERO,
		"states": [],
	}
	var route := level.get_node_or_null("CanopyGap") as Node3D
	var shelf := level.get_node_or_null("RootLedges/MantleShelf") as StaticBody3D
	var developer_start := route.get_node_or_null("DeveloperStart") as Marker3D if route != null else null
	var spawn := route.get_node_or_null("CheckpointArea/Spawn") as Marker3D if route != null else null
	var swing := route.get_node_or_null("Swing") as Node3D if route != null else null
	var landing_pad := route.get_node_or_null("ReleaseLandingPad") as StaticBody3D if route != null else null
	var landing_marker := route.get_node_or_null("ReleaseLanding") as Marker3D if route != null else null
	var zip_line := route.get_node_or_null("ZipLine") as Node3D if route != null else null
	var zip_catch := route.get_node_or_null("ZipCatch") as Marker3D if route != null else null
	var finish_marker := route.get_node_or_null("CanopyGapFinish") as Marker3D if route != null else null
	var input := runner.get("chibi_input") as Node if runner != null else null
	var camera := runner.get("camera_ctrl") as Node if runner != null else null
	if route == null or shelf == null or developer_start == null or spawn == null or swing == null \
			or landing_pad == null or landing_marker == null or zip_line == null \
			or zip_catch == null or finish_marker == null or input == null or camera == null:
		check.call(false, "Canopy Gap driver finds its checkpoint, swing, landing pad, ZipLine, and finish")
		return result

	var start := runner.global_position
	result["start"] = start
	var start_error := start.distance_to(developer_start.global_position)
	var shelf_collision := shelf.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var shelf_local := shelf.to_local(start)
	var on_shelf := false
	if shelf_collision != null and shelf_collision.shape is BoxShape3D:
		var shelf_box := shelf_collision.shape as BoxShape3D
		on_shelf = absf(shelf_local.x) <= shelf_box.size.x * 0.5 + 0.32 \
			and absf(shelf_local.z) <= shelf_box.size.z * 0.5 + 0.32 \
			and absf(start.y - (shelf.global_position.y + shelf_box.size.y * 0.5)) < 0.34
	var camera_yaw := float(camera.get("yaw"))
	var yaw_error := absf(angle_difference(camera_yaw, -PI / 2.0))
	check.call(on_shelf and String(runner.get("current_state")) == "Locomotion" \
		and runner.is_on_floor(),
		"Canopy Gap route starts grounded on the live mantle shelf (pos %s, start marker Δ %.3f m)"
		% [str(start), start_error])
	check.call(yaw_error < 0.05,
		"Camera faces the +X canopy route from the shelf (yaw %.3f, error %.3f rad)"
		% [camera_yaw, yaw_error])
	if not on_shelf or yaw_error >= 0.05 \
			or String(runner.get("current_state")) != "Locomotion" or not runner.is_on_floor():
		return result

	input.call("set_touch_mode", true)
	input.call("clear_touch_input")
	await _ticks(tree, int(options.get("settle_ticks", 30)))
	var lateral_offset := clampf(float(options.get("approach_lateral", 0.0)), -0.65, 0.65)
	if absf(lateral_offset) > 0.01:
		var target_z := runner.global_position.z + lateral_offset
		var lateral_sign := signf(lateral_offset)
		for _tick in 48:
			var error_z := target_z - runner.global_position.z
			if absf(error_z) <= 0.11:
				break
			input.call("set_touch_move", Vector2(lateral_sign, 0.0))
			await _ticks(tree, 1)
		input.call("set_touch_move", Vector2.ZERO)
		await _ticks(tree, 10)
	result["approach_z_offset"] = runner.global_position.z - swing.global_position.z

	var swing_jump_x := float(options.get("swing_jump_x", swing.global_position.x - JUMP_START_OFFSET))
	input.call("set_touch_move", FORWARD_STICK)
	var jumped_to_swing := false
	for _tick in APPROACH_LIMIT_TICKS:
		if not jumped_to_swing and runner.global_position.x >= swing_jump_x:
			await _tap_jump(tree, input)
			jumped_to_swing = true
			(result["states"] as Array).append({"state": "JumpStart", "position": runner.global_position})
		await _ticks(tree, 1)
		var current_state := String(runner.get("current_state"))
		_record_state(result, current_state, runner.global_position)
		if current_state == "RopeSwing":
			result["caught"] = true
			result["swing_catch"] = runner.global_position
			break
		if runner.global_position.y < -4.0 or current_state == "ZipLine":
			break
	check.call(jumped_to_swing and bool(result["caught"])
			and runner.get("_active_swing") == swing and bool(swing.get("is_ridden")),
		"Running from the shelf and jumping at x %.2f catches the authored rope (state %s, pos %s, z offset %.2f m)"
		% [swing_jump_x, String(runner.get("current_state")), str(runner.global_position),
			float(result["approach_z_offset"])])
	if not bool(result["caught"]):
		input.call("clear_touch_input")
		return result
	await _capture(tree, capture_dir, str(options.get("capture_prefix", "canopy")) + "_swing_catch")
	if bool(options.get("stop_after_catch", false)):
		input.call("clear_touch_input")
		result["ok"] = true
		return result

	input.call("set_touch_move", FORWARD_STICK)
	var release_after_ticks := clampi(int(options.get("release_after_swing_ticks", 10)), 1, SWING_RELEASE_LIMIT_TICKS)
	var swing_ticks := 0
	while swing_ticks < release_after_ticks and swing_ticks < SWING_RELEASE_LIMIT_TICKS \
			and String(runner.get("current_state")) == "RopeSwing":
		await _ticks(tree, 1)
		swing_ticks += 1
		_record_state(result, String(runner.get("current_state")), runner.global_position)
	result["swing_ticks"] = swing_ticks
	result["release_angle"] = float(runner.get("_swing_angle"))
	result["release_ang_vel"] = float(runner.get("_swing_ang_vel"))
	result["swing_release"] = runner.global_position
	var release_was_live_swing: bool = String(runner.get("current_state")) == "RopeSwing" \
		and runner.get("_active_swing") == swing and bool(swing.get("is_ridden"))
	if release_was_live_swing:
		await _tap_jump(tree, input)
	result["released"] = release_was_live_swing \
		and String(runner.get("current_state")) == "Locomotion" \
		and runner.get("_active_swing") == null and not bool(swing.get("is_ridden"))
	check.call(bool(result["released"]) and runner.velocity.length() > 0.2,
		"A real jump input releases the rope after %d swing ticks (angle %.3f rad, speed %.2f m/s)"
		% [swing_ticks, float(result["release_angle"]), runner.velocity.length()])
	_record_state(result, String(runner.get("current_state")), runner.global_position)
	await _capture(tree, capture_dir, str(options.get("capture_prefix", "canopy")) + "_swing_release")
	if not bool(result["released"]):
		input.call("clear_touch_input")
		return result
	if bool(options.get("stop_after_release", false)):
		input.call("clear_touch_input")
		result["ok"] = true
		return result

	input.call("set_touch_move", FORWARD_STICK)
	var landed := false
	for _tick in LANDING_LIMIT_TICKS:
		await _ticks(tree, 1)
		var current_state := String(runner.get("current_state"))
		_record_state(result, current_state, runner.global_position)
		if current_state == "Locomotion" and runner.is_on_floor():
			landed = true
			result["landing"] = runner.global_position
			break
		if runner.global_position.y < -4.0:
			break
	result["landed"] = landed
	var landing_error := runner.global_position.distance_to(landing_marker.global_position) \
		if landed else INF
	check.call(landed and _inside_landing_pad(runner.global_position, landing_pad, landing_marker),
		"The swing release lands grounded on the authored landing pad (pos %s, marker Δ %.2f m)"
		% [str(runner.global_position), landing_error])
	if not landed or not _inside_landing_pad(runner.global_position, landing_pad, landing_marker):
		input.call("clear_touch_input")
		return result
	await _capture(tree, capture_dir, str(options.get("capture_prefix", "canopy")) + "_release_landing")

	var zip_jump_x := zip_line.global_position.x - ZIP_JUMP_START_OFFSET
	var zip_jump_sent := false
	var mounted := false
	input.call("set_touch_move", FORWARD_STICK)
	for _tick in ZIP_MOUNT_LIMIT_TICKS:
		if not zip_jump_sent and runner.is_on_floor() and runner.global_position.x >= zip_jump_x:
			await _tap_jump(tree, input)
			zip_jump_sent = true
		if String(runner.get("current_state")) == "ZipLine" and runner.get("_active_line") == zip_line:
			mounted = true
			result["zip_catch"] = runner.call("get_capsule_center") as Vector3
			result["zip_progress"] = float(zip_line.get("_rider_t"))
			break
		await _ticks(tree, 1)
		_record_state(result, String(runner.get("current_state")), runner.global_position)
		if runner.global_position.y < -4.0:
			break
	result["zip_mounted"] = mounted
	var zip_catch_error: float = (runner.call("get_capsule_center") as Vector3).distance_to(zip_catch.global_position) \
		if mounted else INF
	check.call(zip_jump_sent and mounted and zip_line.get("_has_rider") \
			and zip_catch_error < 1.75,
		"Jumping from the pad reaches the descending zip catch (progress %.3f, marker Δ %.2f m, pos %s)"
		% [float(result["zip_progress"]), zip_catch_error, str(runner.global_position)])
	if not mounted:
		input.call("clear_touch_input")
		return result
	await _capture(tree, capture_dir, str(options.get("capture_prefix", "canopy")) + "_zip_catch")
	input.call("set_touch_move", Vector2.ZERO)

	var dismounted := false
	for _tick in ZIP_RIDE_LIMIT_TICKS:
		await _ticks(tree, 1)
		var current_state := String(runner.get("current_state"))
		_record_state(result, current_state, runner.global_position)
		if current_state != "ZipLine" and runner.get("_active_line") == null \
				and not bool(zip_line.get("_has_rider")):
			dismounted = true
			result["zip_dismount"] = runner.global_position
			break
	result["zip_dismounted"] = dismounted
	check.call(dismounted and String(runner.get("current_state")) == "Locomotion" \
		and runner.global_position.x > zip_catch.global_position.x,
		"The zip rider reaches the descending cable end and dismounts under its own motion (pos %s)"
		% str(runner.global_position))
	if not dismounted:
		input.call("clear_touch_input")
		return result
	await _capture(tree, capture_dir, str(options.get("capture_prefix", "canopy")) + "_zip_dismount")

	var finished_grounded := false
	input.call("set_touch_move", FORWARD_STICK)
	for _tick in FINISH_LIMIT_TICKS:
		await _ticks(tree, 1)
		var current_state := String(runner.get("current_state"))
		_record_state(result, current_state, runner.global_position)
		if current_state == "Locomotion" and runner.is_on_floor():
			finished_grounded = true
			result["finish"] = runner.global_position
			break
		if runner.global_position.y < -4.0:
			break
	result["finish_grounded"] = finished_grounded
	var finish_error := runner.global_position.distance_to(finish_marker.global_position) \
		if finished_grounded else INF
	check.call(finished_grounded and finish_error < 2.5,
		"The zip dismount finishes grounded near the authored valley landing (pos %s, marker Δ %.2f m)"
		% [str(runner.global_position), finish_error])
	if finished_grounded:
		await _capture(tree, capture_dir, str(options.get("capture_prefix", "canopy")) + "_finish")

	input.call("clear_touch_input")
	result["ok"] = bool(result["caught"]) and bool(result["released"]) \
		and bool(result["landed"]) and bool(result["zip_mounted"]) \
		and bool(result["zip_dismounted"]) and bool(result["finish_grounded"])
	return result


func _inside_landing_pad(position: Vector3, pad: StaticBody3D, marker: Marker3D) -> bool:
	var collision := pad.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or not collision.shape is BoxShape3D:
		return position.distance_to(marker.global_position) < 1.5
	var box := collision.shape as BoxShape3D
	var local_position := collision.to_local(position)
	return absf(local_position.x) <= box.size.x * 0.5 + 0.28 \
		and absf(local_position.z) <= box.size.z * 0.5 + 0.28 \
		and absf(position.y - marker.global_position.y) <= 0.34


func _record_state(result: Dictionary, state: String, position: Vector3) -> void:
	var states := result["states"] as Array
	if states.is_empty() or String(states[-1].get("state", "")) != state:
		states.append({"state": state, "position": position})


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
		print("CAPTURE skipped for Canopy Gap %s: viewport image empty" % label)
		return
	var error := DirAccess.make_dir_recursive_absolute(capture_dir)
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_warning("Could not create Canopy Gap capture folder %s" % capture_dir)
		return
	var destination := capture_dir.path_join("canopy_%s.png" % label)
	error = image.save_png(destination)
	if error == OK:
		print("CAPTURE: %s (%s)" % [destination, RenderingServer.get_video_adapter_name()])
	else:
		push_warning("Could not save Canopy Gap capture %s (error %d)" % [destination, error])
