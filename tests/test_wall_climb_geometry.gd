extends SceneTree

const WALL_GEOMETRY = preload("res://scripts/climbing/wall_climb_geometry.gd")

var _failures: int = 0


func _initialize() -> void:
	var test_root := Node3D.new()
	test_root.name = "WallClimbGeometryTestRoot"
	root.add_child(test_root)

	var wall := Node3D.new()
	wall.name = "GroupedWall"
	wall.add_to_group("climbable_wall")
	test_root.add_child(wall)
	_add_box(wall, Vector3(0.0, 1.0, 0.0), Vector3(2.0, 2.0, 0.2))

	var runner := CharacterBody3D.new()
	runner.name = "GeometryProbe"
	runner.collision_layer = 2
	runner.collision_mask = 1
	runner.position = Vector3(0.0, 0.1, 1.2)
	test_root.add_child(runner)
	await physics_frame
	await process_frame

	var face: Dictionary = WALL_GEOMETRY.find_face(runner, Vector3.FORWARD, 2.0)
	_check(not face.is_empty(), "find_face detects the nearest visible grouped wall")
	if not face.is_empty():
		_check(face["wall"] == wall, "face reports the nearest grouped ancestor")
		_check((face["normal"] as Vector3).is_equal_approx(Vector3.BACK), "face normal points outward toward the runner")
		_check((face["right"] as Vector3).is_equal_approx(Vector3.RIGHT), "face right follows the wall plane")

	var contacts: Array[Dictionary] = WALL_GEOMETRY.find_contacts(runner, face, Vector3(0.0, 2.0, 0.1), 0.20)
	_check(not contacts.is_empty(), "find_contacts discovers a broad upward support cap")
	if not contacts.is_empty():
		var support: Dictionary = contacts[0]
		_check(absf((support["point"] as Vector3).y - 2.0) < 0.015, "contact point is on the actual top support")
		_check((support["top_normal"] as Vector3).dot(Vector3.UP) > 0.99, "contact reports the upward top normal")
		_check(support["collider"] is StaticBody3D, "contact returns its static collision body")
		_check((support["local_point"] as Vector3).distance_to(wall.to_local(support["point"])) < 0.001, "contact includes a root-local support point")

	var smooth_only: Dictionary = {"wall": wall, "point": Vector3(0.0, 0.9, 0.1), "normal": Vector3.BACK, "right": Vector3.RIGHT, "up": Vector3.UP}
	var smooth_contacts: Array[Dictionary] = WALL_GEOMETRY.find_contacts(runner, smooth_only, Vector3(0.0, 0.9, 0.1), 0.16)
	_check(smooth_contacts.is_empty(), "a distant wall cap is not reported as a nearby grip")

	var blocker := _add_box(test_root, Vector3(0.0, 1.0, 0.58), Vector3(2.0, 2.0, 0.16))
	await physics_frame
	var blocked_face: Dictionary = WALL_GEOMETRY.find_face(runner, Vector3.FORWARD, 2.0)
	_check(blocked_face.is_empty(), "an unmarked world collider blocks the grouped wall behind it")
	blocker.queue_free()
	await physics_frame

	var wall_scene: PackedScene = load("res://scenes/stations/dynamic_climbing_wall.tscn")
	if wall_scene != null:
		var authored_wall := wall_scene.instantiate() as Node3D
		authored_wall.position.x = 5.0
		test_root.add_child(authored_wall)
		runner.position = Vector3(5.0, 0.1, 1.2)
		await physics_frame
		var authored_face: Dictionary = WALL_GEOMETRY.find_face(runner, Vector3.FORWARD, 2.0)
		_check(not authored_face.is_empty(), "authored climbing wall has a visible climb face")
		var lip_specs := [
			Vector3(-0.76, 0.68, 0.02),
			Vector3(-0.50, 0.99, 0.02),
			Vector3(-0.12, 1.30, 0.02),
			Vector3(0.33, 1.90, 0.02),
			Vector3(0.67, 2.22, 0.02),
			Vector3(0.35, 2.54, 0.02),
			Vector3(0.00, 2.76, -0.21),
		]
		for lip_spec: Vector3 in lip_specs:
			var grip_center := authored_wall.to_global(lip_spec)
			var lip_contacts: Array[Dictionary] = WALL_GEOMETRY.find_contacts(runner, authored_face, grip_center, 0.20)
			var found_level := false
			var front_z := 0.075 if not is_equal_approx(lip_spec.y, 2.76) else 0.015
			for lip_contact in lip_contacts:
				var local_contact: Vector3 = authored_wall.to_local(lip_contact["point"])
				if absf(local_contact.x - lip_spec.x) <= 0.20 and absf(local_contact.y - lip_spec.y) <= 0.02:
					found_level = true
					_check(absf(local_contact.z - front_z) <= 0.012, "lip support at y=%.2f m stays near its front edge" % lip_spec.y)
					break
			_check(found_level, "authored wall exposes support near lip at y=%.2f m" % lip_spec.y)

		var start := authored_wall.get_node("StartLip") as StaticBody3D
		start.position += Vector3(-0.40, -0.22, 0.0)
		await physics_frame
		await physics_frame
		var moved_center := authored_wall.to_global(Vector3(-1.16, 0.46, 0.075))
		var rearranged := WALL_GEOMETRY.find_contacts(runner, authored_face, moved_center, 0.18)
		var follows_masonry := rearranged.any(func(contact: Dictionary) -> bool:
			return contact["collider"] == start and absf((contact["point"] as Vector3).y - moved_center.y) < 0.015
		)
		var original_center := authored_wall.to_global(Vector3(-0.76, 0.68, 0.075))
		var original := WALL_GEOMETRY.find_contacts(runner, authored_face, original_center, 0.12)
		var has_old_grip := original.any(func(contact: Dictionary) -> bool:
			return contact["collider"] == start and absf((contact["point"] as Vector3).y - original_center.y) < 0.015
		)
		_check(follows_masonry and not has_old_grip, "Grip detection follows a rearranged lip")
	else:
		_check(false, "authored dynamic wall scene can be loaded for geometry checks")

	if _failures == 0:
		print("PASS: wall climb geometry checks")
	else:
		push_error("%d wall climb geometry check(s) failed" % _failures)
	test_root.queue_free()
	quit(_failures)


func _add_box(parent: Node3D, position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	body.collision_layer = 1
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		_failures += 1
		push_error("FAIL: %s" % message)
