@tool
extends Node3D

## A compact masonry tower with separated physical holds on all four sides.
## Corner turning is opt-in through `tower_corner_route` so ordinary climb walls
## keep their existing single-face behavior.

const BODY_HALF_EXTENT := 2.29
const OUTER_HALF_EXTENT := 2.40
const BODY_HEIGHT := 8.0
const ROOF_DECK_THICKNESS := 0.09
const WallClimbCapability := preload("res://features/runner/climbing/wall_climb_capability.gd")

const FIRST_HOLD_TOP := 0.78
const HOLD_THICKNESS := 0.14
const HOLD_DEPTH := 0.15
const HOLD_LENGTH := 0.76
const COURSE_RISES := [0.33, 0.82, 0.78, 0.33, 0.84, 0.80, 0.33, 0.86, 0.81, 0.33, 0.81]
const WINDOW_SILL_ROWS := [2, 4, 9]

var _built := false
var _climb_capability: WallClimbCapability


func _ready() -> void:
	_build_tower()


## Returns the tower's XZ corner selected by the current outward normal and the
## signed lateral direction. The returned point is at the tower's base height.
func get_corner_point(wall_normal: Vector3, lateral_direction: Vector3) -> Vector3:
	var local_normal := global_basis.inverse() * wall_normal
	var local_lateral := global_basis.inverse() * lateral_direction
	var local_corner := Vector3(
		1.0 if (local_normal.x if absf(local_normal.x) > 0.5 else local_lateral.x) >= 0.0 else -1.0,
		0.0,
		1.0 if (local_normal.z if absf(local_normal.z) > 0.5 else local_lateral.z) >= 0.0 else -1.0
	) * OUTER_HALF_EXTENT
	return to_global(local_corner)


## Route-specific climbing behavior is opt-in through the authored group. Removing
## `tower_corner_route` keeps this assembly on the ordinary single-face wall path.
func get_climb_capability() -> WallClimbCapability:
	if not is_in_group("tower_corner_route"):
		return null
	if _climb_capability == null:
		_climb_capability = WallClimbCapability.new()
		_climb_capability.corner_point_query = Callable(self, "get_corner_point")
		_climb_capability.summit_marker = get_node_or_null("LaunchMarker") as Marker3D
		_climb_capability.summit_group = &"tower_summit"
		_climb_capability.summit_height_tolerance = 0.42
		_climb_capability.roof_reach = 0.34
		var short_leap := WallClimbCapability.LeapProfile.new()
		short_leap.stride = 0.48
		short_leap.search_radius = 0.54
		short_leap.min_forward_up = 0.24
		short_leap.min_forward_down = 0.24
		short_leap.max_forward = 0.86
		short_leap.max_side_lateral = 0.24
		short_leap.max_side_cardinal = 0.24
		short_leap.short_side_hop = true
		_climb_capability.short_side_leap = short_leap
		_climb_capability.leap_profiles = [
			_make_leap_profile(0.66, 0.92),
			_make_leap_profile(0.88, 1.24),
			_make_leap_profile(1.20, 1.60),
		]
	return _climb_capability


func _make_leap_profile(stride: float, max_forward: float) -> WallClimbCapability.LeapProfile:
	var profile := WallClimbCapability.LeapProfile.new()
	profile.stride = stride
	profile.search_radius = 0.72
	profile.min_forward_up = 0.37
	profile.min_forward_down = 0.22
	profile.max_forward = max_forward
	profile.max_side_lateral = 0.24
	profile.max_side_cardinal = 0.70
	return profile


