class_name DropWellTunnel
extends Node3D

## A stand-alone deep drop well joined to Zone 5 through a covered swim tunnel.
## Authored in rooftop world coordinates so the scene can be added at identity.

const WATER_SCENE := preload("res://scenes/water/water_body_3d.tscn")
const PALETTE := preload("res://scripts/gym/rooftop_palette.gd")

const WATER_SURFACE_Y := 1.45
const WATER_DEPTH := 3.60
const CHANNEL_CEILING_Y := 1.05
const ROOF_TOP_Y := 1.62
const ROOF_THICKNESS := ROOF_TOP_Y - CHANNEL_CEILING_Y

const TUNNEL_CAP_MIN_X := 26.20
const TUNNEL_CAP_MAX_X := 35.00
const TUNNEL_CAP_MIN_Z := -39.50
const TUNNEL_CAP_MAX_Z := -33.50
const WELL_MIN_X := 34.85
const WELL_MAX_X := 42.20
const WELL_MIN_Z := -41.20
const WELL_MAX_Z := -33.80

const TUNNEL_STATIONS := [
	# x, center z, floor y, channel half-width
	Vector4(26.20, -34.90, -0.67, 1.20),
	Vector4(27.60, -34.90, -0.67, 1.20),
	Vector4(28.00, -34.90, -0.73, 1.20),
	Vector4(28.40, -34.90, -0.84, 1.20),
	Vector4(28.80, -34.90, -0.90, 1.20),
	Vector4(30.20, -35.35, -1.00, 1.45),
	Vector4(32.00, -36.30, -1.42, 1.60),
	Vector4(33.50, -37.15, -1.80, 1.60),
	Vector4(35.00, -37.50, -2.15, 1.60),
]

const FLOOR_CROSS_SLOPES := [0.18, 0.18, 0.13, 0.06, 0.0, 0.0, 0.0, 0.0, 0.0]

const CAP_PROFILE := [
	# x, center z, cap half-width. These rows also drive builder dry-deck infill.
	Vector3(26.20, -34.90, 1.40),
	Vector3(28.80, -34.90, 1.40),
	Vector3(30.20, -35.35, 1.65),
	Vector3(32.00, -36.30, 1.85),
	Vector3(33.50, -37.15, 2.00),
	Vector3(35.00, -37.50, 2.00),
]

const WELL_FLOOR_Y := -2.15
const WELL_WALL_TOP := 1.55
const WELL_WALL_THICKNESS := 0.35
const WELL_OPENING_HALF_WIDTH := 1.60
const WELL_OPENING_CEILING := CHANNEL_CEILING_Y

var _porcelain: StandardMaterial3D
var _interior: StandardMaterial3D
var _mint: StandardMaterial3D
var _peach: StandardMaterial3D
var _roof_material: StandardMaterial3D


static func get_cap_deck_rows() -> PackedVector3Array:
	## Each point is (world X, north Z, south Z), ordered along the tunnel.
	var rows := PackedVector3Array()
	for row: Vector3 in CAP_PROFILE:
		rows.append(Vector3(row.x, row.y - row.z, row.y + row.z))
	return rows


func _ready() -> void:
	_porcelain = _make_matte(PALETTE.PORCELAIN)
	_interior = _make_matte(Color("b8d7cf"))
	_mint = _make_matte(PALETTE.MINT)
	_peach = _make_matte(PALETTE.PEACH)
	_roof_material = _make_matte(Color("d6e5dd"))
	_build_tunnel_floor()
	_build_tunnel_walls()
	_build_tunnel_roof()
	_build_well()
	_build_water_bodies()
	_add_tunnel_guide_strips()
	_add_tunnel_lights()


func _build_water_bodies() -> void:
	var drop_water := WATER_SCENE.instantiate() as WaterBody3D
	drop_water.name = "DropWater"
	drop_water.position.y = WATER_SURFACE_Y
	drop_water.max_depth = WATER_DEPTH
	drop_water.selection_priority = 20
	drop_water.outline = PackedVector2Array([
		Vector2(WELL_MIN_X, WELL_MIN_Z + 0.35),
		Vector2(WELL_MAX_X - 0.35, WELL_MIN_Z + 0.35),
		Vector2(WELL_MAX_X - 0.35, WELL_MAX_Z - 0.35),
		Vector2(WELL_MIN_X, WELL_MAX_Z - 0.35),
	])
	add_child(drop_water)

	var tunnel_water := WATER_SCENE.instantiate() as WaterBody3D
	tunnel_water.name = "TunnelWater"
	tunnel_water.position.y = WATER_SURFACE_Y
	tunnel_water.max_depth = WATER_DEPTH
	tunnel_water.ceiling_below_surface = WATER_SURFACE_Y - CHANNEL_CEILING_Y
	tunnel_water.selection_priority = 30
	tunnel_water.outline = _make_tunnel_water_outline()
	add_child(tunnel_water)


