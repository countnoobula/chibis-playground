extends SceneTree

## Compares the playable First Steps Valley with its ambient breeze disabled and
## enabled. Movement uses a fixed 60 Hz touch-input replay; optional visual
## captures are written when CHIBI_BREEZE_CAPTURE_DIR is set in a rendered run.
##
## Godot_v4.7.2-stable_win64_console.exe --fixed-fps 60 --headless --path . --script res://tests/test_first_steps_breeze.gd

const LEVEL := "res://levels/first_steps/first_steps_valley.tscn"
const CAPTURE_ENV := "CHIBI_BREEZE_CAPTURE_DIR"
const BONE_NAMES := [&"scarf_05", &"scarf_b_03", &"ahoge_01"]
const IDLE_SAMPLE_TICKS := 90
const RUN_TICKS := 132
const JUMP_TICK := 30

var _passed := 0
var _failed := 0
var _capture_dir := ""
var _level: Node3D
var _runner: CharacterBody3D
var _input: Node
var _camera: Node
var _breeze: Node
var _skeleton: Skeleton3D
var _bone_indices: Dictionary = {}
var _foliage_samples: Array[Dictionary] = []
var _root_transforms: Dictionary = {}
var _rooted_foliage_mesh: MeshInstance3D
var _wind_foliage_mesh: MeshInstance3D
var _wind_foliage_material: ShaderMaterial
var _capture_bone_sample := false
var _latest_bone_sample: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.physics_ticks_per_second = 60
	_capture_dir = OS.get_environment(CAPTURE_ENV).strip_edges()
	var packed := load(LEVEL) as PackedScene
	if packed == null:
		_check(false, "First Steps Valley scene loads")
		quit(1)
		return
	_level = packed.instantiate() as Node3D
	root.add_child(_level)
	await _ticks(12)

	_runner = _level.get_node_or_null("ChibiRunner") as CharacterBody3D
	_breeze = _level.get_node_or_null("AmbientBreeze")
	if _runner == null or _breeze == null:
		_check(false, "Valley exposes ChibiRunner and AmbientBreeze")
		await _finish()
		return
	_input = _runner.get("chibi_input") as Node
	_camera = _runner.get("camera_ctrl") as Node
	var binder := _runner.get_node_or_null("ChibiRigBinder")
	_skeleton = binder.get("skeleton") as Skeleton3D if binder != null else null
	if _input == null or _camera == null or _skeleton == null:
		_check(false, "Runner exposes touch input, chase camera and bound Chibi skeleton")
		await _finish()
		return
	_input.call("set_touch_mode", true)
	_skeleton.skeleton_updated.connect(_on_skeleton_updated)
	var ambient_modifier := _skeleton.get_node_or_null("AmbientBreezeModifier") as SkeletonModifier3D
	var scarf_spring := _skeleton.get_node_or_null("ScarfSpringBoneSimulator3D") as SkeletonModifier3D
	var scarf_tail := _skeleton.get_node_or_null("ChibiScarfTail") as SkeletonModifier3D
	_check(ambient_modifier != null and scarf_spring != null and scarf_tail != null,
		"Ambient modifier and both existing scarf modifiers are present in Chibi's skeleton")
	if ambient_modifier != null and scarf_spring != null and scarf_tail != null:
		_check(ambient_modifier.get_index() > scarf_spring.get_index()
			and ambient_modifier.get_index() > scarf_tail.get_index(),
			"Ambient pose response runs after the scarf spring and landing-tail modifiers")
	for bone_name in BONE_NAMES:
		var bone_index := _skeleton.find_bone(bone_name)
		_bone_indices[bone_name] = bone_index
		_check(bone_index >= 0, "Chibi rig contains %s for visible secondary motion" % bone_name)
	if _failed > 0:
		await _finish()
		return

	_check(bool(_breeze.call("is_breeze_enabled")), "Ambient Breeze is enabled in the playable valley by default")
	_check(int(_breeze.call("get_foliage_material_count")) > 0,
		"Ambient Breeze binds independent foliage material instances in the valley")
	_collect_foliage(_level.get_node("Dressing"), _foliage_samples)
	_check(not _foliage_samples.is_empty(), "The current valley contains wind-capable foliage meshes")
	if _foliage_samples.is_empty():
		await _finish()
		return
	var wind_sample := _find_wind_sample(_foliage_samples)
	_check(not wind_sample.is_empty(),
		"A valley leaf with nonzero authored amplitude is available for the breeze comparison")
	if wind_sample.is_empty():
		await _finish()
		return
	_wind_foliage_mesh = wind_sample["mesh"] as MeshInstance3D
	_wind_foliage_material = wind_sample["material"] as ShaderMaterial
	var rooted_sample := _find_ground_root_sample(_foliage_samples, _wind_foliage_mesh)
	_check(not rooted_sample.is_empty(), "A valley foliage mesh exposes a ground-level root vertex")
	if rooted_sample.is_empty():
		await _finish()
		return
	var rooted_material := rooted_sample["material"] as ShaderMaterial
	var rooted_shader := rooted_material.shader
	var rooted_min_y := float(rooted_sample["min_y"])
	var plant_height := maxf(float(rooted_material.get_shader_parameter("plant_height")), 0.001)
	var root_weight := pow(clampf(rooted_min_y / plant_height, 0.0, 1.0), 2.0)
	var enabled_wind_amplitude := float(_wind_foliage_material.get_shader_parameter("wind_amplitude"))
	_check(_wind_foliage_mesh != null and rooted_sample["mesh"] != _wind_foliage_mesh,
		"Wind motion and root anchoring use separate valley foliage instances")
	_check(enabled_wind_amplitude > 0.0 and _wind_foliage_material.shader.code.contains("TIME"),
		"Wind-capable foliage animates over time at %s (amplitude %.4f)"
		% [str(_wind_foliage_mesh.get_path()), enabled_wind_amplitude])
	_check(rooted_shader != null and rooted_shader.code.contains("anchor * anchor"),
		"Foliage vertex bending squares its height anchor so ground roots stay planted")
	_check(absf(rooted_min_y) <= 0.04 and root_weight <= 0.002,
		"The selected plant's ground vertex has near-zero wind displacement weight (%.4f) at %s"
		% [root_weight, str(rooted_sample["mesh"].get_path())])
	_set_breeze(false)
	_check(absf(float(_wind_foliage_material.get_shader_parameter("wind_amplitude"))) <= 0.00001,
		"Disabling ambient breeze stops foliage motion")
	_set_breeze(true)
	_check(is_equal_approx(float(_wind_foliage_material.get_shader_parameter("wind_amplitude")), enabled_wind_amplitude),
		"Enabling ambient breeze restores the authored foliage motion strength")

	_root_transforms.clear()
	_rooted_foliage_mesh = rooted_sample.mesh as MeshInstance3D
	_root_transforms[_rooted_foliage_mesh.get_instance_id()] = _rooted_foliage_mesh.global_transform
	var trunk := _level.get_node_or_null("Dressing/Bend/BendTreeWest/Trunk") as Node3D
	if trunk != null:
		_root_transforms[trunk.get_instance_id()] = trunk.global_transform
	_check(trunk != null, "The valley exposes a fixed tree trunk to check anchoring")

	var still_off := await _sample_idle_bones(false, "idle_breeze_off")
	var still_on := await _sample_idle_bones(true, "idle_breeze_on")
	_compare_idle_bones(still_off, still_on)

	var breeze_off_trace := await _replay_run_and_jump(false)
	var breeze_on_trace := await _replay_run_and_jump(true)
	_compare_motion_traces(breeze_off_trace, breeze_on_trace)
	_check_roots_anchored()

	_input.call("clear_touch_input")
	_set_breeze(false)
	await _finish()


