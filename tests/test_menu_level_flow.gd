extends SceneTree

## Run on desktop for mouse input and with --mobile-menu for touch input.
func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var entry: String = ProjectSettings.get_setting("application/run/main_scene")
	if change_scene_to_file(entry) != OK:
		_fail("The configured title scene could not be loaded.")
		return
	await scene_changed
	var main_menu := current_scene
	var controls := main_menu.get_node_or_null("ArtworkCanvas/TitleControls")
	var play := controls.get_node_or_null("PlayButton") as BaseButton if controls != null else null
	if not _check(play != null and play.has_focus(), "Play should have focus on the title screen."):
		return

	var touch_input := OS.get_cmdline_user_args().has("--mobile-menu")
	var play_position := _center(play)
	_click(play_position, touch_input)
	_click(play_position, touch_input)
	await create_timer(0.5).timeout
	var atlas := main_menu.get_node_or_null("AtlasPreview") as Control
	if not _check(atlas != null and atlas.is_visible_in_tree(), "Play should open the working atlas, including after a double activation."):
		return
	var map_viewport := atlas.get_node_or_null("DesignCanvas/MapViewport") as Control
	var world_map := atlas.get_node_or_null("DesignCanvas/MapViewport/WorldMap") as Control
	var postcard := atlas.get_node_or_null("DesignCanvas/Postcard") as Control
	var launch_button := postcard.get_node_or_null("LaunchButton") as BaseButton if postcard != null else null
	if not _check(map_viewport != null and world_map != null and launch_button != null, "The atlas map and postcard Play control should be present."):
		return

	var first_steps_pin := world_map.get_node_or_null("FirstStepsPin") as BaseButton
	var intro_pin := world_map.get_node_or_null("IntroPin") as BaseButton
	var lake_pin := world_map.get_node_or_null("LakePin") as BaseButton
	var rooftop_pin := world_map.get_node_or_null("RooftopGymPin") as BaseButton
	if not _check(first_steps_pin != null and intro_pin != null and lake_pin != null and rooftop_pin != null, "All four destination pins should be present."):
		return
	if not _check(StringName(atlas.get("selected_destination_id")) == &"first_steps", "First Steps Valley should be selected when the atlas opens."):
		return
	if not _check(StringName(postcard.get("current_destination")) == &"first_steps" and launch_button.disabled, "The First Steps postcard should show its pending status and disable Play."):
		return
	if not _check_pending_cta(postcard, launch_button, &"first_steps"):
		return

	# Controller navigation reaches the selected pin. Selecting a pending pin and
	# confirming it must not leave the atlas.
	_gamepad_axis(JOY_AXIS_LEFT_X, 1.0)
	await process_frame
	var initial_pin_focus := root.gui_get_focus_owner()
	if not _check(initial_pin_focus == first_steps_pin, "Controller stick right should focus the selected First Steps pin (focus: %s)." % (str(initial_pin_focus.get_path()) if initial_pin_focus != null else "<none>")):
		return
	_gamepad_button(JOY_BUTTON_A)
	await process_frame
	if not _check(current_scene == main_menu and atlas.is_visible_in_tree(), "Confirming a pin should select it without launching a level."):
		return

	# The selected pending destination keeps the separate postcard Play action
	# disabled. Right pans the focused map; confirm returns focus to the pin.
	_action(&"ui_right", true)
	_action(&"ui_right", false)
	await process_frame
	if not _check(root.gui_get_focus_owner() == map_viewport and launch_button.disabled, "A pending destination should pan the map instead of focusing disabled Play."):
		return
	_gamepad_button(JOY_BUTTON_A)
	await process_frame
	if not _check(current_scene == main_menu and root.gui_get_focus_owner() == first_steps_pin, "Confirm on the map should return to the selected pin without launching."):
		return

	# A drag that begins on a different pin must pan without selecting that pin.
	var pin_drag_scroll := float(atlas.get("map_scroll_x"))
	if not _check(is_equal_approx(pin_drag_scroll, float(atlas.get("map_scroll_max_x"))), "The pin-drag regression should begin at the eastern map bound."):
		return
	var rooftop_pin_center := _pin_center(atlas, &"rooftop_gym")
	await _drag_pointer(rooftop_pin_center, Vector2(60.0, 0.0), touch_input)
	if not _check(float(atlas.get("map_scroll_x")) < pin_drag_scroll, "Dragging from a pin should pan the map."):
		return
	if not _check(StringName(atlas.get("selected_destination_id")) == &"first_steps" and StringName(postcard.get("current_destination")) == &"first_steps", "Dragging from Rooftop Gym should not select it or change the postcard."):
		return
	if not _check(current_scene == main_menu, "Dragging from a pin must not launch a destination."):
		return

	# Drag across the clipped map in each direction. The map must stop at both
	# authored ends even when the drag requests more travel than the available span.
	var map_scroll_min := float(atlas.get("map_scroll_min_x"))
	var map_scroll_max := float(atlas.get("map_scroll_max_x"))
	if not _check(is_zero_approx(map_scroll_min) and is_equal_approx(map_scroll_max, 600.0), "The map should expose its authored 0–600 scroll range."):
		return
	var current_scroll := float(atlas.get("map_scroll_x"))
	if not _check(current_scroll >= map_scroll_min and current_scroll <= map_scroll_max, "Pointer movement should keep map_scroll_x inside the authored range."):
		return
	await _drag_map(map_viewport, 1.0, touch_input)
	if not _check(is_equal_approx(float(atlas.get("map_scroll_x")), map_scroll_min), "Dragging past the western edge should clamp map_scroll_x to zero."):
		return
	await _drag_map(map_viewport, -1.0, touch_input)
	if not _check(is_equal_approx(float(atlas.get("map_scroll_x")), map_scroll_max), "Dragging past the eastern edge should clamp map_scroll_x to 600."):
		return

	# Select each destination through its real pin hit area. Pending destinations
	# update the fixed postcard but never switch the scene.
	var intro_selected := await _select_pin(atlas, map_viewport, postcard, launch_button, &"intro", intro_pin, main_menu, touch_input)
	if not intro_selected:
		return
	if not _check_pin_title(intro_pin, "Change can be scary..."):
		return
	if not _check_postcard_copy(postcard, "Change can be scary...", "...but it doesn't always have to be."):
		return
	var lake_selected := await _select_pin(atlas, map_viewport, postcard, launch_button, &"lake", lake_pin, main_menu, touch_input)
	if not lake_selected:
		return
	if not _check_pin_title(lake_pin, "We fear what we cannot see..."):
		return
	if not _check_postcard_copy(postcard, "We fear what we cannot see...", "...but beneath the surface lies a world of wonder."):
		return
	var lake_tip_screen: Vector2 = atlas.call("get_pin_tip_screen", &"lake")
	var lake_tip_local := map_viewport.get_global_transform_with_canvas().affine_inverse() * lake_tip_screen
	if not _check(float(atlas.get("map_scroll_x")) == map_scroll_min and lake_tip_local.distance_to(Vector2(145.0, 496.0)) < 0.1, "LakePin should reveal at its west-lake anchor (145, 496)."):
		return
	var first_steps_selected := await _select_pin(atlas, map_viewport, postcard, launch_button, &"first_steps", first_steps_pin, main_menu, touch_input)
	if not first_steps_selected:
		return
	var rooftop_selected := await _select_pin(atlas, map_viewport, postcard, launch_button, &"rooftop_gym", rooftop_pin, main_menu, touch_input)
	if not rooftop_selected:
		return
	if not _check(not launch_button.disabled and not str(postcard.get("availability_label")).is_empty(), "Rooftop Gym should be the available destination."):
		return

	# Return to the title with controller Cancel, then reopen with keyboard confirm.
	_gamepad_button(JOY_BUTTON_B)
	await create_timer(0.5).timeout
	if not _check(main_menu.get_node_or_null("AtlasPreview") == null and play.is_visible_in_tree() and play.has_focus(), "Atlas Back should return to focused title Play."):
		return
	_action(&"ui_accept", true)
	_action(&"ui_accept", false)
	await create_timer(0.5).timeout
	atlas = main_menu.get_node_or_null("AtlasPreview") as Control
	if not _check(atlas != null and atlas.is_visible_in_tree(), "Keyboard confirm should reopen the atlas from title Play."):
		return
	map_viewport = atlas.get_node_or_null("DesignCanvas/MapViewport") as Control
	world_map = atlas.get_node_or_null("DesignCanvas/MapViewport/WorldMap") as Control
	postcard = atlas.get_node_or_null("DesignCanvas/Postcard") as Control
	launch_button = postcard.get_node_or_null("LaunchButton") as BaseButton if postcard != null else null
	first_steps_pin = world_map.get_node_or_null("FirstStepsPin") as BaseButton if world_map != null else null
	intro_pin = world_map.get_node_or_null("IntroPin") as BaseButton if world_map != null else null
	lake_pin = world_map.get_node_or_null("LakePin") as BaseButton if world_map != null else null
	rooftop_pin = world_map.get_node_or_null("RooftopGymPin") as BaseButton if world_map != null else null
	if not _check(map_viewport != null and launch_button != null and first_steps_pin != null and intro_pin != null and lake_pin != null and rooftop_pin != null, "The reopened atlas should restore its map and destination controls."):
		return

	# Use only controller navigation to select Rooftop Gym, then move focus to
	# postcard Play and confirm. Pin selection itself remains non-launching.
	_gamepad_axis(JOY_AXIS_LEFT_X, 1.0)
	await process_frame
	var first_steps_focus := root.gui_get_focus_owner()
	if not _check(first_steps_focus == first_steps_pin, "Controller stick right should focus First Steps Valley from Back (focus: %s)." % (str(first_steps_focus.get_path()) if first_steps_focus != null else "<none>")):
		return
	_gamepad_axis(JOY_AXIS_LEFT_X, -1.0)
	await process_frame
	var intro_focus := root.gui_get_focus_owner()
	if not _check(intro_focus == intro_pin, "Controller stick left should navigate from First Steps Valley to Intro (focus: %s)." % (str(intro_focus.get_path()) if intro_focus != null else "<none>")):
		return
	_gamepad_axis(JOY_AXIS_LEFT_Y, -1.0)
	await process_frame
	var rooftop_focus := root.gui_get_focus_owner()
	if not _check(rooftop_focus == rooftop_pin and StringName(atlas.get("selected_destination_id")) == &"rooftop_gym" and not launch_button.disabled, "Controller stick up should select Rooftop Gym and enable its postcard Play (focus: %s)." % (str(rooftop_focus.get_path()) if rooftop_focus != null else "<none>")):
		return
	if not _check(current_scene == main_menu, "Controller pin selection must not launch Rooftop Gym."):
		return
	_gamepad_axis(JOY_AXIS_LEFT_X, 1.0)
	await process_frame
	if not _check(root.gui_get_focus_owner() == launch_button, "Rooftop Gym focus navigation should reach postcard Play."):
		return
	_gamepad_button(JOY_BUTTON_A)
	var rooftop_opened := await _wait_for_scene("res://levels/rooftop_gym/rooftop_parkour_gym.tscn", 240)
	if not rooftop_opened:
		_fail("Postcard Play should launch Rooftop Gym.")
		return

	var runner := current_scene.get_node_or_null("ChibiRunner") as ParkourController
	if not _check(runner != null and runner.touch_hud != null, "Rooftop Gym should provide the playable runner and HUD."):
		return
	_action(&"ui_cancel", true)
	await process_frame
	_action(&"ui_cancel", false)
	var resume := runner.touch_hud.find_child("ResumeButton", true, false) as BaseButton
	if not _check(paused and resume != null, "Pause should open the journal with a Resume button."):
		return
	_click(_center(resume), touch_input)
	await process_frame
	if not _check(not paused and not runner.touch_hud.menu_open, "Resume should return input to Rooftop Gym."):
		return

	unload_current_scene()
	# Let the audio mixer release rooftop wind playback on its own clock.
	var settle_until := Time.get_ticks_msec() + 350
	while Time.get_ticks_msec() < settle_until:
		await process_frame
	print("PASS: Title, four atlas pins, Intro/Lake copy and lead-ins, pending Coming soon CTA, Rooftop Gym Play, pause/resume")
	quit(0)


