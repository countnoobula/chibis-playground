extends RefCounted

const BASIN := "res://features/water/examples/rocky_basin.tscn"
const BODY_SCENE := "res://features/water/water_body_3d.tscn"
const RECEIVER_SHADER := preload("res://features/water/shaders/water_caustic_receiver.gdshader")


func run(tree: SceneTree, check: Callable) -> void:
	var basin := (load(BASIN) as PackedScene).instantiate() as Node3D
	tree.root.add_child(basin)
	await _ticks(tree, 4)
	var player := basin.get_node("ChibiRunner") as ParkourController
	var water := basin.get_node("WaterBody3D") as WaterBody3D
	var surface := water.get_surface_height()
	_test_caustic_receivers(water, check)
	var gear := player.pose_mod.dive_gear
	var forehead := gear.find_child("ForeheadGoggles", true, false) as MeshInstance3D
	var dive_mask := gear.find_child("DivingMask", true, false) as MeshInstance3D
	var snorkel := gear.find_child("Snorkel", true, false) as MeshInstance3D
	var strap := gear.find_child("HeadStrap", true, false) as MeshInstance3D
	var strap_material := strap.get_surface_override_material(0) as BaseMaterial3D
	var dry_strap_color := strap_material.albedo_color
	var stowed_y := forehead.position.y
	check.call(strap.is_visible_in_tree() and not gear.get_snorkel_outlet_world().is_finite(),
		"The dry strap is visible and the stowed snorkel has no active bubble outlet")
	check.call(forehead.visible and not dive_mask.visible and not snorkel.visible
		and gear.progress == 0.0 and gear.head_bone >= 0, "Dry Chibi starts with head-mounted forehead goggles")
	check.call(absf(surface - ChibiPool.WATER_Y) > 0.5 and water.outline.size() > 4,
		"The same WaterBody3D supports an irregular basin at another elevation")
	check.call(not water.contains_horizontal(Vector3(0.5, surface, 5.98)),
		"Water containment follows the inward notch, inside the polygon's bounding box")

	var shore := Vector3(0.3, surface, 4.2)
	var ground := _floor_at(basin, shore)
	check.call(not ground.is_empty(), "Rocky shallows have a real terrain floor")
	if not ground.is_empty():
		player.reset_for_respawn(ground.position + Vector3.UP * 0.06)
		await _ticks(tree, 12)
		check.call(player.current_state == "Locomotion" and player.get_active_water() == water
			and player.external_walk_speed_cap < player.config.base_run_speed, "Chibi wades on the rocky shallows")
		player.camera_ctrl.yaw = 0.0
		player.chibi_input.set_touch_move(Vector2.UP)
		var entry_kept_momentum := false
		var saw_pull_down := false
		var strap_stayed_opaque := true
		var saw_strap_color_change := false
		for tick in 175:
			var was_walking := player.current_state == "Locomotion"
			var previous_speed := Vector2(player.velocity.x, player.velocity.z).length()
			await _ticks(tree, 1)
			if was_walking and player.current_state == "PoolSwim":
				var swim_speed := Vector2(player.velocity.x, player.velocity.z).length()
				entry_kept_momentum = previous_speed > 0.8 and swim_speed > previous_speed * 0.85
			strap_stayed_opaque = strap_stayed_opaque and strap.is_visible_in_tree() \
				and strap_material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
			if gear.gesture_weight > 0.7 and forehead.visible and dive_mask.visible:
				saw_pull_down = saw_pull_down or forehead.position.y < stowed_y - 0.06
				saw_strap_color_change = saw_strap_color_change or (
					not strap_material.albedo_color.is_equal_approx(dry_strap_color)
					and not strap_material.albedo_color.is_equal_approx(ChibiDiveGear.DIVE_STRAP_COLOR))
		check.call(strap_stayed_opaque and saw_strap_color_change
			and strap_material.albedo_color.is_equal_approx(ChibiDiveGear.DIVE_STRAP_COLOR),
			"Equip keeps one opaque strap visible and blends lavender to sage")
		check.call(saw_pull_down, "Bank entry moves and morphs the goggles during the hands-up gesture")
		check.call(gear.progress == 1.0 and not forehead.visible and dive_mask.visible and snorkel.visible
			and gear.mouthpiece_weight == 1.0, "Swimming settles into the mask and seated snorkel")
		check.call(player.current_state == "PoolSwim" and player.get_active_water() == water,
			"Walking down the rocky bank transitions from wading to swimming (state %s, position %s)" %
			[player.current_state, str(player.global_position)])
		check.call(entry_kept_momentum, "The last grounded stride carries into the first swim stroke")
		player.chibi_input.set_touch_move(Vector2.ZERO)

	var deep := Vector3(0.5, surface - 1.32, -1.0)
	player.reset_for_respawn(deep)
	await _ticks(tree, 20)
	player.chibi_input.set_touch_jump(true)
	var rise_peak := player.get_capsule_center().y
	for tick in 54:
		await _ticks(tree, 1)
		rise_peak = maxf(rise_peak, player.get_capsule_center().y)
	player.chibi_input.set_touch_jump(false)
	var surfaced := player.get_capsule_center().y
	check.call(player.current_state == "PoolSwim" and absf(surfaced - surface) < 0.24,
		"Held Rise brings Chibi to the surface of the rocky basin (state %s, surface distance %.2f m)" %
		[player.current_state, surface - surfaced])
	check.call(rise_peak <= surface - 0.010 and absf(player.velocity.y) < 0.21,
		"Resurfacing brakes at the waterline before settling into a tread")
	var tread_blend: float = player.anim_ctrl.anim_tree.get("parameters/Swim/TreadBlend/blend_amount")
	var surface_blend: float = player.anim_ctrl.anim_tree.get("parameters/Swim/SurfaceBlend/blend_amount")
	check.call(tread_blend > 0.85 and surface_blend > 0.55, "An idle swimmer blends into treading at the surface")
	player.chibi_input.set_touch_slide(true)
	await _ticks(tree, 7)
	player.chibi_input.set_touch_slide(false)
	await _ticks(tree, 38)
	var tap_depth := surfaced - player.get_capsule_center().y
	var deep_idle: float = player.anim_ctrl.anim_tree.get("parameters/Swim/DeepIdleBlend/blend_amount")
	check.call(player.current_state == "PoolSwim" and tap_depth > 0.19 and tap_depth < 0.48
		and absf(player.velocity.y) < 0.08 and deep_idle > 0.78,
		"A short dive kick eases into a submerged idle (depth %.2f m, idle %.2f)" % [tap_depth, deep_idle])
	player.chibi_input.set_touch_jump(true)
	await _ticks(tree, 53)
	player.chibi_input.set_touch_jump(false)
	surfaced = player.get_capsule_center().y
	player.chibi_input.set_touch_slide(true)
	await _ticks(tree, 31)
	player.chibi_input.set_touch_slide(false)
	check.call(player.current_state == "PoolSwim" and player.get_capsule_center().y < surfaced - 0.50,
		"Held Dive submerges Chibi without leaving the swim state")
	check.call(gear.progress == 1.0 and dive_mask.visible and snorkel.visible,
		"The same gear stays fitted through submerging")
	var bubbles_from_vent := false
	for tick in 50:
		await _ticks(tree, 1)
		if water._bubble_effects.is_empty():
			continue
		var newest: Dictionary = water._bubble_effects.back()
		var origin: Vector3 = water.to_global(newest["origin"])
		var outlet := gear.get_snorkel_outlet_world()
		if newest["age"] < 0.035 and origin.distance_to(outlet) < 0.045:
			bubbles_from_vent = origin.y < surface - 0.025
			break
	check.call(bubbles_from_vent, "Fresh underwater bubbles start at the moving snorkel vent")

	var adjoining := (load(BODY_SCENE) as PackedScene).instantiate() as WaterBody3D
	adjoining.position = Vector3(deep.x, surface + 0.06, deep.z)
	adjoining.outline = PackedVector2Array([Vector2(-2, -2), Vector2(2, -2), Vector2(2, 2), Vector2(-2, 2)])
	adjoining.max_depth = 2.7
	adjoining.selection_priority = 10
	basin.add_child(adjoining)
	player.chibi_input.set_touch_move(Vector2.UP)
	await _ticks(tree, 8)
	check.call(player.get_active_water() == adjoining and player.current_state == "PoolSwim",
		"An overlapping volume hands off to the higher priority body while swimming")
	adjoining.queue_free()
	await _ticks(tree, 5)
	check.call(player.get_active_water() == water and player.current_state == "PoolSwim",
		"Removing the selected body hands swimming back to the remaining body")
	check.call(gear.progress == 1.0, "Water-body handoffs keep the dive gear equipped")
	player.chibi_input.set_touch_move(Vector2.ZERO)

	var camera := Camera3D.new()
	basin.add_child(camera)
	camera.make_current()
	player.camera_ctrl.active_camera = camera
	camera.global_position = Vector3(0.1, surface + 0.7, -1.6)
	camera.reset_physics_interpolation()
	await _ticks(tree, 6)
	check.call(player.current_state == "PoolSwim" and player.camera_ctrl.get_camera_water() == null,
		"The camera stays dry while Chibi swims underneath it")
	camera.global_position.y = surface - 0.63
	camera.reset_physics_interpolation()
	await _ticks(tree, 10)
	check.call(player.camera_ctrl.get_camera_water() == water and camera.environment != null
		and camera.environment != basin.get_node("WorldEnvironment").environment,
		"A submerged camera uses its own water atmosphere")
	camera.global_position = Vector3(10.0, surface - 0.3, 6.0)
	camera.reset_physics_interpolation()
	await tree.create_timer(1.3).timeout
	check.call(player.camera_ctrl.get_camera_water() == null and camera.environment == null,
		"Exiting the water sideways restores the dry camera environment")

	player.reset_for_respawn(Vector3(0.5, surface - 1.05, 1.9))
	player.chibi_input.set_touch_move(Vector2.DOWN)
	player.chibi_input.set_touch_jump(true)
	var strap_on_during_stow := true
	var saw_stow_color_change := false
	for tick in 155:
		await _ticks(tree, 1)
		strap_on_during_stow = strap_on_during_stow and strap.is_visible_in_tree() \
			and strap_material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
		if player.current_state == "Locomotion" and gear.progress > 0.2 and gear.progress < 0.6:
			saw_stow_color_change = saw_stow_color_change or not strap_material.albedo_color.is_equal_approx(dry_strap_color)
	player.chibi_input.set_touch_move(Vector2.ZERO)
	player.chibi_input.set_touch_jump(false)
	check.call(player.current_state == "Locomotion" and player.get_active_water() == null,
		"Swimming back up the rocky bank returns to dry locomotion")
	await _ticks(tree, 50)
	check.call(gear.progress == 0.0 and forehead.visible and not dive_mask.visible and not snorkel.visible,
		"Bank exit puts the original goggles back on her forehead")
	check.call(strap_on_during_stow and saw_stow_color_change
		and strap_material.albedo_color.is_equal_approx(dry_strap_color),
		"Stow keeps the same strap visible and restores lavender")
	gear.advance(0.34, "PoolSwim", 1.2)
	var interrupted_at := gear.progress
	gear.advance(0.09, "Locomotion", 0.0)
	var reversed := gear.progress > 0.0 and gear.progress < interrupted_at
	gear.advance(0.09, "PoolSwim", 1.2)
	check.call(reversed and is_equal_approx(gear.progress, interrupted_at),
		"A canceled equip and immediate re-entry reverse the same transition without a snap")
	player.reset_for_respawn(shore)
	check.call(gear.progress == 0.0 and gear.gesture_weight == 0.0 and gear.mouthpiece_weight == 0.0,
		"Respawn clears an interrupted dive-gear gesture")
	await _test_swim_glide(tree, player, deep, check)
	await _test_enclosed_swimming(tree, basin, player, surface, check)
	basin.queue_free()
	await tree.process_frame
	await tree.process_frame


