extends RefCounted

var _tree: SceneTree
var _gym: Node3D
var _runner: ParkourController
var _check: Callable


func run(tree: SceneTree, gym: Node3D, runner: ParkourController, check: Callable) -> void:
	_tree = tree
	_gym = gym
	_runner = runner
	_check = check
	for bar_name in ["VaultBar_Low", "VaultBar_Med", "VaultBar_High"]:
		var bar := gym.get_node("Zone1_FlowAndSlides/" + bar_name) as StaticBody3D
		for flow in [0.0, 1.0]:
			await _vault_input(bar, flow)
	await _interrupted_vault()
	await _blocked_dry_mantle()
	await _directional_ledge_drop(KEY_C, 1.0)
	await _directional_ledge_drop(KEY_CTRL, -1.0)
	await _directional_ledge_drop(KEY_C, 0.0)
	await _outside_corner()
	await _drop_during_corner()
	await _blocked_pool_mantle()
	_runner.chibi_input.clear_touch_input()
	_runner.reset_for_respawn(Vector3(0.0, 0.10, 6.0))
	await _ticks(3)


func _ticks(count: int) -> void:
	for _tick in count:
		await _tree.physics_frame


func _reset(feet: Vector3, yaw: float = 0.0) -> void:
	_runner.chibi_input.clear_touch_input()
	_runner.reset_for_respawn(feet)
	_runner.rotation.y = yaw
	_runner.camera_ctrl.yaw = yaw
	_runner.camera_ctrl.reset_after_teleport()


func _jump() -> void:
	_runner.chibi_input.set_touch_jump(true)
	await _ticks(1)
	_runner.chibi_input.set_touch_jump(false)


func _clear_capsule() -> bool:
	var active := _runner.collision_shape.shape as CapsuleShape3D
	var capsule := CapsuleShape3D.new()
	capsule.radius = active.radius - 0.004
	capsule.height = active.height - 0.008
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = _runner.collision_shape.global_transform
	query.collision_mask = 5
	query.exclude = [_runner.get_rid()]
	return _runner.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _vault_approach(bar: StaticBody3D, flow: float) -> float:
	var collider := bar.get_node("CollisionShape3D") as CollisionShape3D
	var bar_depth := (collider.shape as BoxShape3D).size.z
	var front := collider.global_position.z + bar_depth * 0.5
	_reset(Vector3(bar.global_position.x, 0.04, front + 2.60))
	await _ticks(8)
	_runner.chibi_input.set_touch_move(Vector2.UP)
	for _tick in 38:
		if _runner.global_position.z <= front + 1.58:
			break
		await _ticks(1)
	_runner.flow_level = flow
	await _jump()
	return front - bar_depth


func _vault_input(bar: StaticBody3D, flow: float) -> void:
	var back := await _vault_approach(bar, flow)
	var vaulted := false
	var clear := true
	for _tick in 100:
		if _runner.current_state == "SpeedVault":
			vaulted = true
			clear = clear and _clear_capsule() and _runner.get_collision_mask_value(1)
		elif vaulted:
			break
		await _ticks(1)
	_check.call(vaulted and clear and _runner.current_state == "Locomotion" and _runner.global_position.z < back - 0.28
		and -_runner.velocity.z >= _runner.config.base_run_speed - 0.01,
		"%s clears the entire capsule from approach to landing (Flow %.1f, state %s, z %.2f)" % [bar.name, flow, _runner.current_state, _runner.global_position.z])


func _interrupted_vault() -> void:
	var bar := _gym.get_node("Zone1_FlowAndSlides/VaultBar_Low") as StaticBody3D
	await _vault_approach(bar, 0.0)
	for _tick in 20:
		if _runner.current_state == "SpeedVault":
			break
		await _ticks(1)
	var entered := _runner.current_state == "SpeedVault"
	var obstacle := _box(Vector3(0.0, 1.60, -0.10), Vector3(1.8, 0.35, 0.12))
	for _tick in 65:
		if _runner.current_state != "SpeedVault":
			break
		await _ticks(1)
	_check.call(entered and _runner.current_state == "Locomotion" and _runner.global_position.z > obstacle.global_position.z and _clear_capsule(),
		"An obstruction added during a vault aborts at a clear pose on its near side")
	obstacle.queue_free()
	await _ticks(2)


func _grab_flat_ledge() -> void:
	_reset(Vector3(-24.0, 0.035, 3.73))
	await _ticks(9)
	_runner.chibi_input.set_touch_move(Vector2.UP)
	await _jump()
	for _tick in 40:
		if _runner.current_state == "LedgeHang":
			break
		await _ticks(1)
	_runner.chibi_input.set_touch_move(Vector2.ZERO)


