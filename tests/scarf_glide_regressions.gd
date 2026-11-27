extends RefCounted

const OPEN_DECK := Vector3(4.0, 0.08, 21.0)
const JUMP_CIRCLE := "HUDRoot/TouchRoot/Jump"

var _tree: SceneTree
var _gym: Node3D
var _chibi: ParkourController
var _check: Callable


func run(tree: SceneTree, gym: Node3D, chibi: ParkourController, check: Callable) -> void:
	_tree = tree
	_gym = gym
	_chibi = chibi
	_check = check
	_chibi.touch_hud.set_touch_visible(true)
	var scarf := _chibi.pose_mod.scarf_glider if _chibi.pose_mod != null else null
	_check.call(scarf != null and scarf.get_corner_targets().size() == 4,
		"The rooftop runner binds four scarf corners to the live hand rig")

	await _test_ground_jump()
	await _test_partial_deploy_touch_cancel()
	await _test_key_cancel_bindings()
	await _test_steering_and_landing()
	await _test_uninterrupted_glide_landing()
	await _test_gentle_glide_first_step()
	await _test_partial_touchdown_and_hop()
	await _test_near_floor_and_ceiling()
	await _test_trampoline_landing()
	await _test_water_entry()

	_chibi.chibi_input.clear_touch_input()
	_chibi.touch_hud.set_touch_visible(false)
	_chibi.reset_for_respawn(OPEN_DECK)
	await _ticks(3)
	_check = Callable()
	_chibi = null
	_gym = null
	_tree = null


func _test_ground_jump() -> void:
	_reset(OPEN_DECK)
	await _ticks(10)
	var button := _chibi.touch_hud.get_node(JUMP_CIRCLE) as Control
	var point := button.get_global_rect().get_center()
	_touch_jump(point, true)
	await _ticks(4)
	_check.call(_chibi.velocity.y > 0.0 and not _chibi.can_deploy_scarf()
		and button.get("caption") == "Jump" and button.get("symbol") != "parachute",
		"Scarf glide leaves the ordinary jump and ascent prompt intact")

	await _wait_until_available()
	var ready_during_descent: bool = _chibi.can_deploy_scarf() and _chibi.velocity.y < 0.0
	_check.call(ready_during_descent and _chibi.scarf_glide_phase == &"stowed"
		and button.get("symbol") == "parachute" and button.get("caption") == "Glide",
		"An ordinary jump offers glide on descent without retriggering held Jump")

	_touch_jump(point, false)
	_touch_jump(point, true)
	await _ticks(2)
	_check.call(_chibi.scarf_glide_phase == &"deploy" and not _chibi.can_deploy_scarf()
		and button.get("symbol") != "parachute" and _chibi.jump_buffer_timer <= 0.0,
		"A fresh touch deploys once and removes the availability icon")
	_touch_jump(point, false)


func _test_partial_deploy_touch_cancel() -> void:
	_reset(OPEN_DECK + Vector3.UP * 6.2)
	await _wait_until_available()
	var button := _chibi.touch_hud.get_node(JUMP_CIRCLE) as Control
	var point := button.get_global_rect().get_center()
	_touch_jump(point, true)
	await _ticks(2)
	var partial_drop_action: bool = _chibi.scarf_glide_phase == &"deploy" \
		and _chibi.scarf_glide_progress > 0.0 and _chibi.scarf_glide_progress < 1.0 \
		and button.get("caption") == "Drop" and button.get("symbol") == "drop"
	var deployment_finger_cleared: bool = not _chibi.chibi_input.jump_held \
		and not _chibi.chibi_input.jump_just_pressed and not button.get("held")

	# The deployment finger remains the Jump owner until it lifts, but its release is not Drop.
	_touch_jump(point, false)
	await _ticks(1)
	var release_did_not_cancel: bool = _chibi.scarf_glide_phase == &"deploy" \
		and _chibi.jump_buffer_timer <= 0.0 and _chibi.roll_buffer_timer <= 0.0
	_check.call(partial_drop_action and deployment_finger_cleared and release_did_not_cancel,
		"A deployment finger lifts without triggering the newly actionable Drop prompt")

	var fall_speed_before := _chibi.velocity.y
	_touch_jump(point, true)
	var touch_cancelled := false
	for frame in 4:
		await _ticks(1)
		if _chibi.scarf_glide_phase == &"cancel":
			touch_cancelled = true
			break
	var gravity_step := _chibi.config.gravity / float(Engine.physics_ticks_per_second)
	var ordinary_gravity: bool = _chibi.velocity.y < fall_speed_before - gravity_step * 0.4
	var no_cancel_buffer: bool = _chibi.jump_buffer_timer <= 0.0 and _chibi.roll_buffer_timer <= 0.0
	_touch_jump(point, false)
	_check.call(touch_cancelled and ordinary_gravity and no_cancel_buffer,
		"A fresh mid-deploy touch folds the scarf and resumes ordinary gravity without buffering")
	await _finish_cancel()
	_check.call(_chibi.scarf_glide_phase == &"stowed" and not _chibi.can_deploy_scarf(),
		"A partial-deploy cancel cannot reopen during the same airtime")


