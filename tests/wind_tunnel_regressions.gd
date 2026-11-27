extends RefCounted

const OUTSIDE := Vector3(8.0, 0.08, 15.0)
const LULL := 0.8
const PEAK := 2.9

class Crosswind extends RunnerWindField3D:
	func contains_point(_point: Vector3) -> bool:
		return true

	func flow_velocity_at(_point: Vector3) -> Vector3:
		return Vector3.RIGHT * 4.0

	func get_flow_direction() -> Vector3:
		return Vector3.RIGHT

	func get_reference_speed() -> float:
		return 4.0


var _tree: SceneTree
var _chibi: ParkourController
var _tunnel: RooftopWindTunnel
var _check: Callable


func run(tree: SceneTree, gym: Node3D, chibi: ParkourController, check: Callable) -> void:
	_tree = tree
	_chibi = chibi
	_tunnel = gym.get_node_or_null("WindTunnel") as RooftopWindTunnel
	_check = check
	_check.call(_tunnel != null and _chibi.wind_field == _tunnel, "The rooftop binds its typed wind field to Chibi")
	if _tunnel == null:
		return

	var crosswind := Crosswind.new()
	gym.add_child(crosswind)
	chibi.wind_field = crosswind
	await _ticks(2)
	_check.call(chibi.wind_velocity.is_equal_approx(Vector3.RIGHT * 4.0),
		"The runner samples a level-supplied crosswind independently of the rooftop tunnel")
	chibi.wind_field = _tunnel
	crosswind.free()

	# Hold the phase during individual movement tests so their result is independent of render timing.
	var elapsed := _tunnel.elapsed_physics
	_tunnel.set_physics_process(false)
	var center := _world(Vector3(0.0, 0.6, 0.0))
	_tunnel.elapsed_physics = LULL
	var lull := _tunnel.flow_velocity_at(center)
	_tunnel.elapsed_physics = PEAK
	var peak := _tunnel.flow_velocity_at(center)
	var edge := _tunnel.flow_velocity_at(_world(Vector3(2.22, 0.6, 0.0)))
	var outside := _world(Vector3(2.4, 0.6, 0.0))
	_check.call(lull.length() > 2.9 and peak.length() > lull.length() * 2.0
		and peak.normalized().dot(Vector3.FORWARD) > 0.99 and edge.length() < peak.length() * 0.5
		and not _tunnel.contains_point(outside) and _tunnel.flow_velocity_at(outside).is_zero_approx(),
		"The tunnel eases inward and shares one directional lull and peak")

	await _test_headwind()
	await _test_tailwind()
	await _test_slide_through_exit()
	await _test_lateral_slide_exit()
	await _test_upwind_slide_turn()
	await _test_slide_jump()

	await _reset(OUTSIDE, LULL)
	_tunnel.elapsed_physics = elapsed
	_tunnel.set_physics_process(true)
	_tree = null
	_chibi = null
	_tunnel = null
	_check = Callable()


