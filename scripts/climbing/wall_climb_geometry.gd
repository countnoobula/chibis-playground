extends RefCounted

## Ray based geometry queries for climbable static wall assemblies.
## A climbable assembly is a Node3D in the `climbable_wall` group. Its static
## collision bodies remain on World (layer 1), so unmarked geometry can occlude it.

const WORLD_MASK: int = 1
const FACE_MIN_ALIGNMENT: float = 0.72
const FACE_MAX_VERTICAL_NORMAL: float = 0.32
const CONTACT_SAMPLE_STEP: float = 0.105
const CONTACT_MAX_RADIUS: float = 0.72
const CONTACT_MAX_SAMPLES_PER_AXIS: int = 11
const FRONT_INSET: float = 0.025
const FACE_PROBE_DEPTH: float = 0.62
const TOP_SEARCH_ABOVE_FACE: float = 0.19
const TOP_SEARCH_BELOW_FACE: float = 0.07
const CONTACT_DEDUP_DISTANCE: float = 0.075
const CONTACT_WIDTH_MIN: float = 0.085


static func owns_collider(collider: Object) -> bool:
	return _find_climbable_root(collider as Node) != null


## Finds the first visible wall face in `direction`. World layer 1 is queried so
## an unmarked collider in front of a climbable assembly blocks the grab.
## `direction` points from the runner toward the wall.
static func find_face(runner: CharacterBody3D, direction: Vector3, reach: float) -> Dictionary:
	if runner == null or not is_instance_valid(runner) or not runner.is_inside_tree():
		return {}
	if reach <= 0.0:
		return {}
	return find_face_from(runner, _runner_center(runner), direction, reach)


## Queries a wall face from a chosen point. The tower corner route uses this to
## inspect the adjoining face before moving Chibi around the outside corner.
## `required_wall` can constrain the result to the same authored assembly.
static func find_face_from(runner: CharacterBody3D, origin: Vector3, direction: Vector3, reach: float, required_wall: Node3D = null) -> Dictionary:
	if runner == null or not is_instance_valid(runner) or not runner.is_inside_tree() or reach <= 0.0:
		return {}

	var heading := Vector3(direction.x, 0.0, direction.z)
	if heading.length_squared() < 0.0001:
		return {}
	heading = heading.normalized()
	var hit := _ray(runner, origin, origin + heading * reach)
	if hit.is_empty():
		return {}

	var wall := _find_climbable_root(hit.get("collider") as Node)
	if wall == null:
		return {}
	if required_wall != null and wall != required_wall:
		return {}
	var hit_normal: Vector3 = hit.get("normal", Vector3.ZERO)
	var horizontal_normal := Vector3(hit_normal.x, 0.0, hit_normal.z)
	if horizontal_normal.length_squared() < 0.0001 or absf(hit_normal.normalized().dot(Vector3.UP)) > FACE_MAX_VERTICAL_NORMAL:
		return {}
	horizontal_normal = horizontal_normal.normalized()
	# Reject glancing hits at corners and side faces; a valid face points back
	# toward the approach vector with a clear margin.
	if heading.dot(horizontal_normal) > -FACE_MIN_ALIGNMENT:
		return {}

	var collider := hit.get("collider") as StaticBody3D
	var right := Vector3.UP.cross(horizontal_normal).normalized()
	if right.length_squared() < 0.5:
		return {}
	return {
		"wall": wall,
		"point": hit.get("position", Vector3.ZERO),
		"normal": horizontal_normal,
		"right": right,
		"up": Vector3.UP,
		"collider": collider,
		"local_point": wall.to_local(hit.get("position", Vector3.ZERO)),
	}