func _test_key_cancel_bindings() -> void:
	var button := _chibi.touch_hud.get_node(JUMP_CIRCLE) as Control
	var point := button.get_global_rect().get_center()
	for key_case in [
		{"name": "Space", "physical_keycodes": [KEY_SPACE]},
		{"name": "C", "physical_keycodes": [KEY_C]},
		{"name": "Ctrl", "physical_keycodes": [KEY_CTRL]},
		{"name": "Space + C", "physical_keycodes": [KEY_SPACE, KEY_C]},
	]:
		_reset(OPEN_DECK + Vector3.UP * 6.2)
		await _deploy_touch_until_glide(point)
		var open_prompt: bool = _chibi.scarf_glide_phase == &"glide" \
			and button.get("caption") == "Drop" and button.get("symbol") == "drop"
		var fall_speed_before := _chibi.velocity.y
		for physical_keycode in key_case["physical_keycodes"]:
			_key_event(physical_keycode, true)
		var cancelled := false
		for frame in 5:
			await _ticks(1)
			if _chibi.scarf_glide_phase == &"cancel":
				cancelled = true
				break
		for physical_keycode in key_case["physical_keycodes"]:
			_key_event(physical_keycode, false)
		var gravity_step := _chibi.config.gravity / float(Engine.physics_ticks_per_second)
		var ordinary_gravity: bool = _chibi.velocity.y < fall_speed_before - gravity_step * 0.4
		var no_buffers: bool = _chibi.jump_buffer_timer <= 0.0 and _chibi.roll_buffer_timer <= 0.0
		_check.call(open_prompt and cancelled and ordinary_gravity and no_buffers,
			"%s cancels an open scarf without a jump or roll buffer" % key_case["name"])
		await _finish_cancel()
		_check.call(_chibi.scarf_glide_phase == &"stowed" and not _chibi.can_deploy_scarf(),
			"%s cannot reopen the scarf during the same airtime" % key_case["name"])


func _test_steering_and_landing() -> void:
	_reset(OPEN_DECK + Vector3.UP * 6.2)
	_chibi.rotation.y = PI * 0.5
	_chibi.camera_ctrl.yaw = PI * 0.5
	await _wait_until_available()
	_check.call(_chibi.can_deploy_scarf(), "A walk-off fall can deploy without an initial jump")
	var button := _chibi.touch_hud.get_node(JUMP_CIRCLE) as Control
	var point := button.get_global_rect().get_center()
	_touch_jump(point, true)
	_chibi.chibi_input.set_touch_move(Vector2.RIGHT * 0.5)
	await _ticks(2)
	_touch_jump(point, false)
	await _ticks(44)
	var steer_speed := Vector2(_chibi.velocity.x, _chibi.velocity.z).length()
	var stable_glide: bool = _chibi.scarf_glide_phase == &"glide" \
		and button.get("caption") == "Drop" and button.get("symbol") == "drop"
	_check.call(stable_glide and absf(_chibi.velocity.y + 2.4) < 0.30,
		"An open scarf offers Drop and settles into the configured slow descent")
	_check.call(stable_glide and _chibi.velocity.z < -1.35 and absf(_chibi.velocity.x) < 0.35
		and steer_speed < 3.1, "Half-stick input steers relative to the camera at partial speed")

	_chibi.chibi_input.set_touch_move(Vector2.ZERO)
	await _ticks(4)
	var coasting := Vector2(_chibi.velocity.x, _chibi.velocity.z).length()
	_check.call(coasting > steer_speed * 0.65 and coasting < steer_speed,
		"Releasing steering eases the glide into a coast")
	_chibi.chibi_input.set_touch_move(Vector2.RIGHT * 0.5)

	# Cancel low enough to keep the dry touchdown an ordinary running landing.
	for frame in 180:
		if _chibi.global_position.y <= OPEN_DECK.y + 0.86:
			break
		await _ticks(1)
	var fall_speed_before := _chibi.velocity.y
	_touch_jump(point, true)
	var touch_cancelled := false
	for frame in 4:
		await _ticks(1)
		if _chibi.scarf_glide_phase == &"cancel":
			touch_cancelled = true
			break
	var gravity_step := _chibi.config.gravity / float(Engine.physics_ticks_per_second)
	var ordinary_gravity: bool = _chibi.velocity.y < fall_speed_before - gravity_step * 0.4
	var no_buffers: bool = _chibi.jump_buffer_timer <= 0.0 and _chibi.roll_buffer_timer <= 0.0
	_touch_jump(point, false)
	_check.call(touch_cancelled and ordinary_gravity and no_buffers,
		"A fresh midair Drop touch cancels glide into ordinary gravity without buffering")

	var landed := false
	for frame in 220:
		await _ticks(1)
		if _chibi.is_on_floor():
			landed = true
			break
	var touchdown := _chibi.global_position
	await _ticks(9)
	var travel := _chibi.global_position.distance_to(touchdown)
	_check.call(landed and _chibi.current_state == "Locomotion" and travel > 0.10,
		"A cancelled scarf lands in an ordinary run and ground movement resumes")
	_chibi.chibi_input.set_touch_move(Vector2.ZERO)
	await _ticks(25)
	_check.call(_chibi.scarf_glide_phase == &"stowed" and button.get("caption") == "Jump",
		"Finishing the wrap restores the dry scarf and ordinary Jump prompt")
	_chibi.chibi_input.set_touch_jump(true)
	await _ticks(2)
	_chibi.chibi_input.set_touch_jump(false)
	await _wait_until_available()
	_check.call(_chibi.can_deploy_scarf(), "A new airtime after dry touchdown re-arms the scarf")


