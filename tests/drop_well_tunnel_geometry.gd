extends SceneTree

const COURSE_SCENE := "res://levels/rooftop_gym/stations/drop_well_tunnel.tscn"
const POOL_SCRIPT := "res://levels/rooftop_gym/stations/chibi_pool.gd"

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var course := (load(COURSE_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(course)
	var pool := Node3D.new()
	pool.name = "Zone5TestPool"
	pool.set_script(load(POOL_SCRIPT))
	pool.set("underwater_east_opening", true)
	pool.position = Vector3(24.0, 0.0, -22.0)
	pool.rotation_degrees.y = 90.0
	root.add_child(pool)
	for i in 5:
		await physics_frame
		await process_frame

	var tunnel_water := course.get_node("TunnelWater") as WaterBody3D
	var drop_water := course.get_node("DropWater") as WaterBody3D
	var pool_water := pool.get("water_body") as WaterBody3D
	_check(tunnel_water != null and drop_water != null and pool_water != null,
		"Drop, tunnel, and existing pool water volumes are created at their stable paths")	
	if tunnel_water == null or drop_water == null or pool_water == null:
		quit(1)
		return

	_check(is_equal_approx(tunnel_water.get_volume_ceiling_height(), 1.05)
		and tunnel_water.ceiling_below_surface > 0.39,
		"The enclosed tunnel reports its strict 1.05 m volume ceiling")
	_check(not (tunnel_water.get_node("Surface") as MeshInstance3D).visible
		and (drop_water.get_node("Surface") as MeshInstance3D).visible,
		"Only the open well renders a water surface plane")
	_check(WaterBody3D.find_at(course, Vector3(31.3, 1.04, -35.9)) == tunnel_water
		and WaterBody3D.find_at(course, Vector3(31.3, 1.06, -35.9)) == null,
		"Tunnel water selection ends at its roof instead of leaking above it")
	_check(WaterBody3D.find_at(course, Vector3(38.5, -2.0, -37.5)) == drop_water,
		"The drop well retains a 3.6 m deep selectable volume")
	var shallow_floor := _ray(course, Vector3(27.6, 0.0, -34.9), Vector3(27.6, -1.25, -34.9))
	var shallow_floor_point: Vector3 = shallow_floor.get("position", Vector3.ZERO)
	_check(not shallow_floor.is_empty() and absf(shallow_floor_point.y + 0.67) < 0.08,
		"The pool-to-tunnel bed meets flush at the shared doorway")
	var cap_top := _ray(course, Vector3(31.3, 1.80, -35.9), Vector3(31.3, 1.35, -35.9))
	var cap_top_point: Vector3 = cap_top.get("position", Vector3.ZERO)
	_check(not cap_top.is_empty() and absf(cap_top_point.y - 1.62) < 0.04,
		"The sealed tunnel cap rises above the legacy waterline")
	_check(not tunnel_water.contains_horizontal(Vector3(27.06, 0.42, -37.0))
		and WaterBody3D.find_at(course, Vector3(27.06, 0.42, -37.0)) == pool_water,
		"The old peach climb-out route remains assigned to Zone 5")

	var open_ray := _ray(course, Vector3(26.5, 0.40, -34.9), Vector3(29.0, 0.40, -34.9))
	_check(open_ray.is_empty(), "The east-side submerged doorway stays open through the coping wall")
	var legacy_ray := _ray(course, Vector3(26.5, 0.40, -37.0), Vector3(29.0, 0.40, -37.0))
	_check(not legacy_ray.is_empty() and (legacy_ray.collider as Node).name == "BasinCoping",
		"The adjacent peach climb-out retains its physical wall below the coping")

	course.queue_free()
	pool.queue_free()
	await process_frame
	print("=== DROP WELL / TUNNEL GEOMETRY: %s ===" % ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] ", message)
	else:
		_failed = true
		printerr("[FAIL] ", message)


func _ray(anchor: Node3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	return anchor.get_world_3d().direct_space_state.intersect_ray(query)
