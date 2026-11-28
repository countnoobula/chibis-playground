extends SceneTree

const GYM_SCENE_PATH := "res://levels/rooftop_gym/rooftop_parkour_gym.tscn"
const EXPRESSION_DIRECTOR := preload("res://features/runner/expression_director.gd")

var failures := 0
var gym: Node3D
var player: ParkourController
var director: Node
var gym_scene: PackedScene


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL ", description)


func _run() -> void:
	gym_scene = load(GYM_SCENE_PATH) as PackedScene
	check(gym_scene != null, "Rooftop scene loads")
	if gym_scene == null:
		quit(1)
		return
	var first_gym := gym_scene.instantiate()
	root.add_child(first_gym)
	current_scene = first_gym
	await process_frame
	await physics_frame
	_set_live_scene(first_gym)
	check(player != null and director != null, "Rooftop runner and expression director are ready")
	if player == null or director == null:
		quit(1)
		return

	_check_all_face_and_cloud_modes()
	_check_repeats_replacements_and_cancellation()
	_check_near_vertical_cloud_orbit()
	_check_bright_smile_thresholds()
	_check_dive_bite_overlay()
	await _check_missing_face_binding()
	await _check_auto_during_fall()
	await _check_scene_reload()

	_stop_scene_audio(gym)
	if is_instance_valid(gym):
		gym.queue_free()
	var drain_until := Time.get_ticks_msec() + 350
	while Time.get_ticks_msec() < drain_until:
		await process_frame
	print("Expression interruptions with ", Engine.physics_ticks_per_second, " physics ticks/s: ", failures, " failures")
	quit(1 if failures else 0)


func _set_live_scene(scene: Node) -> void:
	gym = scene as Node3D
	if gym == null:
		player = null
		director = null
		return
	player = gym.get_node_or_null("ChibiRunner") as ParkourController
	director = player.expression_director if player != null else null


func _check_all_face_and_cloud_modes() -> void:
	var ids: Array = director.IDS
	director.set_automatic(0)
	var face = director.get_node_or_null("ExpressionFace")
	for i in range(ids.size()):
		var id: StringName = ids[i]
		var face_handle: int = director.request_expression(id, 0.0, 10, &"face")
		check(face_handle > 0 and director._face_index == i and director._cloud_index == -1,
			"Face-only output selects " + str(id))
		check(face != null and face._pose_index == i, "Bound face displays " + str(id))
		director.release_expression(face_handle)
		check(director._face_index == director._automatic_face and director._cloud_index == -1,
			"Face-only Auto restores after " + str(id))

		var face_before_cloud: int = director._face_index
		var cloud_handle: int = director.request_expression(id, 0.0, 10, &"cloud")
		var cloud = player.get_node_or_null("ExpressionCloud")
		check(cloud_handle > 0 and director._face_index == face_before_cloud and director._cloud_index == i,
			"Cloud-only output selects " + str(id) + " without changing the face")
		check(cloud != null and cloud._current_pose == i and cloud.visible,
			"Bound cloud displays " + str(id))
		director.release_expression(cloud_handle)
		check(director._face_index == face_before_cloud and director._cloud_index == -1,
			"Cloud-only Auto hides " + str(id) + " and preserves the face")


func _check_repeats_replacements_and_cancellation() -> void:
	director.set_automatic(1)
	var first: int = director.request_expression(&"sad", 0.0, 10, &"face")
	var repeated: int = director.request_expression(&"sad", 0.0, 10, &"face")
	check(first > 0 and repeated > first and director._face_index == 18, "Repeating one held request keeps the same pose")
	director.release_expression(first)
	check(director._face_index == 18 and director.has_request(repeated), "Cancelling an older repeat preserves the newer request")
	var replacement: int = director.request_expression(&"angry", 0.0, 10, &"face")
	check(director._face_index == 17, "A newer equal-priority request replaces the visible face")
	director.release_expression(replacement)
	check(director._face_index == 18, "Releasing a replacement restores the held request")
	director.release_expression(repeated)
	check(director._face_index == 1, "Releasing the final repeat returns to Auto")

	var face_handle: int = director.request_expression(&"playful_wink", 0.0, 10, &"face")
	var cloud_handle: int = director.request_expression(&"sad", 0.0, 10, &"cloud")
	director.release_expression(cloud_handle)
	check(director._face_index == 5 and director._cloud_index == -1,
		"Cancelling the cloud output leaves a separately held face request active")
	director.release_expression(face_handle)
	check(director._face_index == 1 and director._cloud_index == -1,
		"Cancelling the face output returns both channels to Auto")