func _set_breeze(enabled: bool) -> void:
	_breeze.call("set_breeze_enabled", enabled)
	_check(bool(_breeze.call("is_breeze_enabled")) == enabled,
		"AmbientBreeze reports %s" % ("enabled" if enabled else "disabled"))


func _sample_idle_bones(enabled: bool, capture_label: String) -> Array[Dictionary]:
	_set_breeze(enabled)
	_level.call("retry_section")
	_input.call("clear_touch_input")
	# Give the modifier's eased response the same settled strength in each sample.
	await _ticks(55)
	var poses: Array[Dictionary] = []
	for tick in IDLE_SAMPLE_TICKS:
		_capture_bone_sample = true
		_latest_bone_sample.clear()
		await _ticks(1)
		_capture_bone_sample = false
		poses.append(_latest_bone_sample.duplicate(true))
		if tick == 44:
			await _capture(capture_label)
	return poses


func _compare_idle_bones(off: Array[Dictionary], on: Array[Dictionary]) -> void:
	_check(off.size() == on.size() and off.size() == IDLE_SAMPLE_TICKS,
		"Idle pose comparison records the same number of physics ticks")
	if off.size() != on.size() or off.is_empty():
		return
	for bone_name in BONE_NAMES:
		var max_position_delta := 0.0
		var max_angle_delta := 0.0
		for tick in off.size():
			var off_pose: Transform3D = off[tick][bone_name]
			var on_pose: Transform3D = on[tick][bone_name]
			max_position_delta = maxf(max_position_delta, off_pose.origin.distance_to(on_pose.origin))
			max_angle_delta = maxf(max_angle_delta,
				off_pose.basis.get_rotation_quaternion().angle_to(on_pose.basis.get_rotation_quaternion()))
		var visible_motion := max_position_delta >= 0.004 or max_angle_delta >= 0.018
		_check(visible_motion,
			"Ambient breeze changes %s pose while Chibi stands still (%.4f m, %.4f rad)"
			% [bone_name, max_position_delta, max_angle_delta])