func _test_caustic_receivers(water: WaterBody3D, check: Callable) -> void:
	var inline_receiver_shader := Shader.new()
	inline_receiver_shader.code = RECEIVER_SHADER.code
	var receiver := ShaderMaterial.new()
	receiver.shader = inline_receiver_shader
	receiver.set_shader_parameter("base_color", Color("d28ac2"))
	water.register_caustic_receiver(receiver)
	check.call(receiver.get_shader_parameter("water_outline_count") == water.outline.size()
		and is_equal_approx(float(receiver.get_shader_parameter("water_plane_y")), water.get_volume_ceiling_height())
		and receiver.get_shader_parameter("base_color").is_equal_approx(Color("d28ac2")),
		"Explicit registration updates inline custom receivers and preserves their own surface settings")
	var standard_surface := StandardMaterial3D.new()
	standard_surface.albedo_color = Color("bf8c73")
	standard_surface.roughness = 0.61
	var standard_mesh := MeshInstance3D.new()
	standard_mesh.material_override = standard_surface
	water.configure_caustic_receiver(standard_mesh)
	var converted_surface := standard_mesh.material_override as ShaderMaterial
	check.call(converted_surface != null and converted_surface.shader == RECEIVER_SHADER
		and converted_surface.get_shader_parameter("base_color").is_equal_approx(standard_surface.albedo_color)
		and is_equal_approx(float(converted_surface.get_shader_parameter("roughness")), standard_surface.roughness),
		"Legacy receiver setup converts standard surfaces and preserves their appearance")
	var generic_source := ShaderMaterial.new()
	generic_source.shader = RECEIVER_SHADER
	var generic_mesh := MeshInstance3D.new()
	generic_mesh.material_override = generic_source
	water.configure_caustic_receiver(generic_mesh)
	check.call(generic_mesh.material_override is ShaderMaterial and generic_mesh.material_override != generic_source
		and (generic_mesh.material_override as ShaderMaterial).shader == RECEIVER_SHADER,
		"Legacy receiver setup duplicates the generic shader material")
	var blank_mesh := MeshInstance3D.new()
	water.configure_caustic_receiver(blank_mesh)
	check.call(blank_mesh.material_override is ShaderMaterial
		and (blank_mesh.material_override as ShaderMaterial).shader == RECEIVER_SHADER,
		"Legacy receiver setup supplies a shared shader for a mesh without a material")
	standard_mesh.free()
	generic_mesh.free()
	blank_mesh.free()


