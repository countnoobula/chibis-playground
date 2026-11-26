extends SceneTree

## Focused end-to-end checks for the roofed swim tunnel and the real gameplay camera.
## Run with the Godot 4.7 console executable using --headless --path <project> --script
## res://tests/test_tower_tunnel_camera.gd

const GYM_SCENE := "res://scenes/gym/rooftop_parkour_gym.tscn"
const CAMERA_ARM_MAX := 1.70
const TUNNEL_CROWN_PROBE := Vector3(31.3, 1.50, -35.95)
const TUNNEL_MIDPOINT := Vector3(31.3, -0.05, -35.95)
const TUNNEL_ZONE5_SEAM := Vector3(27.2, -0.05, -34.90)
const DROP_WATER_SEAM := Vector3(35.3, -0.05, -37.50)
const POOL_TUNNEL_START_POSITION := Vector3(25.35, 0.0, -34.90)

var _gym: RooftopGymController
var _runner: ParkourController
var _pool_water: WaterBody3D
var _drop_water: WaterBody3D
var _tunnel_water: WaterBody3D
var _camera: Camera3D
var _failures := 0
var _checks := 0
var _camera_override_before: Environment


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(GYM_SCENE) as PackedScene
	_check(packed != null, "The normal rooftop gym scene loads")
	if packed == null:
		_finish()
		return

	_gym = packed.instantiate() as RooftopGymController
	root.add_child(_gym)
	_runner = _gym.get_node_or_null("ChibiRunner") as ParkourController
	var pool := _gym.get_node_or_null("Zone5_SlopedSwimPool") as ChibiPool
	_pool_water = pool.water_body if pool != null else null
	_drop_water = _gym.get_node_or_null("TowerDropCourse/DropWater") as WaterBody3D
	_tunnel_water = _gym.get_node_or_null("TowerDropCourse/TunnelWater") as WaterBody3D
	_camera = _runner.get_node_or_null("MainCamera3D") as Camera3D if _runner != null else null
	if _runner == null or _pool_water == null or _drop_water == null or _tunnel_water == null or _camera == null:
		_check(false, "Rooftop player, gameplay camera, Zone 5 water, drop water, and tunnel water are all present")
		await _finish()
		return

	_camera.make_current()
	_runner.camera_ctrl.active_camera = _camera
	await _ticks(6)
	_camera_override_before = _camera.environment
	_check(_camera.get_viewport().get_camera_3d() == _camera,
		"The camera-water checks observe Chibi's live gameplay Camera3D")
	_check(_pool_water != _drop_water and _tunnel_water != _pool_water and _tunnel_water != _drop_water,
		"Zone 5, the tower drop well, and the roofed tunnel use distinct water volumes")
	_check(absf(_tunnel_water.get_surface_height() - 1.45) < 0.03
		and _tunnel_water.has_method("get_volume_ceiling_height")
		and absf(float(_tunnel_water.call("get_volume_ceiling_height")) - 1.05) < 0.05,
		"Tunnel water keeps its 1.45 m surface and 1.05 m roof underside")
	_check(WaterBody3D.find_at(_runner, TUNNEL_MIDPOINT) == _tunnel_water,
		"The submerged tunnel centerline selects TunnelWater")
	_check(WaterBody3D.find_at(_runner, TUNNEL_ZONE5_SEAM) == _tunnel_water
		and WaterBody3D.find_at(_runner, DROP_WATER_SEAM) == _drop_water,
		"Both tunnel seams overlap their adjoining water volumes")
	_check(WaterBody3D.find_at(_runner, TUNNEL_CROWN_PROBE) == null,
		"The cap probe above the tunnel waterline stays dry")
	_check(runner_camera_is_dry(), "The gameplay camera starts with the dry environment")

	# Begin in Zone 5, then use the real camera-relative swim input to cross into the tunnel.
	var pool_spawn := POOL_TUNNEL_START_POSITION
	pool_spawn.y = _pool_water.get_surface_height() - 1.03
	_runner.reset_for_respawn(pool_spawn)
	_runner.camera_ctrl.yaw = -PI * 0.5 # Forward input swims toward +X, into the tunnel.
	_runner.camera_ctrl.pitch = -0.22
	_runner.camera_ctrl.reset_after_teleport()
	_runner.camera_ctrl.yaw = -PI * 0.5
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	_runner.chibi_input.set_touch_slide(false)
	_runner.chibi_input.set_touch_jump(false)
	await _ticks(12)
	_check(_runner.current_state == "PoolSwim" and _runner.get_active_water() == _pool_water,
		"Chibi begins swimming in the existing Zone 5 pool")

	_runner.chibi_input.set_touch_slide(true) # Dive beneath the low roof.
	var reached_tunnel := await _swim_segment(Vector3(29.0, 0.0, -34.90), 240)
	_check(reached_tunnel and _runner.current_state == "PoolSwim"
		and _runner.get_active_water() == _tunnel_water,
		"Held forward swim carries Chibi from Zone 5 into TunnelWater")
	if not reached_tunnel:
		_runner.chibi_input.set_touch_move(Vector2.ZERO)
		_runner.chibi_input.set_touch_slide(false)
		await _finish()
		return

	# Turn the view and look sharply upward while the swimmer remains below the cap.
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	_runner.camera_ctrl.apply_look(Vector2(-0.55, -2.0))
	await _ticks(48)
	_assert_tunnel_camera("turning and looking up")
	_check(_camera.global_position.y <= float(_tunnel_water.call("get_volume_ceiling_height")) + 0.12,
		"The live camera stays below the tunnel roof during an upward look")

	# Recenter the camera and continue forward through the enclosed part of the route.
	var reached_far_end := await _swim_segment(Vector3(34.2, 0.0, -37.10), 260)
	_check(reached_far_end and _runner.current_state == "PoolSwim",
		"Forward swim continues through the roofed tunnel without leaving PoolSwim")
	_assert_tunnel_camera("forward travel under the roof")
	var reached_drop_pool := await _swim_segment(Vector3(35.4, 0.0, -37.50), 120)
	_check(reached_drop_pool and _runner.current_state == "PoolSwim"
		and _runner.get_active_water() == _drop_water,
		"Forward swim crosses the tunnel's far seam into the separate DropWater pool")

	# Reverse from DropWater through the tunnel, then return to the existing Zone 5 pool.
	var reversed_into_tunnel := await _swim_segment(Vector3(32.8, 0.0, -36.60), 220)
	var saw_reverse_tunnel := reversed_into_tunnel and _runner.get_active_water() == _tunnel_water
	_check(saw_reverse_tunnel,
		"Reverse swim crosses the DropWater seam into the submerged TunnelWater")
	_assert_tunnel_camera("reverse travel under the roof")
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	_runner.camera_ctrl.apply_look(Vector2(0.30, -0.55))
	await _ticks(42)
	_assert_tunnel_camera("turning upward during the reverse swim")
	var reversed_to_midpoint := await _swim_segment(Vector3(31.3, 0.0, -35.95), 120)
	_check(reversed_to_midpoint and _runner.get_active_water() == _tunnel_water,
		"The reverse swim holds TunnelWater while crossing its center")
	var reversed_to_pool_mouth := await _swim_segment(Vector3(28.8, 0.0, -34.90), 220)
	var returned_to_pool := await _swim_segment(POOL_TUNNEL_START_POSITION, 180)
	var reached_pool_again := _runner.global_position.x <= 25.85 and _runner.get_active_water() == _pool_water
	_check(reversed_to_pool_mouth and returned_to_pool and reached_pool_again and _runner.current_state == "PoolSwim"
		and _runner.get_active_water() == _pool_water,
		"The return swim hands Chibi back to the existing Zone 5 water")

	# Leave the tunnel for the basin's real walk-in shore using Rise and forward swim input.
	_runner.chibi_input.set_touch_slide(false)
	_runner.chibi_input.set_touch_jump(true)
	_runner.camera_ctrl.yaw = PI # Forward input travels +Z from the deep end toward the entry ramp.
	_runner.chibi_input.set_touch_move(Vector2.UP)
	var reached_dry_shore := false
	for _i in 760:
		await _ticks(1)
		if _runner.current_state == "Locomotion" and _runner.get_active_water() == null:
			reached_dry_shore = true
			break
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	_runner.chibi_input.set_touch_jump(false)
	_check(reached_dry_shore,
		"Held Rise and forward swim return Chibi from the tunnel through Zone 5 to dry shore")
	await _ticks(90)
	_check(runner_camera_is_dry(),
		"Leaving both connected water bodies restores the gameplay camera's original dry environment")

	await _finish()


