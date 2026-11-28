extends SceneTree

const REGION_SIZE := 64
const GRID_SIZE := 128
const WORLD_MIN := -64
const VALLEY_DATA_DIR := "res://levels/first_steps/terrain/valley_data"
const STARTER_DATA_DIR := "res://levels/first_steps/terrain/designer_starter_data"

const TRAIL_POINTS: Array[Vector3] = [
	Vector3(0.0, 5.0, 34.0),
	Vector3(-5.0, 4.1, 18.0),
	Vector3(-10.0, 3.4, 8.0),
	Vector3(-15.0, 2.8, 0.0),
	Vector3(-18.0, 2.4, -8.0),
]

const CREEK_POINTS: Array[Vector2] = [
	Vector2(-64.0, -60.0),
	Vector2(-46.0, -43.0),
	Vector2(-31.0, -28.0),
	Vector2(-22.0, -22.0),
	Vector2(-14.0, -18.0),
	Vector2(-8.0, -17.0),
	Vector2(-2.0, -20.0),
	Vector2(12.0, -25.0),
	Vector2(32.0, -43.0),
	Vector2(64.0, -61.0),
]

# Checkpoint 5 bathymetry: the trail approaches the creek from the northwest,
# with a shallow shelf before the channel drops into the dive pocket.
const WATER_ENTRY_POINTS: Array[Vector3] = [
	Vector3(-18.0, 2.40, -10.5),
	Vector3(-18.0, 2.00, -12.5),
	Vector3(-17.0, 1.35, -14.5),
	Vector3(-16.0, 0.82, -16.0),
	Vector3(-14.0, -0.20, -18.0),
]
const WADING_SHELF_CENTER := Vector2(-16.0, -16.0)
const WADING_SHELF_RADII := Vector2(3.0, 2.2)
const WADING_SHELF_HEIGHT := 0.78
const DIVE_POOL_CENTER := Vector2(-8.5, -17.5)
const DIVE_POOL_RADII := Vector2(4.1, 3.0)
const DIVE_POOL_CUT := 1.35
const WALK_OUT_POINTS: Array[Vector3] = [
	Vector3(-2.5, 0.20, -22.0),
	Vector3(1.0, 1.20, -19.9),
	Vector3(5.5, 2.35, -17.3),
]

const EXPOSED_STONE_CENTERS: Array[Vector2] = [
	Vector2(-23.0, -18.0),
	Vector2(-11.0, -9.0),
	Vector2(4.0, -20.0),
]

const STARTER_SWATCH_CENTERS := [-24.0, -8.0, 8.0, 24.0]
const STARTER_SWATCH_SIZE := Vector2(12.0, 14.0)
var _builder_camera: Camera3D


func _initialize() -> void:
	call_deferred("_build")


func _build() -> void:
	if not ClassDB.class_exists("Terrain3D") or not ClassDB.class_exists("Terrain3DRegion"):
		push_error("Terrain3D GDExtension is unavailable. Enable res://addons/terrain_3d/plugin.cfg and import the project first.")
		quit(1)
		return

	var user_args := OS.get_cmdline_user_args()
	var allow_replace := user_args.has("--replace")
	var valley_only := user_args.has("--valley-only")
	if not _prepare_data_directory(VALLEY_DATA_DIR, allow_replace):
		quit(1)
		return
	if not valley_only and not _prepare_data_directory(STARTER_DATA_DIR, allow_replace):
		quit(1)
		return
	_builder_camera = Camera3D.new()
	_builder_camera.name = "TerrainDataBuilderCamera"
	root.add_child(_builder_camera)
	_builder_camera.current = true

	var valley: Node = _new_terrain()
	root.add_child(valley)
	await process_frame
	valley.set("region_size", REGION_SIZE)
	valley.set("vertex_spacing", 1.0)
	var valley_data = valley.get("data")
	if valley_data == null:
		push_error("Terrain3D node did not initialize its data resource.")
		quit(1)
		return
	var valley_images := _create_images(_make_valley_heightmap())
	valley_data.import_images(valley_images, Vector3(WORLD_MIN, 0.0, WORLD_MIN))
	_paint_valley(valley_data)
	valley_data.update_maps()
	valley_data.calc_height_range(true)
	valley_data.save_directory(VALLEY_DATA_DIR)
	print("Saved valley Terrain3D data to %s (%d regions)." % [VALLEY_DATA_DIR, valley_data.get_regions_active().size()])

	var starter: Node = null
	if not valley_only:
		starter = _new_terrain()
		root.add_child(starter)
		await process_frame
		starter.set("region_size", REGION_SIZE)
		starter.set("vertex_spacing", 1.0)
		var starter_data = starter.get("data")
		if starter_data == null:
			push_error("Terrain3D node did not initialize its data resource.")
			quit(1)
			return
		var starter_images := _create_images(_make_flat_heightmap(2.35))
		starter_data.import_images(starter_images, Vector3(WORLD_MIN, 0.0, WORLD_MIN))
		_paint_starter(starter_data)
		starter_data.update_maps()
		starter_data.calc_height_range(true)
		starter_data.save_directory(STARTER_DATA_DIR)
		print("Saved independent designer starter data to %s (%d regions)." % [STARTER_DATA_DIR, starter_data.get_regions_active().size()])

	var verification_failed := not await _verify_saved_data()
	valley.free()
	if is_instance_valid(starter):
		starter.free()
	if verification_failed:
		quit(1)
	else:
		print("Terrain3D data save/reopen and independence checks passed.")
		quit(0)


