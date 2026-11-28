extends SceneTree

const VALLEY_SCENE_PATH := "res://levels/first_steps/first_steps_valley.tscn"
const ROCK_SCENE_PATH := "res://assets/environment/woodland/forest/moss_boulder.glb"
const PLACEMENT_ACTION := preload("res://addons/scene_builder/scene_builder_placement.gd")
const TEST_SAVE_PATH := "user://codex_scene_builder_terrain_placement_check.tscn"
const STARTER_SCENE_PATH := "res://levels/first_steps/terrain/woodland_terrain_starter.tscn"

const SLOPE_CANDIDATES: Array[Vector2] = [
	Vector2(-10.0, 14.0),
	Vector2(-9.0, 14.0),
	Vector2(-11.0, 14.0),
	Vector2(-10.0, 13.0),
	Vector2(-10.0, 15.0),
]

var _failure_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _verify_disposable_starter_resculpt()

	var valley_scene := load(VALLEY_SCENE_PATH) as PackedScene
	_assert(valley_scene != null, "the playable First Steps Valley scene loads")
	if valley_scene == null:
		quit(1)
		return
	var valley := valley_scene.instantiate() as Node3D
	root.add_child(valley)
	await _wait_physics_frames(8)

	var terrain := valley.get_node("CreekTerrain") as Node3D
	var physics_space: PhysicsDirectSpaceState3D = terrain.get_world_3d().direct_space_state
	var slope_hit := _find_slope_hit(physics_space)
	_assert(not slope_hit.is_empty(), "Terrain3D collision raycast finds a resculpted slope")
	if slope_hit.is_empty():
		valley.free()
		await process_frame
		quit(1)
		return
	var slope_degrees := rad_to_deg((slope_hit.normal as Vector3).angle_to(Vector3.UP))
	_assert(slope_degrees >= 8.0 and slope_degrees <= 35.0,
		"placement target is a usable %.1f degree terrain slope" % slope_degrees)

	var rock_scene := load(ROCK_SCENE_PATH) as PackedScene
	_assert(rock_scene != null, "woodland moss boulder scene loads")
	var rock := rock_scene.instantiate() as Node3D
	rock.name = "MossBoulder"
	var normal: Vector3 = slope_hit.normal.normalized()
	var surface_alignment := Quaternion(Vector3.UP, normal)
	var local_yaw := Quaternion(Vector3.UP, deg_to_rad(37.0))
	var rock_basis := Basis(surface_alignment * local_yaw).scaled(Vector3.ONE * 1.08)
	var placed_transform := Transform3D(rock_basis, slope_hit.position)
	var manager := UndoRedo.new()
	PLACEMENT_ACTION.commit_item_placement(manager, valley, valley, rock, placed_transform)
	_assert(rock.get_parent() == valley and rock.owner == valley
		and rock.global_transform.is_equal_approx(placed_transform),
		"Scene Builder placement records the rock parent, owner, rotation and scale")
	var rock_support_offset := _support_distance_from_surface(rock, normal)
	print("Moss boulder lowest visual point is %.3f m from its terrain anchor" % rock_support_offset)
	_assert(rock_support_offset >= -1.0 and rock_support_offset <= 0.15,
		"woodland rock is grounded with only a shallow embed on the slope")

	var undo_succeeded := manager.undo()
	_assert(undo_succeeded and rock.get_parent() == null and rock.owner == null,
		"undo removes the rock from the valley scene")
	var redo_succeeded := manager.redo()
	_assert(redo_succeeded and rock.get_parent() == valley and rock.owner == valley
		and rock.global_transform.is_equal_approx(placed_transform),
		"redo restores the rock to the same slope and transform")

	# The valley binds its live runner in _ready. Save the placement as authored
	# in the editor, before that transient runtime binding exists.
	terrain.set("clipmap_target", null)
	var packed_valley := PackedScene.new()
	var pack_error := packed_valley.pack(valley)
	_assert(pack_error == OK, "slope placement scene packs for persistence")
	if pack_error == OK:
		var save_error := ResourceSaver.save(packed_valley, TEST_SAVE_PATH)
		_assert(save_error == OK, "placed valley scene saves")
		manager.clear_history()
		manager.free()
		valley.free()
		await process_frame
		var reopened_scene := load(TEST_SAVE_PATH) as PackedScene
		_assert(reopened_scene != null, "placed valley scene reopens")
		if reopened_scene:
			var reopened_valley := reopened_scene.instantiate() as Node3D
			root.add_child(reopened_valley)
			await _wait_physics_frames(8)
			var reopened_rock := reopened_valley.get_node_or_null("MossBoulder") as Node3D
			_assert(reopened_rock != null, "placed moss boulder remains in the reopened valley")
			if reopened_rock:
				_assert(reopened_rock.owner == reopened_valley
					and reopened_rock.global_transform.is_equal_approx(placed_transform),
					"reopened rock preserves its terrain position, rotation and scale")
			var reopened_space: PhysicsDirectSpaceState3D = reopened_valley.get_node("CreekTerrain").get_world_3d().direct_space_state
			var reopened_hit := _raycast(reopened_space, Vector2(-10.0, 14.0))
			_assert(not reopened_hit.is_empty(), "Terrain3D collision is available after reopening")
			reopened_valley.free()
			await process_frame
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	else:
		manager.clear_history()
		manager.free()
		valley.free()
		await process_frame

	await process_frame
	quit(0 if _failure_count == 0 else 1)


