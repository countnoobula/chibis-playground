class_name ChibiPool
extends Node3D

## Rooftop basin geometry. Swimming and water lighting are supplied by WaterBody3D.

const WATER_Y := 1.45
const POOL_DEPTH := 2.35
const COPING_WIDTH := 1.0
const COPING_TOP := WATER_Y + 0.10
const BEVEL := 0.055
const UNDERWATER_OPENING_MIN_X := 11.60
const UNDERWATER_OPENING_MAX_X := 14.20
const UNDERWATER_OPENING_LOCAL_Z := 3.60
const UNDERWATER_OPENING_TOP := 1.05

# Each row gives distance from the entry, left and right edges, and bed depth.
# The paired rows define every wet surface and the dry pieces around it.
const SECTIONS := [
	Vector4(0.00, -1.67, 1.83, 0.00),
	Vector4(0.26, -2.01, 2.15, 0.03),
	Vector4(0.72, -2.25, 2.38, 0.12),
	Vector4(2.20, -2.32, 2.46, 0.52),
	Vector4(4.40, -2.34, 2.48, 0.52),
	Vector4(6.20, -2.48, 2.69, 0.82),
	Vector4(8.55, -3.10, 3.18, 1.28),
	Vector4(10.25, -3.48, 3.50, 1.61),
	Vector4(11.60, -3.60, 3.60, 1.91),
	Vector4(14.20, -3.60, 3.60, POOL_DEPTH),
	Vector4(16.85, -3.60, 3.60, POOL_DEPTH),
	Vector4(17.80, -3.49, 3.54, POOL_DEPTH),
	Vector4(18.56, -3.05, 3.21, POOL_DEPTH),
	Vector4(19.00, -2.48, 2.72, POOL_DEPTH),
	Vector4(19.20, -1.74, 2.05, POOL_DEPTH),
]

const WATER_SCENE := preload("res://features/water/water_body_3d.tscn")
const RECEIVER_SHADER := preload("res://features/water/shaders/water_caustic_receiver.gdshader")
const PALETTE := preload("res://levels/rooftop_gym/rooftop_palette.gd")

@export var deck_material: Material
## Opens the east (+local Z) coping wall below the tunnel crown.
## Disabled by default so existing pool instances keep their sealed side wall.
@export var underwater_east_opening: bool = false

var water_body: WaterBody3D


static func shoreline() -> PackedVector2Array:
	var outline := PackedVector2Array()
	for row: Vector4 in SECTIONS:
		outline.append(Vector2(row.x, row.y))
	for i in range(SECTIONS.size() - 1, -1, -1):
		var row: Vector4 = SECTIONS[i]
		outline.append(Vector2(row.x, row.z))
	return outline


static func deck_opening_bounds() -> Rect2:
	var outline := shoreline()
	var bounds := Rect2(outline[0], Vector2.ZERO)
	for point in outline:
		bounds = bounds.expand(point)
	return bounds


func _ready() -> void:
	var outline := shoreline()
	water_body = WATER_SCENE.instantiate() as WaterBody3D
	water_body.position.y = WATER_Y
	water_body.max_depth = POOL_DEPTH
	water_body.outline = outline
	add_child(water_body)

	var ceramic := ShaderMaterial.new()
	ceramic.shader = RECEIVER_SHADER
	ceramic.set_shader_parameter("base_color", Color.WHITE)
	ceramic.set_shader_parameter("use_vertex_color", true)
	ceramic.set_shader_parameter("roughness", 0.77)
	water_body.register_caustic_receiver(ceramic)
	_build_bed(ceramic)
	_build_coping(outline, ceramic)
	_build_approach()
	_close_dry_deck_gaps()


func _build_bed(material: Material) -> MeshInstance3D:
	var bed := SurfaceTool.new()
	bed.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(SECTIONS.size() - 1):
		var near_row: Vector4 = SECTIONS[i]
		var far_row: Vector4 = SECTIONS[i + 1]
		var near_tint := _bed_tint(near_row.w)
		var far_tint := _bed_tint(far_row.w)
		_quad(bed, [
			Vector3(near_row.x, WATER_Y - near_row.w, near_row.y),
			Vector3(far_row.x, WATER_Y - far_row.w, far_row.y),
			Vector3(far_row.x, WATER_Y - far_row.w, far_row.z),
			Vector3(near_row.x, WATER_Y - near_row.w, near_row.z),
		], Vector3.UP, [near_tint, far_tint, far_tint, near_tint])
	return _add_solid("BasinBed", bed, material)


