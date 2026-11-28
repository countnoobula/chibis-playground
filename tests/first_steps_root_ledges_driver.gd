extends RefCounted

## Reusable continuous-input route from the DryExit approach to the Root Ledges
## shelf. This helper assumes the valley and runner are already live; it never
## changes the runner transform, retries, or reloads the scene.

const APPROACH_JUMP_X := 5.55
const PERCH_SETTLE_TICKS := 8
const APPROACH_LIMIT_TICKS := 220
const ROUTE_LIMIT_TICKS := 600
const FORWARD_STICK := Vector2(0.0, -1.0)


func drive_from_dry_exit(tree: SceneTree, level: Node3D, runner: CharacterBody3D,
		check: Callable, capture_dir: String = "") -> Dictionary:
	var result := {
		"ok": false,
		"start": Vector3.ZERO,
		"finish": Vector3.ZERO,
		"pole_perch": Vector3.ZERO,
		"root_catch": Vector3.ZERO,
		"shelf_contact": Vector3.ZERO,
		"shelf_landing": Vector3.ZERO,
		"states": [],
		"climb_camera_active": false,
		"climb_camera_distance": 0.0,
		"climb_camera_arm": -1.0,
	}
	var input := runner.get("chibi_input") as Node
	var camera := runner.get("camera_ctrl") as Node
	var dry_exit := level.get_node_or_null("DryCrossing/DryExit") as Node3D
	var developer_start := level.get_node_or_null("RootLedges/DeveloperStart") as Node3D
	var pole_target := level.get_node_or_null("RootLedges/PolePerchTarget") as Node3D
	var root_catch := level.get_node_or_null("RootLedges/RootCatch") as Node3D
	var climbable_root := level.get_node_or_null("RootLedges/ClimbableRoot") as Node3D
	var shelf := level.get_node_or_null("RootLedges/MantleShelf") as StaticBody3D
	var shelf_landing := level.get_node_or_null("RootLedges/ShelfLanding") as Node3D
	if input == null or camera == null or dry_exit == null or developer_start == null \
			or pole_target == null or root_catch == null or climbable_root == null \
			or shelf == null or shelf_landing == null:
		check.call(false, "Root Ledges driver finds DryExit, pole, climb face, and shelf markers")
		return result

	var start := runner.global_position
	result["start"] = start
	var start_matches_dry_exit := Vector2(start.x - dry_exit.global_position.x,
		start.z - dry_exit.global_position.z).length() < 3.25
	var start_matches_debug_marker := Vector2(start.x - developer_start.global_position.x,
		start.z - developer_start.global_position.z).length() < 1.25
	var forward_yaw_error := absf(angle_difference(float(camera.get("yaw")), -PI / 2.0))
	check.call((start_matches_dry_exit or start_matches_debug_marker)
		and String(runner.get("current_state")) == "Locomotion" and runner.is_on_floor(),
		"Root Ledges route begins on the live DryExit approach or its developer checkpoint (at %s)" % str(start))
	check.call(forward_yaw_error < 0.42,
		"Runner and camera face the authored +X route (camera yaw %.3f, error %.3f rad)"
		% [float(camera.get("yaw")), forward_yaw_error])
	if not (start_matches_dry_exit or start_matches_debug_marker) or forward_yaw_error >= 0.42:
		return result

	input.call("set_touch_mode", true)
	input.call("clear_touch_input")
	await _ticks(tree, 16)
	var before_approach := runner.global_position
	input.call("set_touch_move", FORWARD_STICK)
	var jump_sent := false
	for _tick in APPROACH_LIMIT_TICKS:
		if not jump_sent and runner.global_position.x >= APPROACH_JUMP_X:
			input.call("set_touch_jump", true)
			await _ticks(tree, 1)
			input.call("set_touch_jump", false)
			jump_sent = true
			break
		await _ticks(tree, 1)
		if runner.global_position.y < -4.0:
			break
	check.call(jump_sent and runner.global_position.x >= APPROACH_JUMP_X - 0.18,
		"Continuous forward input reaches the pole launch point before the first jump (x %.2f)"
		% runner.global_position.x)
	if not jump_sent:
		input.call("clear_touch_input")
		result["finish"] = runner.global_position
		return result
	if not await _wait_for_state(tree, runner, "PolePerch", 110):
		input.call("clear_touch_input")
		check.call(false, "The first running jump lands on PolePerch (state %s, position %s, Δ %.2f m)"
			% [String(runner.get("current_state")), str(runner.global_position), runner.global_position.distance_to(before_approach)])
		result["finish"] = runner.global_position
		return result

	result["pole_perch"] = runner.global_position
	(result["states"] as Array).append({"state": "PolePerch", "position": runner.global_position})
	var perch_error := runner.global_position.distance_to(pole_target.global_position)
	check.call(perch_error < 0.22,
		"The pole jump settles on its authored top (error %.2f m at %s)"
		% [perch_error, str(runner.global_position)])
	await _capture(tree, capture_dir, "pole_perch")
	await _ticks(tree, PERCH_SETTLE_TICKS)
	input.call("set_touch_jump", true)
	await _ticks(tree, 1)
	input.call("set_touch_jump", false)
	var saw_climb := false
	var saw_mantle := false
	var camera_checked := false
	var root_catch_distance := INF
	var shelf_left_edge := shelf.global_position.x - 0.5
	var shelf_right_edge := shelf.global_position.x + 0.5
	var collision := shelf.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision != null and collision.shape is BoxShape3D:
		var box := collision.shape as BoxShape3D
		var half_x := box.size.x * 0.5 * absf(collision.global_basis.x.x)
		shelf_left_edge = shelf.global_position.x - half_x
		shelf_right_edge = shelf.global_position.x + half_x
	var last_state: String = String(runner.get("current_state"))
	input.call("set_touch_move", FORWARD_STICK)
	for _tick in ROUTE_LIMIT_TICKS:
		await _ticks(tree, 1)
		var state: String = String(runner.get("current_state"))
		if state != last_state:
			(result["states"] as Array).append({"state": state, "position": runner.global_position})
			last_state = state
		if state == "Climbing" and not saw_climb:
			saw_climb = true
			result["root_catch"] = runner.global_position
			root_catch_distance = Vector2(runner.global_position.x - root_catch.global_position.x,
				runner.global_position.z - root_catch.global_position.z).length()
			var capability: Object = climbable_root.call("get_climb_capability") \
				if climbable_root.has_method("get_climb_capability") else null
			check.call(bool(runner.call("is_wall_climbing")) and capability != null
				and root_catch_distance < 0.90
				and absf(runner.global_position.y - root_catch.global_position.y) < 1.55,
				"Jumping from the pole catches the climbable root at its authored grip (state %s, pos %s, marker Δ %.2f m)"
				% [state, str(runner.global_position), root_catch_distance])
			await _capture(tree, capture_dir, "root_catch")
		if state == "Climbing" and not camera_checked:
			camera_checked = true
			await _ticks(tree, 5)
			var active_camera := camera.get("active_camera") as Camera3D
			var camera_distance := active_camera.global_position.distance_to(runner.global_position) \
				if active_camera != null else 0.0
			var climb_arm := float(camera.get("_climb_collision_arm_length"))
			result["climb_camera_active"] = bool(camera.call("is_climbing_camera_active"))
			result["climb_camera_distance"] = camera_distance
			result["climb_camera_arm"] = climb_arm
			check.call(bool(result["climb_camera_active"]) and active_camera != null
				and camera_distance > 0.65 and (climb_arm < 0.0 or climb_arm > 0.35),
				"The climb camera stays clear of the root face (distance %.2f m, resolved arm %.2f m)"
				% [camera_distance, climb_arm])
			last_state = String(runner.get("current_state"))
			if last_state != "Climbing":
				(result["states"] as Array).append({"state": last_state,
					"position": runner.global_position})
				last_state = String(runner.get("current_state"))
		if state == "MantleUp" and not saw_mantle:
			saw_mantle = true
			await _capture(tree, capture_dir, "mantle_up")
		if state == "Locomotion" and runner.is_on_floor() and saw_mantle \
				and runner.global_position.x >= shelf_left_edge + 0.45 \
				and runner.global_position.x <= shelf_right_edge - 0.20 \
				and runner.global_position.y >= shelf_landing.global_position.y - 0.35:
			if (result["shelf_contact"] as Vector3) == Vector3.ZERO:
				result["shelf_contact"] = runner.global_position
				await _capture(tree, capture_dir, "shelf_contact")
			# Continue moving across the actual shelf after the mantle. The first
			# collision landing may be near its west lip; finish at the authored
			# ShelfLanding marker so the following section can start there.
			if runner.global_position.x >= shelf_landing.global_position.x - 0.28:
				result["shelf_landing"] = runner.global_position
				await _capture(tree, capture_dir, "shelf_landing")
				break
		if runner.global_position.y < -4.0:
			break

	input.call("set_touch_move", Vector2.ZERO)
	input.call("set_touch_jump", false)
	result["finish"] = runner.global_position
	var shelf_position: Vector3 = result["shelf_landing"]
	var initial_shelf_contact: Vector3 = result["shelf_contact"]
	var landed_on_shelf := shelf_position != Vector3.ZERO and initial_shelf_contact != Vector3.ZERO
	check.call(saw_climb and saw_mantle and landed_on_shelf
		and String(runner.get("current_state")) == "Locomotion" and runner.is_on_floor(),
		"Continuous pole → root climb → mantle input lands grounded on the shelf (states %s, final %s)"
		% [str(result["states"]), str(runner.global_position)])
	check.call(initial_shelf_contact != Vector3.ZERO
		and initial_shelf_contact.x >= shelf_left_edge + 0.35
		and initial_shelf_contact.x <= shelf_right_edge - 0.15
		and absf(initial_shelf_contact.y - shelf_landing.global_position.y) < 0.35,
		"Mantle first lands inside the physical shelf collision bounds (contact %s, bounds %.2f–%.2f)"
		% [str(initial_shelf_contact), shelf_left_edge, shelf_right_edge])
	check.call(shelf_position != Vector3.ZERO
		and absf(shelf_position.x - shelf_landing.global_position.x) < 0.55
		and absf(shelf_position.y - shelf_landing.global_position.y) < 0.35,
		"Continuous forward input walks from shelf contact to its onward landing marker (finish %s, marker %s)"
		% [str(shelf_position), str(shelf_landing.global_position)])
	check.call(not bool(camera.call("is_climbing_camera_active")),
		"Climb camera hands control back after the mantle onto the shelf")
	result["ok"] = saw_climb and saw_mantle and landed_on_shelf
	return result


func _wait_for_state(tree: SceneTree, runner: CharacterBody3D, state_name: String, limit: int) -> bool:
	for _tick in limit:
		await _ticks(tree, 1)
		if String(runner.get("current_state")) == state_name:
			return true
	return false


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
		print("CAPTURE skipped for root ledges %s: viewport image empty" % label)
		return
	var error := DirAccess.make_dir_recursive_absolute(capture_dir)
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_warning("Could not create root ledges capture folder %s" % capture_dir)
		return
	var destination := capture_dir.path_join("root_ledges_%s.png" % label)
	error = image.save_png(destination)
	if error == OK:
		print("CAPTURE: %s (%s)" % [destination, RenderingServer.get_video_adapter_name()])
	else:
		push_warning("Could not save root ledges capture %s (error %d)" % [destination, error])