func _replay_run_and_jump(enabled: bool) -> Array[Dictionary]:
	_set_breeze(enabled)
	_level.call("retry_section")
	_input.call("clear_touch_input")
	await _ticks(8)
	var start_position := _runner.global_position
	var trace: Array[Dictionary] = []
	var peak_y := start_position.y
	var jump_launched := false
	var landed_after_jump := false
	for tick in RUN_TICKS:
		_input.call("set_touch_move", Vector2(0.0, -1.0))
		if tick == JUMP_TICK:
			_input.call("set_touch_jump", true)
		elif tick == JUMP_TICK + 1:
			_input.call("set_touch_jump", false)
		await _ticks(1)
		peak_y = maxf(peak_y, _runner.global_position.y)
		jump_launched = jump_launched or _runner.velocity.y > 0.5
		landed_after_jump = landed_after_jump or (tick > JUMP_TICK and _runner.is_on_floor())
		trace.append({
			"position": _runner.global_position,
			"heading": _runner.global_rotation.y,
			"velocity": _runner.velocity,
			"state": String(_runner.get("current_state")),
		})
	_input.call("set_touch_jump", false)
	_input.call("set_touch_move", Vector2.ZERO)
	_check(jump_launched and peak_y - start_position.y > 0.45,
		"%s replay includes an actual running jump (rise %.2f m)" % ["Breezy" if enabled else "Still", peak_y - start_position.y])
	_check(landed_after_jump, "%s replay lands during the measured run" % ("Breezy" if enabled else "Still"))
	_check(trace.size() == RUN_TICKS and _runner.global_position.distance_to(start_position) > 1.0,
		"%s replay records a timed forward run" % ("Breezy" if enabled else "Still"))
	return trace


