extends RefCounted

## Drives Chibi through First Steps Valley's creek with the same virtual-stick
## input path used by the touch HUD. The runner starts at SafeSpawn and is never
## repositioned during the traversal.

const LEVEL_SCENE := "res://levels/first_steps/first_steps_valley.tscn"
const WAYPOINT_REACH_RADIUS := 1.10


func run(tree: SceneTree, check: Callable) -> void:
	var packed := load(LEVEL_SCENE) as PackedScene
	if packed == null:
		check.call(false, "First Steps Valley scene loads for the creek traversal")
		return
	var level := packed.instantiate() as Node3D
	tree.root.add_child(level)
	await _ticks(tree, 8)

	var player := level.get_node_or_null("ChibiRunner") as ParkourController
	var spawn := level.get_node_or_null("SafeSpawn") as Marker3D
	var water := level.get_node_or_null("CreekWater") as WaterBody3D
	if player == null or spawn == null or water == null:
		check.call(false, "First Steps Valley exposes ChibiRunner, SafeSpawn, and CreekWater")
		level.queue_free()
		await tree.process_frame
		return

	var start := player.global_position
	var start_matches_spawn := Vector2(start.x - spawn.global_position.x, start.z - spawn.global_position.z).length() < 0.35
	check.call(start_matches_spawn and player.current_state == "Locomotion" and player.get_active_water() == null,
		"The creek traversal starts in dry locomotion at the authored valley spawn")

	player.camera_ctrl.yaw = 0.0
	player.chibi_input.set_touch_mode(true)
	var observations := {
		"saw_wading": false,
		"saw_slow_wading": false,
		"saw_swimming": false,
		"saw_walkout": false,
		"minimum_wade_cap": 99.0,
		"travel_distance": 0.0,
	}

	var dry_approach: Array[Vector2] = [Vector2(-5.0, 18.0), Vector2(-10.0, 8.0), Vector2(-15.0, 0.0), Vector2(-18.0, -8.0)]
	var reached_approach := await _drive_route(tree, player, water, dry_approach, observations)
	check.call(reached_approach and player.get_active_water() == null,
		"Real movement input follows the dry trail to the creek approach (position %s)" % str(player.global_position))

	var creek_entry: Array[Vector2] = [
		Vector2(-18.0, -10.5), Vector2(-18.0, -12.5), Vector2(-17.0, -14.5),
		Vector2(-16.0, -16.0), Vector2(-14.0, -18.0), Vector2(-8.5, -17.5),
	]
	var reached_pool := await _drive_route(tree, player, water, creek_entry, observations)
	var pool_camera_xz := Vector2(player.global_position.x, player.global_position.z)
	check.call(reached_pool and bool(observations["saw_wading"]) and bool(observations["saw_slow_wading"])
		and bool(observations["saw_swimming"]) and player.current_state == "PoolSwim"
		and player.get_active_water() == water,
		"One continuous trail walk crosses the slow wade shelf into creek swimming (wade cap %.2f, state %s, at %s)"
		% [float(observations["minimum_wade_cap"]), player.current_state, str(player.global_position)])
	check.call(float(observations["travel_distance"]) > 40.0,
		"The creek sequence is driven through in-game movement for %.1f m without respawning" % float(observations["travel_distance"]))

	if reached_pool and player.current_state == "PoolSwim" and player.get_active_water() == water:
		await _exercise_dive_and_surface(tree, player, water, check)
	else:
		check.call(false, "Chibi reaches the deep pool before the dive and surface inputs")

	var exit_route: Array[Vector2] = [
		Vector2(-2.5, -22.0), Vector2(1.0, -19.9), Vector2(5.5, -17.3), Vector2(7.0, -16.0),
	]
	var reached_exit := await _drive_route(tree, player, water, exit_route, observations)
	var dry_after_swim: bool = reached_exit and bool(observations["saw_walkout"])
	check.call(dry_after_swim and player.current_state == "Locomotion" and player.get_active_water() == null
		and player.external_walk_speed_cap >= player.config.base_run_speed - 0.01,
		"Forward stick input carries Chibi up the east bank into dry locomotion (state %s, water %s, at %s)"
		% [player.current_state, str(player.get_active_water()), str(player.global_position)])

	var before_dry_control := player.global_position
	var dry_control_route: Array[Vector2] = [Vector2(8.5, -15.0)]
	var dry_control_moved := await _drive_route(tree, player, water, dry_control_route, observations)
	var dry_distance := Vector2(player.global_position.x - before_dry_control.x,
		player.global_position.z - before_dry_control.z).length()
	check.call(dry_control_moved and dry_distance > 0.8 and player.current_state == "Locomotion"
		and player.get_active_water() == null,
		"Ground movement remains responsive after the walk-out (%.2f m on dry ground)" % dry_distance)

	var reentry_observations := {
		"saw_wading": false,
		"saw_slow_wading": false,
		"saw_swimming": false,
		"saw_walkout": false,
		"minimum_wade_cap": 99.0,
		"travel_distance": 0.0,
	}
	var reentry_route: Array[Vector2] = [Vector2(5.5, -17.3), Vector2(-2.5, -22.0), Vector2(-8.5, -17.5)]
	var reentered := await _drive_route(tree, player, water, reentry_route, reentry_observations)
	check.call(reentered and bool(reentry_observations["saw_swimming"]) and player.current_state == "PoolSwim"
		and player.get_active_water() == water,
		"The same east bank also lets Chibi wade and swim back into the creek")
	var second_exit_route: Array[Vector2] = [Vector2(1.0, -19.9), Vector2(5.5, -17.3), Vector2(7.0, -16.0)]
	var reexited := await _drive_route(tree, player, water, second_exit_route, reentry_observations)
	check.call(reexited and bool(reentry_observations["saw_walkout"]) and player.current_state == "Locomotion"
		and player.get_active_water() == null,
		"A second continuous swim back up the east ramp returns to dry ground")

	# Exercise the water-camera presentation against the creek's actual outline
	# and profile. Reuse observed water and bank coordinates from this traversal.
	await _exercise_camera_water_state(tree, level, player, water, pool_camera_xz,
		Vector2(player.global_position.x, player.global_position.z), check)

	player.chibi_input.clear_touch_input()
	level.queue_free()
	await tree.process_frame
	await tree.process_frame