func _check_near_vertical_cloud_orbit() -> void:
	var camera := player.camera_ctrl.active_camera
	var cloud_handle: int = director.request_expression(&"surprised", 0.0, 10, &"cloud")
	var cloud = player.get_node("ExpressionCloud")
	var previous_transform := camera.global_transform
	var prior_yaw: float = cloud._last_valid_global_yaw
	# The camera's local Z points almost straight up, so the cloud must keep the
	# last valid heading instead of deriving an unstable yaw from a tiny projection.
	camera.global_basis = Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP).orthonormalized()
	cloud._process(1.0 / float(Engine.physics_ticks_per_second))
	check(absf(angle_difference(cloud.global_rotation.y, prior_yaw)) < 0.001,
		"A near-vertical camera keeps the cloud's last valid heading")
	check(absf(cloud.global_rotation.x) < 0.001 and absf(cloud.global_rotation.z) < 0.001,
		"The cloud stays upright during a near-vertical camera orbit")
	camera.global_transform = previous_transform
	director.release_expression(cloud_handle)


func _check_bright_smile_thresholds() -> void:
	var reactions = gym.get_node("RooftopReactions")
	reactions._context_elapsed = reactions.SETTLE_DELAY
	reactions._state_elapsed = reactions.SETTLE_DELAY
	reactions._bright_smile_active = false
	reactions._update_bright_smile("Locomotion", "Sprint", true, 0.679)
	check(not reactions._bright_smile_active, "Flow just below the enter threshold does not start the bright smile")
	reactions._update_bright_smile("Locomotion", "Sprint", true, 0.68)
	check(reactions._bright_smile_active, "Flow at the enter threshold starts the bright smile")
	check(reactions._select_automatic("Locomotion", "Sprint", true, 6.0) == 3,
		"A qualified sprint maps to the bright smile")
	reactions._update_bright_smile("Locomotion", "Sprint", true, 0.541)
	check(reactions._bright_smile_active, "Flow above the exit threshold keeps the bright smile")
	reactions._update_bright_smile("Locomotion", "Sprint", true, 0.54)
	check(not reactions._bright_smile_active, "Flow at the exit threshold releases the bright smile")
	reactions._update_bright_smile("Locomotion", "Sprint", false, 0.9)
	check(not reactions._bright_smile_active, "Leaving the floor cancels the bright smile")


func _check_dive_bite_overlay() -> void:
	var gear: ChibiDiveGear = player.pose_mod.dive_gear
	var expression_face = director.get_node("ExpressionFace")
	var handle: int = director.request_expression(&"surprised", 0.0, 10, &"face")
	check(gear != null and handle > 0 and expression_face._mouth_overlay.visible,
		"The active expression mouth is visible before the dive bite")
	if gear == null or handle <= 0:
		return
	var delta := 1.0 / float(Engine.physics_ticks_per_second)
	var transition_frames := ceili(gear.TRANSITION_TIME / delta) + 1
	for tick in range(transition_frames):
		gear.advance(delta, "PoolSwim", 1.0)
		expression_face._update_mouth_overlay_for_bite()
	check(gear.progress >= 0.99 and gear.mouthpiece_weight >= 0.99
		and expression_face._bite_overlays_hidden and not expression_face._mouth_overlay.visible,
		"The deployed dive mouthpiece hides the expression mouth overlay while the face remains active")
	for tick in range(transition_frames):
		gear.advance(delta, "Locomotion", 0.0)
		expression_face._update_mouth_overlay_for_bite()
	check(gear.progress <= 0.01 and gear.mouthpiece_weight <= 0.001
		and not expression_face._bite_overlays_hidden and expression_face._mouth_overlay.visible,
		"Stowing dive gear restores the active expression mouth overlay")
	director.release_expression(handle)