func _select_pin(atlas: Control, map_viewport: Control, postcard: Control, launch_button: BaseButton, destination: StringName, pin: BaseButton, main_menu: Node, touch_input: bool) -> bool:
	var pin_visible := await _move_pin_into_view(atlas, map_viewport, destination, touch_input)
	if not pin_visible:
		return _check(false, "Destination %s should be reachable within the map bounds." % destination)
	if not _check(pin.is_visible_in_tree(), "The %s destination pin should remain visible." % destination):
		return false
	_click(_pin_center(atlas, destination), touch_input)
	await process_frame
	if not _check(StringName(atlas.get("selected_destination_id")) == destination, "Selecting %s should update atlas selection." % destination):
		return false
	if not _check(StringName(postcard.get("current_destination")) == destination, "Selecting %s should update the postcard." % destination):
		return false
	if not _check(not str(postcard.get("availability_label")).is_empty(), "The %s postcard should show availability." % destination):
		return false
	if destination != &"rooftop_gym":
		if not _check_pending_cta(postcard, launch_button, destination):
			return false
		_click(_center(launch_button), touch_input)
		await process_frame
		if not _check(current_scene == main_menu and atlas.is_visible_in_tree(), "Selecting or clicking Play for %s must not launch it." % destination):
			return false
	else:
		if not _check(not launch_button.disabled, "Rooftop Gym should enable postcard Play."):
			return false
		var launch_label := postcard.get_node_or_null("LaunchButton/LaunchLabel") as Label
		if not _check(postcard.get("availability_label") == "Available" and launch_label != null and launch_label.text == "Play", "Rooftop Gym should show its available Play CTA."):
			return false
		if not _check(current_scene == main_menu and atlas.is_visible_in_tree(), "Selecting the Rooftop Gym pin must not launch it."):
			return false
	return true