func _test_uninterrupted_glide_landing() -> void:
	_reset(OPEN_DECK + Vector3.UP * 6.2)
	_chibi.rotation.y = PI * 0.5
	_chibi.camera_ctrl.yaw = PI * 0.5
	await _wait_until_available()
	var button := _chibi.touch_hud.get_node(JUMP_CIRCLE) as Control
	var point := button.get_global_rect().get_center()
	_touch_jump(point, true)
	_chibi.chibi_input.set_touch_move(Vector2.RIGHT * 0.5)
	await _ticks(2)
	_touch_jump(point, false)
	await _ticks(44)
	var opened: bool = _chibi.scarf_glide_phase == &"glide" \
		and button.get("caption") == "Drop" and button.get("symbol") == "drop"
	var landed := false
	for frame in 220:
		await _ticks(1)
		if _chibi.scarf_glide_phase == &"stow" and _chibi.is_on_floor():
			landed = true
			break
	var touchdown := _chibi.global_position
	await _ticks(9)
	var travel := _chibi.global_position.distance_to(touchdown)
	_check.call(opened and landed and _chibi.scarf_glide_phase == &"stow" \
		and _chibi.current_state == "Locomotion" and travel > 0.10,
		"An uninterrupted scarf tosses back on dry touchdown as the ordinary run resumes")
	_chibi.chibi_input.set_touch_move(Vector2.ZERO)
	await _ticks(25)
	_check.call(_chibi.scarf_glide_phase == &"stowed" and button.get("caption") == "Jump",
		"An uninterrupted touchdown finishes the scarf wrap and restores Jump")
	_touch_jump(point, true)
	await _ticks(2)
	_touch_jump(point, false)
	await _wait_until_available()
	_check.call(_chibi.can_deploy_scarf(), "A normal scarf landing re-arms the next airtime")