func _check_missing_face_binding() -> void:
	var runner_scene := load("res://features/runner/chibi_runner.tscn") as PackedScene
	var unbound_runner = runner_scene.instantiate()
	var rig_binder := unbound_runner.get_node_or_null("ChibiRigBinder")
	if rig_binder != null:
		unbound_runner.remove_child(rig_binder)
		rig_binder.free()
	root.add_child(unbound_runner)
	await process_frame
	var unbound_director = unbound_runner.expression_director
	var cloud_handle: int = unbound_director.request_expression(&"sad", 0.0, 10, &"cloud")
	var unbound_cloud = unbound_runner.get_node_or_null("ExpressionCloud")
	check(cloud_handle > 0 and unbound_cloud != null and unbound_cloud.visible and unbound_cloud._current_pose == 18,
		"Cloud-only output works without the rig binder")
	var face_handle: int = unbound_director.request_expression(&"crying", 0.0, 10, &"face")
	var unbound_face = unbound_director.get_node_or_null("ExpressionFace")
	check(face_handle > 0 and unbound_director._face_index == 19 and unbound_face != null
		and unbound_face._setup_complete and unbound_face._pose_index == 19 and unbound_director._cloud_index == 18,
		"The face falls back to its skinned mesh and keeps the independent cloud without the rig binder")
	_stop_scene_audio(unbound_runner)
	unbound_director.clear_requests()
	unbound_runner.queue_free()


func _check_auto_during_fall() -> void:
	player.reset_for_respawn(Vector3(-21.95, 13.0, 3.65))
	player.rotation.y = 0.0
	var saw_gasp := false
	for tick in range(Engine.physics_ticks_per_second * 2):
		await physics_frame
		if director._automatic_face == 11:
			saw_gasp = true
			break
	check(saw_gasp, "The real Zone 2 drop enters the automatic gasp before Auto is tested")
	if not saw_gasp:
		return

	var late_request: int = director.request_expression(&"sleepy", 0.0, 10, &"face")
	check(late_request > 0 and director._face_index == director._automatic_face and director._automatic_face in [11, 14],
		"A late ordinary request yields to the active fall reaction")
	var picker = gym.get_node("EmojiPicker")
	picker._open_picker()
	(picker._grid.get_child(19) as Button).pressed.emit()
	check(picker._active_handle > 0 and director._face_index == 19 and director._cloud_index == 19,
		"A high-priority picker request can interrupt the fall reaction")
	for tick in range(maxi(2, int(Engine.physics_ticks_per_second / 12))):
		await physics_frame
	picker._open_picker()
	picker._auto_button.pressed.emit()
	check(director._cloud_index == -1 and director._face_index == director._automatic_face
		and director._automatic_face in [11, 14] and picker._active_handle == -1,
		"The picker Auto button during the fall restores its current face-only reaction")
	picker._close_picker()
	director.release_expression(late_request)


func _check_scene_reload() -> void:
	var stale_request: int = director.request_expression(&"angry", 0.0, 100, &"both")
	check(stale_request > 0 and director._face_index == 17 and director._cloud_index == 17,
		"The old scene holds an explicit expression before reload")
	_stop_scene_audio(gym)
	var error: Error = change_scene_to_packed(gym_scene)
	check(error == OK, "Rooftop scene reload is accepted")
	await process_frame
	await process_frame
	_set_live_scene(current_scene)
	check(player != null and director != null, "Reload creates a new runner and expression director")
	if player == null or director == null:
		return
	check(director._requests.is_empty() and director._cloud_index == -1 and not director._face_manual,
		"A scene reload clears held expressions and cloud visibility")
	await physics_frame
	check(director._face_index != 17, "The reloaded runner does not inherit the old manual face")


func _stop_scene_audio(scene: Node) -> void:
	if not is_instance_valid(scene):
		return
	for voice in scene.find_children("*", "AudioStreamPlayer3D", true, false):
		voice.stop()