func _bed_tint(depth: float) -> Color:
	return Color("dceee3").lerp(Color("9fbbb0"), smoothstep(0.20, POOL_DEPTH, depth)).srgb_to_linear()


func _build_coping(outline: PackedVector2Array, material: Material) -> MeshInstance3D:
	var rim := SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var white := PALETTE.PORCELAIN.srgb_to_linear()
	var peach := PALETTE.PEACH.srgb_to_linear()

	# The closing edge at the south end is the open walk-in mouth.
	for i in range(outline.size() - 1):
		var a := outline[i]
		var b := outline[i + 1]
		var outside := _edge_outward(a, b)
		var outward := Vector3(outside.x, 0.0, outside.y)
		var corner_a := _corner_outward(outline, i)
		var corner_b := _corner_outward(outline, i + 1)
		var upper_a := a + corner_a * BEVEL
		var upper_b := b + corner_b * BEVEL
		var lower_a := a + corner_a * COPING_WIDTH
		var lower_b := b + corner_b * COPING_WIDTH
		var outer_a := a + corner_a * (COPING_WIDTH - BEVEL)
		var outer_b := b + corner_b * (COPING_WIDTH - BEVEL)
		var bevel_y := COPING_TOP - BEVEL
		var bed_a := WATER_Y - _row_depth(i) - 0.12
		var bed_b := WATER_Y - _row_depth(i + 1) - 0.12
		var midpoint_x := (a.x + b.x) * 0.5
		var exit_segment := a.y > 3.5 and b.y > 3.5 and midpoint_x > 14.20 and midpoint_x < 16.85
		var underwater_opening := _is_underwater_opening_edge(a, b)
		var trim := peach if exit_segment else white

		if underwater_opening:
			# Keep the coping and its load-bearing header while removing only the
			# submerged wall face. This preserves the peach climb-out at the far end.
			_quad_solid(rim, _at(a, UNDERWATER_OPENING_TOP), _at(b, UNDERWATER_OPENING_TOP),
				_at(b, bevel_y), _at(a, bevel_y), -outward, white)
		else:
			_quad_solid(rim, _at(a, bed_a), _at(b, bed_b), _at(b, bevel_y), _at(a, bevel_y), -outward, white)
		_quad_solid(rim, _at(a, bevel_y), _at(b, bevel_y), _at(upper_b, COPING_TOP), _at(upper_a, COPING_TOP), Vector3.UP - outward, trim)
		_quad_solid(rim, _at(upper_a, COPING_TOP), _at(upper_b, COPING_TOP), _at(outer_b, COPING_TOP), _at(outer_a, COPING_TOP), Vector3.UP, trim)
		if underwater_opening:
			_quad_solid(rim, _at(outer_a, COPING_TOP), _at(outer_b, COPING_TOP),
				_at(lower_b, UNDERWATER_OPENING_TOP), _at(lower_a, UNDERWATER_OPENING_TOP), Vector3.UP + outward, trim)
		else:
			_quad_solid(rim, _at(outer_a, COPING_TOP), _at(outer_b, COPING_TOP), _at(lower_b, bevel_y), _at(lower_a, bevel_y), Vector3.UP + outward, trim)
			_quad_solid(rim, _at(lower_a, bevel_y), _at(lower_b, bevel_y), _at(lower_b, minf(bed_b, 0.0)), _at(lower_a, minf(bed_a, 0.0)), outward, white)

	var first := outline[0]
	var last := outline[outline.size() - 1]
	# Seal the underside of the entry so the roof can't lead under the beach.
	_quad_solid(rim, _at(first, 0.0), _at(last, 0.0), _at(last, WATER_Y - 0.025), _at(first, WATER_Y - 0.025), Vector3.LEFT, white)
	return _add_solid("BasinCoping", rim, material)


func _is_underwater_opening_edge(a: Vector2, b: Vector2) -> bool:
	if not underwater_east_opening:
		return false
	if not is_equal_approx(a.y, UNDERWATER_OPENING_LOCAL_Z) or not is_equal_approx(b.y, UNDERWATER_OPENING_LOCAL_Z):
		return false
	return is_equal_approx(minf(a.x, b.x), UNDERWATER_OPENING_MIN_X) \
		and is_equal_approx(maxf(a.x, b.x), UNDERWATER_OPENING_MAX_X)


func _row_depth(outline_index: int) -> float:
	var row := mini(outline_index, SECTIONS.size() * 2 - 1 - outline_index)
	return SECTIONS[row].w


func _edge_outward(a: Vector2, b: Vector2) -> Vector2:
	var edge := (b - a).normalized()
	return Vector2(edge.y, -edge.x)