func _test_swim_glide(tree: SceneTree, player: ParkourController, start: Vector3, check: Callable) -> void:
	player.reset_for_respawn(start)
	player.camera_ctrl.yaw = 0.0
	await _ticks(tree, 5)
	player.chibi_input.set_touch_move(Vector2.UP)
	await _ticks(tree, 28)
	var released_at := player.global_position
	var release_speed := -player.velocity.z
	player.chibi_input.set_touch_move(Vector2.ZERO)
	await _ticks(tree, 30)
	var coast_distance := released_at.z - player.global_position.z
	var stopped_speed := absf(player.velocity.z)
	player.chibi_input.set_touch_move(Vector2.DOWN)
	await _ticks(tree, 14)
	check.call(player.current_state == "PoolSwim" and release_speed > 2.15
		and coast_distance > 0.25 and coast_distance < 0.46 and stopped_speed < 0.03 and player.velocity.z > 1.4,
		"Released swim input glides to rest and responds to a new direction (%.2f m of carry)" % coast_distance)
	var reverse_at := player.global_position.z
	player.chibi_input.set_touch_move(Vector2.UP)
	await _ticks(tree, 3)
	var still_braking := player.velocity.z > 0.15
	await _ticks(tree, 21)
	check.call(player.current_state == "PoolSwim" and still_braking and player.velocity.z < -1.9
		and player.global_position.z < reverse_at and absf(angle_difference(player.rotation.y, 0.0)) < 0.68,
		"A sharp swim reversal brakes the old travel and turns the body into the new stroke")
	player.chibi_input.set_touch_move(Vector2.ZERO)


