extends SceneTree

## Comprehensive automated headless test suite for the Godot 4.7 Rooftop Parkour Gym port.
## Run via:
##   Godot_v4.7.2-stable_win64_console.exe --headless --path "c:\Users\count\Documents\chibi" --script res://tests/run_tests.gd

var _passed: int = 0
var _failed: int = 0

const LEVEL_PROGRESS_PROVIDER := preload("res://ui/hud/journal_level_progress_provider.gd")


func _init() -> void:
	call_deferred("_run_all")


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("[PASS] ", msg)
	else:
		_failed += 1
		printerr("[FAIL] ", msg)


func _run_all() -> void:
	print("=== CHIBI GODOT 4.7 PARKOUR GYM TEST SUITE ===")
	Engine.physics_ticks_per_second = 60
	_assert_true(Engine.physics_ticks_per_second == 60, "Parkour physics tests run at 60 ticks per second")
	_test_chibi_assets()
	_test_two_bone_ik()
	_test_rope_swing_solver()
	_test_running_wind_ribbon()
	await _test_touch_hud()
	await _test_full_gym_and_physics()
	await preload("res://tests/water_regressions.gd").new().run(self, _assert_true)

	print("=== SUMMARY: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_running_wind_ribbon() -> void:
	var anchor := Node3D.new()
	anchor.position = Vector3(-30.0, 0.65, 18.0)
	anchor.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var ribbon := WindRibbon.new()
	anchor.add_child(ribbon)
	root.add_child(anchor)
	ribbon.set_process(false)

	var tail_lengths: Array[float] = []
	var head_aligned := true
	for fps: int in [30, 60]:
		ribbon.clear_trail()
		anchor.position = Vector3(-30.0, 0.65, 18.0)
		var delta := 1.0 / fps
		ribbon.set_emitting(true)
		ribbon._process(delta)
		for i in fps:
			anchor.position.z -= 7.8 * delta
			ribbon._process(delta)
			head_aligned = head_aligned and ribbon.to_global(ribbon._head).is_equal_approx(anchor.global_position)
		if not ribbon._points.is_empty():
			tail_lengths.append(ribbon._head.distance_to(ribbon._points.back()))

	_assert_true(head_aligned, "Running wind head stays on the anchor away from world origin")
	_assert_true(tail_lengths.size() == 2 and absf(tail_lengths[0] - tail_lengths[1]) < 0.02,
		"Running wind keeps its trail length at 30 and 60 FPS")
	ribbon.set_emitting(false)
	ribbon._process(0.40)
	_assert_true(ribbon.mesh.get_surface_count() == 0, "Running wind fades out after emission stops")

	ribbon.set_emitting(true)
	ribbon._process(0.02)
	ribbon.clear_trail()
	_assert_true(ribbon.mesh.get_surface_count() == 0 and ribbon._points.is_empty(),
		"Clearing the wind trail removes its mesh and saved world positions")
	anchor.free()


func _test_touch_hud() -> void:
	var controls := ChibiInput.new()
	root.add_child(controls)
	var hud := TouchControlsHUD.new()
	hud.chibi_input = controls
	root.add_child(hud)
	hud.set_touch_visible(true)
	var bounds := root.get_visible_rect()
	var stick_origin := bounds.position + bounds.size * Vector2(0.20, 0.78)
	var look_origin := bounds.position + bounds.size * Vector2(0.68, 0.43)
	var jump := hud.get_node("HUDRoot/TouchRoot/Jump") as Control
	var slide := hud.get_node("HUDRoot/TouchRoot/Slide") as Control
	var pickup := hud.get_node("HUDRoot/TouchRoot/Pickup") as Control
	var stick := hud.get_node("HUDRoot/TouchRoot/Joystick") as Control
	var gear := hud.get_node("HUDRoot/PauseGear") as Control
	var jump_point := jump.get_global_rect().get_center()

	_assert_true(not stick.visible, "Floating touch stick is hidden until claimed")
	_hud_touch(0, stick_origin, true)
	_assert_true(stick.visible and stick.get_global_rect().get_center().is_equal_approx(stick_origin), "Joystick appears under the left thumb")
	_hud_drag(0, stick_origin + Vector2(25, 0), Vector2(25, 0))
	_hud_touch(1, look_origin, true)
	_hud_drag(1, look_origin + Vector2(34, -10), Vector2(34, -10))
	_hud_touch(2, jump_point, true)
	controls.poll(1.0 / 60.0)
	_assert_true(controls.move_vec.x > 0.30 and controls.move_vec.x < 0.65 and controls.look_delta.x > 0.0 and controls.look_delta.y < 0.0
		and controls.jump_held and controls.jump_just_pressed, "Three fingers can steer with partial input, look, and jump at once")

	_hud_drag(1, stick_origin, Vector2(-50, 0))
	_hud_drag(2, look_origin, Vector2(100, 0))
	_hud_touch(2, look_origin, false)
	controls.poll(1.0 / 60.0)
	_assert_true(controls.look_delta.x < 0.0 and controls.move_vec.x > 0.30 and not controls.jump_held and not controls.jump_just_pressed,
		"Touches keep their starting roles after crossing zones and releasing an action")
	_hud_touch(0, jump_point, false)
	_hud_touch(1, stick_origin, false)
	controls.poll(1.0 / 60.0)
	_assert_true(controls.move_vec.is_zero_approx() and controls.look_delta.is_zero_approx() and not stick.visible, "Releasing both thumbs returns touch input to neutral")

	var outside_circle := jump.get_global_rect().position + Vector2(4, 4)
	_hud_touch(3, outside_circle, true)
	_hud_drag(3, outside_circle + Vector2(12, 0), Vector2(12, 0))
	controls.poll(1.0 / 60.0)
	_assert_true(not controls.jump_held and controls.look_delta.x > 0.0, "The open corner of a circle hitbox still lets the player look")
	_hud_touch(3, outside_circle, false)
	_hud_touch(4, jump_point, true)
	_hud_touch(4, jump_point, false, true)
	controls.poll(1.0 / 60.0)
	_assert_true(not controls.jump_held and not controls.jump_just_pressed, "A canceled jump touch drops its pending press")

	hud.update_hud("PoolSwim", 0.0, 0.0)
	var swimming_icons: bool = jump.get("symbol") == "swim_up" and slide.get("symbol") == "dive" and not pickup.visible
	_hud_touch(5, jump_point, true)
	_hud_touch(6, slide.get_global_rect().get_center(), true)
	controls.poll(1.0 / 60.0)
	_assert_true(swimming_icons and controls.rise_held and controls.dive_held, "Swimming silhouettes keep both vertical actions on their existing held inputs")
	hud.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	controls.poll(1.0 / 60.0)
	_assert_true(not controls.rise_held and not controls.dive_held and not controls.slide_just_pressed, "Losing app focus clears held touch actions")

	hud.update_hud("LedgeHang", 0.0, 0.0)
	var ledge_icons: bool = jump.get("symbol") == "ledge" and slide.get("symbol") == "drop"
	hud.update_hud("LedgeShimmy", 0.0, 0.0)
	var shimmy_drop: bool = slide.get("symbol") == "drop"
	hud.update_hud("LedgeCorner", 0.0, 0.0)
	_assert_true(shimmy_drop and slide.get("symbol") == "drop", "Touch keeps the Drop control visible while shimmying and rounding a corner")
	hud.update_hud("ZipLine", 0.0, 0.0)
	_assert_true(ledge_icons and jump.get("symbol") == "off" and slide.get("symbol") == "drop", "Ledge and zipline controls show the climb and dismount silhouettes")
	hud.update_hud("Climbing", 0.0, 0.0, true)
	_assert_true(jump.get("symbol") == "wall_leap" and slide.get("symbol") == "drop", "Wall climbing shows the leap and drop silhouettes")
	hud.update_hud("Locomotion", 0.0, 0.0)

	_hud_touch(0, stick_origin, true)
	_hud_drag(0, stick_origin + Vector2(36, 0), Vector2(36, 0))
	_hud_touch(2, jump_point, true)
	hud._mobile = true
	var gear_point := gear.get_global_rect().get_center()
	_hud_touch(7, gear_point, true)
	_hud_touch(7, gear_point, false)
	controls.poll(1.0 / 60.0)
	_assert_true(paused and hud.menu_open and not stick.visible and controls.move_vec.is_zero_approx() and not controls.jump_just_pressed,
		"Gear opens the modal pause menu and clears gameplay touches")

	await process_frame
	var journal := hud.get_node("HUDRoot/PauseMenu/Journal")
	for tab in ["Gear", "Map", "Journal", "Options"]:
		await _tap_journal_button(journal, tab + "TabButton")
	_assert_true(paused and hud.menu_open, "All four journal tabs are accessible while gameplay is paused")
	await _tap_journal_button(journal, "JournalTabButton")
	var journal_area := journal.find_child("JournalAreaLabel", true, false) as Label
	var berry_count := journal.find_child("BerryCountLabel", true, false) as Label
	_assert_true(journal_area.text == "Area unavailable" and berry_count.text == "0 / 0 collected",
		"The journal preview shows a safe empty state when no level provider is bound")
	await _tap_journal_button(journal, "OptionsTabButton")
	var level_progress := LEVEL_PROGRESS_PROVIDER.new("Preview Garden")
	hud.bind_journal_level_progress(level_progress)
	await _tap_journal_button(journal, "JournalTabButton")
	_assert_true(journal_area.text == "Preview Garden" and berry_count.text == "0 / 0 collected",
		"The journal displays area and progress from its explicitly bound provider")
	level_progress.register_strawberry()
	await process_frame
	_assert_true(berry_count.text == "0 / 1 collected" and journal.find_child("BerryStamp1", true, false) != null,
		"A late strawberry registration updates an open journal")
	level_progress.collect_strawberry()
	level_progress.register_strawberry()
	await process_frame
	_assert_true(berry_count.text == "1 / 2 collected" and journal.find_child("BerryStamp2", true, false) != null,
		"Collection and later pickups keep the open journal progress synchronized")
	await _tap_journal_button(journal, "OptionsTabButton")
	await _tap_journal_button(journal, "GraphicsSectionButton")
	var ultra := journal.find_child("QualityUltraButton", true, false) as Button
	_assert_true(ultra != null and ultra.is_visible_in_tree(), "Graphics index opens the quality presets")
	await _tap_journal_button(journal, "CameraSectionButton")
	await _tap_journal_button(journal, "ViewControlsButton")
	await _tap_journal_button(journal, "TouchControlsToggle")
	_assert_true(paused and not hud.touch_visible, "A mobile tap can toggle touch controls while paused")
	var guide := journal.find_child("ControlsGuide", true, false) as Control
	var inspector := journal.find_child("StateInspectorToggle", true, false) as Button
	if OS.get_cmdline_user_args().has("--debug-menu"):
		_assert_true(inspector != null and inspector.is_visible_in_tree(), "The journal exposes State Inspector in developer mode")
		await _tap_journal_button(journal, "StateInspectorToggle")
		_assert_true(hud._state_debugger.visible, "State Inspector still toggles in developer mode")
	else:
		_assert_true(inspector == null or not inspector.is_visible_in_tree(),
			"The player controls guide hides developer tools")
		hud._toggle_state_debugger()
		_assert_true(not hud._state_debugger.visible, "The developer shortcut is disabled outside developer mode")
	var focus := root.gui_get_focus_owner()
	_assert_true(focus != null and guide.is_ancestor_of(focus), "Opening the guide puts focus inside it")
	for button_name in ["GearTabButton", "ResumeButton"]:
		var button := journal.find_child(button_name, true, false) as BaseButton
		var center := button.get_global_rect().get_center()
		_hud_touch(8, center, true)
		_hud_touch(8, center, false)
	_assert_true(paused and hud.menu_open and guide.is_visible_in_tree(),
		"The guide blocks taps on journal tabs and Resume")
	var focus_stays_in_guide := true
	for step in 6:
		for down in [true, false]:
			var tab := InputEventKey.new()
			tab.keycode = KEY_TAB
			tab.pressed = down
			root.push_input(tab, true)
		focus = root.gui_get_focus_owner()
		focus_stays_in_guide = focus_stays_in_guide and focus != null and guide.is_ancestor_of(focus)
	_assert_true(focus_stays_in_guide, "Tab navigation stays inside the guide until it closes")
	var escape_guide := InputEventAction.new()
	escape_guide.action = &"ui_cancel"
	escape_guide.pressed = true
	root.push_input(escape_guide, true)
	_assert_true(hud.menu_open and not journal.find_child("ControlsGuide", true, false).visible,
		"Back closes the controls guide before returning to gameplay")
	await _tap_journal_button(journal, "ResumeButton")
	_assert_true(not paused and not hud.menu_open, "A touch can resume the paused scene")

	hud._mobile = true
	hud.set_touch_visible(false)
	_assert_true(gear.visible, "The mobile gear stays available when touch controls are turned off")
	hud._mobile = false
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	_assert_true(paused and hud.menu_open, "Escape opens the same menu on desktop")
	await process_frame
	var map_tab := journal.find_child("MapTabButton", true, false) as Button
	map_tab.grab_focus()
	for code in [KEY_RIGHT, KEY_ENTER]:
		for down in [true, false]:
			var nav := InputEventKey.new()
			nav.keycode = code
			nav.pressed = down
			root.push_input(nav, true)
	await process_frame
	_assert_true(journal.find_child("JournalContent", true, false).is_visible_in_tree(),
		"Arrow and Enter switch pages while the game is paused")
	Input.action_press("jump")
	root.push_input(escape, true)
	controls.poll(1.0 / 60.0)
	_assert_true(not paused and not hud.menu_open and not controls.jump_held and not controls.jump_just_pressed,
		"Escape resumes without passing a held menu key into gameplay")
	Input.action_release("jump")
	controls.poll(1.0 / 60.0)
	Input.action_press("jump")
	controls.poll(1.0 / 60.0)
	_assert_true(controls.jump_held, "Desktop jump works again after the menu key is released")
	Input.action_release("jump")

	hud.queue_free()
	controls.queue_free()
	await process_frame


func _tap_journal_button(journal: Node, button_name: String) -> void:
	var button := journal.find_child(button_name, true, false) as BaseButton
	if button == null or not button.is_visible_in_tree():
		_assert_true(false, "Visible journal button: " + button_name)
		return
	var center := button.get_global_rect().get_center()
	_hud_touch(8, center, true)
	_hud_touch(8, center, false)
	await process_frame


func _hud_touch(index: int, point: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event, true)


func _hud_drag(index: int, point: Vector2, change: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point
	event.relative = change
	event.screen_relative = change
	root.push_input(event, true)


func _test_chibi_assets() -> void:
	var ps := load("res://assets/characters/chibi_runner.glb") as PackedScene
	_assert_true(ps != null, "chibi_runner.glb loads cleanly")
	var inst := ps.instantiate()
	var skel := _find_type(inst, "Skeleton3D") as Skeleton3D
	var mi := _find_type(inst, "MeshInstance3D") as MeshInstance3D
	var ap := _find_type(inst, "AnimationPlayer") as AnimationPlayer

	_assert_true(skel != null and skel.get_bone_count() == 35, "Skeleton3D has all 35 bones")
	for b in ["root", "pelvis", "spine_01", "neck_01", "upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r", "thigh_l", "calf_l", "foot_l", "scarf_01", "ahoge_01"]:
		_assert_true(skel.find_bone(b) >= 0, "Bone exists: " + b)
	_assert_true(mi != null and mi.get_blend_shape_count() == 6, "MeshInstance3D has all 6 facial blend shapes")
	_assert_true(ap != null and ap.get_animation_list().size() == 36, "AnimationPlayer has all 36 animations")
	if ap != null:
		var referenced: Dictionary = {}
		var missing_references: Array[String] = []
		for clip in ChibiAnimController.LOOPING_ANIMS:
			if ap.has_animation(clip):
				referenced[clip] = true
			else:
				missing_references.append(clip)
		for state_key in ChibiAnimController.STATE_TO_ANIM:
			var clip: String = ChibiAnimController.STATE_TO_ANIM[state_key]
			if ap.has_animation(clip):
				referenced[clip] = true
			else:
				missing_references.append("%s -> %s" % [state_key, clip])
		for clip in ["Anim_Chibi_Swim", "Anim_Chibi_SurfaceSwim", "Anim_Chibi_TreadWater"]:
			if ap.has_animation(clip):
				referenced[clip] = true
			else:
				missing_references.append(clip)
		var reachable: Array[String] = []
		var unused: Array[String] = []
		for clip_name in ap.get_animation_list():
			if referenced.has(clip_name):
				reachable.append(String(clip_name))
			else:
				unused.append(String(clip_name))
		reachable.sort()
		unused.sort()
		print("[CLIP AUDIT] reachable (%d/36): %s" % [reachable.size(), str(reachable)])
		print("[CLIP AUDIT] unused (%d/36): %s" % [unused.size(), str(unused)])
		var expected_unused := ["Anim_Chibi_RopeClimb", "Anim_Chibi_RopeDrop", "Anim_Chibi_RopeHang"]
		expected_unused.sort()
		_assert_true(missing_references.is_empty() and unused == expected_unused,
			"All 36 clips are classified: 33 reachable and three currently unused Rope variants (missing=%s, unused=%s)" % [str(missing_references), str(unused)])
	for clip in ["Anim_Chibi_Idle", "Anim_Chibi_Run", "Anim_Chibi_Sprint", "Anim_Chibi_Swim", "Anim_Chibi_SurfaceSwim", "Anim_Chibi_TreadWater", "Anim_Chibi_FallFlail", "Anim_Chibi_MantleUp", "Anim_Chibi_BeamIdle", "Anim_Chibi_BeamWalk", "Anim_Chibi_RopeSwing", "Anim_Chibi_SlothCrawl", "Anim_Chibi_ZipGlide", "Anim_Chibi_PolePerch", "Anim_Chibi_BounceAir"]:
		_assert_true(ap.has_animation(clip), "Animation exists: " + clip)

	# Assert EVERY SINGLE ONE of the 36 animations has real keyframe motion (> 5 deg)!
	var frozen_clips: Array[String] = []
	for aname in ap.get_animation_list():
		var anim := ap.get_animation(aname)
		var max_rot := 0.0
		for ti in anim.get_track_count():
			if anim.track_get_type(ti) == Animation.TYPE_ROTATION_3D and anim.track_get_key_count(ti) >= 2:
				var q0: Quaternion = anim.track_get_key_value(ti, 0)
				for ki in range(1, anim.track_get_key_count(ti)):
					var qk: Quaternion = anim.track_get_key_value(ti, ki)
					max_rot = maxf(max_rot, rad_to_deg(q0.angle_to(qk)))
		if max_rot < 5.0:
			frozen_clips.append("%s(%.1fdeg)" % [aname, max_rot])
	_assert_true(frozen_clips.is_empty(), "ALL 36 animations have live bone rotation motion (frozen=%s)" % [str(frozen_clips)])
	inst.free()

func _test_two_bone_ik() -> void:
	var upper := Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0))
	var lower := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.7, 0.0))
	var tip := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.4, 0.0))
	var target := Vector3(0.25, 0.65, -0.25) # distance ~0.495 < L1+L2=0.60

	var res := TwoBoneIK.solve_chain(upper, lower, tip, target, Vector3(0.0, 0.0, 1.0), false)
	var solved_tip: Vector3 = (res["tip"] as Transform3D).origin
	_assert_true(solved_tip.distance_to(target) < 0.002, "TwoBoneIK reaches target within 2 mm (err=%.5f)" % solved_tip.distance_to(target))

	# Beyond max reach -> clamps gracefully without NaNs
	var far_target := Vector3(0.0, 3.0, 0.0)
	var far_res := TwoBoneIK.solve_chain(upper, lower, tip, far_target, Vector3.BACK, true, 0.05)
	var far_tip: Vector3 = (far_res["tip"] as Transform3D).origin
	_assert_true(far_tip.is_finite() and far_tip.distance_to(upper.origin) <= 0.66, "TwoBoneIK beyond-reach clamps cleanly with protraction")