func _directional_ledge_drop(key: Key, direction: float) -> void:
	await _grab_flat_ledge()
	var ready := _runner.current_state == "LedgeHang"
	if direction != 0.0:
		var move_key := KEY_D if direction > 0.0 else KEY_A
		_set_key(move_key, true)
		for _tick in 40:
			await _ticks(1)
			if _runner.current_state == "LedgeShimmy" and _runner.shimmy_phase >= 0.45:
				break
		ready = ready and _runner.current_state == "LedgeShimmy" and _runner.shimmy_phase >= 0.45
		_set_key(move_key, false)
	var start := _runner.global_position
	_set_key(key, true)
	await _ticks(4)
	_set_key(key, false)
	var displacement := _runner.global_position - start
	var carried := absf(displacement.x) < 0.005 if direction == 0.0 else displacement.x * direction > 0.06
	var ledge_action := "hang" if direction == 0.0 else ("right shimmy" if direction > 0.0 else "left shimmy")
	_check.call(ready and carried and displacement.y < -0.06 and displacement.z > 0.0
		and _runner.current_state == "Locomotion" and _runner.velocity.y < 0.0 and _clear_capsule(),
		"%s drops from a %s with the expected lateral carry (travel %s)" % [OS.get_keycode_string(key), ledge_action, displacement])
	if direction != 0.0:
		await _ticks(9)
		var drift := (_runner.global_position.x - start.x) * direction
		var side_speed := _runner.velocity.x * direction
		_check.call(_runner.current_state == "Locomotion" and not _runner.is_on_floor()
			and _runner.chibi_input.move_vec.is_zero_approx() and drift > 0.26 and side_speed > 0.70,
			"Releasing A or D with %s keeps the shimmy drop drifting (%.2f m at %.2f m/s)" % [OS.get_keycode_string(key), drift, side_speed])


func _set_key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = pressed
	event.ctrl_pressed = key == KEY_CTRL and pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _blocked_dry_mantle() -> void:
	await _grab_flat_ledge()
	var hung_clear := _runner.current_state == "LedgeHang" and _clear_capsule()
	var obstacle := _box(Vector3(-24.0, 2.35, 2.72), Vector3(1.5, 0.20, 0.72))
	await _ticks(3)
	await _jump()
	await _ticks(6)
	_check.call(hung_clear and _runner.current_state == "LedgeHang" and _clear_capsule(),
		"A low ceiling blocks a mantle while Chibi stays clear of the flat ledge")
	obstacle.queue_free()
	await _ticks(3)
	await _jump()
	await _ticks(60)
	_check.call(_runner.current_state == "Locomotion" and _runner.global_position.y > 1.6,
		"The same ledge mantles onto its support after the ceiling is removed")


func _grab_corner_ledge() -> void:
	_reset(Vector3(-24.55, 0.56, -1.71))
	await _ticks(8)
	_runner.chibi_input.set_touch_move(Vector2.UP)
	await _jump()
	for _tick in 50:
		if _runner.current_state == "LedgeHang":
			break
		await _ticks(1)


func _outside_corner() -> void:
	await _grab_corner_ledge()
	_runner.chibi_input.set_touch_move(Vector2.RIGHT)
	var corner := false
	var clear := true
	for _tick in 210:
		if _runner.current_state in ["LedgeHang", "LedgeShimmy", "LedgeCorner"]:
			clear = clear and _clear_capsule()
		corner = corner or _runner.current_state == "LedgeCorner"
		if corner and _runner.current_state == "LedgeHang":
			break
		await _ticks(1)
	_check.call(corner and clear and _runner.current_state == "LedgeHang"
		and _runner.ledge_wall_normal.dot(Vector3.RIGHT) > 0.7,
		"Steering around the actual ledge tower corner keeps the capsule clear")


func _drop_during_corner() -> void:
	await _grab_corner_ledge()
	_runner.chibi_input.set_touch_move(Vector2.RIGHT)
	for _tick in 140:
		await _ticks(1)
		if _runner.current_state == "LedgeCorner" and _runner._corner_alpha >= 0.45:
			break
	var rounding_corner := _runner.current_state == "LedgeCorner"
	var tangent := (-_runner.global_basis.z).cross(Vector3.UP).normalized()
	var start := _runner.global_position
	_runner.chibi_input.set_touch_move(Vector2.ZERO)
	_set_key(KEY_C, true)
	await _ticks(4)
	_set_key(KEY_C, false)
	var travel := _runner.global_position - start
	_check.call(rounding_corner and _runner.current_state == "Locomotion"
		and travel.dot(tangent) > 0.03 and travel.y < -0.06 and _clear_capsule(),
		"C keeps Chibi moving around the ledge corner as she drops (travel %s)" % travel)


func _blocked_pool_mantle() -> void:
	var pool := _gym.get_node("Zone5_SlopedSwimPool") as ChibiPool
	var start := pool.to_global(Vector3(15.0, 0.42, 3.06))
	var obstacle := _box(start + Vector3(1.05, 1.4, 0.0), Vector3(1.2, 0.22, 2.0))
	_reset(start, -PI / 2.0)
	await _ticks(50)
	_runner.chibi_input.set_touch_move(Vector2.UP)
	_runner.chibi_input.set_touch_jump(true)
	var stayed_swimming := _runner.current_state == "PoolSwim"
	for _tick in 38:
		await _ticks(1)
		stayed_swimming = stayed_swimming and _runner.current_state == "PoolSwim"
	_check.call(stayed_swimming and _runner.get_active_water() == pool.water_body,
		"A blocked pool climb-out keeps Chibi swimming in the same water body")
	obstacle.queue_free()
	_runner.chibi_input.clear_touch_input()
	await _ticks(3)
	_reset(start, -PI / 2.0)
	await _ticks(50)
	_runner.chibi_input.set_touch_move(Vector2.UP)
	_runner.chibi_input.set_touch_jump(true)
	var mantled := false
	var clear := true
	for _tick in 100:
		await _ticks(1)
		if _runner.current_state == "MantleUp":
			mantled = true
			clear = clear and _clear_capsule()
			_runner.chibi_input.clear_touch_input()
		elif mantled:
			break
	_check.call(mantled and clear and _runner.current_state == "Locomotion",
		"The unobstructed pool exit lifts the whole capsule onto the coping")


func _box(center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	_gym.add_child(body)
	body.global_position = center
	return body