func _new_terrain() -> Node:
	var terrain := ClassDB.instantiate("Terrain3D") as Node
	terrain.set("clipmap_target", _builder_camera.get_path())
	terrain.set("free_editor_textures", false)
	return terrain


func _create_images(height_map: Image) -> Array[Image]:
	var images: Array[Image] = []
	images.resize(Terrain3DRegion.TYPE_MAX)
	images[Terrain3DRegion.TYPE_HEIGHT] = height_map
	var control_map := Image.create(GRID_SIZE, GRID_SIZE, false, Image.FORMAT_RF)
	control_map.fill(Color(0.0, 0.0, 0.0, 0.0))
	images[Terrain3DRegion.TYPE_CONTROL] = control_map
	return images


func _make_valley_heightmap() -> Image:
	var height_map := Image.create(GRID_SIZE, GRID_SIZE, false, Image.FORMAT_RF)
	for y in GRID_SIZE:
		var world_z := float(WORLD_MIN + y)
		for x in GRID_SIZE:
			var world_x := float(WORLD_MIN + x)
			var height := _valley_height(world_x, world_z)
			height_map.set_pixel(x, y, Color(height, 0.0, 0.0, 1.0))
	return height_map


func _make_flat_heightmap(height: float) -> Image:
	var height_map := Image.create(GRID_SIZE, GRID_SIZE, false, Image.FORMAT_RF)
	height_map.fill(Color(height, 0.0, 0.0, 1.0))
	return height_map


func _valley_height(world_x: float, world_z: float) -> float:
	var nx := absf(world_x) / 64.0
	var nz := absf(world_z) / 64.0
	var height := 2.65 + 2.2 * nx * nx + 1.7 * nz * nz
	height += 2.2 * exp(-pow((absf(world_x) - 43.0) / 13.0, 2.0))
	height += 1.2 * exp(-pow((absf(world_z) - 52.0) / 12.0, 2.0))
	height += 0.15 * sin(world_x * 0.12 + world_z * 0.04) * cos(world_z * 0.09)

	var creek_distance := _distance_to_curve(Vector2(world_x, world_z), CREEK_POINTS)
	height -= 3.5 * exp(-pow(creek_distance / 4.5, 2.0))

	var path_result := _closest_height_on_path(Vector2(world_x, world_z))
	var path_weight := 1.0 - smoothstep(1.8, 5.0, path_result.x)
	height = lerpf(height, path_result.y, path_weight)

	var water_entry := _closest_height_on_points(Vector2(world_x, world_z), WATER_ENTRY_POINTS)
	var entry_weight := 1.0 - smoothstep(1.4, 4.0, water_entry.x)
	height = lerpf(height, water_entry.y, entry_weight)

	# A broad, shallow bed lets Chibi cross into the creek on foot before the
	# channel becomes deep enough to trigger the swim controller.
	var shelf_distance := _elliptical_distance(Vector2(world_x, world_z), WADING_SHELF_CENTER, WADING_SHELF_RADII)
	var shelf_weight := 1.0 - smoothstep(0.25, 1.10, shelf_distance)
	height = lerpf(height, WADING_SHELF_HEIGHT, shelf_weight)

	# Keep the deepest floor below the character's head while preserving the
	# existing creek shape around the localized dive pocket.
	var pool_distance := _elliptical_distance(Vector2(world_x, world_z), DIVE_POOL_CENTER, DIVE_POOL_RADII)
	var pool_weight := 1.0 - smoothstep(0.15, 1.0, pool_distance)
	height -= DIVE_POOL_CUT * pool_weight

	# This shallow, rising lane gives the east/northeast bank a walkable exit.
	var walk_out := _closest_height_on_points(Vector2(world_x, world_z), WALK_OUT_POINTS)
	var walk_out_weight := 1.0 - smoothstep(1.5, 4.0, walk_out.x)
	return lerpf(height, walk_out.y, walk_out_weight)


