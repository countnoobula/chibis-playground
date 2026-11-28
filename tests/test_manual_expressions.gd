extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL ", description)


func _run() -> void:
	var gym = load("res://levels/rooftop_gym/rooftop_parkour_gym.tscn").instantiate()
	root.add_child(gym)
	current_scene = gym
	await process_frame
	var player = gym.get_node("ChibiRunner")
	var director = player.get_node("ExpressionDirector")
	check(gym.has_node("EmojiPicker"), "Rooftop exposes the picker")
	var picker = gym.get_node("EmojiPicker")
	var key := InputEventKey.new()
	key.keycode = KEY_F
	key.pressed = true
	root.push_input(key)
	await process_frame
	check(picker._popup.is_visible_in_tree(), "F opens the picker in the rooftop")
	check(picker._grid.get_child_count() == 20, "All twenty menu choices appear")
	if picker._grid.get_child_count() == 20:
		var button: Button = picker._grid.get_child(19)
		button.pressed.emit()
		check(director._face_index == 19 and director._cloud_index == 19, "Crying menu choice applies both outputs")
		picker._auto_button.pressed.emit()
		check(director._face_index == director._automatic_face and director._cloud_index == -1, "Auto releases the manual hold")
	picker._close_picker()
	for i in director.IDS.size():
		var handle: int = director.request_expression(director.IDS[i])
		check(handle > 0 and director._face_index == i and director._cloud_index == i, "Linked " + str(director.IDS[i]))
		await process_frame
		director.release_expression(handle)
	var closed: int = director.request_expression(&"crying")
	var open: int = director.request_expression(&"neutral")
	var mesh: MeshInstance3D = player.juice.character_mesh
	for surface in mesh.mesh.get_surface_count():
		var material := mesh.mesh.surface_get_material(surface)
		if material.resource_name == "M_Chibi_EyeDark":
			var active := mesh.get_active_material(surface) as BaseMaterial3D
			check(active != null and active.albedo_color.a > 0.0, "Eyes reopen when a held crying pose is replaced")
	director.release_expression(open)
	director.release_expression(closed)
	var baseline: int = director.request_expression(&"sad")
	var overlay: int = director.request_expression(&"angry", 0.0, 3, &"cloud")
	var wink: int = director.request_expression(&"playful_wink", 0.1, 2, &"face")
	check(director._face_index == 5 and director._cloud_index == 17, "Independent channels")
	director._process(0.11)
	check(director._face_index == 18, "Timed overlay returns to held face")
	director.release_expression(wink)
	director.release_expression(overlay)
	check(director._cloud_index == 18, "Cloud returns to held pose")
	director.release_expression(baseline)
	check(director._face_index == director._automatic_face and director._cloud_index == -1, "Auto restored")
	check(director.request_expression(&"missing") == -1, "Invalid ID rejected")
	director.request_expression(&"crying")
	player.reset_for_respawn(player.global_position)
	check(director._requests.is_empty() and director._face_index == -1 and director._cloud_index == -1, "Respawn clears all requests")
	# Let the audio server release the gym's looping wind voices before shutdown.
	for voice in gym.find_children("*", "AudioStreamPlayer3D", true, false):
		voice.stop()
	gym.queue_free()
	await create_timer(0.3).timeout
	await process_frame
	print("Manual expression checks: ", failures, " failures")
	quit(1 if failures else 0)
