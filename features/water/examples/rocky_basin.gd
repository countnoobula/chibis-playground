extends Node3D

## A standalone water test scene with a walk-in bank and a real, uneven bed.

const RECEIVER_SHADER := preload("res://features/water/shaders/water_caustic_receiver.gdshader")
const TERRAIN_RADIUS := 18.0
const GRID_CELLS := 72
const STONE_COLORS := [
	Color("a39780"), Color("8d9b91"), Color("a793a6"), Color("bdac8c"), Color("7c8785"),
]

@onready var water: WaterBody3D = $WaterBody3D
var _noise := FastNoiseLite.new()
var _stone_meshes: Array[ArrayMesh] = []
var _receiver: ShaderMaterial


func _ready() -> void:
	_noise.seed = 18647
	_noise.frequency = 0.48
	_receiver = ShaderMaterial.new()
	_receiver.shader = RECEIVER_SHADER
	_receiver.set_shader_parameter("base_color", Color.WHITE)
	_receiver.set_shader_parameter("use_vertex_color", true)
	water.register_caustic_receiver(_receiver)
	_build_basin_floor()
	for i in STONE_COLORS.size():
		_stone_meshes.append(_make_stone_mesh(i))
	_add_boulders()
	_scatter_pebbles()
	_add_bank_grass()


func _build_basin_floor() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stride := GRID_CELLS + 1
	for row in stride:
		for column in stride:
			var x := lerpf(-TERRAIN_RADIUS, TERRAIN_RADIUS, float(column) / GRID_CELLS)
			var z := lerpf(-TERRAIN_RADIUS, TERRAIN_RADIUS, float(row) / GRID_CELLS)
			var p := Vector2(x, z)
			var shore := _shore_distance(p)
			var flecks := _noise.get_noise_2d(x * 2.1, z * 2.1) * 0.5 + 0.5
			var sand := Color("c9bb98").lerp(Color("8e9b8a"), flecks)
			var soil := Color("a4ad78").lerp(Color("7d906b"), flecks)
			var color := sand.lerp(soil, smoothstep(0.35, 2.6, -shore))
			surface.set_color(color.srgb_to_linear())
			surface.add_vertex(Vector3(x, _terrain_height(p, shore), z))
	for row in GRID_CELLS:
		for column in GRID_CELLS:
			var top_left := row * stride + column
			for vertex in [top_left, top_left + 1, top_left + stride,
				top_left + 1, top_left + stride + 1, top_left + stride]:
				surface.add_index(vertex)
	surface.generate_normals()
	_add_solid_mesh("BasinTerrain", surface.commit(), Transform3D.IDENTITY)


func _shore_distance(p: Vector2) -> float:
	var outline := water.outline
	var distance := INF
	for i in outline.size():
		var edge := Geometry2D.get_closest_point_to_segment(p, outline[i], outline[(i + 1) % outline.size()])
		distance = minf(distance, p.distance_to(edge))
	return distance if Geometry2D.is_point_in_polygon(p, outline) else -distance


func _terrain_height(p: Vector2, shore: float) -> float:
	var surface_y := water.position.y
	var bump := _noise.get_noise_2d(p.x, p.y)
	if shore >= 0.0:
		var depth := minf(2.64, shore * 0.48)
		return surface_y - depth + bump * 0.18 * smoothstep(0.0, 2.0, shore)
	var bank_height := minf(-shore * 0.23, 1.25)
	var hillside := _noise.get_noise_2d(p.x * 0.22, p.y * 0.22)
	var outer_bank := smoothstep(7.2, 15.0, -shore) * (1.7 + hillside * 1.65)
	return surface_y + bank_height + outer_bank + bump * 0.33 * smoothstep(0.0, 4.0, -shore)