## Finds actual upward support faces close to a requested grip target. Samples
## stay in the face frame, but ray depth is clipped around the detected face so
## protrusions and seams can vary in depth without wandering behind the wall.
## Results are deterministically sorted and deduplicated.
static func find_contacts(runner: CharacterBody3D, face: Dictionary, center: Vector3, radius: float) -> Array[Dictionary]:
	var contacts: Array[Dictionary] = []
	if runner == null or not is_instance_valid(runner) or not runner.is_inside_tree() or face.is_empty():
		return contacts
	var wall := face.get("wall") as Node3D
	if wall == null or not is_instance_valid(wall):
		return contacts
	var normal: Vector3 = face.get("normal", Vector3.ZERO)
	normal.y = 0.0
	if normal.length_squared() < 0.0001:
		return contacts
	normal = normal.normalized()
	var right: Vector3 = face.get("right", Vector3.UP.cross(normal))
	right.y = 0.0
	if right.length_squared() < 0.0001:
		right = Vector3.UP.cross(normal)
	right = right.normalized()
	var face_point: Vector3 = face.get("point", center)
	var sample_radius := clampf(absf(radius), 0.08, CONTACT_MAX_RADIUS)
	var sample_offsets := _sample_offsets(sample_radius)
	var center_depth := clampf((center - face_point).dot(normal), -0.18, 0.38)
	var scan_center := center - normal * ((center - face_point).dot(normal) - center_depth)
	var min_support_y := center.y - sample_radius - 0.035
	var max_support_y := center.y + sample_radius + 0.035

	var candidates: Array[Dictionary] = []
	for x_index in sample_offsets.size():
		var lateral: float = sample_offsets[x_index]
		for y_index in sample_offsets.size():
			var vertical: float = sample_offsets[y_index]
			var origin := scan_center + right * lateral + Vector3.UP * vertical + normal * FACE_PROBE_DEPTH
			var face_hit := _ray(runner, origin, origin - normal * (FACE_PROBE_DEPTH * 2.0 + 0.08))
			if face_hit.is_empty():
				continue
			var face_hit_collider := face_hit.get("collider") as Node
			if _find_climbable_root(face_hit_collider) != wall:
				continue
			var front_normal: Vector3 = face_hit.get("normal", Vector3.ZERO)
			if absf(front_normal.normalized().dot(Vector3.UP)) > FACE_MAX_VERTICAL_NORMAL:
				continue
			front_normal.y = 0.0
			if front_normal.length_squared() < 0.0001:
				continue
			front_normal = front_normal.normalized()
			if absf(front_normal.dot(normal)) < 0.72 or absf(front_normal.y) > FACE_MAX_VERTICAL_NORMAL:
				continue
			# Samples are close to the desired grip height. A downward column at
			# the front inset discovers the actual top cap/lip, not the broad wall.
			var front_edge: Vector3 = face_hit.get("position", Vector3.ZERO) - front_normal * FRONT_INSET
			# Search only close above this particular vertical sample. This finds
			# each tier independently instead of letting an upper lip hide lower ones.
			var support_from_y := minf(max_support_y + 0.08, face_hit["position"].y + TOP_SEARCH_ABOVE_FACE)
			var support_to_y := maxf(min_support_y - 0.08, face_hit["position"].y - TOP_SEARCH_BELOW_FACE)
			if support_from_y <= support_to_y:
				continue
			var support_from := Vector3(front_edge.x, support_from_y, front_edge.z)
			var support_to := Vector3(front_edge.x, support_to_y, front_edge.z)
			var support_hit := _ray(runner, support_from, support_to)
			if support_hit.is_empty():
				continue
			var support_collider := support_hit.get("collider") as StaticBody3D
			if support_collider == null or _find_climbable_root(support_collider) != wall:
				continue
			var top_normal: Vector3 = support_hit.get("normal", Vector3.ZERO).normalized()
			if top_normal.dot(Vector3.UP) < 0.84:
				continue
			var support_point: Vector3 = support_hit.get("position", Vector3.ZERO)
			if support_point.y < min_support_y or support_point.y > max_support_y:
				continue
			# Confirm the lip has a front face directly below the support and an
			# open approach above it. This filters top-like hits on backsides,
			# narrow corners, and distant top caps reached only by a long scan.
			if not _has_open_lip_approach(runner, wall, support_point, front_normal):
				continue
			var face_edge_hit := _ray(
				runner,
				support_point + front_normal * 0.20 - Vector3.UP * 0.035,
				support_point - front_normal * 0.035 - Vector3.UP * 0.035
			)
			if face_edge_hit.is_empty() or _find_climbable_root(face_edge_hit.get("collider") as Node) != wall:
				continue
			var edge_normal: Vector3 = face_edge_hit.get("normal", Vector3.ZERO)
			edge_normal.y = 0.0
			if edge_normal.length_squared() < 0.0001 or edge_normal.normalized().dot(front_normal) < 0.70:
				continue
			var local_point := wall.to_local(support_point)
			candidates.append({
				"point": support_point,
				"normal": front_normal,
				"top_normal": top_normal,
				"collider": support_collider,
				"wall": wall,
				"local_point": local_point,
				"collider_local_point": support_collider.to_local(support_point),
				"depth": (support_point - face_point).dot(normal),
				"sample_x": x_index,
				"sample_y": y_index,
			})

	if candidates.is_empty():
		return contacts
	# Require a neighboring contact across at least a hand-sized width. Adjacent
	# samples may sit on separate box colliders, which is expected at seams.
	for candidate in candidates:
		var has_width := false
		for neighbor in candidates:
			if neighbor == candidate:
				continue
			var delta: Vector3 = neighbor["point"] - candidate["point"]
			var side_distance := absf(delta.dot(right))
			var vertical_distance := absf(delta.y)
			var depth_distance := absf(delta.dot(normal))
			if side_distance >= CONTACT_WIDTH_MIN and side_distance <= 0.24 and vertical_distance <= 0.12 and depth_distance <= 0.15:
				has_width = true
				break
		if has_width:
			var duplicate := false
			for existing in contacts:
				if existing["point"].distance_to(candidate["point"]) < CONTACT_DEDUP_DISTANCE:
					duplicate = true
					break
			if not duplicate:
				contacts.append(candidate)

	contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_side: float = (a["point"] as Vector3).dot(right)
		var b_side: float = (b["point"] as Vector3).dot(right)
		if not is_equal_approx(a_side, b_side):
			return a_side < b_side
		if not is_equal_approx(a["point"].y, b["point"].y):
			return a["point"].y < b["point"].y
		return a["depth"] < b["depth"]
	)
	return contacts