func _drive_route(tree: SceneTree, player: ParkourController, water: WaterBody3D,
		waypoints: Array[Vector2], observations: Dictionary) -> bool:
	for target in waypoints:
		var tick_limit := _route_tick_limit(player, target)
		var reached := false
		for _tick in tick_limit:
			var delta := Vector2(target.x - player.global_position.x, target.y - player.global_position.z)
			if delta.length() <= WAYPOINT_REACH_RADIUS:
				reached = true
				break
			player.chibi_input.set_touch_move(delta.normalized())
			var previous := player.global_position
			await _ticks(tree, 1)
			var travelled := Vector2(player.global_position.x - previous.x,
				player.global_position.z - previous.z).length()
			observations["travel_distance"] = float(observations["travel_distance"]) + travelled
			_observe_water_state(player, water, observations)
			if player.global_position.y < -10.0:
				break
		if not reached:
			var final_delta := Vector2(target.x - player.global_position.x, target.y - player.global_position.z)
			reached = final_delta.length() <= WAYPOINT_REACH_RADIUS
		player.chibi_input.set_touch_move(Vector2.ZERO)
		await _ticks(tree, 5)
		_observe_water_state(player, water, observations)
		if not reached:
			return false
	return true


func _route_tick_limit(player: ParkourController, target: Vector2) -> int:
	var distance := Vector2(target.x - player.global_position.x, target.y - player.global_position.z).length()
	# Give the shallow swimmer more time than a dry run while keeping an accidental
	# blocked path from stalling the whole gameplay suite.
	var expected_speed := 2.0 if player.current_state == "PoolSwim" else 4.2
	if player.get_active_water() != null and player.current_state == "Locomotion":
		expected_speed = 1.5
	return clampi(ceilf(distance / expected_speed * 60.0) + 300, 180, 900)


