extends SceneTree

var player: ParkourController
var failures := 0

func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL ", description)


func _run() -> void:
	var gym = load("res://levels/rooftop_gym/rooftop_parkour_gym.tscn").instantiate()
	root.add_child(gym)
	current_scene = gym
	for i in 8:
		await physics_frame
	player = gym.get_node("ChibiRunner")
	var director := player.expression_director

	# Start at a repeatable height beside the gym's existing Zone 2 ledge.
	# Movement, collision detection, flail timing and the catch all run normally.
	player.reset_for_respawn(Vector3(-21.95, 13, 3.65))
	player.rotation.y = 0.0
	var sequence: Array[int] = []
	var saw_hang := false
	var visible_fall_cloud := false
	for tick in 155:
		await physics_frame
		var pose := director._automatic_face
		if pose in [11, 14, 9] and (sequence.is_empty() or sequence.back() != pose):
			sequence.append(pose)
		if director._cloud_index >= 0:
			visible_fall_cloud = true
		if pose == 9:
			saw_hang = saw_hang or player.current_state == "LedgeHang"
	check(sequence == [11, 14, 9], "Gasp, sustained squeal, then brave little smile")
	check(saw_hang and not visible_fall_cloud, "Collision-confirmed ledge recovery stays face-only")

	player.reset_for_respawn(Vector3(-21.95, 4.3, 3.65))
	player.rotation.y = 0.0
	var early_catch := false
	var early_squeal := false
	for tick in 85:
		await physics_frame
		early_catch = early_catch or director._automatic_face == 9
		early_squeal = early_squeal or director._automatic_face == 14 or director._cloud_index >= 0
	check(early_catch and not early_squeal, "Earlier catch goes directly from gasp to relief without a cloud")

	player.reset_for_respawn(Vector3(0, 14, 6))
	var authored := director.request_expression(&"playful_wink", 0, 5, &"face")
	var manual_cloud := director.request_expression(&"sad", 0, 0, &"cloud")
	var cloud_held := true
	var glide_settled := false
	var fall_interrupted_wink := false
	for tick in 110:
		if tick in [49, 51]:
			player.chibi_input.set_touch_jump(tick == 49)
		await physics_frame
		cloud_held = cloud_held and director._cloud_index == 18
		fall_interrupted_wink = fall_interrupted_wink or director._face_index == 14
		if player.scarf_glide_phase == &"glide":
			glide_settled = director._automatic_face == 1
	check(fall_interrupted_wink and glide_settled, "Fall interrupts an ordinary cue, scarf deployment resolves the scare")
	check(cloud_held, "Movement leaves explicitly requested clouds under manual control")
	director.release_expression(manual_cloud)
	director.release_expression(authored)

	player.reset_for_respawn(Vector3(0, 0.04, 6))
	for i in 15:
		await physics_frame
	player.chibi_input.set_touch_jump(true)
	await physics_frame
	player.chibi_input.set_touch_jump(false)
	var short_fall_reaction := false
	for i in 72:
		await physics_frame
		short_fall_reaction = short_fall_reaction or director._automatic_face in [11, 14, 9]
	check(not short_fall_reaction, "Ordinary hop has no fear or rescue expression")

	var manual := director.request_expression(&"crying", 0.0, 100)
	for i in 10:
		await physics_frame
	check(director._face_index == 19 and director._cloud_index == 19, "Picker overrides automatic reactions")
	director.release_expression(manual)
	check(director._face_index == director._automatic_face, "Picker releases into current automatic pose")
	player.reset_for_respawn(Vector3(0, 12, 6))
	var saw_squeal := false
	var grounded_after_squeal := false
	var settled_on_ground := false
	var unexpected_rescue := false
	for i in 155:
		await physics_frame
		saw_squeal = saw_squeal or director._automatic_face == 14
		grounded_after_squeal = grounded_after_squeal or (saw_squeal and player.is_on_floor())
		if grounded_after_squeal:
			settled_on_ground = settled_on_ground or director._automatic_face in [0, 1]
		unexpected_rescue = unexpected_rescue or director._automatic_face == 9 or director._cloud_index >= 0
	check(settled_on_ground and not unexpected_rescue, "A long fall onto the roof settles without a rescue smile or cloud")
	for voice in gym.find_children("*", "AudioStreamPlayer3D", true, false):
		voice.stop()
	gym.queue_free()
	# Fixed-fps runs accelerate game timers, while the audio mixer uses wall time.
	var settle_until := Time.get_ticks_msec() + 350
	while Time.get_ticks_msec() < settle_until:
		await process_frame
	print("Automatic rooftop reactions: ", failures, " failures")
	quit(1 if failures else 0)