func _compare_motion_traces(off: Array[Dictionary], on: Array[Dictionary]) -> void:
	_check(off.size() == RUN_TICKS and off.size() == on.size(),
		"Breeze comparison has paired run-and-jump samples for every physics tick")
	if off.size() != on.size() or off.is_empty():
		return
	var max_position_error := 0.0
	var max_heading_error := 0.0
	var max_velocity_error := 0.0
	for tick in off.size():
		var off_position: Vector3 = off[tick]["position"]
		var on_position: Vector3 = on[tick]["position"]
		var off_velocity: Vector3 = off[tick]["velocity"]
		var on_velocity: Vector3 = on[tick]["velocity"]
		max_position_error = maxf(max_position_error, off_position.distance_to(on_position))
		max_heading_error = maxf(max_heading_error,
			absf(angle_difference(float(off[tick]["heading"]), float(on[tick]["heading"]))))
		max_velocity_error = maxf(max_velocity_error, off_velocity.distance_to(on_velocity))
	_check(max_position_error <= 0.005 and max_heading_error <= 0.004 and max_velocity_error <= 0.02,
		"Identical inputs preserve position, heading and velocity with breeze on/off "
		+ "(max Δ %.5f m, %.5f rad, %.5f m/s)"
		% [max_position_error, max_heading_error, max_velocity_error])


func _collect_foliage(node: Node, out: Array[Dictionary]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface in mesh_instance.mesh.get_surface_count():
				var material := mesh_instance.get_active_material(surface) as ShaderMaterial
				if material == null or material.shader == null \
						or material.shader.resource_path != "res://assets/environment/woodland/foliage.gdshader":
					continue
				var arrays := mesh_instance.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				if vertices.is_empty():
					continue
				var min_y := INF
				for vertex in vertices:
					min_y = minf(min_y, vertex.y)
				out.append({"mesh": mesh_instance, "surface": surface,
					"material": material, "min_y": min_y})
	for child in node.get_children():
		_collect_foliage(child, out)


func _find_wind_sample(samples: Array[Dictionary]) -> Dictionary:
	for sample in samples:
		var material := sample["material"] as ShaderMaterial
		if material != null and float(material.get_shader_parameter("wind_amplitude")) > 0.0:
			return sample
	return {}


func _find_ground_root_sample(samples: Array[Dictionary], excluded_mesh: MeshInstance3D) -> Dictionary:
	for sample in samples:
		if sample["mesh"] != excluded_mesh and absf(float(sample["min_y"])) <= 0.04:
			return sample
	return {}


func _on_skeleton_updated() -> void:
	if not _capture_bone_sample or _skeleton == null:
		return
	for bone_name in BONE_NAMES:
		_latest_bone_sample[bone_name] = _skeleton.get_bone_global_pose(int(_bone_indices[bone_name]))


func _check_roots_anchored() -> void:
	if _rooted_foliage_mesh != null:
		var plant_before: Transform3D = _root_transforms.get(
			_rooted_foliage_mesh.get_instance_id(), _rooted_foliage_mesh.global_transform)
		_check(_rooted_foliage_mesh.global_transform.is_equal_approx(plant_before),
			"Foliage root transform stays fixed at %s" % str(_rooted_foliage_mesh.get_path()))
	var trunk := _level.get_node_or_null("Dressing/Bend/BendTreeWest/Trunk") as Node3D
	if trunk != null:
		var before: Transform3D = _root_transforms.get(trunk.get_instance_id(), trunk.global_transform)
		_check(trunk.global_transform.is_equal_approx(before), "Valley tree trunk remains anchored while its canopy moves")


func _capture(label: String) -> void:
	if _capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		print("CAPTURE skipped for %s: viewport image empty" % label)
		return
	var error := DirAccess.make_dir_recursive_absolute(_capture_dir)
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_warning("Could not create capture folder %s" % _capture_dir)
		return
	var destination := _capture_dir.path_join("first_steps_%s.png" % label)
	error = image.save_png(destination)
	if error == OK:
		print("CAPTURE: %s (%s)" % [destination, RenderingServer.get_video_adapter_name()])
	else:
		push_warning("Could not save capture %s (error %d)" % [destination, error])


func _ticks(count: int) -> void:
	for _tick in count:
		await physics_frame
		await process_frame


func _finish() -> void:
	if _level != null and is_instance_valid(_level):
		_level.queue_free()
		await process_frame
	print("=== FIRST STEPS BREEZE: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("PASS: ", message)
	else:
		_failed += 1
		push_error("FAIL: " + message)