func _build_tower() -> void:
	if _built:
		return
	_built = true
	add_to_group("climbable_wall")
	add_to_group("tower_corner_route")

	var masonry := _material(Color(0.962, 0.932, 0.884), 0.82)
	var plinth_material := _material(Color(0.923, 0.872, 0.810), 0.80)
	var cap_materials: Array[StandardMaterial3D] = [
		_material(Color(0.43, 0.72, 0.64), 0.70),
		_material(Color(0.88, 0.59, 0.42), 0.70),
		_material(Color(0.84, 0.47, 0.49), 0.70),
		_material(Color(0.65, 0.55, 0.80), 0.70),
	]
	var window_trim := _material(Color(0.995, 0.968, 0.913), 0.68)
	var window_reveal := _material(Color(0.716, 0.612, 0.553), 0.72)
	var window_glass := _material(Color(0.48, 0.72, 0.73), 0.28)
	window_glass.metallic = 0.06
	window_glass.clearcoat = 0.32
	window_glass.clearcoat_roughness = 0.22

	var generated := Node3D.new()
	generated.name = "GeneratedMasonry"
	add_child(generated)

	# Low warm fill from the rooftop picks out window trim on the shaded faces.
	var rooftop_bounce := OmniLight3D.new()
	rooftop_bounce.name = "WarmRooftopBounce"
	rooftop_bounce.position = Vector3(4.5, 4.0, 4.5)
	rooftop_bounce.omni_range = 9.0
	rooftop_bounce.light_color = Color(1.0, 0.84, 0.73)
	rooftop_bounce.light_energy = 0.19
	rooftop_bounce.light_specular = 0.0
	generated.add_child(rooftop_bounce)

	# End the climbable core exactly at the underside of the summit deck. The
	# tagged deck is then the first collider seen by the vertical landing probe.
	var core_height := BODY_HEIGHT - ROOF_DECK_THICKNESS
	_add_box(generated, "MasonryCore", Vector3(0.0, core_height * 0.5, 0.0),
		Vector3(BODY_HALF_EXTENT * 2.0, core_height, BODY_HALF_EXTENT * 2.0), masonry, 0.08)

	# A warm, chamfered foot softens the transition into the rooftop. These are
	# visual-only details; the existing tower collision stays exactly in place.
	_add_visual(generated, "WarmBasePlinth", Vector3(0.0, 0.14, 0.0), Vector3(4.74, 0.28, 4.74), plinth_material, 0.07)
	_add_visual(generated, "MintBaseBand", Vector3(0.0, 0.295, 0.0), Vector3(4.82, 0.045, 4.82), cap_materials[0], 0.018)

	# Each course is built from separate collidable masonry pieces. Four shorter
	# rises alternate with seven deliberate leaps, so Up mixes reach-sized steps
	# with weighted jumps instead of climbing an unbroken rail.
	for side in 4:
		var normal := _side_normal(side)
		var tangent := Vector3.RIGHT if side % 2 == 0 else Vector3.BACK
		for row in 12:
			var top_y := _course_top(row)
			var course_shift := _course_shift(row)
			var has_window := row in WINDOW_SILL_ROWS
			var sill_shift := 0.12 if row == 2 or row == 9 else -0.12
			var accent := cap_materials[(row + side) % cap_materials.size()]
			var paired_corner_course := row == 0 or row == 6
			var corner_length := 0.70 if paired_corner_course else _corner_hold_length(row, side)
			var corner_center := 2.05 if paired_corner_course else 1.86
			# Paired corner bricks meet matching pieces on adjacent faces at rows 0
			# and 6. A separate mid-corner step bridges the intentional white gaps
			# from the inner hold into those corner blocks. Their inner ends sit
			# within one short hop of the approach brick.
			for end_sign in [-1.0, 1.0]:
				# Offset windows leave a wider gap on one side. Bring the far
				# brick toward its sill, allowing for the narrower brick variants.
				var sill_approach := 0.0
				if has_window and end_sign != signf(sill_shift):
					sill_approach = -end_sign * (0.40 + maxf(0.0, 0.76 - corner_length))
				var along: float = end_sign * corner_center + course_shift * 0.25 + sill_approach
				var end_top := top_y + _end_hold_offset(row, side, end_sign)
				var end_label := "Negative" if end_sign < 0.0 else "Positive"
				_add_hold(generated, "CornerHold_%02d_Side_%d_%s" % [row, side, end_label],
					normal, tangent, along, end_top, corner_length, HOLD_DEPTH, masonry, accent)
				if paired_corner_course:
					var approach_along: float = end_sign * 1.30
					_add_hold(generated, "CornerApproach_%02d_Side_%d_%s" % [row, side, end_label],
						normal, tangent, approach_along, top_y, 0.50, HOLD_DEPTH, masonry, accent)

			if has_window:
				_add_hold(generated, "WindowSill_%02d_Side_%d" % [row, side],
					normal, tangent, sill_shift, top_y, 1.45, 0.20, masonry, accent)
				_add_window(generated, side, row, normal, tangent, sill_shift, top_y,
					window_trim, window_reveal, window_glass)
			else:
				for inner_sign in [-1.0, 1.0]:
					var along: float = inner_sign * 0.50 + course_shift
					var inner_label := "Negative" if inner_sign < 0.0 else "Positive"
					_add_hold(generated, "LedgeHold_%02d_Side_%d_%s" % [row, side, inner_label],
						normal, tangent, along, top_y, 0.68, HOLD_DEPTH, masonry, accent)

	# A pale, walkable crown gives Chibi a clear landing surface for the top-out.
	var roof_deck := _add_box(generated, "RoofDeck", Vector3(0.0, BODY_HEIGHT - ROOF_DECK_THICKNESS * 0.5, 0.0),
		Vector3(4.80, ROOF_DECK_THICKNESS, 4.80), masonry, 0.035)
	roof_deck.add_to_group("tower_summit")
	_add_visual(generated, "RoofMintLip", Vector3(0.0, BODY_HEIGHT + 0.012, -1.82),
		Vector3(1.25, 0.025, 0.11), cap_materials[0], 0.006)

	var launch_marker := Marker3D.new()
	launch_marker.name = "LaunchMarker"
	launch_marker.position = Vector3(0.0, BODY_HEIGHT, -1.85)
	add_child(launch_marker)


