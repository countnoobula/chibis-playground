extends Node3D
class_name WaterBody3D

## Reusable, local-XZ polygon water volume. Public point arguments are in world space.
const WATER_GROUP: StringName = &"water_bodies"
const MAX_SHADER_OUTLINE_POINTS: int = 32
const DEFAULT_PROFILE: WaterProfile = preload("res://assets/water/default_water_profile.tres")
const WATER_SURFACE_SHADER: Shader = preload("res://shaders/water/water_surface.gdshader")
const RIPPLE_SHADER: Shader = preload("res://shaders/water/water_ripple.gdshader")
const BUBBLE_SHADER: Shader = preload("res://shaders/water/water_bubble.gdshader")
const CAUSTIC_RECEIVER_SHADER: Shader = preload("res://shaders/water/water_caustic_receiver.gdshader")
const CAUSTIC_RECEIVER_INCLUDE: String = "res://shaders/water/water_caustics.gdshaderinc"
const TILE_SHADER_PATH: String = "res://shaders/pool_tile.gdshader"

## Simple shoreline polygon in local XZ, with 3–32 points. Keep the surface level.
@export var outline: PackedVector2Array = PackedVector2Array([
	Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0)
])
@export_range(0.01, 50.0, 0.01, "or_greater") var max_depth: float = 1.2
## Vertical space below the nominal surface that is blocked by a sealed ceiling.
## The volume still uses the same surface reference for depth and caustics, but
## point selection is capped at this offset and no surface plane is rendered.
@export_range(0.0, 20.0, 0.01, "or_greater") var ceiling_below_surface: float = 0.0
@export var profile: WaterProfile
@export var selection_priority: int = 0

static var _next_registration_serial: int = 1

var _registration_serial: int = 0
var _is_registered: bool = false
var _surface: MeshInstance3D
var _surface_material: ShaderMaterial
var _outline_snapshot: PackedVector2Array = PackedVector2Array()
var _last_transform: Transform3D
var _depth_snapshot: float = -1.0
var _ceiling_snapshot: float = -1.0
var _ripple_mesh: ArrayMesh
var _receiver_refs: Array[WeakRef] = []
var _ripple_effects: Array[Dictionary] = []
var _bubble_effects: Array[Dictionary] = []
var _bubble_mesh: SphereMesh
var _bubble_material: ShaderMaterial


func _ready() -> void:
	_surface = get_node_or_null("Surface") as MeshInstance3D
	if _surface == null:
		_surface = MeshInstance3D.new()
		_surface.name = "Surface"
		add_child(_surface)
	_initialize_surface_material()
	_rebuild_surface()
	_register_if_valid()
	_last_transform = global_transform
	_depth_snapshot = max_depth
	_ceiling_snapshot = ceiling_below_surface
	_sync_surface_visibility()
	set_process(true)


func _exit_tree() -> void:
	if _is_registered:
		remove_from_group(WATER_GROUP)
		_is_registered = false
	for effect in _ripple_effects:
		var node: Node = effect.get("node")
		if is_instance_valid(node):
			node.queue_free()
	for effect in _bubble_effects:
		var node: Node = effect.get("node")
		if is_instance_valid(node):
			node.queue_free()


func _process(delta: float) -> void:
	var depth_changed := not is_equal_approx(max_depth, _depth_snapshot)
	var ceiling_changed := not is_equal_approx(ceiling_below_surface, _ceiling_snapshot)
	if outline != _outline_snapshot or depth_changed or ceiling_changed:
		_rebuild_surface()
		_register_if_valid()
		_depth_snapshot = max_depth
		_ceiling_snapshot = ceiling_below_surface
		_sync_surface_visibility()
		_update_receiver_uniforms()
	if global_transform != _last_transform:
		_last_transform = global_transform
		_update_receiver_uniforms()
	_update_effects(delta)


## Returns the world-space Y of the local y=0 water plane.
func get_surface_height() -> float:
	return to_global(Vector3.ZERO).y