func _observe_water_state(player: ParkourController, water: WaterBody3D, observations: Dictionary) -> void:
	var active := player.get_active_water()
	if active == water and player.current_state == "Locomotion":
		observations["saw_wading"] = true
		var cap := player.external_walk_speed_cap
		observations["minimum_wade_cap"] = minf(float(observations["minimum_wade_cap"]), cap)
		if cap < player.config.base_run_speed - 0.3:
			observations["saw_slow_wading"] = true
	if active == water and player.current_state == "PoolSwim":
		observations["saw_swimming"] = true
	if bool(observations["saw_swimming"]) and player.current_state == "Locomotion" and active == null:
		observations["saw_walkout"] = true


func _exercise_dive_and_surface(tree: SceneTree, player: ParkourController, water: WaterBody3D,
		check: Callable) -> void:
	var surface_y := water.get_surface_height()
	var center_before_dive := player.get_capsule_center().y
	player.chibi_input.set_touch_slide(true)
	await _ticks(tree, 30)
	player.chibi_input.set_touch_slide(false)
	await _ticks(tree, 3)
	var dive_depth := center_before_dive - player.get_capsule_center().y
	check.call(player.current_state == "PoolSwim" and player.get_active_water() == water
		and dive_depth > 0.30,
		"The creek dive button submerges Chibi while she stays in the same water body (%.2f m)" % dive_depth)

	player.chibi_input.set_touch_jump(true)
	await _ticks(tree, 90)
	player.chibi_input.set_touch_jump(false)
	await _ticks(tree, 5)
	var center_after_rise := player.get_capsule_center().y
	var surface_blend: float = player.anim_ctrl.anim_tree.get("parameters/Swim/SurfaceBlend/blend_amount")
	check.call(player.current_state == "PoolSwim" and player.get_active_water() == water
		and absf(center_after_rise - surface_y) < 0.28 and surface_blend > 0.45,
		"Holding Rise returns the creek swimmer to the surface pose (center %.2f, surface %.2f, blend %.2f)"
		% [center_after_rise, surface_y, surface_blend])


func _exercise_camera_water_state(tree: SceneTree, level: Node3D, player: ParkourController,
		water: WaterBody3D, pool_xz: Vector2, dry_xz: Vector2, check: Callable) -> void:
	var probe := Camera3D.new()
	probe.name = "CreekCameraStateProbe"
	level.add_child(probe)
	probe.make_current()
	var surface_y := water.get_surface_height()
	probe.global_position = Vector3(pool_xz.x, surface_y + 0.75, pool_xz.y)
	probe.reset_physics_interpolation()
	await _ticks(tree, 8)
	var dry_environment := probe.environment
	check.call(player.camera_ctrl.get_camera_water() == null,
		"A gameplay camera above the creek surface keeps its dry water state")

	probe.global_position.y = surface_y - 0.55
	probe.reset_physics_interpolation()
	await _ticks(tree, 20)
	var underwater_environment := probe.environment
	check.call(player.camera_ctrl.get_camera_water() == water and underwater_environment != null
		and underwater_environment != dry_environment and underwater_environment.fog_enabled,
		"The same camera enters the creek's underwater atmosphere below the surface")

	probe.global_position = Vector3(dry_xz.x, surface_y + 0.9, dry_xz.y)
	probe.reset_physics_interpolation()
	await _ticks(tree, 105)
	check.call(player.camera_ctrl.get_camera_water() == null and probe.environment == dry_environment,
		"Leaving the creek restores the camera's original dry environment")
	var gameplay_camera := player.camera_ctrl.active_camera as Camera3D
	if gameplay_camera != null and gameplay_camera.is_inside_tree():
		gameplay_camera.make_current()
	probe.queue_free()
	await _ticks(tree, 3)


func _ticks(tree: SceneTree, count: int) -> void:
	for _i in count:
		await tree.physics_frame
		await tree.process_frame
