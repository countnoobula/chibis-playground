extends SceneTree

## Runnable First Steps crossing traversal. The first route starts at SafeSpawn
## and uses the touch stick throughout; later attempts use the authored section
## checkpoint. Optional Vulkan captures are enabled with
## CHIBI_DRY_CROSSING_CAPTURE_DIR during a non-headless run.
##
## Godot_v4.7.2-stable_win64_console.exe --fixed-fps 60 --headless --path . --script res://tests/test_first_steps_dry_crossing.gd
## Exported pack: Godot_v4.7.2-stable_win64_console.exe --fixed-fps 60 --headless --main-pack <game.pck> --script <absolute path to this file>

const LEVEL := "res://levels/first_steps/first_steps_valley.tscn"
const APPROACH := [
	Vector2(-5.0, 18.0), Vector2(-10.0, 8.0), Vector2(-15.0, 0.0),
	Vector2(-18.0, -8.0), Vector2(-21.0, -11.0), Vector2(-23.5, -13.5),
	Vector2(-22.5, -16.0),
]
const SWIM_EXIT := [
	Vector3(-6.8, 0.0, -18.7), Vector3(-2.5, 0.0, -22.0),
	Vector3(1.0, 0.0, -19.9), Vector3(5.5, 0.0, -17.3), Vector3(7.0, 0.0, -16.0),
]