func _corner_outward(outline: PackedVector2Array, i: int) -> Vector2:
	var point := outline[i]
	var previous := outline[posmod(i - 1, outline.size())]
	var next := outline[(i + 1) % outline.size()]
	var n1 := _edge_outward(previous, point)
	var n2 := _edge_outward(point, next)
	var sum := n1 + n2
	return sum / maxf(sum.dot(n2), 0.10)


func _build_approach() -> void:
	const APPROACH_X := -7.20
	const BAND_X := -0.52
	var band_y := lerpf(0.0, WATER_Y, inverse_lerp(APPROACH_X, 0.0, BAND_X))
	var mouth: Vector4 = SECTIONS[0]
	var porcelain := _make_matte(PALETTE.PORCELAIN)
	var mint := _make_matte(PALETTE.MINT)
	_add_approach_section("Approach", APPROACH_X, 0.0, BAND_X, band_y, mouth.y, mouth.z, porcelain)
	_add_approach_section("MintEntryBand", BAND_X, band_y, 0.0, WATER_Y, mouth.y, mouth.z, mint)


func _add_approach_section(section_name: String, x0: float, y0: float, x1: float, y1: float, left: float, right: float, material: Material) -> void:
	var slope := atan2(y1 - y0, x1 - x0)
	var vertical_normal := Vector3(-sin(slope), cos(slope), 0.0)
	var center := Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (left + right) * 0.5)
	var body := StaticBody3D.new()
	body.name = section_name
	body.position = center - vertical_normal * 0.08
	body.rotation.z = slope
	add_child(body)
	var size := Vector3(Vector2(x1 - x0, y1 - y0).length(), 0.16, right - left)
	var mesh := BoxMesh.new()
	mesh.size = size
	_add_mesh_and_collider(body, mesh, material)


func _close_dry_deck_gaps() -> void:
	# The deck has an opening at the basin's bounds. Fill its dry corners flush with the deck.
	var bounds := deck_opening_bounds()
	var dry_deck := SurfaceTool.new()
	dry_deck.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(SECTIONS.size() - 1):
		var a: Vector4 = SECTIONS[i]
		var b: Vector4 = SECTIONS[i + 1]
		_quad_solid(dry_deck, Vector3(a.x, 0.0, bounds.position.y), Vector3(b.x, 0.0, bounds.position.y),
			Vector3(b.x, 0.0, b.y), Vector3(a.x, 0.0, a.y), Vector3.UP, Color.WHITE)
		_quad_solid(dry_deck, Vector3(a.x, 0.0, a.z), Vector3(b.x, 0.0, b.z),
			Vector3(b.x, 0.0, bounds.end.y), Vector3(a.x, 0.0, bounds.end.y), Vector3.UP, Color.WHITE)
	var material := deck_material if deck_material != null else _make_matte(PALETTE.PORCELAIN)
	_add_solid("BasinDeckInfill", dry_deck, material)


func _at(point: Vector2, height: float) -> Vector3:
	return Vector3(point.x, height, point.y)


func _quad_solid(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, facing: Vector3, tint: Color) -> void:
	_quad(surface, [a, b, c, d], facing, [tint, tint, tint, tint])


func _quad(surface: SurfaceTool, points: Array[Vector3], facing: Vector3, colors: Array[Color]) -> void:
	for triangle in [[0, 1, 2], [0, 2, 3]]:
		var normal := (points[triangle[1]] - points[triangle[0]]).cross(points[triangle[2]] - points[triangle[0]])
		if normal.length_squared() <= 0.0000001:
			continue
		if normal.dot(facing) > 0.0:
			triangle.reverse() # Godot front faces have clockwise winding.
		for vertex_index: int in triangle:
			surface.set_color(colors[vertex_index])
			surface.add_vertex(points[vertex_index])


func _add_solid(body_name: String, surface: SurfaceTool, material: Material) -> MeshInstance3D:
	surface.generate_normals()
	surface.index()
	var body := StaticBody3D.new()
	body.name = body_name
	add_child(body)
	return _add_mesh_and_collider(body, surface.commit(), material)


func _add_mesh_and_collider(body: StaticBody3D, mesh: Mesh, material: Material) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	body.add_child(visual)
	var collider := CollisionShape3D.new()
	if mesh is BoxMesh:
		var shape := BoxShape3D.new()
		shape.size = (mesh as BoxMesh).size
		collider.shape = shape
	else:
		collider.shape = mesh.create_trimesh_shape()
	body.add_child(collider)
	return visual


func _make_matte(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	material.metallic_specular = 0.22
	return material
