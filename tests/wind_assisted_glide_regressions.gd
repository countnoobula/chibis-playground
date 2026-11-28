extends RefCounted

const PERCH_APPROACH := Vector3(25.8, 0.08, 19.45)
const TUNNEL_FALL := Vector3(16.0, 2.23, 16.0)
const DRY_FALL := Vector3(8.0, 2.23, 21.0)
const LULL := 0.8
const PEAK := 2.9

var _tree: SceneTree
var _chibi: ParkourController
var _tunnel: RooftopWindTunnel
var _check: Callable


func run(tree: SceneTree, gym: Node3D, chibi: ParkourController, check: Callable) -> void:
	_tree = tree
	_chibi = chibi
	_tunnel = gym.get_node("WindTunnel") as RooftopWindTunnel
	_check = check
	var elapsed := _tunnel.elapsed_physics
	_tunnel.set_physics_process(false)

	await _test_perch_launch()
	await _test_carry_and_steering()
	await _test_exit()
	await _test_drop_and_respawn()

	await _place(Vector3(8.0, 0.08, 15.0), elapsed)
	_tunnel.set_physics_process(true)
	_check = Callable()
	_tunnel = null
	_chibi = null
	_tree = null


func _test_perch_launch() -> void:
	await _place(PERCH_APPROACH, PEAK, PI * 0.5)
	_chibi.chibi_input.set_touch_move(Vector2.UP)
	var reached_top := false
	for frame in 145:
		await _ticks(1)
		if _chibi.is_on_floor() and _chibi.global_position.y > 2.30:
			reached_top = true
		if _chibi.can_deploy_scarf():
			break
	_check.call(reached_top and _chibi.can_deploy_scarf() and _chibi.velocity.y < 0.0
		and _tunnel.contains_point(_chibi.get_capsule_center()),
		"The rooftop ramp leads to a real walk-off launch into the wind")

	_chibi.chibi_input.set_touch_move(Vector2.ZERO)
	await _press_jump()
	var partial_load := _chibi.scarf_wind_load
	var opened_in_wind := false
	var max_carry := 0.0
	var glide := _chibi.pose_mod.scarf_glider
	var pin_samples := [0, 0]
	var skeleton := _chibi.pose_mod.get_skeleton()
	# Skeleton3D restores its base poses outside this notification.
	var sample_pins := func() -> void:
		if _chibi.scarf_glide_phase == &"glide" and _chibi.scarf_wind_load > 0.85:
			pin_samples[0] += 1
			if _loaded_canopy_pins_follow_hands(glide):
				pin_samples[1] += 1
	skeleton.skeleton_updated.connect(sample_pins)
	for frame in 66:
		await _ticks(1)
		if _chibi.scarf_glide_phase == &"glide" and _chibi.scarf_wind_load > 0.85:
			opened_in_wind = true
			max_carry = maxf(max_carry, -_chibi.velocity.z)
		if _chibi.is_on_floor():
			break
	skeleton.skeleton_updated.disconnect(sample_pins)
	_check.call(partial_load > 0.0 and partial_load < 0.25 and opened_in_wind
		and pin_samples[0] > 0 and pin_samples[1] == pin_samples[0] and max_carry > 1.9,
		"The canopy catches during deployment and carries Chibi downwind with all four hand pins (%.2f m/s)" % max_carry)
	_check.call(_chibi.is_on_floor() and _chibi.scarf_glide_phase in [&"stow", &"stowed"]
		and is_zero_approx(_chibi.scarf_wind_load),
		"The perch glide lands with its normal wrap and clears canopy load")


func _loaded_canopy_pins_follow_hands(glide: ChibiScarfGlider) -> bool:
	var targets := glide.get_corner_targets()
	var material := glide._canopy_material
	var deltas: PackedVector3Array = material.get_shader_parameter("scarf_pin_delta")
	var wind_load: float = material.get_shader_parameter("wind_load")
	if targets.size() != 4 or deltas.size() != 4 or wind_load < 0.75:
		return false
	var collapse: Vector3 = material.get_shader_parameter("collapse_center")
	var opening: float = material.get_shader_parameter("deploy_amount")
	for index in 4:
		var pinned_corner := collapse.lerp(glide._source_pin_points[index], opening) + deltas[index]
		if glide._canopy_mesh.to_global(pinned_corner).distance_to(targets[index]) > 0.025:
			return false
	return true