func _check_pin_title(pin: BaseButton, expected_title: String) -> bool:
	return _check(pin.accessibility_name == expected_title and pin.tooltip_text == expected_title, "Pin title should be '%s'." % expected_title)


func _check_postcard_copy(postcard: Control, expected_title: String, expected_lead_in: String) -> bool:
	var title_label := postcard.get_node_or_null("TitleLabel") as Label
	var lead_label := postcard.get_node_or_null("LeadInLabel") as RichTextLabel
	if not _check(title_label != null and title_label.text == expected_title, "Postcard title should be '%s'." % expected_title):
		return false
	if not _check(str(postcard.get("lead_in_text")) == expected_lead_in, "Postcard lead-in should be '%s'." % expected_lead_in):
		return false
	var italic_markup := "[i]%s[/i]" % expected_lead_in
	return _check(lead_label != null and lead_label.bbcode_enabled and lead_label.text.contains(italic_markup), "Postcard lead-in should render '%s' in italics." % expected_lead_in)


func _check_pending_cta(postcard: Control, launch_button: BaseButton, destination: StringName) -> bool:
	var launch_label := postcard.get_node_or_null("LaunchButton/LaunchLabel") as Label
	if not _check(launch_button.disabled and launch_label != null and launch_label.text == "Coming soon", "Pending %s should expose one disabled Coming soon CTA." % destination):
		return false
	if not _check(postcard.get_node_or_null("AvailabilityFrame") == null, "Pending %s should not repeat Coming soon in an availability chip." % destination):
		return false
	if not _check(_count_visible_label_text(postcard, "Coming soon") == 1, "Pending %s should show exactly one Coming soon label." % destination):
		return false
	return _check(str(postcard.get("availability_label")) == "Coming soon", "Pending %s availability should be Coming soon." % destination)