func _test_rope_swing_solver() -> void:
	var angle := 0.0
	var vel := 0.0
	var rope_len := 2.40
	var max_ang := deg_to_rad(56.0)
	var max_seen := 0.0
	for _i in 240:
		var pump := 1.0 if vel >= 0.0 else -1.0
		var r := RopeSwingSolver.advance(1.0 / 60.0, angle, vel, rope_len, pump, 3.4, max_ang)
		angle = r.x
		vel = r.y
		max_seen = maxf(max_seen, absf(angle))
	_assert_true(is_finite(angle) and is_finite(vel), "RopeSwingSolver remains finite over 240 pumping steps")
	_assert_true(max_seen > deg_to_rad(15.0) and max_seen < deg_to_rad(86.0), "RopeSwingSolver builds swing arc (%.1f deg) and stays energy-bounded" % rad_to_deg(max_seen))


func _test_full_gym_and_physics() -> void:
	var gym_ps := load("res://levels/rooftop_gym/rooftop_parkour_gym.tscn") as PackedScene
	_assert_true(gym_ps != null, "rooftop_parkour_gym.tscn loads cleanly")
	var gym := gym_ps.instantiate()
	root.add_child(gym)
	await physics_frame
	await physics_frame

	var chibi := gym.get_node_or_null("ChibiRunner") as ParkourController
	_assert_true(chibi != null, "ChibiRunner instantiated in gym")
	_assert_true(chibi.pose_mod != null, "ChibiPoseModifier bound to Skeleton3D")
	_assert_true(chibi.state_chart != null, "Godot StateChart attached to ChibiRunner")
	_assert_true(chibi.camera_ctrl != null and chibi.camera_ctrl.parkour_pcam != null, "PhantomCamera3D rig attached to ChibiRunner")
	await _test_contextual_pickup(gym, chibi)

	# Verify FindGrip on Zone 2 beveled trimesh ledge!
	var bev := gym.get_node_or_null("Zone2_WallRunAndLedges/LedgeBeveled_Trimesh") as Node3D
	_assert_true(bev != null, "Zone2 beveled trimesh ledge exists")
	if bev != null:
		# Front face is at Z = 7.5 + 1.1 = 8.6, top at Y = 1.65; inward = -Z
		var space := chibi.get_world_3d().direct_space_state
		var left_grip := ChibiPoseModifier.find_grip_in_space(space, [chibi.get_rid()], Vector3(-24.11, 1.65, 8.60), Vector3(0.0, 0.0, -1.0), 1)
		var right_grip := ChibiPoseModifier.find_grip_in_space(space, [chibi.get_rid()], Vector3(-23.89, 1.65, 8.60), Vector3(0.0, 0.0, -1.0), 1)
		_assert_true(left_grip.is_valid() and right_grip.is_valid(), "FindGrip locates beveled top surface for both left & right hands")
		if left_grip.is_valid():
			var wf := left_grip.world_transform()
			_assert_true(wf.basis.y.y >= 0.58 and absf(wf.origin.y - 1.65) < 0.25, "FindGrip top surface normal & height valid (y=%.3f, ny=%.2f)" % [wf.origin.y, wf.basis.y.y])

	# Verify LIVE LedgeHang IK runs AFTER AnimationTree and plants both hands within 1 cm at GPU skin upload!
	var binder := chibi.get_node("ChibiRigBinder") as ChibiRigBinder
	var skel := binder.skeleton
	var pm := chibi.pose_mod
	var last_hand_err := [99.0, 99.0]
	var on_skel := func():
		if pm._ledge_weight > 0.5 and pm._arms[0].active and pm._arms[1].active:
			for s in 2:
				var hw := (skel.global_transform * skel.get_bone_global_pose(pm._arms[s].bones[2])).origin
				last_hand_err[s] = hw.distance_to(pm._arms[s].wrist_world)
	skel.skeleton_updated.connect(on_skel)
	chibi.reset_for_respawn(Vector3(-24.0, 1.11, 8.90))
	chibi.ledge_edge_point = Vector3(-24.0, 1.65, 8.60)
	chibi.ledge_wall_normal = Vector3(0.0, 0.0, 1.0)
	chibi.transition_to("LedgeHang")
	for _i in 10:
		await physics_frame
		await process_frame
	skel.skeleton_updated.disconnect(on_skel)
	for side in 2:
		_assert_true(last_hand_err[side] < 0.01, "Live LedgeHang IK plants hand %d on beveled rim at skin upload (err=%.4f m)" % [side, last_hand_err[side]])
	chibi.transition_to("Locomotion")
	await physics_frame

	# Verify dispatch independently of the geometry needed to run those states.
	for st in ["SpeedVault", "LedgeHang", "LedgeShimmy", "MantleUp", "PoolSwim", "Locomotion"]:
		chibi.transition_to(st)
		_assert_true(chibi.current_state == st, "Transitioned cleanly to state: " + st)

	# Verify Slide & LandRoll entry with realistic velocity & timers
	chibi.global_position = Vector3(0.0, 0.05, 6.0)
	chibi.velocity = Vector3(0.0, 0.0, -5.0)
	await physics_frame
	chibi._start_slide()
	_assert_true(chibi.current_state == "Slide", "Slide entered cleanly with lowered capsule")
	chibi._start_land_roll()
	_assert_true(chibi.current_state == "LandRoll", "LandRoll entered cleanly with timer")
	chibi.transition_to("Locomotion")
	await physics_frame

	# Verify SlothCrawl (upside-down rope hang) attaches Chibi's hands & feet directly onto the rope
	# AND never flips her head above the rope during grab, stop/start, or 180-deg direction reversals!
	var sloth_line := gym.get_node_or_null("Zone4_AerialCircuit/SlothLine_01") as ParkourLine
	_assert_true(sloth_line != null, "SlothLine_01 exists in Zone 4")
	if sloth_line != null:
		var mid_rope := sloth_line.get_rope_world_pos_at_t(0.5)
		chibi.global_position = mid_rope - Vector3(0.0, 0.616, 0.0)
		var entered := chibi.try_enter_parkour_line(sloth_line, false, 0.5, 9.0, 3.8, 7.4)
		_assert_true(entered and chibi.current_state == "RopeLine", "Chibi attaches cleanly to SlothLine_01")
		var max_head_dy := -99.0
		var yaw_fwd := 0.0
		var yaw_rev := 0.0
		for step in 55:
			if step < 15:
				chibi.chibi_input.set_touch_move(Vector2(0.0, -1.0))
			elif step < 20:
				chibi.chibi_input.set_touch_move(Vector2.ZERO)
			elif step < 40:
				chibi.chibi_input.set_touch_move(Vector2(0.0, 1.0))
			else:
				chibi.chibi_input.set_touch_move(Vector2(0.0, -1.0))
			await physics_frame
			await process_frame
			var cur_t := clampf(chibi._line_distance / chibi._line_length, 0.0, 1.0)
			var rw_y := sloth_line.get_rope_world_pos_at_t(cur_t).y
			var head_y := (skel.global_transform * skel.get_bone_global_pose(skel.find_bone("head"))).origin.y
			max_head_dy = maxf(max_head_dy, head_y - rw_y)
			if step == 14:
				yaw_fwd = chibi.rotation.y
			elif step == 39:
				yaw_rev = chibi.rotation.y
		chibi.chibi_input.set_touch_move(Vector2.ZERO)
		var final_t := clampf(chibi._line_distance / chibi._line_length, 0.0, 1.0)
		var rope_world := sloth_line.get_rope_world_pos_at_t(final_t)
		var hl_y := (skel.global_transform * skel.get_bone_global_pose(skel.find_bone("hand_l"))).origin.y
		var fl_y := (skel.global_transform * skel.get_bone_global_pose(skel.find_bone("foot_l"))).origin.y
		var yaw_delta_deg := rad_to_deg(absf(angle_difference(yaw_fwd, yaw_rev)))
		_assert_true(absf(hl_y - rope_world.y) < 0.06 and absf(fl_y - rope_world.y) < 0.06, "SlothHang hands & feet wrap directly onto rope (hand_dy=%.3f m, foot_dy=%.3f m)" % [hl_y - rope_world.y, fl_y - rope_world.y])
		_assert_true(max_head_dy < -0.18, "SlothHang head stays cleanly below rope across all 55 frames of grab & reversal (max_head_dy=%.3f m)" % max_head_dy)
		_assert_true(yaw_delta_deg > 165.0, "SlothHang cleanly rotates 180 deg around Y on direction reversal (delta=%.1f deg)" % yaw_delta_deg)
		chibi._jump_off_rope_line()
		await _wait_physics_frames(7)
		_assert_true(chibi.current_state == "Locomotion" and chibi.anim_ctrl.current_state == "RopeDrop" and _get_clip_phase(chibi.anim_ctrl, "RopeDrop") > 0.2, "Rope dismount pose advances without being replaced by the airborne loop")

	# Verify Unreal Gravity (16.17 m/s^2) jump arc & air braking
	chibi.reset_for_respawn(Vector3(0.0, 0.02, 12.0))
	chibi.velocity = Vector3(0.0, 0.0, -4.8)
	await physics_frame
	await physics_frame
	var start_y := chibi.global_position.y
	chibi._execute_ground_jump()
	var peak_y := start_y
	for _jf in 45:
		await physics_frame
		peak_y = maxf(peak_y, chibi.global_position.y)
	var jump_h := peak_y - start_y
	var end_spd := Vector2(chibi.velocity.x, chibi.velocity.z).length()
	_assert_true(jump_h > 0.64 and jump_h < 0.78, "Jump peak height matches Unreal 16.17 m/s^2 gravity (h=%.3f m, expected ~0.71 m)" % jump_h)
	_assert_true(end_spd < 1.5, "Air braking decelerates unpowered horizontal velocity (end_spd=%.2f m/s)" % end_spd)

	# Verify ZipLine moving pulley (0.76 m strap), hands locked onto PulleyHandle, and head clearance!
	var zip_line := gym.get_node_or_null("Zone4_AerialCircuit/ZipLine_01") as ParkourLine
	_assert_true(zip_line != null and zip_line.is_zip_line, "ZipLine_01 exists in Zone 4")
	if zip_line != null:
		var zip_len := zip_line.end_offset.length()
		var zip_start_rope := zip_line.get_rope_world_pos_at_t(0.10)
		chibi.global_position = zip_start_rope - Vector3(0.0, 1.325, 0.0)
		chibi.velocity = Vector3(0.0, -0.5, -4.5)
		var z_ok := chibi.try_enter_parkour_line(zip_line, true, 0.10, zip_len, zip_line.zip_speed_min, zip_line.zip_speed_max)
		_assert_true(z_ok and chibi.current_state == "ZipLine", "Chibi attaches cleanly to ZipLine_01")
		var start_pulley_pos := zip_line.get_pulley_handle_world_pos()
		for _zf in 25:
			await physics_frame
			await process_frame
		var mid_pulley_pos := zip_line.get_pulley_handle_world_pos()
		var pulley_travel := start_pulley_pos.distance_to(mid_pulley_pos)
		var zh_l := (skel.global_transform * skel.get_bone_global_pose(skel.find_bone("hand_l"))).origin
		var zh_r := (skel.global_transform * skel.get_bone_global_pose(skel.find_bone("hand_r"))).origin
		var z_hands_mid := (zh_l + zh_r) * 0.5
		var z_head := (skel.global_transform * skel.get_bone_global_pose(skel.find_bone("head"))).origin
		var z_rope_now := zip_line.get_rope_world_pos_at_t(zip_line._rider_t)
		var hand_to_bar := z_hands_mid.distance_to(mid_pulley_pos)
		var head_clearance := z_rope_now.y - z_head.y
		_assert_true(pulley_travel > 1.2, "ZipLine pulley glides smoothly along cable with rider (travel=%.2f m)" % pulley_travel)
		_assert_true(hand_to_bar < 0.12, "ZipLine hands grip moving 0.76 m PulleyHandle (err=%.3f m)" % hand_to_bar)
		_assert_true(head_clearance > 0.65, "ZipLine head clears cable cleanly (clearance=%.3f m)" % head_clearance)
		chibi._jump_off_zip_line()
		await physics_frame
		var reset_pulley_dist := zip_line.get_pulley_handle_world_pos().distance_to(zip_line.get_rope_world_pos_at_t(0.0) - Vector3(0.0, 0.76, 0.0))
		_assert_true(reset_pulley_dist < 0.02, "ZipLine pulley resets to cable start on release (err=%.3f m)" % reset_pulley_dist)
		chibi.reset_for_respawn(zip_start_rope - Vector3(0.0, 1.325, 0.0))
		var reattached := chibi.try_enter_parkour_line(zip_line, true, 0.10, zip_len, zip_line.zip_speed_min, zip_line.zip_speed_max)
		var new_spawn := Vector3(4.0, 0.06, 21.0)
		chibi.reset_for_respawn(new_spawn)
		_assert_true(reattached and chibi._active_line == null and not zip_line._has_rider and chibi.current_state == "Locomotion"
			and chibi.anim_ctrl.current_state == "LocomotionGait" and chibi.velocity.is_zero_approx() and chibi.global_position.is_equal_approx(new_spawn),
			"Respawn releases an active zipline and resets movement and animation")
	if sloth_line != null and zip_line != null:
		await _test_parkour_line_keyboard(chibi, sloth_line)
		await _test_parkour_line_keyboard(chibi, zip_line)

	# Verify the Zone 3 wall remains and the removed rooftop net is absent.
	var cwall := gym.get_node_or_null("Zone3_ClimbingPlaza/Climb_HandholdWall") as Node3D
	_assert_true(cwall != null and cwall.is_in_group("climbable_wall"), "Collision-based climbing wall active in Zone 3")
	_assert_true(gym.get_node_or_null("Zone3_ClimbingPlaza/Climb_RopeNet") == null,
		"Removed rope net station is absent from Zone 3")
	if cwall != null:
		await preload("res://tests/dynamic_wall_checks.gd").new().run(self, chibi, cwall, _assert_true)

	# Exercise the reusable body inside the generated rooftop basin.
	var pool := gym.get_node_or_null("Zone5_SlopedSwimPool") as ChibiPool
	_assert_true(pool != null and pool.water_body != null, "Reusable water active in the rooftop basin")
	if pool != null and pool.water_body != null:
		var floor_query := PhysicsRayQueryParameters3D.create(
			pool.to_global(Vector3(15.0, ChibiPool.WATER_Y, 0.0)),
			pool.to_global(Vector3(15.0, ChibiPool.WATER_Y - ChibiPool.POOL_DEPTH - 0.10, 0.0)), 1
		)
		var space := pool.get_world_3d().direct_space_state
		var floor_hit := space.intersect_ray(floor_query)
		var deep_floor_y := pool.to_global(Vector3(0.0, ChibiPool.WATER_Y - ChibiPool.POOL_DEPTH, 0.0)).y
		_assert_true(not floor_hit.is_empty() and floor_hit.collider.name == &"BasinBed"
			and absf(floor_hit.position.y - deep_floor_y) < 0.04,
			"Rooftop deck clears the actual deep basin floor")
		var dry_corner := pool.to_global(Vector3(0.95, 0.42, 3.55))
		var dry_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(dry_corner, dry_corner - Vector3.UP, 1))
		var boundary_probe := pool.to_global(Vector3(15.0, 0.4, 3.55))
		_assert_true(not pool.water_body.contains_horizontal(dry_corner)
			and pool.water_body.contains_horizontal(boundary_probe) and not dry_hit.is_empty()
			and dry_hit.collider.name == &"BasinDeckInfill" and absf(dry_hit.position.y) < 0.02,
			"The narrower shelf leaves a dry roof corner beside the wide deep end")

		var shelf_above := pool.to_global(Vector3(3.5, ChibiPool.WATER_Y + 0.20, 0.0))
		var shelf_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(shelf_above, shelf_above - Vector3.UP, 1))
		var wade_start: Vector3 = shelf_above if shelf_hit.is_empty() else shelf_hit.position + Vector3.UP * 0.025
		chibi.reset_for_respawn(wade_start)
		await physics_frame
		await physics_frame
		_assert_true(chibi.external_walk_speed_cap > 1.7 and chibi.external_walk_speed_cap < 4.2, "ChibiPool wading smoothly slows walk speed cap (cap=%.2f m/s)" % chibi.external_walk_speed_cap)

		await _wait_physics_frames(30)
		var idle_wrist := chibi.pose_mod.get_wade_wrist_world(0)
		var idle_position := chibi.global_position
		var wrist_motion := 0.0
		for sample in 5:
			await _wait_physics_frames(8)
			var wrist := chibi.pose_mod.get_wade_wrist_world(0)
			if idle_wrist.is_finite() and wrist.is_finite():
				wrist_motion = maxf(wrist_motion, idle_wrist.distance_to(wrist))
		var left_wrist := chibi.pose_mod.get_wade_wrist_world(0)
		var other_wrist := chibi.pose_mod.get_wade_wrist_world(1)
		var hand_span := left_wrist.distance_to(other_wrist) if left_wrist.is_finite() and other_wrist.is_finite() else 0.0
		_assert_true(chibi.current_state == "Locomotion" and chibi.is_on_floor()
			and chibi.global_position.distance_to(idle_position) < 0.02
			and wrist_motion > 0.017 and hand_span > 0.39,
			"Standing on the rooftop shelf stays grounded while the hands move (travel %.3f m, span %.3f m)" % [wrist_motion, hand_span])

		# Check the horizontal stroke during active travel, independent of the submerged idle.
		chibi.reset_for_respawn(pool.to_global(Vector3(15.0, ChibiPool.WATER_Y - 1.50, 0.0)))
		chibi.chibi_input.set_touch_move(Vector2.UP)
		for _sf in 35:
			await physics_frame
			await process_frame
		_assert_true(chibi.current_state == "PoolSwim" and chibi.get_active_water() == pool.water_body,
			"Chibi enters PoolSwim cleanly in the rooftop basin")
		var sw_pel := skel.get_bone_global_pose(skel.find_bone("pelvis")).origin
		var sw_head := skel.get_bone_global_pose(skel.find_bone("head")).origin
		var sw_foot := skel.get_bone_global_pose(skel.find_bone("foot_l")).origin
		var head_fwd_offset := absf(sw_head.z - sw_pel.z)
		_assert_true(sw_pel.y > 0.44 and head_fwd_offset > 0.22 and absf(sw_foot.y - sw_pel.y) < 0.15, "Retargeted Anim_Chibi_Swim is properly horizontal (pel_y=%.2f m, head_fwd=%.2f m, foot_y=%.2f m)" % [sw_pel.y, head_fwd_offset, sw_foot.y])
		chibi.chibi_input.set_touch_move(Vector2.ZERO)

		chibi.reset_for_respawn(pool.to_global(Vector3(15.0, 0.42, 3.06)))
		var saved_yaw := chibi.camera_ctrl.yaw
		chibi.camera_ctrl.yaw = -PI / 2.0
		chibi.rotation.y = -PI / 2.0
		await _wait_physics_frames(50)
		var gear := chibi.pose_mod.dive_gear
		var started_in_water := chibi.current_state == "PoolSwim"
		var gear_held_during_mantle := true
		chibi.chibi_input.set_touch_move(Vector2.UP)
		chibi.chibi_input.set_touch_jump(true)
		var mantled := false
		for _frame in 80:
			await _wait_physics_frames(1)
			if chibi.current_state == "MantleUp":
				mantled = true
				gear_held_during_mantle = gear_held_during_mantle and gear.progress == 1.0 and gear.gesture_weight == 0.0
				chibi.chibi_input.set_touch_move(Vector2.ZERO)
				chibi.chibi_input.set_touch_jump(false)
			elif mantled and chibi.current_state == "Locomotion":
				break
		chibi.chibi_input.set_touch_move(Vector2.ZERO)
		chibi.chibi_input.set_touch_jump(false)
		chibi.camera_ctrl.yaw = saved_yaw
		_assert_true(started_in_water and mantled and chibi.current_state == "Locomotion"
			and chibi.global_position.y > pool.water_body.get_surface_height(),
			"Held Rise mantles out of the rooftop basin onto the coping")
		_assert_true(mantled and gear_held_during_mantle,
			"Dive gear stays fitted through pool mantle while both hands are on the ledge")
		await _wait_physics_frames(50)
		_assert_true(gear.progress == 0.0, "After the mantle she stows the mask and snorkel")

		chibi.reset_for_respawn(pool.to_global(Vector3(15.0, ChibiPool.WATER_Y - 1.50, 0.0)))
		await _wait_physics_frames(4)
		(gym as RooftopGymController).teleport_to_zone(4)
		await _wait_physics_frames(12)
		_assert_true(chibi.current_state == "Locomotion" and chibi.get_active_water() == null
			and chibi.external_walk_speed_cap > chibi.config.max_flow_speed, "A dry rooftop respawn clears water state and speed cap")

	await _test_runner_motion(gym, chibi, skel)
	await _test_wall_run_and_roll(gym, chibi)
	await _test_running_turns_at_render_rates(chibi)
	await _test_ground_foot_drift(chibi)
	await _test_running_landing_overlay(chibi)
	await _test_station_overlap_after_respawn(gym, chibi)
	await preload("res://tests/rooftop_station_regressions.gd").new().run(self, gym, chibi, _assert_true)
	await preload("res://tests/balance_footing_regression.gd").new().run(self, _assert_true, gym, chibi, skel)
	await preload("res://tests/scarf_glide_regressions.gd").new().run(self, gym, chibi, _assert_true)
	await _test_automatic_ledge(chibi)
	await preload("res://tests/rooftop_ledge_vault_regressions.gd").new().run(self, gym, chibi, _assert_true)
	await preload("res://tests/wind_tunnel_regressions.gd").new().run(self, gym, chibi, _assert_true)
	await preload("res://tests/wind_assisted_glide_regressions.gd").new().run(self, gym, chibi, _assert_true)

	gym.queue_free()
	await process_frame
	await process_frame