func _test_carry_and_steering() -> void:
	var dry := await _sample_glide(DRY_FALL, PEAK, Vector2.ZERO)
	var lull := await _sample_glide(TUNNEL_FALL, LULL, Vector2.ZERO)
	var peak := await _sample_glide(TUNNEL_FALL, PEAK, Vector2.ZERO)
	_check.call(absf(dry.z) < 0.03 and lull.z < -0.65 and lull.z > -1.15
		and peak.z < -2.0 and peak.z > -3.15 and absf(peak.y - dry.y) < 0.08
		and absf(lull.y - dry.y) < 0.08 and _chibi.flow_level < 0.005,
		"Neutral glide drifts with the lull and peak, preserving descent and earning no Flow (%.2f and %.2f m/s)"
		% [-lull.z, -peak.z])

	var side := await _sample_glide(TUNNEL_FALL, PEAK, Vector2.RIGHT)
	var side_flow := _chibi.flow_level
	var upwind := await _sample_glide(TUNNEL_FALL, PEAK, Vector2.DOWN)
	_check.call(side.x > 1.05 and absf(side.z - peak.z) < 0.15 and upwind.z > peak.z + 1.2,
		"Glide keeps camera-relative lateral steering and can counter the gust (side %.2f, upwind %.2f m/s)"
		% [side.x, upwind.z])
	_check.call(Vector2(side.x, side.z).length() > 3.2 and side_flow < 0.005,
		"Wind does not grant Flow when combined steering and carry cross the normal speed threshold")


func _test_exit() -> void:
	await _place(Vector3(17.73, TUNNEL_FALL.y, 16.0), PEAK)
	await _wait_for_deploy()
	_chibi.chibi_input.set_touch_move(Vector2.RIGHT)
	await _press_jump()
	var previous_carry := 0.0
	var largest_step := 0.0
	for frame in 43:
		await _ticks(1)
		var carry := -_chibi.velocity.z
		largest_step = maxf(largest_step, absf(carry - previous_carry))
		previous_carry = carry
		if not _tunnel.contains_point(_chibi.get_capsule_center()):
			break
	_chibi.chibi_input.set_touch_move(Vector2.ZERO)
	var exit_carry := -_chibi.velocity.z
	var cleared := (not _tunnel.contains_point(_chibi.get_capsule_center())
		and _chibi.scarf_glide_phase == &"glide" and is_zero_approx(_chibi.scarf_wind_load))
	await _ticks(4)
	_check.call(cleared and exit_carry > 0.25 and largest_step < 0.6
		and -_chibi.velocity.z > exit_carry - 0.15 and _chibi.flow_level < 0.005,
		"Steering out of the tunnel feathers the scarf load and preserves coasting momentum (%.2f m/s at exit)"
		% exit_carry)


func _test_drop_and_respawn() -> void:
	await _place(TUNNEL_FALL, PEAK)
	await _wait_for_deploy()
	await _press_jump()
	await _ticks(7)
	var caught := _chibi.scarf_wind_load > 0.15
	var before_drop := _chibi.velocity
	await _press_jump()
	var after_drop := _chibi.velocity
	_check.call(caught and _chibi.scarf_glide_phase == &"cancel"
		and is_zero_approx(_chibi.scarf_wind_load) and after_drop.y < before_drop.y - 0.1
		and after_drop.z >= before_drop.z - 0.02 and not _chibi.can_deploy_scarf()
		and _chibi.jump_buffer_timer <= 0.0,
		"Dropping a loaded scarf immediately stops wind acceleration and uses ordinary fall gravity")

	await _sample_glide(TUNNEL_FALL, PEAK, Vector2.ZERO)
	var loaded := _chibi.scarf_wind_load > 0.85
	await _place(DRY_FALL, PEAK)
	_check.call(loaded and _chibi.scarf_glide_phase == &"stowed" and is_zero_approx(_chibi.scarf_wind_load)
		and _chibi.scarf_wind_velocity.is_zero_approx() and _chibi.flow_level < 0.005,
		"Respawning during a loaded glide clears wind and scarf state")


func _sample_glide(position: Vector3, gust: float, input: Vector2) -> Vector3:
	await _place(position, gust)
	await _wait_for_deploy()
	_chibi.chibi_input.set_touch_move(input)
	await _press_jump()
	await _ticks(26)
	return _chibi.velocity


func _place(position: Vector3, gust: float, yaw: float = 0.0) -> void:
	_chibi.chibi_input.clear_touch_input()
	await _tree.physics_frame
	_tunnel.elapsed_physics = gust
	_chibi.reset_for_respawn(position)
	_chibi.rotation.y = yaw
	_chibi.camera_ctrl.yaw = yaw
	_chibi.camera_ctrl.reset_after_teleport()
	await _ticks(2)


func _wait_for_deploy() -> void:
	for frame in 16:
		if _chibi.can_deploy_scarf():
			return
		await _ticks(1)


func _press_jump() -> void:
	_chibi.chibi_input.set_touch_jump(true)
	await _ticks(2)
	_chibi.chibi_input.set_touch_jump(false)


func _ticks(count: int) -> void:
	for frame in count:
		await _tree.physics_frame