func _paint_valley(data) -> void:
	for world_z in range(WORLD_MIN, WORLD_MIN + GRID_SIZE):
		for world_x in range(WORLD_MIN, WORLD_MIN + GRID_SIZE):
			var position := Vector3(float(world_x), 0.0, float(world_z))
			var xz := Vector2(float(world_x), float(world_z))
			var trail_distance := _closest_height_on_path(xz).x
			if trail_distance < 8.0:
				data.set_control_base_id(position, 0)
				data.set_control_overlay_id(position, 1)
				data.set_control_blend(position, 1.0 - smoothstep(2.4, 8.0, trail_distance))
				continue

			var stone_distance := _distance_to_points(xz, EXPOSED_STONE_CENTERS)
			if stone_distance < 4.8:
				data.set_control_base_id(position, 0)
				data.set_control_overlay_id(position, 3)
				data.set_control_blend(position, 1.0 - smoothstep(2.0, 4.8, stone_distance))
				continue

			var creek_distance := _distance_to_curve(xz, CREEK_POINTS)
			if creek_distance < 8.5:
				if creek_distance <= 3.2:
					data.set_control_base_id(position, 2)
				else:
					data.set_control_base_id(position, 0)
					data.set_control_overlay_id(position, 2)
					data.set_control_blend(position, 1.0 - smoothstep(3.2, 8.5, creek_distance))


func _paint_starter(data) -> void:
	for swatch_index in STARTER_SWATCH_CENTERS.size():
		var center_x: float = STARTER_SWATCH_CENTERS[swatch_index]
		var min_x := int(center_x - STARTER_SWATCH_SIZE.x * 0.5)
		var max_x := int(center_x + STARTER_SWATCH_SIZE.x * 0.5)
		var min_z := int(-STARTER_SWATCH_SIZE.y * 0.5)
		var max_z := int(STARTER_SWATCH_SIZE.y * 0.5)
		for world_z in range(min_z, max_z):
			for world_x in range(min_x, max_x):
				data.set_control_base_id(Vector3(float(world_x), 0.0, float(world_z)), swatch_index)


func _verify_saved_data() -> bool:
	var valley_check: Node = _new_terrain()
	root.add_child(valley_check)
	await process_frame
	valley_check.set("region_size", REGION_SIZE)
	valley_check.get("data").load_directory(VALLEY_DATA_DIR)
	var starter_check: Node = _new_terrain()
	root.add_child(starter_check)
	await process_frame
	starter_check.set("region_size", REGION_SIZE)
	starter_check.get("data").load_directory(STARTER_DATA_DIR)
	var valley_data = valley_check.get("data")
	var starter_data = starter_check.get("data")
	var success := true

	if valley_data.get_regions_active().size() != 4 or starter_data.get_regions_active().size() != 4:
		push_error("Expected four saved regions in each independent dataset.")
		success = false

	var height_samples := [
		["trailhead", Vector3(0.0, 0.0, 34.0)],
		["approach", Vector3(-15.0, 0.0, 5.0)],
		["west bank", Vector3(-22.0, 0.0, -14.0)],
		["east bank", Vector3(22.0, 0.0, -14.0)],
		["creek bed", Vector3(-8.0, 0.0, -17.0)],
		["root arch", Vector3(0.0, 0.0, 28.0)],
		["west rock", Vector3(-23.7, 0.0, -13.8)],
		["east rock", Vector3(22.0, 0.0, -13.2)],
		["west shelf", Vector3(-28.0, 0.0, -19.0)],
		["east shelf", Vector3(26.0, 0.0, -19.0)],
		["flower entry", Vector3(-18.8, 0.0, -9.5)],
		["flower east bank", Vector3(18.8, 0.0, -17.8)],
		["flower south bank", Vector3(-21.3, 0.0, -20.2)],
		["flower north bank", Vector3(22.5, 0.0, -7.0)],
	]
	for sample in height_samples:
		var name: String = sample[0]
		var position: Vector3 = sample[1]
		var actual: float = valley_data.get_height(position)
		print("Valley height after save/reopen — %s at (%.0f, %.0f): %.2f m" % [name, position.x, position.z, actual])
		if is_nan(actual) or is_inf(actual):
			push_error("Terrain height sample '%s' is outside saved regions." % name)
			success = false

	var feather_samples := [
		["trail edge", Vector3(4.0, 0.0, 34.0), 1],
		["creek edge", Vector3(25.0, 0.0, -30.0), 2],
	]
	for sample in feather_samples:
		var name: String = sample[0]
		var position: Vector3 = sample[1]
		var expected_overlay_id: int = sample[2]
		var overlay_id: int = valley_data.get_control_overlay_id(position)
		var blend: float = valley_data.get_control_blend(position)
		print("Valley %s after save/reopen — overlay id %d, blend %.3f" % [name, overlay_id, blend])
		if overlay_id != expected_overlay_id or blend <= 0.05 or blend >= 0.95:
			push_error("Valley %s did not reopen with its expected feathered overlay (id %d, blend %.3f)." % [name, expected_overlay_id, blend])
			success = false

	var expected_ids := [0, 1, 2, 3]
	for index in STARTER_SWATCH_CENTERS.size():
		var position := Vector3(STARTER_SWATCH_CENTERS[index], 0.0, 0.0)
		var actual_id: int = starter_data.get_control_base_id(position)
		if actual_id != expected_ids[index]:
			push_error("Starter swatch %d reopened with base texture %d; expected %d." % [index, actual_id, expected_ids[index]])
			success = false
		else:
			print("Starter swatch %d reopened with material id %d." % [index + 1, actual_id])

	var valley_before: int = valley_data.get_control_base_id(Vector3(0.0, 0.0, 0.0))
	starter_data.set_control_base_id(Vector3(0.0, 0.0, 0.0), 3)
	starter_data.save_directory(STARTER_DATA_DIR)
	var valley_reopened: Node = _new_terrain()
	root.add_child(valley_reopened)
	await process_frame
	valley_reopened.set("region_size", REGION_SIZE)
	valley_reopened.get("data").load_directory(VALLEY_DATA_DIR)
	var valley_after: int = valley_reopened.get("data").get_control_base_id(Vector3(0.0, 0.0, 0.0))
	if valley_before != valley_after:
		push_error("Editing the starter data changed the valley data; the datasets are not independent.")
		success = false
	else:
		print("Independent edit check preserved valley control id %d while starter data changed." % valley_after)
	starter_data.set_control_base_id(Vector3(0.0, 0.0, 0.0), 0)
	starter_data.save_directory(STARTER_DATA_DIR)

	valley_check.free()
	starter_check.free()
	valley_reopened.free()
	return success