func _make_tunnel_water_outline() -> PackedVector2Array:
	var outline := PackedVector2Array()
	for i in range(TUNNEL_STATIONS.size()):
		var station: Vector4 = TUNNEL_STATIONS[i]
		var offset := _station_normal(i) * (station.w - 0.04)
		outline.append(Vector2(station.x + offset.x, station.y + offset.y))
	for i in range(TUNNEL_STATIONS.size() - 1, -1, -1):
		var station: Vector4 = TUNNEL_STATIONS[i]
		var offset := _station_normal(i) * (station.w - 0.04)
		outline.append(Vector2(station.x - offset.x, station.y - offset.y))
	return outline


func _build_tunnel_floor() -> void:
	const FLOOR_THICKNESS := 0.28
	var floor_surface := SurfaceTool.new()
	floor_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(TUNNEL_STATIONS.size() - 1):
		var a_left := _floor_vertex(i, -1.0)
		var a_right := _floor_vertex(i, 1.0)
		var b_left := _floor_vertex(i + 1, -1.0)
		var b_right := _floor_vertex(i + 1, 1.0)
		var a_left_bottom := a_left - Vector3.UP * FLOOR_THICKNESS
		var a_right_bottom := a_right - Vector3.UP * FLOOR_THICKNESS
		var b_left_bottom := b_left - Vector3.UP * FLOOR_THICKNESS
		var b_right_bottom := b_right - Vector3.UP * FLOOR_THICKNESS
		_quad_solid(floor_surface, [a_left, b_left, b_right, a_right], Vector3.UP)
		_quad_solid(floor_surface, [a_left_bottom, a_right_bottom, b_right_bottom, b_left_bottom], Vector3.DOWN)
		_quad_solid(floor_surface, [a_left_bottom, b_left_bottom, b_left, a_left], -_station_side(i))
		_quad_solid(floor_surface, [a_right_bottom, a_right, b_right, b_right_bottom], _station_side(i))
		if i == 0:
			_quad_solid(floor_surface, [a_left_bottom, a_left, a_right, a_right_bottom], Vector3.LEFT)
		if i == TUNNEL_STATIONS.size() - 2:
			_quad_solid(floor_surface, [b_left_bottom, b_right_bottom, b_right, b_left], Vector3.RIGHT)
	_add_mesh_body("TunnelFloor", floor_surface, _interior)


func _floor_vertex(index: int, side_sign: float) -> Vector3:
	var station: Vector4 = TUNNEL_STATIONS[index]
	var offset: Vector2 = _station_normal(index) * station.w * side_sign
	var cross_slope: float = FLOOR_CROSS_SLOPES[index] * side_sign * station.w
	return Vector3(station.x + offset.x, station.z + cross_slope, station.y + offset.y)


func _station_side(index: int) -> Vector3:
	var normal := _station_normal(index)
	return Vector3(normal.x, 0.0, normal.y)


func _build_tunnel_walls() -> void:
	const WALL_THICKNESS := 0.24
	for i in range(TUNNEL_STATIONS.size() - 1):
		var a: Vector4 = TUNNEL_STATIONS[i]
		var b: Vector4 = TUNNEL_STATIONS[i + 1]
		var horizontal := Vector2(b.x - a.x, b.y - a.y)
		var length := horizontal.length()
		var tangent_2d := horizontal.normalized()
		var side_2d := Vector2(-tangent_2d.y, tangent_2d.x)
		var yaw_basis := Basis(Vector3(tangent_2d.x, 0.0, tangent_2d.y), Vector3.UP, Vector3(side_2d.x, 0.0, side_2d.y))
		var avg_half_width := (a.w + b.w) * 0.5
		var low_floor := minf(a.z - FLOOR_CROSS_SLOPES[i] * a.w, b.z - FLOOR_CROSS_SLOPES[i + 1] * b.w) - 0.10
		var wall_bottom := low_floor - WALL_THICKNESS * 0.5
		var wall_top := CHANNEL_CEILING_Y + WALL_THICKNESS * 0.5
		var wall_height := wall_top - wall_bottom
		var center_x := (a.x + b.x) * 0.5
		var center_z := (a.y + b.y) * 0.5
		var position := Vector3(center_x, (wall_bottom + wall_top) * 0.5, center_z)
		var side_offset := side_2d * (avg_half_width + WALL_THICKNESS * 0.5)
		position.x += side_offset.x
		position.z += side_offset.y
		_add_box_body("TunnelWallL_%02d" % i, position, Vector3(length + 0.12, wall_height, WALL_THICKNESS), _porcelain, yaw_basis)
		position.x = center_x - side_offset.x
		position.z = center_z - side_offset.y
		_add_box_body("TunnelWallR_%02d" % i, position, Vector3(length + 0.12, wall_height, WALL_THICKNESS), _porcelain, yaw_basis)