## Returns the highest world-space Y included in this water volume.
func get_volume_ceiling_height() -> float:
	return get_surface_height() - ceiling_below_surface * absf(global_transform.basis.y.y)


## Tests whether a world-space point lies inside the local-XZ outline.
func contains_horizontal(point: Vector3) -> bool:
	if outline.size() < 3:
		return false
	var local_point := to_local(point)
	var p := Vector2(local_point.x, local_point.z)
	if Geometry2D.is_point_in_polygon(p, outline):
		return true
	# Treat points on the polygon boundary as inside for stable edge detection.
	for i in range(outline.size()):
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) <= 0.0001:
			return true
	return false


## Starts a small expanding surface ring at a world-space point. Diameter is in world units.
func emit_ripple(point: Vector3, diameter: float) -> void:
	if ceiling_below_surface > 0.0 or diameter <= 0.01 or not is_inside_tree() or not contains_horizontal(point):
		return
	var local := to_local(point)
	local.y = 0.018
	var node := MeshInstance3D.new()
	node.name = "Ripple"
	node.mesh = _get_ring_mesh()
	var material := ShaderMaterial.new()
	material.shader = RIPPLE_SHADER
	material.set_shader_parameter("ripple_color", get_profile().ripple_color)
	material.set_shader_parameter("ring_alpha", 1.0)
	node.material_override = material
	node.position = local
	add_child(node)
	if _ripple_effects.size() >= 12:
		var oldest: Dictionary = _ripple_effects.pop_front()
		var old_node: Node = oldest.get("node")
		if is_instance_valid(old_node):
			old_node.queue_free()
	_ripple_effects.append({"node": node, "material": material, "age": 0.0, "diameter": diameter})


## Emits a short cluster and returns whether the source is underwater.
func emit_bubble(point: Vector3) -> bool:
	if not is_inside_tree() or not contains_horizontal(point):
		return false
	var local := to_local(point)
	if local.y >= -ceiling_below_surface - 0.025:
		return false
	var settings := get_profile()
	for i in range(3):
		if _bubble_effects.size() >= 36:
			var oldest: Dictionary = _bubble_effects.pop_front()
			var old_node: Node = oldest.get("node")
			if is_instance_valid(old_node):
				old_node.queue_free()
		var phase := float(_bubble_effects.size()) * 2.399963
		var node := MeshInstance3D.new()
		node.name = "Bubble"
		node.mesh = _get_bubble_mesh()
		var material := _get_bubble_material().duplicate(true) as ShaderMaterial
		material.set_shader_parameter("bubble_color", settings.bubble_color)
		material.set_shader_parameter("bubble_opacity", 0.0)
		node.material_override = material
		node.position = local
		node.scale = Vector3.ONE * (0.045 + 0.02 * float(i))
		add_child(node)
		_bubble_effects.append({
			"node": node,
			"material": material,
			"age": 0.0,
			"origin": node.position,
			"phase": phase,
			"speed": settings.bubble_rise_speed * (0.88 + 0.12 * float(i)),
			"size": 0.045 + 0.02 * float(i),
		})
	return true