func _assert_tunnel_camera(phase: String) -> void:
	var camera_water := _runner.camera_ctrl.get_camera_water()
	_check(camera_water == _tunnel_water,
		"The live gameplay camera sees TunnelWater while " + phase)
	var arm_length := _runner.camera_ctrl.parkour_pcam.spring_length
	_check(arm_length <= CAMERA_ARM_MAX,
		"The gameplay camera arm shortens under the roof while " + phase + " (%.2f m)" % arm_length)
	_check(_camera.environment != null and _camera.environment != _camera_override_before
		and _camera.environment.fog_enabled
		and _camera.environment.fog_mode == Environment.FOG_MODE_DEPTH
		and _camera.environment.fog_density > 0.20
		and _camera.environment.fog_depth_end < 25.0,
		"The underwater camera uses its water haze while " + phase)


func _swim_segment(target: Vector3, max_ticks: int) -> bool:
	var start := _runner.global_position
	var direction := Vector2(target.x - start.x, target.z - start.z)
	if direction.length_squared() <= 0.001:
		return true
	direction = direction.normalized()
	_runner.camera_ctrl.yaw = atan2(-direction.x, -direction.y)
	_runner.chibi_input.set_touch_move(Vector2.UP)
	var target_distance := Vector2(target.x - start.x, target.z - start.z).length()
	var travelled := 0.0
	for _i in max_ticks:
		await _ticks(1)
		travelled = Vector2(_runner.global_position.x - start.x, _runner.global_position.z - start.z).dot(direction)
		if travelled >= target_distance:
			break
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	return travelled >= target_distance - 0.10


func runner_camera_is_dry() -> bool:
	return _runner.camera_ctrl.get_camera_water() == null \
		and _camera.environment == _camera_override_before


func _ticks(count: int) -> void:
	for _i in count:
		await physics_frame
		await process_frame


func _check(passed: bool, message: String) -> void:
	_checks += 1
	if passed:
		print("[PASS] ", message)
	else:
		_failures += 1
		printerr("[FAIL] ", message)


func _finish() -> void:
	if is_instance_valid(_gym):
		_gym.queue_free()
		await process_frame
		await process_frame
	print("Tower tunnel camera checks: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