func _build_tunnel_roof() -> void:
	var roof := SurfaceTool.new()
	roof.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(CAP_PROFILE.size() - 1):
		var a: Vector3 = CAP_PROFILE[i]
		var b: Vector3 = CAP_PROFILE[i + 1]
		var north_a := Vector3(a.x, CHANNEL_CEILING_Y, a.y - a.z)
		var south_a := Vector3(a.x, CHANNEL_CEILING_Y, a.y + a.z)
		var north_b := Vector3(b.x, CHANNEL_CEILING_Y, b.y - b.z)
		var south_b := Vector3(b.x, CHANNEL_CEILING_Y, b.y + b.z)
		var north_top_a := north_a + Vector3.UP * ROOF_THICKNESS
		var south_top_a := south_a + Vector3.UP * ROOF_THICKNESS
		var north_top_b := north_b + Vector3.UP * ROOF_THICKNESS
		var south_top_b := south_b + Vector3.UP * ROOF_THICKNESS
		_quad_solid(roof, [north_top_a, north_top_b, south_top_b, south_top_a], Vector3.UP)
		_quad_solid(roof, [north_a, south_a, south_b, north_b], Vector3.DOWN)
		_quad_solid(roof, [north_a, north_b, north_top_b, north_top_a], Vector3.FORWARD)
		_quad_solid(roof, [south_a, south_top_a, south_top_b, south_b], Vector3.BACK)
	var first: Vector3 = CAP_PROFILE[0]
	var last: Vector3 = CAP_PROFILE[CAP_PROFILE.size() - 1]
	_quad_solid(roof, [
		Vector3(first.x, CHANNEL_CEILING_Y, first.y - first.z),
		Vector3(first.x, CHANNEL_CEILING_Y, first.y + first.z),
		Vector3(first.x, ROOF_TOP_Y, first.y + first.z),
		Vector3(first.x, ROOF_TOP_Y, first.y - first.z),
	], Vector3.LEFT)
	_quad_solid(roof, [
		Vector3(last.x, CHANNEL_CEILING_Y, last.y - last.z),
		Vector3(last.x, ROOF_TOP_Y, last.y - last.z),
		Vector3(last.x, ROOF_TOP_Y, last.y + last.z),
		Vector3(last.x, CHANNEL_CEILING_Y, last.y + last.z),
	], Vector3.RIGHT)
	_add_mesh_body("TunnelCap", roof, _roof_material)