func _test_contextual_pickup(gym: Node3D, chibi: ParkourController) -> void:
	var item := gym.get_node("Zone1_FlowAndSlides/StrawberryPickup") as Node3D
	var level_progress := chibi.touch_hud.journal_level_progress_provider
	_assert_true(gym.get("strawberries_total") == 1 and gym.get("strawberries_collected") == 0,
		"The Journal starts with the rooftop strawberry available")
	_assert_true(level_progress != null and level_progress.get_area_name() == "Rooftop Parkour Gym"
		and level_progress.get_berry_progress() == Vector2i(0, 1),
		"The rooftop explicitly binds its area and starting progress to the HUD")
	var button := chibi.touch_hud.get_node("HUDRoot/TouchRoot/Pickup") as Control
	chibi.touch_hud.set_touch_visible(true)
	var point := button.get_global_rect().get_center()
	_hud_touch(11, point, true)
	await _wait_physics_frames(2)
	_hud_touch(11, point, false)
	_assert_true(not button.visible and is_instance_valid(item), "The pickup circle is hidden and inactive out of reach")

	var approach := item.global_position - Vector3(0.85, 0.18, 0)
	chibi.reset_for_respawn(approach)
	await _wait_physics_frames(4)
	_assert_true(button.visible and button.get("symbol") == "pickup", "Entering reach reveals the strawberry silhouette")

	var blocker := _test_collision_box(gym, item.global_position - Vector3(0.40, -0.34, 0.0), Vector3(0.12, 1.1, 0.5))
	await _wait_physics_frames(3)
	_assert_true(not button.visible, "A wall between Chibi and the item hides the pickup circle")
	blocker.queue_free()
	await _wait_physics_frames(3)
	_hud_touch(11, point, true)
	_hud_touch(11, point, false, true)
	await _wait_physics_frames(2)
	_assert_true(button.visible and is_instance_valid(item), "A canceled pickup touch leaves the item available")
	_hud_touch(11, point, true)
	await _wait_physics_frames(3)
	_hud_touch(11, point, false)
	_assert_true(not is_instance_valid(item) and not button.visible and chibi.current_state == "Locomotion",
		"Tapping the strawberry collects it, hides the circle, and preserves locomotion")

	var second_item := preload("res://features/items/strawberry_pickup.tscn").instantiate() as Node3D
	gym.add_child(second_item)
	second_item.global_position = approach + Vector3(0.65, 0.32, 0.0)
	await _wait_physics_frames(3)
	var pickup_key := InputEventKey.new()
	pickup_key.physical_keycode = KEY_E
	pickup_key.pressed = true
	Input.parse_input_event(pickup_key)
	Input.flush_buffered_events()
	await _wait_physics_frames(3)
	pickup_key.pressed = false
	Input.parse_input_event(pickup_key)
	Input.flush_buffered_events()
	_assert_true(not is_instance_valid(second_item) and not button.visible, "The desktop pickup key collects a reachable item")
	_assert_true(gym.get("strawberries_total") == 2 and gym.get("strawberries_collected") == 2,
		"The Journal counts both the original and newly added strawberry")
	_assert_true(level_progress.get_berry_progress() == Vector2i(2, 2),
		"Late rooftop pickups update the level provider consumed by the Journal")
	chibi.touch_hud.set_touch_visible(false)
	chibi.reset_for_respawn(Vector3(0, 0.1, 6))
	await _wait_physics_frames(4)