func _test_gentle_glide_first_step() -> void:
	var contacts := [0]
	var record_contact := func(_side: StringName) -> void:
		contacts[0] += 1
	var scarf := _chibi.pose_mod.scarf_glider
	var skeleton := _chibi.pose_mod.get_skeleton()
	var pinned_then_released := [false, false]
	var sample_pins := func() -> void:
		if not _chibi.scarf_glide_touchdown or scarf._opacity <= 0.15:
			return
		var progress := _chibi.scarf_glide_progress
		var targets := scarf.get_corner_targets()
		if targets.size() != 4:
			return
		var grip_error := Vector2.ZERO
		for index in 4:
			var side := 0 if index < 2 else 1
			var hand := skeleton.get_bone_global_pose(scarf._hand_bones[side])
			var wrist_target := skeleton.global_transform * hand * scarf._hand_pin_offsets[index]
			grip_error[side] = maxf(grip_error[side], targets[index].distance_to(wrist_target))
		if progress < 0.32 and grip_error.length() < 0.005:
			pinned_then_released[0] = true
		if progress > 0.53 and progress < 0.73 and grip_error.y > grip_error.x + 0.008:
			pinned_then_released[1] = true
	_chibi.anim_ctrl.ground_foot_contact.connect(record_contact)
	skeleton.skeleton_updated.connect(sample_pins)
	var approach_speed := await _land_dry_glide(0.40, 3.2)
	var contact_speed := Vector2(_chibi.velocity.x, _chibi.velocity.z).length()
	var started_gait := (_chibi.is_on_floor() and _chibi.scarf_glide_touchdown
		and _chibi.anim_ctrl.current_state == "LocomotionGait")
	_check.call(started_gait and approach_speed > 1.65 and absf(contact_speed - approach_speed) < 0.08,
		"A gentle scarf landing carries %.2f m/s straight into the gait" % approach_speed)

	var planted_side := -1
	var first_plant_tick := -1
	for frame in 7:
		for side in 2:
			if _chibi.pose_mod.is_ground_foot_planted(side):
				planted_side = side
				first_plant_tick = frame
				break
		if planted_side >= 0:
			break
		await _ticks(1)
	_chibi.anim_ctrl.ground_foot_contact.disconnect(record_contact)
	_check.call(planted_side >= 0 and contacts[0] == 1 and _chibi.scarf_glide_phase == &"stow",
		"The first scarf landing shoe plants once while the wrap is active (tick %d)" % first_plant_tick)
	await _ticks(17)
	skeleton.skeleton_updated.disconnect(sample_pins)
	_check.call(pinned_then_released[0] and pinned_then_released[1],
		"The wrap starts with all corners in the hands and transfers the throwing side first")


func _test_partial_touchdown_and_hop() -> void:
	await _land_dry_glide(0.0, 0.48)
	_check.call(_chibi.is_on_floor() and _chibi.scarf_glide_touchdown
		and _chibi.scarf_glide_stow_open > 0.15 and _chibi.scarf_glide_stow_open < 0.99,
		"Touching down during deployment gathers only the scarf that opened")
	await _ticks(22)
	_check.call(_chibi.scarf_glide_phase == &"stowed" and not _chibi.scarf_glide_touchdown,
		"The partial scarf settles at the collar and releases the touchdown state")

	await _land_dry_glide(0.72, 3.2)
	var moving_plant := false
	for frame in 6:
		moving_plant = (moving_plant or _chibi.pose_mod.is_ground_foot_planted(0)
			or _chibi.pose_mod.is_ground_foot_planted(1))
		await _ticks(1)
	_check.call(moving_plant, "A quicker scarf landing still makes a planted step before toe-off")
	_chibi.chibi_input.set_touch_jump(true)
	await _ticks(2)
	_chibi.chibi_input.set_touch_jump(false)
	_check.call(not _chibi.is_on_floor() and _chibi.velocity.y > 2.5
		and _chibi.scarf_glide_phase == &"stow"
		and not _chibi.pose_mod.is_ground_foot_planted(0) and not _chibi.pose_mod.is_ground_foot_planted(1),
		"A fresh hop during the wrap releases the shoe and leaves the scarf gathering")
	await _ticks(22)
	_check.call(_chibi.scarf_glide_phase == &"stowed" and not _chibi.scarf_glide_touchdown,
		"The wrap finishes in the new airtime")


func _land_dry_glide(move_strength: float, height: float) -> float:
	_reset(OPEN_DECK + Vector3.UP * height)
	_chibi.camera_ctrl.reset_after_teleport()
	_chibi.chibi_input.set_touch_move(Vector2.UP * move_strength)
	await _wait_until_available()
	_chibi.chibi_input.set_touch_jump(true)
	await _ticks(1)
	_chibi.chibi_input.set_touch_jump(false)
	var approach_speed := 0.0
	for frame in 170:
		await _ticks(1)
		if _chibi.is_on_floor():
			break
		approach_speed = Vector2(_chibi.velocity.x, _chibi.velocity.z).length()
	return approach_speed