func _build_well() -> void:
	const FLOOR_THICKNESS := 0.28
	const OUTER_WIDTH := WELL_MAX_X - WELL_MIN_X
	const OUTER_DEPTH := WELL_MAX_Z - WELL_MIN_Z
	const wall_center_y := (WELL_FLOOR_Y + WELL_WALL_TOP) * 0.5
	const wall_height := WELL_WALL_TOP - WELL_FLOOR_Y
	var center_x := (WELL_MIN_X + WELL_MAX_X) * 0.5
	var center_z := (WELL_MIN_Z + WELL_MAX_Z) * 0.5

	_add_box_body("WellBed", Vector3(center_x, WELL_FLOOR_Y - FLOOR_THICKNESS * 0.5, center_z),
		Vector3(OUTER_WIDTH - 0.52, FLOOR_THICKNESS, OUTER_DEPTH - 0.52), _interior)

	# Full north, south and east shell walls. Their lower edges overlap the bed.
	var inner_x_min := WELL_MIN_X + WELL_WALL_THICKNESS * 0.5
	var inner_x_max := WELL_MAX_X - WELL_WALL_THICKNESS * 0.5
	var inner_z_min := WELL_MIN_Z + WELL_WALL_THICKNESS * 0.5
	var inner_z_max := WELL_MAX_Z - WELL_WALL_THICKNESS * 0.5
	_add_box_body("WellNorthWall", Vector3(center_x, wall_center_y, WELL_MIN_Z + WELL_WALL_THICKNESS * 0.5),
		Vector3(OUTER_WIDTH, wall_height + 0.16, WELL_WALL_THICKNESS), _porcelain)
	_add_box_body("WellSouthWall", Vector3(center_x, wall_center_y, WELL_MAX_Z - WELL_WALL_THICKNESS * 0.5),
		Vector3(OUTER_WIDTH, wall_height + 0.16, WELL_WALL_THICKNESS), _porcelain)
	_add_box_body("WellEastWall", Vector3(WELL_MAX_X - WELL_WALL_THICKNESS * 0.5, wall_center_y, center_z),
		Vector3(WELL_WALL_THICKNESS, wall_height + 0.16, OUTER_DEPTH), _porcelain)

	# The west wall has a submerged doorway into the tunnel, capped at the tunnel ceiling.
	var opening_half := WELL_OPENING_HALF_WIDTH
	var north_opening_edge := center_z - opening_half
	var south_opening_edge := center_z + opening_half
	var side_z_length := north_opening_edge - WELL_MIN_Z
	var south_side_length := WELL_MAX_Z - south_opening_edge
	_add_box_body("WellWestWallNorth", Vector3(WELL_MIN_X + WELL_WALL_THICKNESS * 0.5, wall_center_y,
		(WELL_MIN_Z + north_opening_edge) * 0.5), Vector3(WELL_WALL_THICKNESS, wall_height + 0.16, side_z_length), _porcelain)
	_add_box_body("WellWestWallSouth", Vector3(WELL_MIN_X + WELL_WALL_THICKNESS * 0.5, wall_center_y,
		(south_opening_edge + WELL_MAX_Z) * 0.5), Vector3(WELL_WALL_THICKNESS, wall_height + 0.16, south_side_length), _porcelain)
	_add_box_body("WellWestLintel", Vector3(WELL_MIN_X + WELL_WALL_THICKNESS * 0.5,
		(WELL_OPENING_CEILING + WELL_WALL_TOP) * 0.5, center_z),
		Vector3(WELL_WALL_THICKNESS, WELL_WALL_TOP - WELL_OPENING_CEILING, opening_half * 2.0), _porcelain)

	# Coping traces the four edges. The west coping is split around the doorway.
	const COPING_THICKNESS := 0.16
	const COPING_DEPTH := 0.38
	var coping_y := WELL_WALL_TOP + COPING_THICKNESS * 0.5
	_add_box_body("WellCopingNorth", Vector3(center_x, coping_y, WELL_MIN_Z + WELL_WALL_THICKNESS * 0.5),
		Vector3(OUTER_WIDTH, COPING_THICKNESS, COPING_DEPTH), _porcelain)
	_add_box_body("WellCopingEast", Vector3(WELL_MAX_X - WELL_WALL_THICKNESS * 0.5, coping_y, center_z),
		Vector3(COPING_DEPTH, COPING_THICKNESS, OUTER_DEPTH), _porcelain)
	_add_box_body("WellCopingWestNorth", Vector3(WELL_MIN_X + WELL_WALL_THICKNESS * 0.5, coping_y,
		(WELL_MIN_Z + north_opening_edge) * 0.5), Vector3(COPING_DEPTH, COPING_THICKNESS, side_z_length), _porcelain)
	_add_box_body("WellCopingWestSouth", Vector3(WELL_MIN_X + WELL_WALL_THICKNESS * 0.5, coping_y,
		(south_opening_edge + WELL_MAX_Z) * 0.5), Vector3(COPING_DEPTH, COPING_THICKNESS, south_side_length), _porcelain)
	var exit_width := 2.0
	var south_side_north_span := center_x - exit_width * 0.5 - WELL_MIN_X
	var south_side_south_span := WELL_MAX_X - (center_x + exit_width * 0.5)
	_add_box_body("WellCopingSouthWest", Vector3((WELL_MIN_X + center_x - exit_width * 0.5) * 0.5, coping_y,
		WELL_MAX_Z - WELL_WALL_THICKNESS * 0.5), Vector3(south_side_north_span, COPING_THICKNESS, COPING_DEPTH), _porcelain)
	_add_box_body("WellCopingSouthEast", Vector3((center_x + exit_width * 0.5 + WELL_MAX_X) * 0.5, coping_y,
		WELL_MAX_Z - WELL_WALL_THICKNESS * 0.5), Vector3(south_side_south_span, COPING_THICKNESS, COPING_DEPTH), _porcelain)
	_add_box_body("PeachClimbOut", Vector3(center_x, coping_y + 0.012, WELL_MAX_Z - WELL_WALL_THICKNESS * 0.5),
		Vector3(exit_width, COPING_THICKNESS + 0.025, COPING_DEPTH + 0.025), _peach)

	# Broad submerged treads make the peach exit legible and physically climbable.
	for i in range(4):
		# Keep the final tread deep enough that Rise still climbs to the rim.
		var tread_y := -1.58 + float(i) * 0.64
		var tread_z := WELL_MAX_Z - 1.82 + float(i) * 0.34
		_add_box_body("ClimbStep_%d" % i, Vector3(center_x, tread_y, tread_z), Vector3(1.70, 0.18, 0.38), _mint if i % 2 == 0 else _porcelain)

	# Narrow tile lines catch light just inside the basin walls without narrowing the well.
	_add_box_visual("WellWaterlineNorth", Vector3(center_x, 0.80, inner_z_min + 0.018), Vector3(OUTER_WIDTH - 0.70, 0.09, 0.035), _mint)
	_add_box_visual("WellWaterlineSouth", Vector3(center_x, 0.80, inner_z_max - 0.018), Vector3(OUTER_WIDTH - 0.70, 0.09, 0.035), _mint)