## Adds this volume's clipping and caustic settings to a compatible opaque receiver.
## Supports res://shaders/pool_tile.gdshader, the generic water receiver shader,
## and StandardMaterial3D (converted while preserving its base color and texture).
func configure_caustic_receiver(mesh: MeshInstance3D) -> void:
	if not is_instance_valid(mesh):
		return
	var source: Material = mesh.material_override
	if source == null and mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
		source = mesh.get_surface_override_material(0)
		if source == null:
			source = mesh.mesh.surface_get_material(0)
	var receiver: ShaderMaterial
	if source is ShaderMaterial:
		var source_shader: Shader = (source as ShaderMaterial).shader
		var source_path := source_shader.resource_path if source_shader != null else ""
		if source_path == TILE_SHADER_PATH or source_path.ends_with("/water_caustic_receiver.gdshader"):
			receiver = (source as ShaderMaterial).duplicate(true) as ShaderMaterial
		else:
			push_warning("WaterBody3D can configure caustics only on pool_tile.gdshader or water_caustic_receiver.gdshader ShaderMaterials.")
			return
	elif source is StandardMaterial3D:
		receiver = ShaderMaterial.new()
		receiver.shader = CAUSTIC_RECEIVER_SHADER
		var standard := source as StandardMaterial3D
		receiver.set_shader_parameter("base_color", standard.albedo_color)
		if standard.albedo_texture != null:
			receiver.set_shader_parameter("base_texture", standard.albedo_texture)
		receiver.set_shader_parameter("has_base_texture", standard.albedo_texture != null)
		receiver.set_shader_parameter("use_vertex_color", standard.vertex_color_use_as_albedo)
		receiver.set_shader_parameter("roughness", standard.roughness)
		receiver.set_shader_parameter("metallic", standard.metallic)
	else:
		# A mesh with no explicit material uses the same receiver shader and vertex colors.
		receiver = ShaderMaterial.new()
		receiver.shader = CAUSTIC_RECEIVER_SHADER
	mesh.material_override = receiver
	_apply_caustic_parameters(receiver)
	_remember_receiver(mesh)


static func find_at(anchor: Node3D, point: Vector3, previous: WaterBody3D = null, upper_tolerance: float = 0.0) -> WaterBody3D:
	if not is_instance_valid(anchor) or not anchor.is_inside_tree():
		return null
	var target_world: World3D = anchor.get_world_3d()
	if target_world == null:
		return null
	var tree := anchor.get_tree()
	var best: WaterBody3D
	for node in tree.get_nodes_in_group(WATER_GROUP):
		if not node is WaterBody3D:
			continue
		var body := node as WaterBody3D
		if not body._is_registered or body.max_depth <= 0.0 or not body.is_inside_tree():
			continue
		if body.get_world_3d() != target_world or not body.contains_horizontal(point):
			continue
		var ceiling_y := body.get_volume_ceiling_height()
		# Preserve the old exposed-water camera tolerance, while never allowing it
		# to extend a roofed volume through its physical ceiling.
		var allowed_above_ceiling := maxf(upper_tolerance, 0.0) if body.ceiling_below_surface <= 0.0 else 0.0
		if point.y > ceiling_y + allowed_above_ceiling:
			continue
		var surface_y := body.get_surface_height()
		var vertical_scale := absf(body.global_transform.basis.y.y)
		var floor_y := surface_y - body.max_depth * vertical_scale
		if point.y < floor_y - 0.02:
			continue
		if best == null or _is_better_candidate(body, best, previous):
			best = body
	return best


static func _is_better_candidate(candidate: WaterBody3D, current: WaterBody3D, previous: WaterBody3D) -> bool:
	if candidate.selection_priority != current.selection_priority:
		return candidate.selection_priority > current.selection_priority
	if candidate == previous and current != previous:
		return true
	if current == previous and candidate != previous:
		return false
	var candidate_surface := candidate.get_surface_height()
	var current_surface := current.get_surface_height()
	if not is_equal_approx(candidate_surface, current_surface):
		return candidate_surface > current_surface
	return candidate._registration_serial > current._registration_serial


func _register_if_valid() -> void:
	if not is_inside_tree():
		return
	if _has_valid_outline():
		if not _is_registered:
			add_to_group(WATER_GROUP)
			_registration_serial = _next_registration_serial
			_next_registration_serial += 1
			_is_registered = true
	elif _is_registered:
		remove_from_group(WATER_GROUP)
		_is_registered = false


func _has_valid_outline() -> bool:
	return max_depth > 0.0 and outline.size() >= 3 and outline.size() <= MAX_SHADER_OUTLINE_POINTS \
		and Geometry2D.triangulate_polygon(outline).size() >= 3 and absf(_polygon_area(outline)) > 0.0001


func _polygon_area(points: PackedVector2Array) -> float:
	var area := 0.0
	for i in range(points.size()):
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		area += a.x * b.y - b.x * a.y
	return area * 0.5