func _test_headwind() -> void:
	await _reset(_world(Vector3(0.0, 0.08, -2.0)), LULL)
	var rig := _chibi.get_node("ChibiRigBinder") as ChibiRigBinder
	var skeleton := rig.skeleton
	var upper_r := skeleton.find_bone(&"upperarm_r")
	var wrist_r := skeleton.find_bone(&"hand_r")
	var upper_l := skeleton.find_bone(&"upperarm_l")
	var wrist_l := skeleton.find_bone(&"hand_l")
	var hips := [skeleton.find_bone(&"thigh_l"), skeleton.find_bone(&"thigh_r")]
	var ankles := [skeleton.find_bone(&"foot_l"), skeleton.find_bone(&"foot_r")]
	var brace_samples := [0, 0, 0, 0]
	var sample_brace := func() -> void:
		var left_planted := _chibi.pose_mod.is_ground_foot_planted(0)
		var right_planted := _chibi.pose_mod.is_ground_foot_planted(1)
		if _chibi.pose_mod.wind_pose_brace_blend > 0.20 and (left_planted or right_planted):
			brace_samples[2] += 1
		if _chibi.pose_mod.wind_pose_recoil_blend > 0.60 and left_planted != right_planted:
			var free_side := 1 if left_planted else 0
			var leg_reach := skeleton.global_basis * (
				skeleton.get_bone_global_pose(ankles[free_side]).origin
				- skeleton.get_bone_global_pose(hips[free_side]).origin)
			if leg_reach.z < -0.045:
				brace_samples[3] += 1
		if _chibi.pose_mod.wind_pose_brace_blend < 0.55:
			return
		var right_reach := skeleton.global_basis * (
			skeleton.get_bone_global_pose(wrist_r).origin - skeleton.get_bone_global_pose(upper_r).origin)
		var left_reach := skeleton.global_basis * (
			skeleton.get_bone_global_pose(wrist_l).origin - skeleton.get_bone_global_pose(upper_l).origin)
		brace_samples[0] += 1
		if right_reach.z > 0.10 and right_reach.z > left_reach.z + 0.035:
			brace_samples[1] += 1
	skeleton.skeleton_updated.connect(sample_brace)
	_chibi.chibi_input.set_touch_move(Vector2.DOWN)
	await _ticks(30)
	var lull_speed := _chibi.get_real_velocity().z
	var lull_brace := _chibi.wind_brace_weight
	var lull_scarf_force := rig.scarf_spring_sim.external_force.length()
	_tunnel.elapsed_physics = PEAK
	await _ticks(28)
	skeleton.skeleton_updated.disconnect(sample_brace)
	var peak_speed := _chibi.get_real_velocity().z
	var facing_upwind := (-_chibi.global_basis.z).dot(Vector3.BACK) > 0.85
	_check.call(lull_speed > 0.8 and lull_brace > 0.10 and peak_speed < -0.3
		and _chibi.wind_recoil_weight > 0.15 and facing_upwind,
		"A full upwind input advances in the lull and keeps bracing during blowback (%.2f then %.2f m/s)"
		% [lull_speed, peak_speed])
	_check.call(brace_samples[0] > 0 and brace_samples[1] >= brace_samples[0] * 0.75,
		"The live rig keeps the right palm ahead of the left arm in the brace (%d/%d frames)"
		% [brace_samples[1], brace_samples[0]])
	_check.call(brace_samples[2] > 0, "The wind brace preserves planted shoe contact during the stride")
	_check.call(brace_samples[3] > 2, "The peak gust trails the free leg downwind while the other shoe is planted")
	var scarf := rig.scarf_spring_sim
	var peak_scarf_force := scarf.external_force.dot(Vector3.FORWARD)
	_check.call(scarf.setting_count == 2 and scarf.get_root_bone_name(0) == &"scarf_01"
		and scarf.get_root_bone_name(1) == &"scarf_b_01" and lull_scarf_force > 0.0
		and peak_scarf_force > lull_scarf_force * 1.25 and rig.spring_sim.external_force.is_zero_approx(),
		"The gust drives both scarf tails downwind and leaves the other spring chains alone")

	_chibi.chibi_input.set_touch_move(Vector2.ZERO)
	var flow_before_idle := _chibi.flow_level
	await _ticks(22)
	_check.call(_chibi.get_real_velocity().z < -0.2 and _chibi.flow_level <= flow_before_idle + 0.005,
		"Wind moves an idle runner without earning Flow")
	await _reset(OUTSIDE, PEAK)
	_check.call(_chibi.wind_velocity.is_zero_approx() and is_zero_approx(_chibi.wind_brace_weight)
		and is_zero_approx(_chibi.wind_recoil_weight) and _chibi.current_state == "Locomotion"
		and is_zero_approx(_chibi.pose_mod.wind_pose_brace_blend) and scarf.external_force.is_zero_approx(),
		"Respawning outside the tunnel clears wind, brace, and scarf force")


func _test_tailwind() -> void:
	_chibi.flow_level = 1.0
	_chibi.chibi_input.set_touch_move(Vector2.UP)
	await _ticks(37)
	var dry_speed := _chibi.resolved_planar_speed
	var dry_flow := _chibi.flow_level
	await _reset(_world(Vector3(0.0, 0.08, 4.0)), PEAK)
	_chibi.flow_level = 1.0
	_chibi.chibi_input.set_touch_move(Vector2.UP)
	await _ticks(37)
	var wind_speed := _chibi.resolved_planar_speed
	_check.call(wind_speed > dry_speed + 0.16 and wind_speed <= dry_speed * 1.12 + 0.025
		and absf(_chibi.flow_level - dry_flow) < 0.075 and _chibi.wind_brace_weight < 0.05,
		"Tailwind raises normal running speed within its 12%% budget (%.2f to %.2f m/s)"
		% [dry_speed, wind_speed])

	await _reset(_world(Vector3(0.0, 0.08, 4.0)), PEAK)
	_chibi.chibi_input.set_touch_move(Vector2.UP * 0.60)
	await _ticks(51)
	_check.call(_chibi.resolved_planar_speed > 3.0 and _chibi.flow_level < 0.02,
		"Crossing the Flow speed threshold with wind assistance alone earns no Flow")