func _add_tunnel_guide_strips() -> void:
	# The outer route walls are light porcelain; the inner mint band and crown tint
	# give the player a continuous cue through the bend.
	for i in range(TUNNEL_STATIONS.size() - 1):
		var a: Vector4 = TUNNEL_STATIONS[i]
		var b: Vector4 = TUNNEL_STATIONS[i + 1]
		var horizontal := Vector2(b.x - a.x, b.y - a.y)
		var tangent := horizontal.normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var yaw_basis := Basis(Vector3(tangent.x, 0.0, tangent.y), Vector3.UP, Vector3(normal.x, 0.0, normal.y))
		var half_width := (a.w + b.w) * 0.5
		var center := Vector3((a.x + b.x) * 0.5, 0.38, (a.y + b.y) * 0.5)
		for side_sign in [-1.0, 1.0]:
			var offset: Vector2 = normal * (half_width + 0.012) * float(side_sign)
			var pos := center + Vector3(offset.x, 0.0, offset.y)
			_add_box_visual("GuideBand_%02d_%s" % [i, "L" if side_sign < 0.0 else "R"], pos,
				Vector3(horizontal.length() * 0.90, 0.075, 0.025), _mint, yaw_basis)


func _add_tunnel_lights() -> void:
	for i in range(1, TUNNEL_STATIONS.size() - 1, 2):
		var station: Vector4 = TUNNEL_STATIONS[i]
		var light := OmniLight3D.new()
		light.name = "TunnelLight_%02d" % i
		light.light_color = Color("9cddd1")
		light.light_energy = 0.38
		light.omni_range = 4.2
		light.shadow_enabled = false
		light.position = Vector3(station.x, 0.80, station.y)
		add_child(light)


func _station_normal(index: int) -> Vector2:
	var current: Vector4 = TUNNEL_STATIONS[index]
	var previous: Vector4 = TUNNEL_STATIONS[maxi(index - 1, 0)]
	var next: Vector4 = TUNNEL_STATIONS[mini(index + 1, TUNNEL_STATIONS.size() - 1)]
	var tangent := Vector2(next.x - previous.x, next.y - previous.y).normalized()
	return Vector2(-tangent.y, tangent.x)


func _add_box_visual(node_name: String, position: Vector3, size: Vector3, material: Material, basis: Basis = Basis.IDENTITY) -> void:
	var visual := MeshInstance3D.new()
	visual.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = material
	visual.transform = Transform3D(basis, position)
	add_child(visual)


func _add_box_body(node_name: String, position: Vector3, size: Vector3, material: Material, basis: Basis = Basis.IDENTITY) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.transform = Transform3D(basis, position)
	add_child(body)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Body"
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)


func _add_mesh_body(node_name: String, surface: SurfaceTool, material: Material) -> void:
	surface.generate_normals()
	surface.index()
	var mesh := surface.commit()
	var body := StaticBody3D.new()
	body.name = node_name
	add_child(body)
	var visual := MeshInstance3D.new()
	visual.name = "Body"
	visual.mesh = mesh
	visual.material_override = material
	body.add_child(visual)
	var collider := CollisionShape3D.new()
	collider.shape = mesh.create_trimesh_shape()
	body.add_child(collider)


func _quad_solid(surface: SurfaceTool, points: Array[Vector3], facing: Vector3) -> void:
	for triangle in [[0, 1, 2], [0, 2, 3]]:
		var normal := (points[triangle[1]] - points[triangle[0]]).cross(points[triangle[2]] - points[triangle[0]])
		if normal.length_squared() <= 0.0000001:
			continue
		if normal.dot(facing) > 0.0:
			triangle.reverse()
		for vertex_index: int in triangle:
			surface.add_vertex(points[vertex_index])


func _make_matte(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.80
	material.metallic_specular = 0.18
	return material