func _count_visible_label_text(node: Node, target_text: String) -> int:
	var count := 0
	var label := node as Label
	if label != null and label.is_visible_in_tree() and label.text == target_text:
		count += 1
	for child in node.get_children():
		count += _count_visible_label_text(child, target_text)
	return count


func _move_pin_into_view(atlas: Control, map_viewport: Control, destination: StringName, touch_input: bool) -> bool:
	var viewport_rect := Rect2(Vector2.ZERO, map_viewport.size)
	for _attempt in range(4):
		var screen_point := _pin_center(atlas, destination)
		var local_point := map_viewport.get_global_transform_with_canvas().affine_inverse() * screen_point
		if viewport_rect.has_point(local_point):
			return true
		var scroll := float(atlas.get("map_scroll_x"))
		if local_point.x < viewport_rect.position.x and scroll > 0.01:
			await _drag_map(map_viewport, 1.0, touch_input)
		elif local_point.x >= viewport_rect.end.x and scroll < 599.99:
			await _drag_map(map_viewport, -1.0, touch_input)
		else:
			return false
	return false


func _pin_center(atlas: Control, destination: StringName) -> Vector2:
	return atlas.call("get_pin_center_screen", destination)


func _drag_map(map_viewport: Control, direction: float, touch_input: bool) -> void:
	var transform := map_viewport.get_global_transform_with_canvas()
	var start_fraction := 0.10 if direction > 0.0 else 0.90
	var start := transform * Vector2(map_viewport.size.x * start_fraction, map_viewport.size.y * 0.5)
	var local_delta := Vector2(map_viewport.size.x * 0.75 * direction, 0.0)
	await _drag_pointer(start, transform.basis_xform(local_delta), touch_input)