func _initialize_surface_material() -> void:
	var existing := _surface.material_override as ShaderMaterial
	if existing != null and existing.shader == WATER_SURFACE_SHADER:
		_surface_material = existing.duplicate(true) as ShaderMaterial
	else:
		_surface_material = ShaderMaterial.new()
		_surface_material.shader = WATER_SURFACE_SHADER
	_surface.material_override = _surface_material
	_apply_surface_profile()


func _apply_surface_profile() -> void:
	if _surface_material == null:
		return
	var settings := get_profile()
	_surface_material.set_shader_parameter("shallow_color", settings.shallow_color)
	_surface_material.set_shader_parameter("deep_color", settings.deep_color)
	_surface_material.set_shader_parameter("foam_color", settings.foam_color)
	_surface_material.set_shader_parameter("surface_opacity", settings.surface_opacity)
	_surface_material.set_shader_parameter("wave_height", settings.wave_height)
	_surface_material.set_shader_parameter("refraction_strength", settings.refraction_strength)
	_surface_material.set_shader_parameter("shoreline_width", settings.shoreline_width)
	_surface_material.set_shader_parameter("water_depth", max_depth)
	_apply_caustic_parameters(_surface_material)


func _rebuild_surface() -> void:
	_outline_snapshot = outline.duplicate()
	if _surface == null:
		return
	if not _has_valid_outline():
		_surface.mesh = null
		return
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for point in outline:
		vertices.append(Vector3(point.x, 0.0, point.y))
		normals.append(Vector3.UP)
		uvs.append(Vector2(point.x, point.y))
	var triangulated := Geometry2D.triangulate_polygon(outline)
	var indices := PackedInt32Array()
	for i in range(0, triangulated.size(), 3):
		var a := triangulated[i]
		var b := triangulated[i + 1]
		var c := triangulated[i + 2]
		var normal := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
		if normal.y > 0.0:
			var swap := b
			b = c
			c = swap
		indices.append(a)
		indices.append(b)
		indices.append(c)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_surface.mesh = mesh
	_sync_surface_visibility()
	_apply_surface_profile()


func _sync_surface_visibility() -> void:
	if _surface != null:
		_surface.visible = ceiling_below_surface <= 0.0


func get_profile() -> WaterProfile:
	return profile if profile != null else DEFAULT_PROFILE


func _remember_receiver(mesh: MeshInstance3D) -> void:
	for existing_ref in _receiver_refs:
		if existing_ref.get_ref() == mesh:
			return
	_receiver_refs.append(weakref(mesh))


func _update_receiver_uniforms() -> void:
	var retained: Array[WeakRef] = []
	for receiver_ref in _receiver_refs:
		var mesh := receiver_ref.get_ref() as MeshInstance3D
		if is_instance_valid(mesh):
			var material := mesh.material_override as ShaderMaterial
			if material != null:
				_apply_caustic_parameters(material)
			retained.append(receiver_ref)
	_receiver_refs = retained
	if _surface_material != null:
		_apply_surface_profile()


func _apply_caustic_parameters(material: ShaderMaterial) -> void:
	var settings := get_profile()
	var point_count := mini(outline.size(), MAX_SHADER_OUTLINE_POINTS)
	var world_outline := PackedVector2Array()
	world_outline.resize(MAX_SHADER_OUTLINE_POINTS)
	for i in range(point_count):
		var local_point := outline[i]
		var world_point := global_transform * Vector3(local_point.x, 0.0, local_point.y)
		world_outline[i] = Vector2(world_point.x, world_point.z)
	material.set_shader_parameter("water_outline_points", world_outline)
	material.set_shader_parameter("water_outline_count", point_count)
	material.set_shader_parameter("water_plane_y", get_volume_ceiling_height())
	material.set_shader_parameter("water_depth", maxf(max_depth - ceiling_below_surface, 0.01) * absf(global_transform.basis.y.y))
	material.set_shader_parameter("water_caustic_color", settings.caustic_color)
	material.set_shader_parameter("water_caustic_strength", settings.caustic_strength)
	material.set_shader_parameter("water_caustic_scale", settings.caustic_scale)
	material.set_shader_parameter("water_caustic_speed", settings.caustic_speed)
	material.set_shader_parameter("water_caustic_shore_fade", settings.caustic_shore_fade)