func _course_shift(row: int) -> float:
	var shifts: Array[float] = [0.0, 0.12, -0.10, 0.18, -0.14, 0.14, 0.0, -0.16, 0.10, 0.0, -0.12, 0.08]
	return shifts[row]


func _course_top(row: int) -> float:
	var height := FIRST_HOLD_TOP
	for gap_index in row:
		height += COURSE_RISES[gap_index]
	return height


func _corner_hold_length(row: int, side: int) -> float:
	match posmod(row + side, 4):
		0:
			return 0.66
		2:
			return 0.84
		_:
			return HOLD_LENGTH


func _end_hold_offset(row: int, side: int, end_sign: float) -> float:
	if row == COURSE_RISES.size():
		return -0.07 # Leave a hand-sized opening below the roof overhang.
	if row == 0 or row == 6:
		return 0.0
	var end_index := 1 if end_sign > 0.0 else 0
	return 0.07 if posmod(row + side + end_index, 2) == 0 else -0.07


func _add_hold(
	parent: Node3D,
	label: String,
	normal: Vector3,
	tangent: Vector3,
	along: float,
	top_y: float,
	length: float,
	depth: float,
	masonry: StandardMaterial3D,
	accent: StandardMaterial3D
) -> void:
	var center := normal * (OUTER_HALF_EXTENT - depth * 0.5) + tangent * along
	center.y = top_y - HOLD_THICKNESS * 0.5
	var size := Vector3(length, HOLD_THICKNESS, depth) if absf(normal.z) > 0.5 else Vector3(depth, HOLD_THICKNESS, length)
	_add_box(parent, label, center, size, masonry)

	# One soft-edged tile wraps the top and upper lip of the white brick.
	# Its shadow would sit almost flush with the brick and flicker at a distance.
	var cap_depth := minf(0.11, depth - 0.025)
	var cap_height := 0.044
	var cap_size := Vector3(length - 0.045, cap_height, cap_depth) if absf(normal.z) > 0.5 else Vector3(cap_depth, cap_height, length - 0.045)
	var cap_center := normal * (OUTER_HALF_EXTENT - cap_depth * 0.5 + 0.010) + tangent * along
	cap_center.y = top_y - 0.015
	var cap := _add_visual(parent, "%s_PastelCap" % label, cap_center, cap_size, accent, 0.009)
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _add_window(
	parent: Node3D,
	side: int,
	row: int,
	normal: Vector3,
	tangent: Vector3,
	along: float,
	sill_top: float,
	trim: StandardMaterial3D,
	reveal: StandardMaterial3D,
	glass: StandardMaterial3D
) -> void:
	# The darker inset sits against the core. Smaller glass panes are raised just
	# enough to catch a soft highlight, with warm trim and two slim mullions over
	# them to make the window read as a recess from every face.
	var center := normal * (BODY_HALF_EXTENT + 0.020) + tangent * along + Vector3.UP * (sill_top + 0.36)
	var inset_size := Vector3(0.88, 0.62, 0.040) if absf(normal.z) > 0.5 else Vector3(0.040, 0.62, 0.88)
	_add_visual(parent, "WindowReveal_%d_%d" % [side, row], center, inset_size, reveal, 0.012)
	var glass_center := center + normal * 0.026
	var glass_size := Vector3(0.70, 0.43, 0.012) if absf(normal.z) > 0.5 else Vector3(0.012, 0.43, 0.70)
	_add_visual(parent, "WindowGlass_%d_%d" % [side, row], glass_center, glass_size, glass, 0.004)

	var frame_center := center + normal * 0.038
	var rail_width := 0.065
	var outer_width := 0.96
	var outer_height := 0.68
	var upright_size := Vector3(rail_width, outer_height, 0.034) if absf(normal.z) > 0.5 else Vector3(0.034, outer_height, rail_width)
	var upright_offset := (outer_width - rail_width) * 0.5
	for side_sign in [-1.0, 1.0]:
		_add_visual(parent, "WindowTrimSide_%d_%d_%d" % [side, row, int(side_sign)],
			frame_center + tangent * upright_offset * side_sign, upright_size, trim, 0.016)
	var rail_size := Vector3(outer_width, rail_width, 0.034) if absf(normal.z) > 0.5 else Vector3(0.034, rail_width, outer_width)
	var rail_offset := (outer_height - rail_width) * 0.5
	for vertical_sign in [-1.0, 1.0]:
		_add_visual(parent, "WindowTrimRail_%d_%d_%d" % [side, row, int(vertical_sign)],
			frame_center + Vector3.UP * rail_offset * vertical_sign, rail_size, trim, 0.016)

	var mullion_center := glass_center + normal * 0.008
	var vertical_mullion := Vector3(0.024, 0.43, 0.018) if absf(normal.z) > 0.5 else Vector3(0.018, 0.43, 0.024)
	var horizontal_mullion := Vector3(0.70, 0.022, 0.018) if absf(normal.z) > 0.5 else Vector3(0.018, 0.022, 0.70)
	_add_visual(parent, "WindowMullionV_%d_%d" % [side, row], mullion_center, vertical_mullion, trim, 0.004)
	_add_visual(parent, "WindowMullionH_%d_%d" % [side, row], mullion_center, horizontal_mullion, trim, 0.004)