func _test_automatic_ledge(chibi: ParkourController) -> void:
	chibi.reset_for_respawn(Vector3(-24.0, 0.035, 3.73))
	chibi.rotation.y = 0.0
	chibi.camera_ctrl.yaw = 0.0
	await _wait_physics_frames(9)
	chibi.chibi_input.set_touch_move(Vector2.UP)
	chibi.chibi_input.set_touch_jump(true)
	await _wait_physics_frames(2)
	chibi.chibi_input.set_touch_jump(false)
	var caught := false
	var mantled := false
	for _tick in 85:
		await _wait_physics_frames(1)
		caught = caught or chibi.current_state == "LedgeHang"
		mantled = mantled or chibi.current_state == "MantleUp"
		if mantled and chibi.current_state == "Locomotion":
			break
	_assert_true(caught and mantled and chibi.global_position.y > 1.6, "Jump with forward movement catches and climbs the ledge")
	chibi.chibi_input.clear_touch_input()
	chibi.reset_for_respawn(Vector3(0, 0.1, 6))
	await _wait_physics_frames(4)


func _test_parkour_line_keyboard(chibi: ParkourController, line: ParkourLine) -> void:
	var line_dir := line.get_line_direction()
	var horizontal_dir := Vector3(line_dir.x, 0.0, line_dir.z)
	var feet_offset := Vector3.UP * 0.616
	if line.is_zip_line:
		feet_offset = Vector3.UP * 1.325 + horizontal_dir.normalized() * 0.29
	var spawn := line.get_rope_world_pos_at_t(0.5) - feet_offset
	for key: Key in [KEY_C, KEY_CTRL, KEY_SPACE]:
		await physics_frame
		chibi.reset_for_respawn(spawn)
		chibi.chibi_input.set_touch_move(Vector2.ZERO)
		for _i in 10:
			await physics_frame
		var attached := chibi._active_line == line and line._has_rider
		var entry_speed := chibi._zip_speed
		var before_release := chibi.global_position
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.pressed = true
		event.ctrl_pressed = key == KEY_CTRL
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		for _i in 3:
			await physics_frame
			if chibi.current_state == "Locomotion":
				break
		var released := chibi.current_state == "Locomotion" and chibi._active_line == null and not line._has_rider and chibi.line_cooldown > 0.0
		var moved_as_expected := chibi.velocity.y > 1.5 and chibi.global_position.y > before_release.y
		if key != KEY_SPACE:
			var forward_velocity := Vector3(chibi.velocity.x, 0.0, chibi.velocity.z)
			var expected := horizontal_dir * entry_speed if line.is_zip_line else Vector3.ZERO
			moved_as_expected = chibi.velocity.y < 0.0 and chibi.global_position.y < before_release.y and forward_velocity.distance_to(expected) < 0.25
		var pulley_reset := not line.is_zip_line or line.get_pulley_handle_world_pos().distance_to(
			line.get_rope_world_pos_at_t(0.0) - Vector3.UP * 0.76
		) < 0.02
		_assert_true(attached and released and moved_as_expected and pulley_reset,
			"%s %s from %s (velocity %s, attached=%s, released=%s)" % [
				OS.get_keycode_string(key), "jumps off" if key == KEY_SPACE else "drops", line.name, chibi.velocity, attached, released
			])
		var key_up := InputEventKey.new()
		key_up.physical_keycode = key
		Input.parse_input_event(key_up)
		Input.flush_buffered_events()

	var hud := chibi.touch_hud
	hud.set_touch_visible(true)
	for button_name in ["Slide", "Jump"]:
		await physics_frame
		chibi.reset_for_respawn(spawn)
		for _i in 10:
			await physics_frame
		var attached := chibi._active_line == line
		var circle := hud.get_node("HUDRoot/TouchRoot/" + button_name) as Control
		var point := circle.get_global_rect().get_center()
		_hud_touch(6, point, true)
		for _i in 3:
			await physics_frame
			if chibi.current_state == "Locomotion":
				break
		var released := chibi.current_state == "Locomotion" and chibi._active_line == null and not line._has_rider
		var motion_matches := chibi.velocity.y < 0.0 if button_name == "Slide" else chibi.velocity.y > 1.5
		_assert_true(attached and released and motion_matches, "Touch %s releases from %s with the expected motion" % [button_name, line.name])
		_hud_touch(6, point, false)
	hud.set_touch_visible(false)