func _verify_disposable_starter_resculpt() -> void:
	var starter_scene := load(STARTER_SCENE_PATH) as PackedScene
	_assert(starter_scene != null, "the independent Woodland Terrain3D starter loads")
	if starter_scene == null:
		return
	var starter := starter_scene.instantiate() as Node3D
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	starter.set("collision_mode", Terrain3DCollision.FULL_GAME)
	root.add_child(starter)
	await _wait_physics_frames(8)
	var space: PhysicsDirectSpaceState3D = starter.get_world_3d().direct_space_state
	var before_hit := _raycast(space, Vector2.ZERO)
	_assert(not before_hit.is_empty(), "starter Terrain3D has a pre-resculpt collision surface")
	if before_hit.is_empty():
		camera.queue_free()
		starter.free()
		await process_frame
		return

	var terrain_data: Object = starter.get("data")
	var base_height: float = terrain_data.get_height(Vector3.ZERO)
	var samples: Array[Dictionary] = [
		{"position": Vector3(0.0, 0.0, 0.0), "height": base_height + 6.0},
		{"position": Vector3(-2.0, 0.0, 0.0), "height": base_height + 4.0},
		{"position": Vector3(2.0, 0.0, 0.0), "height": base_height + 4.0},
		{"position": Vector3(0.0, 0.0, -2.0), "height": base_height + 4.0},
		{"position": Vector3(0.0, 0.0, 2.0), "height": base_height + 4.0},
	]
	for sample in samples:
		terrain_data.set_height(sample.position, sample.height)
	terrain_data.update_maps(Terrain3DRegion.TYPE_HEIGHT, false, false)
	var collision: Object = starter.get("collision")
	collision.update()
	await _wait_physics_frames(8)
	var after_hit := _raycast(space, Vector2.ZERO)
	_assert(not after_hit.is_empty(), "Terrain3D collision remains available after in-memory resculpt")
	if not after_hit.is_empty():
		var height_delta: float = after_hit.position.y - before_hit.position.y
		print("Disposable starter resculpt collision moved %.3f m (data %.3f → %.3f m)" % [
			height_delta, base_height, terrain_data.get_height(Vector3.ZERO)])
		_assert(height_delta >= 3.0,
			"five in-memory Terrain3D height samples and collision update move the raycast surface")
	camera.queue_free()
	starter.free()
	await process_frame


func _raycast(physics_space: PhysicsDirectSpaceState3D, xz: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(Vector3(xz.x, 80.0, xz.y), Vector3(xz.x, -24.0, xz.y))
	query.collision_mask = 1
	return physics_space.intersect_ray(query)


func _find_slope_hit(physics_space: PhysicsDirectSpaceState3D) -> Dictionary:
	for xz in SLOPE_CANDIDATES:
		var hit := _raycast(physics_space, xz)
		if hit.is_empty():
			continue
		var collider: Object = hit.collider
		var angle := rad_to_deg((hit.normal as Vector3).angle_to(Vector3.UP))
		print("Terrain placement probe at %s hit %s at %s (%.2f degrees)" % [
			str(xz), collider.name, str(hit.position), angle])
		if angle >= 8.0 and angle <= 35.0:
			return hit
	return {}


func _support_distance_from_surface(rock: Node3D, normal: Vector3) -> float:
	var visuals: Array[VisualInstance3D] = []
	_collect_visual_instances(rock, visuals)
	var min_support := INF
	for visual in visuals:
		var aabb := visual.get_aabb()
		for x in [0.0, 1.0]:
			for y in [0.0, 1.0]:
				for z in [0.0, 1.0]:
					var corner := aabb.position + Vector3(aabb.size.x * x, aabb.size.y * y, aabb.size.z * z)
					var world_point := visual.global_transform * corner
					min_support = minf(min_support, (world_point - rock.global_position).dot(normal))
	return min_support


func _collect_visual_instances(node: Node, result: Array[VisualInstance3D]) -> void:
	if node is VisualInstance3D:
		result.append(node as VisualInstance3D)
	for child in node.get_children():
		_collect_visual_instances(child, result)


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failure_count += 1
		push_error("FAIL: " + message)


func _wait_physics_frames(count: int) -> void:
	for _frame in count:
		await physics_frame
		await process_frame