func _side_normal(side: int) -> Vector3:
	match side:
		0:
			return Vector3.FORWARD
		1:
			return Vector3.RIGHT
		2:
			return Vector3.BACK
		_:
			return Vector3.LEFT


func _add_box(
	parent: Node3D,
	label: String,
	center: Vector3,
	size: Vector3,
	material: StandardMaterial3D,
	bevel: float = -1.0
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = center
	body.collision_layer = 1
	body.collision_mask = 1
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = shape
	body.add_child(collision)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Brick"
	mesh_instance.mesh = _beveled_box_mesh(size, _resolve_bevel(size, bevel))
	mesh_instance.material_override = material
	body.add_child(mesh_instance)
	parent.add_child(body)
	return body


func _add_visual(
	parent: Node3D,
	label: String,
	center: Vector3,
	size: Vector3,
	material: StandardMaterial3D,
	bevel: float = -1.0
) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.position = center
	visual.mesh = _beveled_box_mesh(size, _resolve_bevel(size, bevel))
	visual.material_override = material
	parent.add_child(visual)
	return visual


func _resolve_bevel(size: Vector3, requested: float) -> float:
	var shortest_axis := minf(size.x, minf(size.y, size.z))
	var bevel := requested if requested >= 0.0 else minf(0.024, shortest_axis * 0.22)
	return minf(bevel, shortest_axis * 0.48)


func _beveled_box_mesh(size: Vector3, bevel: float) -> Mesh:
	if bevel <= 0.0001:
		var box := BoxMesh.new()
		box.size = size
		return box
	var half := size * 0.5
	var inset := half - Vector3.ONE * minf(bevel, minf(half.x, minf(half.y, half.z)) * 0.48)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in 3:
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for sign_value: float in [-1.0, 1.0]:
			var face_normal := Vector3.ZERO
			face_normal[axis] = sign_value
			var face: Array[Vector3] = []
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var point := Vector3.ZERO
				point[axis] = sign_value * half[axis]
				point[u] = corner.x * inset[u]
				point[v] = corner.y * inset[v]
				face.append(point)
			_append_beveled_face(surface, face, face_normal)

		for u_sign: float in [-1.0, 1.0]:
			for v_sign: float in [-1.0, 1.0]:
				var a := Vector3.ZERO
				a[axis] = -inset[axis]
				a[u] = u_sign * half[u]
				a[v] = v_sign * inset[v]
				var b := a
				b[u] = u_sign * inset[u]
				b[v] = v_sign * half[v]
				var c := b
				c[axis] = inset[axis]
				var d := a
				d[axis] = inset[axis]
				var edge_normal := Vector3.ZERO
				edge_normal[u] = u_sign
				edge_normal[v] = v_sign
				_append_beveled_face(surface, [a, b, c, d], edge_normal)

	for x_sign: float in [-1.0, 1.0]:
		for y_sign: float in [-1.0, 1.0]:
			for z_sign: float in [-1.0, 1.0]:
				var corner_sign := Vector3(x_sign, y_sign, z_sign)
				var corner := inset * corner_sign
				var lengths := (half - inset) * corner_sign
				_append_beveled_face(surface, [
					corner + Vector3(lengths.x, 0.0, 0.0),
					corner + Vector3(0.0, lengths.y, 0.0),
					corner + Vector3(0.0, 0.0, lengths.z),
				], corner_sign)
	surface.index()
	return surface.commit()


func _append_beveled_face(surface: SurfaceTool, points: Array[Vector3], normal: Vector3) -> void:
	var outward := normal.normalized()
	if (points[1] - points[0]).cross(points[2] - points[0]).dot(outward) > 0.0:
		points.reverse()
	for index in range(1, points.size() - 1):
		for vertex in [points[0], points[index], points[index + 1]]:
			surface.set_normal(outward)
			surface.add_vertex(vertex)


func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.clearcoat = 0.08
	material.clearcoat_roughness = 0.62
	return material