func _test_runner_motion(gym: Node3D, chibi: ParkourController, skeleton: Skeleton3D) -> void:
	var anim := chibi.anim_ctrl
	var playback := anim.anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	var root_sm := anim.anim_tree.tree_root as AnimationNodeStateMachine
	var missing_state_nodes: Array[String] = []
	for state_key in ChibiAnimController.STATE_TO_ANIM:
		if not root_sm.has_node(state_key):
			missing_state_nodes.append(state_key)
	_assert_true(missing_state_nodes.is_empty(), "Live AnimationTree has every configured action state (missing=%s)" % str(missing_state_nodes))
	var ground_contacts: Array[StringName] = []
	var record_contact := func(foot: StringName): ground_contacts.append(foot)
	anim.ground_foot_contact.connect(record_contact)
	chibi.reset_for_respawn(Vector3(4.0, 0.06, 21.0))
	chibi.camera_ctrl.yaw = 0.0
	chibi.chibi_input.set_touch_move(Vector2(0.0, -0.5))
	await _wait_physics_frames(52)
	_assert_true(absf(chibi.resolved_planar_speed - chibi.config.base_run_speed * 0.5) < 0.16, "Half stick gives half running speed")
	chibi.chibi_input.set_touch_move(Vector2(0.0, -1.0))
	await _wait_physics_frames(55)
	var gait_path := ChibiAnimController.GAIT_PATH + "Strides/"
	var run_pos: float = anim.anim_tree.get(gait_path + "Run/current_position")
	var sprint_pos: float = anim.anim_tree.get(gait_path + "Sprint/current_position")
	var run_len: float = anim.anim_tree.get(gait_path + "Run/current_length")
	var sprint_len: float = anim.anim_tree.get(gait_path + "Sprint/current_length")
	var phase_gap := absf(wrapf(run_pos / run_len - sprint_pos / sprint_len, -0.5, 0.5))
	_assert_true(phase_gap < 0.04, "Run and sprint share normalized stride phase (gap=%.3f)" % phase_gap)
	var alternating := ground_contacts.size() >= 3
	for i in range(1, ground_contacts.size()):
		alternating = alternating and ground_contacts[i - 1] != ground_contacts[i]
	_assert_true(alternating, "Ground cadence emits alternating foot contact cues (%d contacts)" % ground_contacts.size())

	var wall_at := chibi.global_position + Vector3.FORWARD * 1.5 + Vector3.UP
	var blocker := _test_collision_box(gym, wall_at, Vector3(3.0, 2.0, 0.2))
	await _wait_physics_frames(32)
	var contacts_when_blocked := ground_contacts.size()
	await _wait_physics_frames(22)
	_assert_true(chibi.resolved_planar_speed < 0.05 and anim._ground_weight < 0.10 and ground_contacts.size() == contacts_when_blocked, "Running into a wall settles to idle without footsteps")
	anim.ground_foot_contact.disconnect(record_contact)
	blocker.queue_free()
	chibi.chibi_input.set_touch_move(Vector2.ZERO)
	chibi.reset_for_respawn(Vector3(4.0, 0.06, 21.0))
	await _wait_physics_frames(18)
	chibi.chibi_input.set_touch_jump(true)
	await _wait_physics_frames(2)
	chibi.chibi_input.set_touch_jump(false)
	var jump_clip_progress := 0.0
	var landing_clip_progress := 0.0
	var blended_landing := false
	var normal_jump_flailed := false
	for _i in 55:
		await _wait_physics_frames(1)
		if playback.get_current_node() == &"JumpStart":
			jump_clip_progress = maxf(jump_clip_progress, _get_clip_phase(anim, "JumpStart"))
		elif playback.get_current_node() == &"LandSoft":
			landing_clip_progress = maxf(landing_clip_progress, _get_clip_phase(anim, "LandSoft"))
			blended_landing = blended_landing or playback.get_fading_from_node() == &"FallLoop"
		normal_jump_flailed = normal_jump_flailed or playback.get_current_node() == &"FallFlail"
	_assert_true(jump_clip_progress > 0.35, "JumpStart advances past takeoff (phase %.3f)" % jump_clip_progress)
	_assert_true(landing_clip_progress > 0.5 and blended_landing and not normal_jump_flailed,
		"Ordinary jump crossfades directly from fall to landing compression (phase %.3f)" % landing_clip_progress)

	chibi.request_jump()
	await _wait_physics_frames(31)
	chibi.chibi_input.set_touch_jump(true)
	await _wait_physics_frames(2)
	chibi.chibi_input.set_touch_jump(false)
	var buffered_launch := false
	var buffered_landing_pose := false
	for _i in 28:
		await _wait_physics_frames(1)
		buffered_launch = buffered_launch or (playback.get_current_node() == &"JumpStart" and _get_clip_phase(anim, "JumpStart") > 0.1)
		buffered_landing_pose = buffered_landing_pose or playback.get_current_node() == &"LandSoft"
	_assert_true(buffered_launch and not buffered_landing_pose, "Buffered landing jump takes priority over the soft landing pose")

	var vault_bar := gym.get_node("Zone1_FlowAndSlides/VaultBar_Low") as StaticBody3D
	var bar_collision := _find_type(vault_bar, "CollisionShape3D") as CollisionShape3D
	var bar_size := (bar_collision.shape as BoxShape3D).size
	var front_z := bar_collision.global_position.z + bar_size.z * 0.5
	var top_y := bar_collision.global_position.y + bar_size.y * 0.5
	for flow: float in [0.0, 1.0]:
		chibi.reset_for_respawn(Vector3(vault_bar.global_position.x, 0.15, front_z + 1.0))
		chibi.rotation.y = 0.0
		chibi.flow_level = flow
		chibi.velocity = Vector3(0.0, 1.5, -lerpf(chibi.config.base_run_speed, chibi.config.max_flow_speed, flow))
		var found := chibi._try_start_speed_vault()
		_assert_true(found, "Real rooftop bar starts a vault at flow %.1f" % flow)
		var phase_error := 0.0
		var plant_sample := [INF, INF]
		var sample_plant := func():
			if chibi.current_state != "SpeedVault":
				return
			var distance_from_plant := absf(chibi._vault_alpha - 0.24)
			if distance_from_plant < plant_sample[0]:
				var hand := (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hand_l"))).origin
				var rail := Vector3(hand.x, top_y, clampf(hand.z, front_z - bar_size.z, front_z))
				plant_sample[0] = distance_from_plant
				plant_sample[1] = hand.distance_to(rail)
		skeleton.skeleton_updated.connect(sample_plant)
		for _i in 60:
			await _wait_physics_frames(1)
			if chibi.current_state != "SpeedVault":
				break
			var phase := _get_clip_phase(anim, "SpeedVault")
			phase_error = maxf(phase_error, absf(chibi._vault_alpha - phase))
		skeleton.skeleton_updated.disconnect(sample_plant)
		var hand_error: float = plant_sample[1]
		_assert_true(phase_error < 0.065 and hand_error < 0.085 and chibi.current_state == "Locomotion" and chibi.get_collision_mask_value(1),
			"Vault clip follows body through plant and clearance at flow %.1f (phase error %.3f, contact %.3f m)" % [flow, phase_error, hand_error])

	for flow: float in [0.0, 1.0]:
		chibi.reset_for_respawn(Vector3(-24.0, 1.1, 8.8))
		chibi.ledge_edge_point = Vector3(-24.0, 1.65, 8.6)
		chibi.ledge_wall_normal = Vector3.BACK
		chibi.transition_to("LedgeHang")
		await _wait_physics_frames(8)
		chibi.flow_level = flow
		chibi.start_ledge_mantle()
		# The body interpolates between physics ticks. Sample its clip after the
		# mixer applies that same rendered frame, including at lower render rates.
		var mantle_sample := {"error": 0.0, "first": 1.0, "last": 0.0}
		var sample_mantle := func():
			if chibi.current_state != "MantleUp":
				return
			# On entry the mixer may still have the zero-time seek queued.
			# Its clip telemetry then belongs to the preceding mantle.
			if anim.anim_tree.get("parameters/MantleUp/Phase/seek_request") >= 0.0:
				return
			var step := 1.0 / (Engine.physics_ticks_per_second * chibi._mantle_duration)
			var previous := maxf(0.0, chibi.mantle_alpha - step)
			var expected := lerpf(previous, chibi.mantle_alpha, Engine.get_physics_interpolation_fraction())
			var clip_phase := _get_clip_phase(anim, "MantleUp")
			mantle_sample.error = maxf(mantle_sample.error, absf(expected - clip_phase))
			mantle_sample.first = minf(mantle_sample.first, clip_phase)
			mantle_sample.last = maxf(mantle_sample.last, clip_phase)
		anim.anim_tree.mixer_applied.connect(sample_mantle)
		for _i in 75:
			await physics_frame
			if chibi.current_state != "MantleUp":
				break
		anim.anim_tree.mixer_applied.disconnect(sample_mantle)
		var sampled_lift: bool = mantle_sample.first < 0.15 and mantle_sample.last > 0.85
		_assert_true(sampled_lift and mantle_sample.error < 0.065 and chibi.current_state == "Locomotion" and chibi.get_collision_mask_value(1) and chibi.global_position.y > 1.6,
			"Mantle clip follows ledge release and landing at flow %.1f (phase error %.3f)" % [flow, mantle_sample.error])

	var ceiling := _test_collision_box(gym, Vector3(4.0, 1.1, 16.0), Vector3(2.5, 0.55, 4.0))
	chibi.reset_for_respawn(Vector3(4.0, 0.06, 18.6))
	await _wait_physics_frames(18)
	chibi.velocity = Vector3(0.0, 0.0, -5.0)
	chibi._start_slide()
	await _wait_physics_frames(35)
	chibi._try_end_slide()
	_assert_true(chibi.current_state == "Slide" and not chibi.pose_mod.slide_dive_active and chibi._current_half_height() < 0.4, "Slide dive completes once and holds a low capsule under the gate")
	for _i in 45:
		if chibi.current_state != "Slide":
			break
		await _wait_physics_frames(1)
	var full_body_clear := chibi.global_position.z < ceiling.global_position.z - 2.0 - 0.22
	_assert_true(chibi.current_state == "Locomotion" and chibi._current_half_height() > 0.55 and full_body_clear,
		"Slide stands only after the capsule clears the gate edge (z=%.3f)" % chibi.global_position.z)
	ceiling.queue_free()


func _test_wall_run_and_roll(gym: Node3D, chibi: ParkourController) -> void:
	var anim := chibi.anim_ctrl
	var wall := gym.get_node("Zone2_WallRunAndLedges/WallRun_Left1") as StaticBody3D
	var wall_collision := _find_type(wall, "CollisionShape3D") as CollisionShape3D
	var wall_face := wall_collision.global_position.x + (wall_collision.shape as BoxShape3D).size.x * 0.5
	var along_wall := Vector2(0.0, -1.0)
	chibi.camera_ctrl.yaw = 0.0
	for scenario in [
		[0.44, 0, along_wall, "A casual hop beside the wall stays in locomotion as Chibi speeds up"],
		[0.44, 11, Vector2.ZERO, "A running jump without continued steering stays in locomotion"],
		[0.60, 11, along_wall, "A running jump outside close wall reach stays in locomotion"],
	]:
		chibi.chibi_input.set_touch_move(Vector2.ZERO)
		chibi.reset_for_respawn(Vector3(wall_face + float(scenario[0]), 0.06, -3.0))
		chibi.rotation.y = 0.0
		await _wait_physics_frames(18)
		chibi.chibi_input.set_touch_move(along_wall)
		await _wait_physics_frames(scenario[1])
		chibi.chibi_input.set_touch_jump(true)
		await _wait_physics_frames(2)
		var jumped := not chibi.is_on_floor() and chibi.velocity.y > 3.0
		chibi.chibi_input.set_touch_jump(false)
		chibi.chibi_input.set_touch_move(scenario[2])
		var stayed_in_locomotion := true
		for _i in 30:
			await _wait_physics_frames(1)
			stayed_in_locomotion = stayed_in_locomotion and chibi.current_state == "Locomotion"
		_assert_true(jumped and stayed_in_locomotion, scenario[3])

	var platform := _test_collision_box(gym, Vector3(wall_face + 0.48, 1.10, -1.45), Vector3(0.96, 0.2, 1.7))
	chibi.chibi_input.set_touch_move(Vector2.ZERO)
	chibi.reset_for_respawn(Vector3(wall_face + 0.44, 1.28, -0.80))
	chibi.rotation.y = 0.0
	await _wait_physics_frames(18)
	var started_on_ledge := chibi.is_on_floor()
	var fell_from_ledge := false
	var ran_during_drop := false
	chibi.chibi_input.set_touch_move(along_wall)
	for _i in 55:
		await _wait_physics_frames(1)
		fell_from_ledge = fell_from_ledge or (not chibi.is_on_floor() and chibi.velocity.y < -2.0)
		ran_during_drop = ran_during_drop or chibi.current_state == "WallRun"
	_assert_true(started_on_ledge and fell_from_ledge and not ran_during_drop,
		"Running off a high ledge beside a wall produces a normal fall")
	platform.queue_free()

	chibi.chibi_input.set_touch_move(Vector2.ZERO)
	chibi.reset_for_respawn(Vector3(wall_face + 0.44, 0.06, -3.0))
	chibi.rotation.y = 0.0
	await _wait_physics_frames(18)
	chibi.chibi_input.set_touch_move(along_wall)
	await _wait_physics_frames(11)
	chibi.chibi_input.set_touch_jump(true)
	await _wait_physics_frames(2)
	chibi.chibi_input.set_touch_jump(false)
	var last_x := chibi.global_position.x
	var max_wall_step := 0.0
	for _i in 21:
		await _wait_physics_frames(1)
		max_wall_step = maxf(max_wall_step, absf(chibi.global_position.x - last_x))
		last_x = chibi.global_position.x
	var wall_gap := chibi.global_position.x - wall_face
	_assert_true(chibi.current_state == "WallRun" and wall_gap > chibi.config.capsule_radius and wall_gap < 0.35
		and max_wall_step < 0.067 and absf(chibi.velocity.z) >= chibi.config.wall_run_base_speed,
		"Wall run closes the gap while preserving capsule clearance and forward speed (gap %.3f m, max correction %.3f m)" % [wall_gap, max_wall_step])
	chibi.chibi_input.set_touch_move(Vector2(0.70, -0.714))
	chibi.chibi_input.set_touch_jump(true)
	await _wait_physics_frames(2)
	chibi.chibi_input.set_touch_jump(false)
	await _wait_physics_frames(7)
	_assert_true(chibi.current_state == "Locomotion" and anim.current_state == "WallKick" and _get_clip_phase(anim, "WallKick") > 0.15
		and chibi.velocity.x > 1.8 and chibi.velocity.y > 2.5, "Jump input kicks off the wall and advances the kick pose")
	var reached_opposite_wall := false
	for _i in 33:
		await _wait_physics_frames(1)
		if chibi.current_state == "WallRun" and chibi._wall_run_normal.dot(Vector3.LEFT) > 0.9:
			reached_opposite_wall = true
			break
	_assert_true(reached_opposite_wall, "Steering after a wall kick transfers to the opposite corridor wall")

	chibi.chibi_input.set_touch_move(Vector2.ZERO)
	chibi.reset_for_respawn(Vector3(4.0, 3.3, 21.0))
	var roll_clip_progress := 0.0
	for _i in 100:
		await _wait_physics_frames(1)
		if chibi.current_state == "LandRoll":
			roll_clip_progress = maxf(roll_clip_progress, _get_clip_phase(anim, "LandRoll"))
	_assert_true(roll_clip_progress > 0.7 and chibi.current_state == "Locomotion",
		"Hard landing plays a full roll and returns to locomotion (phase %.3f)" % roll_clip_progress)


func _test_running_turns_at_render_rates(chibi: ParkourController) -> void:
	var old_max_fps := Engine.max_fps
	for render_fps in [30, 60, 120]:
		Engine.max_fps = render_fps
		await _prepare_full_flow_run(chibi)
		var old_axis := Vector3.FORWARD
		var start_position := chibi.global_position
		var start_speed := Vector3(chibi.velocity.x, 0.0, chibi.velocity.z).dot(old_axis)
		chibi.chibi_input.set_touch_move(Vector2(0.0, 1.0))
		var reversal_tick := 0
		var old_axis_carry := 0.0
		for tick in 9:
			await physics_frame
			var displacement := chibi.global_position - start_position
			old_axis_carry = maxf(old_axis_carry, displacement.dot(old_axis))
			var planar := Vector3(chibi.velocity.x, 0.0, chibi.velocity.z)
			if planar.dot(old_axis) < 0.0:
				reversal_tick = tick + 1
				break
		print("[TURN] render=%d fps 180: %d ticks, carry=%.3f m, initial=%.2f m/s" % [render_fps, reversal_tick, old_axis_carry, start_speed])
		_assert_true(start_speed > 7.5 and reversal_tick > 0 and reversal_tick <= 9 and old_axis_carry < 0.30,
			"Full-Flow 180 reversal at %d render FPS reverses within 9 physics ticks and carries <0.30 m (ticks=%d, carry=%.3f m)" % [render_fps, reversal_tick, old_axis_carry])

		await _prepare_full_flow_run(chibi)
		var new_axis := Vector3.RIGHT
		var dominant_tick := 0
		chibi.chibi_input.set_touch_move(Vector2(1.0, 0.0))
		for tick in 7:
			await physics_frame
			var planar := Vector3(chibi.velocity.x, 0.0, chibi.velocity.z)
			if planar.dot(new_axis) > absf(planar.dot(old_axis)):
				dominant_tick = tick + 1
				break
		_assert_true(dominant_tick > 0 and dominant_tick <= 7,
			"Full-Flow 90-degree turn is dominated by the new axis within 7 physics ticks at %d render FPS (tick=%d)" % [render_fps, dominant_tick])
	Engine.max_fps = old_max_fps
	chibi.chibi_input.set_touch_move(Vector2.ZERO)


func _prepare_full_flow_run(chibi: ParkourController) -> void:
	chibi.chibi_input.set_touch_move(Vector2.ZERO)
	chibi.reset_for_respawn(Vector3(4.0, 0.06, 21.0))
	chibi.camera_ctrl.yaw = 0.0
	chibi.flow_level = 1.0
	chibi.velocity = Vector3.FORWARD * chibi.config.max_flow_speed
	chibi.chibi_input.set_touch_move(Vector2(0.0, -1.0))
	await physics_frame


func _test_ground_foot_drift(chibi: ParkourController) -> void:
	var old_max_fps := Engine.max_fps
	Engine.max_fps = 60
	var binder := chibi.get_node("ChibiRigBinder") as ChibiRigBinder
	var skeleton := binder.skeleton
	for test_case in [{"name": "base", "flow": 0.0, "limit": 0.05}, {"name": "top", "flow": 1.0, "limit": 0.08}]:
		chibi.chibi_input.set_touch_move(Vector2.ZERO)
		chibi.reset_for_respawn(Vector3(4.0, 0.06, 21.0))
		chibi.camera_ctrl.yaw = 0.0
		chibi.flow_level = test_case["flow"]
		chibi.chibi_input.set_touch_move(Vector2(0.0, -1.0))
		for _i in 35:
			chibi.flow_level = test_case["flow"]
			await _wait_physics_frames(1)
		var samples := {
			"was_planted": [false, false],
			"anchors": [Vector3.ZERO, Vector3.ZERO],
			"target_anchors": [Vector3.ZERO, Vector3.ZERO],
			"max_drift": [0.0, 0.0],
			"planted_samples": [0, 0],
			"stance_frames": [0, 0],
			"max_stance_frames": [0, 0],
			"last_process_frame": -1,
		}
		var sample_uploaded_pose := func() -> void:
			var process_frame_id := Engine.get_process_frames()
			if samples["last_process_frame"] == process_frame_id:
				return
			samples["last_process_frame"] = process_frame_id
			for side in 2:
				if not chibi.pose_mod.is_ground_foot_planted(side):
					samples["was_planted"][side] = false
					samples["stance_frames"][side] = 0
					continue
				var sole := chibi.pose_mod.get_ground_sole_world(side)
				var target := chibi.pose_mod.get_ground_contact_target_world(side)
				if not samples["was_planted"][side]:
					samples["anchors"][side] = sole
					samples["target_anchors"][side] = target
					samples["was_planted"][side] = true
					samples["stance_frames"][side] = 0
				if target.distance_to(samples["target_anchors"][side]) > 0.001:
					samples["was_planted"][side] = false
					samples["stance_frames"][side] = 0
					continue
				samples["planted_samples"][side] += 1
				samples["stance_frames"][side] += 1
				samples["max_stance_frames"][side] = maxi(samples["max_stance_frames"][side], samples["stance_frames"][side])
				samples["max_drift"][side] = maxf(samples["max_drift"][side], sole.distance_to(samples["anchors"][side]))
		skeleton.skeleton_updated.connect(sample_uploaded_pose)
		for _i in 180:
			chibi.flow_level = test_case["flow"]
			await _wait_physics_frames(1)
		skeleton.skeleton_updated.disconnect(sample_uploaded_pose)
		var max_drift: Array = samples["max_drift"]
		var planted_samples: Array = samples["planted_samples"]
		var max_stance_frames: Array = samples["max_stance_frames"]
		var worst_drift := maxf(max_drift[0], max_drift[1])
		print("[FOOT] %s flow: L %.3f m (%d samples, %d consecutive), R %.3f m (%d samples, %d consecutive)" % [test_case["name"], max_drift[0], planted_samples[0], max_stance_frames[0], max_drift[1], planted_samples[1], max_stance_frames[1]])
		_assert_true(planted_samples[0] >= 8 and planted_samples[1] >= 8 and max_stance_frames[0] >= 2 and max_stance_frames[1] >= 2 and worst_drift < test_case["limit"],
			"Planted feet drift <%.0f cm at %s speed over consecutive skin uploads (L %.3f m, R %.3f m; samples %d/%d)" % [test_case["limit"] * 100.0, test_case["name"], max_drift[0], max_drift[1], planted_samples[0], planted_samples[1]])
	Engine.max_fps = old_max_fps
	chibi.chibi_input.set_touch_move(Vector2.ZERO)


func _test_running_landing_overlay(chibi: ParkourController) -> void:
	var anim := chibi.anim_ctrl
	var playback := anim.anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	var skeleton := (chibi.get_node("ChibiRigBinder") as ChibiRigBinder).skeleton
	var pelvis_bone := skeleton.find_bone("pelvis")
	chibi.chibi_input.set_touch_move(Vector2.ZERO)
	chibi.reset_for_respawn(Vector3(4.0, 0.06, 21.0))
	chibi.camera_ctrl.yaw = 0.0
	chibi.flow_level = 1.0
	chibi.chibi_input.set_touch_move(Vector2(0.0, -1.0))
	await _wait_physics_frames(35)
	var pelvis_before := (skeleton.global_transform * skeleton.get_bone_global_pose(pelvis_bone)).origin
	anim.begin_running_landing(8.0)
	var direct_overlay_weight := anim.get_running_landing_weight()
	anim._apply_running_landing_pose()
	skeleton.force_update_all_bone_transforms()
	var pelvis_after := (skeleton.global_transform * skeleton.get_bone_global_pose(pelvis_bone)).origin
	var pelvis_drop := pelvis_before.y - pelvis_after.y
	_assert_true(direct_overlay_weight > 0.5 and pelvis_drop > 0.04,
		"Running landing overlay compresses the pelvis by >4 cm while weight exceeds 0.5 (weight %.3f, drop %.3f m)" % [direct_overlay_weight, pelvis_drop])
	await _wait_physics_frames(10)
	_assert_true(anim.get_running_landing_weight() <= 0.001 and playback.get_current_node() == &"LocomotionGait"
		and chibi.resolved_planar_speed > 5.0,
		"Landing overlay fades while moving gait continues after pose compression")
	var speed_before_jump := chibi.resolved_planar_speed
	chibi.request_jump()
	var peak_overlay := 0.0
	var gait_overlay_peak := 0.0
	var speed_during_gait_overlay := 0.0
	for _i in 52:
		await _wait_physics_frames(1)
		var overlay := anim.get_running_landing_weight()
		peak_overlay = maxf(peak_overlay, overlay)
		if overlay > gait_overlay_peak and playback.get_current_node() == &"LocomotionGait":
			gait_overlay_peak = overlay
			speed_during_gait_overlay = chibi.resolved_planar_speed
	_assert_true(peak_overlay > 0.20 and gait_overlay_peak > 0.10 and chibi.current_state == "Locomotion"
		and speed_during_gait_overlay > 5.0 and speed_during_gait_overlay > speed_before_jump - 0.7,
		"Moving landing overlays compression while the run gait and forward speed continue (weight %.3f, gait weight %.3f, speed %.2f -> %.2f m/s)" % [peak_overlay, gait_overlay_peak, speed_before_jump, speed_during_gait_overlay])
	print("[LANDING] real jump overlay peak=%.3f, gait overlap=%.3f, speed=%.2f -> %.2f m/s" % [peak_overlay, gait_overlay_peak, speed_before_jump, speed_during_gait_overlay])
	await _wait_physics_frames(10)
	_assert_true(anim.get_running_landing_weight() <= 0.001 and playback.get_current_node() == &"LocomotionGait",
		"Running landing overlay fades out without replacing the continuing gait")
	chibi.chibi_input.set_touch_move(Vector2.ZERO)


func _wait_physics_frames(count: int) -> void:
	for _i in count:
		await physics_frame
		await process_frame


func _test_station_overlap_after_respawn(gym: Node3D, chibi: ParkourController) -> void:
	var pole := gym.get_node("Zone4_AerialCircuit/ParkourPole_01") as ParkourPole
	var beam := gym.get_node("Zone4_AerialCircuit/BalanceBeam_01") as ParkourBalanceBeam
	chibi.reset_for_respawn(pole.get_top_world_position() + Vector3.UP * 0.23)
	await _wait_physics_frames(14)
	var perched := chibi.current_state == "PolePerch"

	chibi.reset_for_respawn(beam.to_global(Vector3(0.0, 0.24, -1.0)))
	# A callback carrying a contact from before the teleport must reject the new position.
	var stale_contact_rejected := not pole.land_on_top(chibi, -1.0, false)
	await _wait_physics_frames(12)
	_assert_true(perched and stale_contact_rejected and chibi.current_state == "BalanceBeam",
		"Respawning from a pole can mount the beam without the old pole recapturing Chibi")


func _get_clip_phase(anim: ChibiAnimController, state: String) -> float:
	var clip_path := "parameters/%s/Clip/" % state
	var length: float = anim.anim_tree.get(clip_path + "current_length")
	var position: float = anim.anim_tree.get(clip_path + "current_position")
	return position / length if length > 0.0 else 0.0


func _test_collision_box(parent: Node3D, center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var box := BoxShape3D.new()
	box.size = size
	var collider := CollisionShape3D.new()
	collider.shape = box
	body.add_child(collider)
	parent.add_child(body)
	body.global_position = center
	return body


func _find_type(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find_type(c, cls)
		if r != null:
			return r
	return null