func _make_stone_mesh(variant: int) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 19
	sphere.rings = 10
	var arrays := sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors := PackedColorArray()
	for i in vertices.size():
		var p := vertices[i]
		var shape := _noise.get_noise_3d(p.x * 4.0 + variant * 9.0, p.y * 4.0, p.z * 4.0)
		vertices[i] = p * (1.0 + shape * 0.29)
		var color: Color = STONE_COLORS[variant]
		colors.append(color.lerp(color.lightened(0.17), clampf(p.y + 0.34 + shape * 0.35, 0.0, 0.65)).srgb_to_linear())
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_boulders() -> void:
	var placements := [
		[Vector2(-5.0, 1.7), Vector3(2.2, 1.05, 1.55), 1],
		[Vector2(-4.35, -2.6), Vector3(1.75, 1.12, 1.35), 2],
		[Vector2(2.6, 1.5), Vector3(1.95, 1.15, 1.58), 2],
		[Vector2(2.6, -3.65), Vector3(2.18, 1.22, 1.15), 1],
		[Vector2(5.15, -4.5), Vector3(2.7, 1.62, 1.85), 0],
		[Vector2(6.8, -5.85), Vector3(2.25, 1.71, 2.2), 2],
		[Vector2(7.7, -3.82), Vector3(2.7, 2.48, 1.4), 4],
		[Vector2(-7.15, -3.3), Vector3(2.2, 1.85, 2.6), 0],
		[Vector2(-6.8, 4.4), Vector3(2.55, 1.83, 2.0), 2],
		[Vector2(-3.9, 6.5), Vector3(1.8, 1.38, 1.45), 3],
		[Vector2(4.6, 6.4), Vector3(2.6, 1.88, 2.2), 0],
		[Vector2(-4.8, -7.3), Vector3(3.45, 2.4, 2.5), 1],
		[Vector2(0.6, -8.0), Vector3(2.15, 1.85, 1.24), 2],
		[Vector2(3.8, -7.9), Vector3(3.5, 2.75, 2.3), 4],
	]
	for i in placements.size():
		var point: Vector2 = placements[i][0]
		var size: Vector3 = placements[i][1]
		var variant: int = placements[i][2]
		var y := _terrain_height(point, _shore_distance(point)) + size.y * 0.26
		var basis := Basis.from_euler(Vector3(0.09, i * 1.39, -0.12)).scaled_local(size)
		_add_solid_mesh("Boulder%02d" % i, _stone_meshes[variant], Transform3D(basis, Vector3(point.x, y, point.y)))


func _add_solid_mesh(body_name: String, mesh: ArrayMesh, placement: Transform3D) -> void:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 1
	body.position = placement.origin
	add_child(body)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.basis = placement.basis
	visual.material_override = _receiver
	body.add_child(visual)

	var faces := mesh.get_faces()
	if placement.basis != Basis.IDENTITY:
		for i in faces.size():
			faces[i] = placement.basis * faces[i]
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)


func _scatter_pebbles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7628
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 245:
		var p := Vector2(rng.randf_range(-8.7, 8.7), rng.randf_range(-8.9, 6.9))
		var shore := _shore_distance(p)
		if shore < -0.9:
			continue
		var size := rng.randf_range(0.075, 0.36)
		var y := _terrain_height(p, shore) + size * 0.06
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled_local(Vector3(size * 1.36, size * 0.6, size))
		surface.append_from(_stone_meshes[i % _stone_meshes.size()], 0, Transform3D(basis, Vector3(p.x, y, p.y)))
	var visual := MeshInstance3D.new()
	visual.name = "Pebbles"
	visual.mesh = surface.commit()
	visual.material_override = _receiver
	add_child(visual)


func _add_bank_grass() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9514
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var clumps := [
		Vector2(-5.6, 5.2), Vector2(5.6, 5.3), Vector2(-7.8, 1.2),
		Vector2(7.8, 0.4), Vector2(-8.2, -4.2), Vector2(-3.5, -7.6),
		Vector2(2.3, -7.9), Vector2(7.5, -6.7), Vector2(5.8, 2.7),
		Vector2(-2.8, 1.2), Vector2(2.95, -0.3), Vector2(-3.9, -3.9), Vector2(3.25, -4.4),
	]
	for clump: Vector2 in clumps:
		for i in 16:
			var p := clump + Vector2(rng.randf_range(-0.42, 0.42), rng.randf_range(-0.42, 0.42))
			var base := Vector3(p.x, _terrain_height(p, _shore_distance(p)) - 0.04, p.y)
			var height := rng.randf_range(0.24, 0.87)
			var across := Vector3.FORWARD.rotated(Vector3.UP, rng.randf_range(0.0, TAU))
			var bend := across.cross(Vector3.UP) * rng.randf_range(0.06, 0.24)
			var width := rng.randf_range(0.045, 0.083)
			var middle := base + Vector3.UP * height * 0.62 + bend * 0.30
			var tip := base + Vector3.UP * height + bend
			surface.set_color(Color("708543").srgb_to_linear())
			surface.add_vertex(base - across * width * 0.32)
			surface.add_vertex(base + across * width * 0.32)
			surface.set_color(Color("a9b967").srgb_to_linear())
			surface.add_vertex(middle + across * width * 0.5)
			surface.add_vertex(middle + across * width * 0.5)
			surface.add_vertex(middle - across * width * 0.5)
			surface.set_color(Color("708543").srgb_to_linear())
			surface.add_vertex(base - across * width * 0.32)
			surface.set_color(Color("a9b967").srgb_to_linear())
			surface.add_vertex(middle - across * width * 0.5)
			surface.add_vertex(middle + across * width * 0.5)
			surface.set_color(Color("bfcd82").srgb_to_linear())
			surface.add_vertex(tip)
	surface.generate_normals()
	var grass := MeshInstance3D.new()
	grass.name = "BankGrass"
	grass.mesh = surface.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.9
	grass.material_override = mat
	add_child(grass)