func _test_enclosed_swimming(tree: SceneTree, basin: Node3D, player: ParkourController, surface: float, check: Callable) -> void:
	var chamber := (load(BODY_SCENE) as PackedScene).instantiate() as WaterBody3D
	chamber.position = Vector3(30.0, surface + 1.0, 0.0)
	chamber.outline = PackedVector2Array([Vector2(-2, -2), Vector2(2, -2), Vector2(2, 2), Vector2(-2, 2)])
	chamber.max_depth = 3.60
	chamber.ceiling_below_surface = 0.65
	basin.add_child(chamber)
	player.reset_for_respawn(Vector3(30.0, surface - 1.9, 0.0))
	await _ticks(tree, 4)
	player.chibi_input.set_touch_jump(true)
	await _ticks(tree, 100)
	player.chibi_input.set_touch_jump(false)
	var headroom := chamber.get_volume_ceiling_height() - (2.0 * player.get_capsule_center().y - player.global_position.y)
	var surface_blend: float = player.anim_ctrl.anim_tree.get("parameters/Swim/SurfaceBlend/blend_amount")
	check.call(player.current_state == "PoolSwim" and player.get_active_water() == chamber
		and headroom > 0.00 and headroom < 0.13 and surface_blend < 0.02,
		"Held Rise eases under an enclosed water ceiling while the pose stays submerged (headroom %.2f m)" % headroom)


func _floor_at(anchor: Node3D, position: Vector3) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(position + Vector3.UP * 2.0, position - Vector3.UP * 3.0, 1)
	return anchor.get_world_3d().direct_space_state.intersect_ray(ray)


func _ticks(tree: SceneTree, count: int) -> void:
	for i in count:
		await tree.physics_frame
		await tree.process_frame