var _passed := 0
var _failed := 0
var _capture_dir := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.physics_ticks_per_second = 60
	_capture_dir = OS.get_environment("CHIBI_DRY_CROSSING_CAPTURE_DIR").strip_edges()
	var packed := load(LEVEL) as PackedScene
	if packed == null:
		_check(false, "First Steps Valley scene loads")
		quit(1)
		return
	var level := packed.instantiate() as Node3D
	root.add_child(level)
	await _ticks(12)

	var player := level.get_node_or_null("ChibiRunner") as CharacterBody3D
	var water := level.get_node_or_null("CreekWater")
	var course := level.get_node_or_null("DryCrossing") as Node3D
	if player == null or water == null or course == null:
		_check(false, "Valley exposes ChibiRunner, CreekWater and DryCrossing")
		level.queue_free()
		await process_frame
		quit(1)
		return
	var input: Node = player.get("chibi_input") as Node
	var camera: Node = player.get("camera_ctrl") as Node
	var section_start := course.get_node("SectionStart") as Node3D
	var developer_start := course.get_node("DeveloperStart") as Node3D
	var checkpoint_spawn := course.get_node("CheckpointArea/Spawn") as Node3D
	var root_obstacle := course.get_node("VaultRoot") as Node3D
	var boulder_a := course.get_node("BoulderHopA") as Node3D
	var boulder_b := course.get_node("BoulderHopB") as Node3D
	var balance_log := course.get_node("BalanceLog") as Node3D
	var dry_exit := course.get_node("DryExit") as Node3D
	if input == null or camera == null:
		_check(false, "Runner exposes its touch input and chase camera controls")
		quit(1)
		return
	input.call("set_touch_mode", true)

	var safe_spawn := level.get_node("SafeSpawn") as Node3D
	var start := player.global_position
	_check(start.distance_to(safe_spawn.global_position) < 0.35
		and String(player.get("current_state")) == "Locomotion"
		and player.call("get_active_water") == null,
		"Chibi starts in dry locomotion at the authored trailhead spawn")
	for point in APPROACH:
		var waypoint := Vector3(point.x, player.global_position.y, point.y)
		if not await _drive_to_point(player, input, camera, waypoint, 0.9, 1500):
			push_error("Trailhead approach stopped at %s while targeting %s" % [str(player.global_position), str(point)])
			break
	input.call("set_touch_move", Vector2.ZERO)
	await _ticks(8)
	var approach_distance := Vector2(player.global_position.x - start.x,
		player.global_position.z - start.z).length()
	var checkpoint_transform: Transform3D = level.get("active_checkpoint_transform")
	_check(approach_distance > 45.0 and String(player.get("current_state")) != "PoolSwim"
		and String(level.get("active_checkpoint_name")) == "Dry Crossing"
		and checkpoint_transform.origin.distance_to(checkpoint_spawn.global_position) < 0.08,
		"Continuous stick input walks from the trailhead into the dry crossing checkpoint (%.1f m, %s)"
		% [approach_distance, str(player.global_position)])
	_check(player.call("get_active_water") == null
		and player.global_position.distance_to(section_start.global_position) < 1.25,
		"The crossing checkpoint is on dry ground at its authored section start")

	await _verify_retry(level, player, input, camera, checkpoint_spawn, "checkpoint entry")
	await _run_forward_until_x(player, input, camera, root_obstacle.global_position.x - 1.4, 180)
	await _verify_retry(level, player, input, camera, checkpoint_spawn, "vault approach")

	var first_hop := await _drive_course(player, input, camera, water, root_obstacle,
		boulder_a, boulder_b, balance_log, dry_exit, 0, 2, false)
	_check(bool(first_hop.get("vault", false)) and bool(first_hop.get("vault_landing", false))
		and bool(first_hop.get("boulder_a", false)),
		"SpeedVault and the first hop land on the marked BoulderHopA top")
	await _verify_retry(level, player, input, camera, checkpoint_spawn, "first boulder landing")

	var clean := await _drive_course(player, input, camera, water, root_obstacle,
		boulder_a, boulder_b, balance_log, dry_exit, 0, 0, true)
	_check(bool(clean.get("vault", false)) and bool(clean.get("vault_landing", false)),
		"SpeedVault clears the root and lands on the far-side footing")
	_check(bool(clean.get("boulder_a", false)),
		"The first hop lands on BoulderHopA's top marker at %s" % str(clean.get("boulder_a_position", Vector3.ZERO)))
	_check(bool(clean.get("boulder_b", false)),
		"The second hop lands on BoulderHopB's top marker at %s" % str(clean.get("boulder_b_position", Vector3.ZERO)))
	_check(bool(clean.get("beam", false)) and bool(clean.get("beam_traversed", false))
		and String(balance_log.get_script().resource_path).ends_with("/features/stations/parkour_balance_beam.gd"),
		"The shared balance beam supports Chibi across the creek")
	_check(bool(clean.get("finish", false)) and String(player.get("current_state")) == "Locomotion"
		and player.is_on_floor() and player.call("get_active_water") == null,
		"Continuous forward input carries Chibi from the log to DryExit")
	await _verify_retry(level, player, input, camera, checkpoint_spawn, "dry finish")

	# Retry while wet, then repeat the same miss and recover without a reset.
	var first_miss := await _drive_course(player, input, camera, water, root_obstacle,
		boulder_a, boulder_b, balance_log, dry_exit, 2, 0, false)
	_check(bool(first_miss.get("miss_swum", false)), "A deliberate first-hop miss drops Chibi into CreekWater swimming")
	await _verify_retry(level, player, input, camera, checkpoint_spawn, "fall into water")
	var first_recovery := await _drive_course(player, input, camera, water, root_obstacle,
		boulder_a, boulder_b, balance_log, dry_exit, 2, 0, false)
	var first_serial := int(player.get("wind_reset_serial"))
	var first_shore := await _swim_to_dry_exit(player, input, camera, water, dry_exit)
	_check(bool(first_recovery.get("miss_swum", false)) and first_shore
		and int(player.get("wind_reset_serial")) == first_serial,
		"The first-hop miss swims to shore and rejoins DryExit without a reset")
	await _verify_retry(level, player, input, camera, checkpoint_spawn, "first-hop recovery")

	var second_miss := await _drive_course(player, input, camera, water, root_obstacle,
		boulder_a, boulder_b, balance_log, dry_exit, 3, 0, false)
	var second_serial := int(player.get("wind_reset_serial"))
	var second_shore := await _swim_to_dry_exit(player, input, camera, water, dry_exit)
	_check(bool(second_miss.get("miss_swum", false)) and second_shore
		and int(player.get("wind_reset_serial")) == second_serial,
		"The second-hop miss swims to shore and rejoins DryExit without a reset")
	await _verify_retry(level, player, input, camera, checkpoint_spawn, "second-hop recovery")

	var log_miss := await _drive_course(player, input, camera, water, root_obstacle,
		boulder_a, boulder_b, balance_log, dry_exit, 5, 0, false)
	var log_serial := int(player.get("wind_reset_serial"))
	var log_shore := await _swim_to_dry_exit(player, input, camera, water, dry_exit)
	_check(bool(log_miss.get("miss_swum", false)) and log_shore
		and int(player.get("wind_reset_serial")) == log_serial,
		"Walking off the log's west end reaches the creek; swimming returns Chibi to DryExit")
	await _verify_retry(level, player, input, camera, checkpoint_spawn, "log recovery")

	if OS.is_debug_build():
		level.call("start_at_developer_section")
		await _ticks(2)
		_check(player.global_position.distance_to(developer_start.global_position) < 0.08,
			"Developer start moves Chibi to the authored dry crossing marker")
		await _verify_retry(level, player, input, camera, developer_start, "developer start")

	input.call("clear_touch_input")
	level.queue_free()
	await process_frame
	print("=== DRY CROSSING: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("PASS: ", message)
	else:
		_failed += 1
		push_error("FAIL: " + message)


func _ticks(count: int) -> void:
	for _tick in count:
		await physics_frame
		await process_frame


func _drive_course(player: CharacterBody3D, input: Node, camera: Node, water: Object,
		root_obstacle: Node3D, boulder_a: Node3D, boulder_b: Node3D,
		balance_log: Node3D, dry_exit: Node3D, miss_jump: int,
		stop_after_landing: int, capture: bool) -> Dictionary:
	var landing_a := boulder_a.get_node("Landing") as Node3D
	var landing_b := boulder_b.get_node("Landing") as Node3D
	var result := {"vault": false, "vault_landing": false, "boulder_a": false,
		"boulder_b": false, "beam": false, "beam_traversed": false, "finish": false,
		"miss_swum": false, "boulder_a_position": Vector3.ZERO, "boulder_b_position": Vector3.ZERO}
	var beam_script := balance_log.get_script() as Script
	_check(beam_script != null and beam_script.resource_path.ends_with("/features/stations/parkour_balance_beam.gd"),
		"BalanceLog is the shared ParkourBalanceBeam scene")
	var takeoff_x := root_obstacle.global_position.x - 1.30
	var vault_landing_x := root_obstacle.global_position.x + 1.20
	var boulder_a_landing_x := landing_a.global_position.x - 0.85
	var boulder_b_landing_x := landing_b.global_position.x - 0.95
	var jumps := 0
	var jump_held := false
	var saw_beam := false
	var beam_start_x := 0.0
	var max_beam_x := -INF
	var miss_started := false
	var pool_target := Vector3(-6.8, 0.0, -18.7)
	input.call("clear_touch_input")
	await _ticks(15)
	input.call("set_touch_move", Vector2(0.0, -1.0))

	for _tick in 720:
		var x := player.global_position.x
		var state := String(player.get("current_state"))
		var grounded := player.is_on_floor()
		var should_press := (jumps == 0 and x >= takeoff_x) \
			or (jumps == 1 and grounded and x >= vault_landing_x) \
			or (jumps == 2 and grounded and x >= boulder_a_landing_x) \
			or (jumps == 3 and grounded and x >= boulder_b_landing_x)
		var pressed_now := should_press and not jump_held
		input.call("set_touch_jump", pressed_now)
		jump_held = should_press

		if pressed_now:
			match jumps:
				0:
					if capture:
						await _capture_chase("root_takeoff")
				1:
					result["vault_landing"] = bool(result["vault"]) and grounded \
						and x > root_obstacle.global_position.x + 0.8
					if capture:
						await _capture_chase("root_landing")
				2:
					result["boulder_a"] = grounded and _at_landing(player, landing_a, 0.80)
					result["boulder_a_position"] = player.global_position
					if capture:
						await _capture_chase("boulder_a_landing")
					if stop_after_landing == 2:
						input.call("set_touch_jump", false)
						break
				3:
					result["boulder_b"] = grounded and _at_landing(player, landing_b, 0.82)
					result["boulder_b_position"] = player.global_position
					if capture:
						await _capture_chase("boulder_b_landing")
			jumps += 1
			if miss_jump == jumps:
				miss_started = true

		if state == "SpeedVault":
			result["vault"] = true
		if state == "BalanceBeam" and player.call("has_balance_footing"):
			if not saw_beam:
				saw_beam = true
				beam_start_x = player.global_position.x
				if capture:
					await _capture_chase("balance_log_landing")
			max_beam_x = maxf(max_beam_x, player.global_position.x)
			if max_beam_x - beam_start_x > 0.90:
				result["beam_traversed"] = true
			result["beam"] = true
		if String(player.get("current_state")) == "PoolSwim" and player.call("get_active_water") == water:
			result["miss_swum"] = miss_started
			if miss_started:
				break
		if miss_jump == 5 and saw_beam and not miss_started:
			if state == "BalanceBeam":
				input.call("set_touch_move", Vector2(0.0, 1.0))
			else:
				miss_started = true
		if miss_started:
			if (jumps == 2 and x < -15.0) or (jumps == 3 and x < -11.0):
				input.call("set_touch_move", Vector2(-0.84, -0.55))
			else:
				_set_toward(player, input, camera, pool_target)
		elif miss_jump != 5 or not saw_beam:
			input.call("set_touch_move", Vector2(0.0, -1.0))

		if miss_jump == 0 and x >= dry_exit.global_position.x \
				and String(player.get("current_state")) == "Locomotion" and grounded:
			result["finish"] = player.call("get_active_water") == null
			break
		if player.global_position.y < -5.0:
			break
		await _ticks(1)

	input.call("set_touch_jump", false)
	input.call("set_touch_move", Vector2.ZERO)
	await _ticks(5)
	return result


func _at_landing(player: CharacterBody3D, marker: Node3D, tolerance: float) -> bool:
	var planar := Vector2(player.global_position.x - marker.global_position.x,
		player.global_position.z - marker.global_position.z).length()
	var height := player.global_position.y - marker.global_position.y
	return planar <= tolerance and height >= -0.20 and height <= 0.52


func _verify_retry(controller: Node, player: CharacterBody3D, input: Node,
		camera: Node, spawn: Node3D, label: String) -> void:
	input.call("clear_touch_input")
	controller.call("retry_section")
	var position_error := player.global_position.distance_to(spawn.global_position)
	var target_yaw := spawn.global_basis.get_euler().y
	var player_yaw_error := absf(angle_difference(player.global_rotation.y, target_yaw))
	var camera_yaw_error := absf(angle_difference(float(camera.get("yaw")), target_yaw))
	await _ticks(24)
	var planar_error := Vector2(player.global_position.x - spawn.global_position.x,
		player.global_position.z - spawn.global_position.z).length()
	_check(position_error < 0.08 and planar_error < 0.08 and player_yaw_error < 0.03
		and camera_yaw_error < 0.03 and String(player.get("current_state")) == "Locomotion"
		and player.call("get_active_water") == null and player.is_on_floor(),
		"Retry after %s restores the authored spawn, heading, camera and dry footing (%.2f m, yaw %.3f/%.3f)"
		% [label, position_error, player_yaw_error, camera_yaw_error])


func _swim_to_dry_exit(player: CharacterBody3D, input: Node, camera: Node,
		water: Object, dry_exit: Node3D) -> bool:
	var swam: bool = String(player.get("current_state")) == "PoolSwim" and player.call("get_active_water") == water
	for target in SWIM_EXIT:
		if not await _drive_to_point(player, input, camera, target, 0.85, 560):
			return false
	var bank_reached: bool = swam and player.call("get_active_water") == null \
		and String(player.get("current_state")) == "Locomotion" and player.is_on_floor()
	if not bank_reached:
		return false
	# Join the dry end of the authored route and prove ordinary ground movement
	# remains available after swimming out.
	return await _drive_to_point(player, input, camera, dry_exit.global_position, 0.95, 500) \
		and player.call("get_active_water") == null and String(player.get("current_state")) == "Locomotion" \
		and player.is_on_floor()


func _drive_to_point(player: CharacterBody3D, input: Node, camera: Node,
		target: Vector3, tolerance: float, max_ticks: int) -> bool:
	for _tick in max_ticks:
		var delta := Vector2(target.x - player.global_position.x, target.z - player.global_position.z)
		if delta.length() <= tolerance:
			input.call("set_touch_move", Vector2.ZERO)
			await _ticks(4)
			return true
		_set_toward(player, input, camera, target)
		await _ticks(1)
		if player.global_position.y < -5.0:
			break
	input.call("set_touch_move", Vector2.ZERO)
	return Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length() <= tolerance


func _run_forward_until_x(player: CharacterBody3D, input: Node, camera: Node,
		target_x: float, max_ticks: int) -> void:
	for _tick in max_ticks:
		if player.global_position.x >= target_x:
			input.call("set_touch_move", Vector2.ZERO)
			return
		_set_world_move(input, camera, Vector3.RIGHT)
		await _ticks(1)
	input.call("set_touch_move", Vector2.ZERO)


func _set_toward(player: CharacterBody3D, input: Node, camera: Node, target: Vector3) -> void:
	var delta := target - player.global_position
	delta.y = 0.0
	_set_world_move(input, camera, delta)


func _set_world_move(input: Node, camera: Node, direction: Vector3) -> void:
	var planar := Vector3(direction.x, 0.0, direction.z)
	if planar.length_squared() < 0.0001:
		input.call("set_touch_move", Vector2.ZERO)
		return
	planar = planar.normalized()
	var basis := Basis(Vector3.UP, float(camera.get("yaw")))
	var forward := -basis.z
	var right := basis.x
	input.call("set_touch_move", Vector2(planar.dot(right), -planar.dot(forward)))


func _capture_chase(label: String) -> void:
	if _capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		print("CAPTURE skipped for %s: viewport image empty" % label)
		return
	var error := DirAccess.make_dir_recursive_absolute(_capture_dir)
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_warning("Could not create capture folder %s" % _capture_dir)
		return
	var destination := _capture_dir.path_join("dry_crossing_%s.png" % label)
	error = image.save_png(destination)
	if error == OK:
		print("CAPTURE: %s (%s)" % [destination, RenderingServer.get_video_adapter_name()])
	else:
		push_warning("Could not save capture %s (error %d)" % [destination, error])