func _test_slide_through_exit() -> void:
	var entrance := _world(Vector3(0.0, 0.08, 7.55))
	await _reset(entrance, LULL)
	await _start_slide()
	await _ticks(18)
	_chibi.chibi_input.set_touch_slide(false)
	await _ticks(46)
	var held := _chibi.current_state == "Slide" and _chibi._current_half_height() < 0.4
	var carried := _chibi.global_position.z < entrance.z - 3.5
	_check.call(held and carried, "Entering the tunnel keeps a released slide low past its usual timeout")

	for frame in 180:
		if _chibi.current_state != "Slide":
			break
		await _ticks(1)
	_check.call(_chibi.current_state == "Locomotion" and _chibi._current_half_height() > 0.55
		and not _tunnel.contains_point(_chibi.get_capsule_center()) and _chibi.velocity.z < -1.0,
		"Sliding out the end restores standing and preserves momentum (z=%.2f, speed=%.2f)"
		% [_chibi.global_position.z, _chibi.velocity.z])


func _test_lateral_slide_exit() -> void:
	await _reset(_world(Vector3(1.7, 0.08, 4.0)), LULL)
	await _start_slide()
	_chibi.chibi_input.set_touch_move(Vector2.RIGHT)
	_chibi.chibi_input.set_touch_slide(false)
	for frame in 70:
		if _chibi.current_state != "Slide":
			break
		await _ticks(1)
	_check.call(_chibi.current_state == "Locomotion" and _chibi.wind_velocity.is_zero_approx()
		and _chibi.global_position.x > _world(Vector3(2.25, 0.0, 0.0)).x - 0.08
		and _chibi.global_position.z > _world(Vector3(0.0, 0.0, -6.8)).z,
		"Chibi can steer a sustained slide out through the side")


func _test_upwind_slide_turn() -> void:
	await _reset(_world(Vector3(0.0, 0.08, 0.0)), LULL)
	_chibi.chibi_input.set_touch_move(Vector2.DOWN)
	_chibi.velocity = Vector3.BACK * 5.0
	_chibi.chibi_input.set_touch_slide(true)
	await _ticks(3)
	_chibi.chibi_input.set_touch_slide(false)
	await _ticks(48)
	_check.call(_chibi.current_state == "Slide" and _chibi.velocity.z < -2.5
		and _tunnel.contains_point(_chibi.get_capsule_center()),
		"An upwind slide turns into downwind carry during the lull")


func _test_slide_jump() -> void:
	await _reset(_world(Vector3(0.0, 0.08, 4.0)), PEAK)
	await _start_slide()
	await _ticks(11)
	_chibi.chibi_input.set_touch_slide(false)
	_chibi.chibi_input.set_touch_jump(true)
	await _ticks(2)
	_chibi.chibi_input.set_touch_jump(false)
	_check.call(_chibi.current_state == "Locomotion" and not _chibi.is_on_floor()
		and _chibi.velocity.y > 3.0 and _chibi.velocity.z < -2.0 and _chibi._current_half_height() > 0.55,
		"Jump exits the wind slide with upward launch and downwind carry")
	await _ticks(45)
	_check.call(_chibi.current_state != "Slide", "Landing inside the tunnel does not resume the canceled slide")


func _start_slide() -> void:
	_chibi.velocity = Vector3.FORWARD * 5.0
	_chibi.chibi_input.set_touch_move(Vector2.UP)
	_chibi.chibi_input.set_touch_slide(true)
	await _ticks(3)


func _reset(position: Vector3, phase: float) -> void:
	_chibi.chibi_input.clear_touch_input()
	_tunnel.elapsed_physics = phase
	await _tree.physics_frame
	_chibi.reset_for_respawn(position)
	_chibi.rotation.y = 0.0
	_chibi.camera_ctrl.yaw = 0.0
	_chibi.camera_ctrl.reset_after_teleport()
	await _ticks(9)


func _world(point: Vector3) -> Vector3:
	return _tunnel.to_global(point)


func _ticks(count: int) -> void:
	for frame in count:
		await _tree.physics_frame
		await _tree.process_frame