func _drag_pointer(start: Vector2, screen_delta: Vector2, touch_input: bool) -> void:
	var end := start + screen_delta
	if touch_input:
		var press := InputEventScreenTouch.new()
		press.index = 1
		press.position = start
		press.pressed = true
		root.push_input(press, true)
		var drag := InputEventScreenDrag.new()
		drag.index = 1
		drag.position = end
		drag.relative = end - start
		root.push_input(drag, true)
		var release := InputEventScreenTouch.new()
		release.index = 1
		release.position = end
		release.pressed = false
		root.push_input(release, true)
	else:
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.button_mask = MOUSE_BUTTON_MASK_LEFT
		press.position = start
		press.global_position = start
		press.pressed = true
		root.push_input(press, true)
		var motion := InputEventMouseMotion.new()
		motion.position = end
		motion.global_position = end
		motion.relative = end - start
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion, true)
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.position = end
		release.global_position = end
		release.pressed = false
		root.push_input(release, true)
	await process_frame


func _click(position: Vector2, touch_input: bool) -> void:
	if touch_input:
		for pressed in [true, false]:
			var finger := InputEventScreenTouch.new()
			finger.index = 1
			finger.position = position
			finger.pressed = pressed
			root.push_input(finger, true)
	else:
		for pressed in [true, false]:
			var mouse := InputEventMouseButton.new()
			mouse.button_index = MOUSE_BUTTON_LEFT
			mouse.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
			mouse.position = position
			mouse.global_position = position
			mouse.pressed = pressed
			root.push_input(mouse, true)


func _center(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size * 0.5)


func _action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	root.push_input(event)


func _gamepad_button(button: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		root.push_input(event)


func _gamepad_axis(axis: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	root.push_input(event)
	var release := InputEventJoypadMotion.new()
	release.axis = axis
	release.axis_value = 0.0
	root.push_input(release)


func _wait_for_scene(path: String, max_frames: int) -> bool:
	for _frame in range(max_frames):
		if current_scene != null and current_scene.scene_file_path == path:
			return true
		await process_frame
	return false


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail(message)
	return false


func _fail(message: String) -> void:
	printerr("FAIL: ", message)
	quit(1)