func _test_near_floor_and_ceiling() -> void:
	_reset(OPEN_DECK + Vector3.UP * 0.48)
	_chibi.velocity.y = -2.3
	await _ticks(2)
	var near_floor_blocked := not _chibi.can_deploy_scarf()
	_chibi.chibi_input.set_touch_jump(true)
	await _ticks(2)
	_chibi.chibi_input.set_touch_jump(false)
	var buffered := _chibi.jump_buffer_timer > 0.0 and _chibi.scarf_glide_phase == &"stowed"
	await _ticks(11)
	_check.call(near_floor_blocked and buffered and _chibi.velocity.y > 0.0,
		"A late falling press buffers the next ground jump beneath the deployment window")

	var roof := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.6, 0.20, 2.6)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	roof.add_child(collision)
	roof.position = OPEN_DECK + Vector3.UP * 5.50
	_gym.add_child(roof)
	_reset(OPEN_DECK + Vector3.UP * 4.05)
	_chibi.velocity.y = -1.1
	await _ticks(4)
	_check.call(not _chibi.is_on_floor() and _chibi.velocity.y < 0.0 and not _chibi.can_deploy_scarf(),
		"A low overhead obstruction suppresses the glide prompt")
	shape.size = Vector3(0.4, 0.20, 0.65)
	roof.position = _chibi.global_position + _chibi.global_basis.x * 0.67 + Vector3.UP * 1.85
	await _ticks(2)
	_check.call(not _chibi.can_deploy_scarf(), "An obstruction above one hand leaves the glide prompt off")
	roof.queue_free()
	await _ticks(4)
	_check.call(_chibi.can_deploy_scarf(), "Removing the overhead obstruction restores availability")
	_chibi.chibi_input.set_touch_jump(true)
	await _ticks(3)
	var opened := _chibi.scarf_glide_phase == &"deploy"
	_reset(OPEN_DECK)
	await _ticks(8)
	_check.call(opened and _chibi.scarf_glide_phase == &"stowed" and not _chibi.can_deploy_scarf(),
		"Respawn clears a scarf deployment in progress")


func _test_water_entry() -> void:
	var pool := _gym.get_node("Zone5_SlopedSwimPool") as ChibiPool
	_reset(pool.to_global(Vector3(15.0, ChibiPool.WATER_Y + 3.0, 0.0)))
	await _wait_until_available()
	_chibi.chibi_input.set_touch_jump(true)
	await _ticks(2)
	var started := _chibi.scarf_glide_phase == &"deploy"
	_chibi.chibi_input.set_touch_jump(false)
	for frame in 220:
		await _ticks(1)
		if _chibi.current_state == "PoolSwim":
			break
	_check.call(started and _chibi.current_state == "PoolSwim" and _chibi.scarf_glide_phase == &"stowed"
		and not _chibi.can_deploy_scarf() and _chibi.touch_hud.get_node(JUMP_CIRCLE).get("caption") == "Rise",
		"Water entry closes the scarf and returns Jump to swimming")


func _test_trampoline_landing() -> void:
	var trampoline := _gym.get_node("Zone4_AerialCircuit/Trampoline_01") as Node3D
	_reset(trampoline.global_position + Vector3.UP * 3.1)
	await _wait_until_available()
	_chibi.chibi_input.set_touch_jump(true)
	await _ticks(2)
	var deployed := _chibi.scarf_glide_phase == &"deploy"
	_chibi.chibi_input.set_touch_jump(false)
	for frame in 160:
		await _ticks(1)
		if _chibi.velocity.y > 4.0:
			break
	_check.call(deployed and _chibi.velocity.y > 4.0
		and _chibi.scarf_glide_phase not in [&"deploy", &"glide"],
		"Landing on the trampoline releases the scarf and keeps the normal bounce")


func _reset(position: Vector3) -> void:
	_chibi.chibi_input.clear_touch_input()
	_chibi.reset_for_respawn(position)
	_chibi.rotation.y = 0.0
	_chibi.camera_ctrl.yaw = 0.0


func _deploy_touch_until_glide(point: Vector2) -> void:
	await _wait_until_available()
	_touch_jump(point, true)
	await _ticks(2)
	_touch_jump(point, false)
	for frame in 48:
		if _chibi.scarf_glide_phase == &"glide":
			return
		await _ticks(1)


func _key_event(physical_keycode: int, pressed: bool) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = physical_keycode
	key.pressed = pressed
	key.ctrl_pressed = pressed and physical_keycode == KEY_CTRL
	Input.parse_input_event(key)
	Input.flush_buffered_events()


func _finish_cancel() -> void:
	for frame in 20:
		if _chibi.scarf_glide_phase != &"cancel":
			return
		await _ticks(1)


func _wait_until_available() -> void:
	for frame in 42:
		if _chibi.can_deploy_scarf():
			return
		await _ticks(1)


func _touch_jump(point: Vector2, pressed: bool) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 8
	touch.position = point
	touch.pressed = pressed
	_tree.root.push_input(touch, true)


func _ticks(count: int) -> void:
	for frame in count:
		await _tree.physics_frame