func _get_ring_mesh() -> ArrayMesh:
	if _ripple_mesh == null:
		_ripple_mesh = _make_ring_mesh()
	return _ripple_mesh


func _make_ring_mesh() -> ArrayMesh:
	const SEGMENTS := 48
	const INNER_RADIUS := 0.965
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in range(SEGMENTS):
		var angle := TAU * float(i) / float(SEGMENTS)
		var direction := Vector2(cos(angle), sin(angle))
		vertices.append(Vector3(direction.x, 0.0, direction.y))
		vertices.append(Vector3(direction.x * INNER_RADIUS, 0.0, direction.y * INNER_RADIUS))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		uvs.append(Vector2(direction.x * 0.5 + 0.5, direction.y * 0.5 + 0.5))
		uvs.append(Vector2(direction.x * INNER_RADIUS * 0.5 + 0.5, direction.y * INNER_RADIUS * 0.5 + 0.5))
	for i in range(SEGMENTS):
		var a := i * 2
		var b := ((i + 1) % SEGMENTS) * 2
		indices.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var ring := ArrayMesh.new()
	ring.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return ring


func _get_bubble_mesh() -> SphereMesh:
	if _bubble_mesh == null:
		_bubble_mesh = SphereMesh.new()
		_bubble_mesh.radius = 0.5
		_bubble_mesh.height = 1.0
		_bubble_mesh.radial_segments = 8
		_bubble_mesh.rings = 4
	return _bubble_mesh


func _get_bubble_material() -> ShaderMaterial:
	if _bubble_material == null:
		_bubble_material = ShaderMaterial.new()
		_bubble_material.shader = BUBBLE_SHADER
	return _bubble_material


func _update_effects(delta: float) -> void:
	var ripple_kept: Array[Dictionary] = []
	for effect in _ripple_effects:
		var node := effect.get("node") as MeshInstance3D
		if not is_instance_valid(node):
			continue
		var age := float(effect.get("age", 0.0)) + delta
		var lifetime := 0.95
		if age >= lifetime:
			node.queue_free()
			continue
		var progress := age / lifetime
		var radius := float(effect.get("diameter", 1.0)) * 0.5 * (0.16 + 0.84 * progress)
		node.scale = Vector3(radius, 1.0, radius)
		var material := effect.get("material") as ShaderMaterial
		if material != null:
			material.set_shader_parameter("ring_alpha", 1.0 - progress)
		effect["age"] = age
		ripple_kept.append(effect)
	_ripple_effects = ripple_kept
	var bubble_kept: Array[Dictionary] = []
	for effect in _bubble_effects:
		var node := effect.get("node") as MeshInstance3D
		if not is_instance_valid(node):
			continue
		var age := float(effect.get("age", 0.0)) + delta
		var lifetime := 1.65
		var material := effect.get("material") as ShaderMaterial

		var progress := clampf(age / lifetime, 0.0, 1.0)
		var origin: Vector3 = effect.get("origin", Vector3.ZERO)
		var phase := float(effect.get("phase", 0.0))
		var speed := float(effect.get("speed", 1.0))
		var spread := smoothstep(0.0, 0.24, age)
		node.position = origin + Vector3(sin(phase + age * 2.1) * 0.055 * spread,
			age * speed, cos(phase + age * 1.8) * 0.045 * spread)
		var bubble_top := -ceiling_below_surface
		if age >= lifetime or node.position.y >= bubble_top - 0.012:
			node.queue_free()
			continue
		var pop := 1.0 - smoothstep(0.78, 1.0, progress)
		node.scale = Vector3.ONE * float(effect.get("size", 0.05)) * (1.0 + 0.25 * sin(age * 5.0)) * pop
		if material != null:
			material.set_shader_parameter("bubble_opacity", (1.0 - progress) * pop * smoothstep(0.015, 0.10, -node.position.y))
		effect["age"] = age
		bubble_kept.append(effect)
	_bubble_effects = bubble_kept