func _prepare_data_directory(resource_directory: String, allow_replace: bool) -> bool:
	var absolute_directory := ProjectSettings.globalize_path(resource_directory)
	var error := DirAccess.make_dir_recursive_absolute(absolute_directory)
	if error != OK:
		push_error("Could not create %s: %s" % [resource_directory, error_string(error)])
		return false

	var existing_regions: Array[String] = []
	for file_name in DirAccess.get_files_at(absolute_directory):
		if file_name.begins_with("terrain3d_") and file_name.ends_with(".res"):
			existing_regions.append(file_name)
	if existing_regions.is_empty():
		return true
	if not allow_replace:
		push_error("Refusing to overwrite %s. Pass -- --replace to regenerate the region files." % resource_directory)
		return false
	for file_name in existing_regions:
		var remove_error := DirAccess.remove_absolute(absolute_directory.path_join(file_name))
		if remove_error != OK:
			push_error("Could not remove generated region %s: %s" % [file_name, error_string(remove_error)])
			return false
	return true


func _closest_height_on_path(position: Vector2) -> Vector2:
	return _closest_height_on_points(position, TRAIL_POINTS)


func _closest_height_on_points(position: Vector2, points: Array[Vector3]) -> Vector2:
	var best_distance := INF
	var best_height := 0.0
	for index in range(points.size() - 1):
		var start: Vector3 = points[index]
		var finish: Vector3 = points[index + 1]
		var start_xz := Vector2(start.x, start.z)
		var end_xz := Vector2(finish.x, finish.z)
		var segment := end_xz - start_xz
		var amount := clampf((position - start_xz).dot(segment) / segment.length_squared(), 0.0, 1.0)
		var closest := start_xz + segment * amount
		var distance := position.distance_to(closest)
		if distance < best_distance:
			best_distance = distance
			best_height = lerpf(start.y, finish.y, amount)
	return Vector2(best_distance, best_height)


func _elliptical_distance(position: Vector2, center: Vector2, radii: Vector2) -> float:
	return Vector2((position.x - center.x) / radii.x, (position.y - center.y) / radii.y).length()


func _distance_to_curve(position: Vector2, points: Array[Vector2]) -> float:
	var best_distance := INF
	for index in range(points.size() - 1):
		var start: Vector2 = points[index]
		var segment := points[index + 1] - start
		var amount := clampf((position - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
		best_distance = minf(best_distance, position.distance_to(start + segment * amount))
	return best_distance


func _distance_to_points(position: Vector2, points: Array[Vector2]) -> float:
	var best_distance := INF
	for point in points:
		best_distance = minf(best_distance, position.distance_to(point))
	return best_distance