static func _has_open_lip_approach(runner: CharacterBody3D, wall: Node3D, support_point: Vector3, normal: Vector3) -> bool:
	# A short vertical probe above the support must be clear. The support ray
	# itself established the top; this detects shelves/ceilings right above it.
	var clear_from := support_point + Vector3.UP * 0.16
	var clear_to := support_point + Vector3.UP * 0.045
	var overhead := _ray(runner, clear_from, clear_to)
	if not overhead.is_empty():
		return false
	# Retread toward the lip at just below its top. The nearest surface must be
	# the same assembly, on the same outward-facing side.
	var approach_from := support_point + normal * 0.24 - Vector3.UP * 0.035
	var approach_to := support_point - normal * 0.04 - Vector3.UP * 0.035
	var approach := _ray(runner, approach_from, approach_to)
	if approach.is_empty() or _find_climbable_root(approach.get("collider") as Node) != wall:
		return false
	var approach_normal: Vector3 = approach.get("normal", Vector3.ZERO)
	approach_normal.y = 0.0
	return approach_normal.length_squared() > 0.0001 and approach_normal.normalized().dot(normal) >= 0.70


static func _sample_offsets(radius: float) -> Array[float]:
	var count := clampi(int(ceil((radius * 2.0) / CONTACT_SAMPLE_STEP)) + 1, 3, CONTACT_MAX_SAMPLES_PER_AXIS)
	if count % 2 == 0:
		count = mini(count + 1, CONTACT_MAX_SAMPLES_PER_AXIS)
	var offsets: Array[float] = []
	for i in count:
		offsets.append(lerpf(-radius, radius, float(i) / float(count - 1)))
	return offsets


static func _runner_center(runner: CharacterBody3D) -> Vector3:
	if runner.has_method("get_capsule_center"):
		return runner.call("get_capsule_center") as Vector3
	return runner.global_position + Vector3.UP * 0.60


static func _find_climbable_root(node: Node) -> Node3D:
	var current := node
	while current != null:
		if current is Node3D and current.is_in_group("climbable_wall"):
			return current as Node3D
		current = current.get_parent()
	return null


static func _ray(runner: CharacterBody3D, from: Vector3, to: Vector3) -> Dictionary:
	var world := runner.get_world_3d()
	if world == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK, [runner.get_rid()])
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return world.direct_space_state.intersect_ray(query)
