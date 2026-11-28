class_name FirstStepsAmbientBreeze
extends Node

## Valley-only ambient motion. Foliage keeps its authored shader amplitude and
## fixed roots; the runner receives a small post-spring pose offset only.

const FOLIAGE_SHADER: Shader = preload("res://assets/environment/woodland/foliage.gdshader")
const WIND_ANGULAR_SPEED := 1.122
const BREEZE_MODIFIER_SCRIPT := preload("res://levels/first_steps/ambient_breeze_modifier.gd")

@export var runner_path: NodePath = NodePath("../ChibiRunner")
@export var foliage_root_path: NodePath = NodePath("../Dressing")
@export_range(0.0, 1.0, 0.01) var breeze_strength: float:
	get:
		return _breeze_strength
	set(value):
		_breeze_strength = clampf(value, 0.0, 1.0)
		_apply_foliage_strength()

@export var breeze_enabled: bool:
	get:
		return _breeze_enabled
	set(value):
		_breeze_enabled = value
		_apply_foliage_strength()

var _breeze_strength := 0.72
var _breeze_enabled := true
var _breeze_phase := 0.0
var _runner: ParkourController
var _modifier: FirstStepsAmbientBreezeModifier
var _foliage_materials: Array[Dictionary] = []
var _foliage_materials_by_source: Dictionary = {}


func _ready() -> void:
	var foliage_root := get_node_or_null(foliage_root_path)
	if foliage_root == null:
		push_error("First Steps ambient breeze could not find its Dressing root.")
	else:
		_bind_foliage_materials(foliage_root)
	_apply_foliage_strength()

	_runner = get_node_or_null(runner_path) as ParkourController
	if _runner == null:
		push_error("First Steps ambient breeze could not find ChibiRunner.")
		return
	call_deferred("_attach_character_modifier")


func _attach_character_modifier() -> void:
	if not is_instance_valid(_runner):
		return
	var skeleton := _find_skeleton(_runner)
	if skeleton == null:
		push_error("First Steps ambient breeze could not find Chibi's Skeleton3D.")
		return
	_modifier = BREEZE_MODIFIER_SCRIPT.new() as FirstStepsAmbientBreezeModifier
	_modifier.name = "AmbientBreezeModifier"
	_modifier.configure(self, _runner)
	skeleton.add_child(_modifier)


func _process(delta: float) -> void:
	_breeze_phase = fposmod(_breeze_phase + maxf(delta, 0.0) * WIND_ANGULAR_SPEED, TAU)


func _input(event: InputEvent) -> void:
	if not OS.is_debug_build() or get_tree().paused or not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if key_event.pressed and not key_event.echo and key_event.physical_keycode == KEY_B:
		set_breeze_enabled(not _breeze_enabled)
		get_viewport().set_input_as_handled()


## Toggle both the valley foliage and the additive scarf/ahoge response.
## Foliage changes immediately; character motion fades over a short response.
func set_breeze_enabled(value: bool) -> void:
	breeze_enabled = value


func is_breeze_enabled() -> bool:
	return _breeze_enabled


func get_effective_strength() -> float:
	return _breeze_strength if _breeze_enabled else 0.0


func get_foliage_material_count() -> int:
	return _foliage_materials.size()


func get_breeze_phase() -> float:
	return _breeze_phase


## Same slow two-axis wave used by foliage.gdshader, expressed in world XZ.
func get_breeze_vector_world() -> Vector3:
	return Vector3(
		sin(_breeze_phase),
		0.0,
		0.62 * sin(_breeze_phase + 1.1)
	)


func _bind_foliage_materials(root: Node) -> void:
	if root is MeshInstance3D:
		_bind_mesh_foliage(root as MeshInstance3D)
	for child in root.get_children():
		_bind_foliage_materials(child)


func _bind_mesh_foliage(mesh_instance: MeshInstance3D) -> void:
	if mesh_instance.mesh == null:
		return
	if mesh_instance.material_override != null:
		var override_clone := _get_foliage_clone(mesh_instance.material_override)
		if override_clone != null:
			mesh_instance.material_override = override_clone
		return

	for surface in mesh_instance.mesh.get_surface_count():
		var source := mesh_instance.get_surface_override_material(surface)
		if source == null:
			source = mesh_instance.mesh.surface_get_material(surface)
		var clone := _get_foliage_clone(source)
		if clone != null:
			mesh_instance.set_surface_override_material(surface, clone)


func _get_foliage_clone(source: Material) -> ShaderMaterial:
	if not source is ShaderMaterial:
		return null
	var source_material := source as ShaderMaterial
	if source_material.shader != FOLIAGE_SHADER:
		return null
	var source_id := source_material.get_instance_id()
	if _foliage_materials_by_source.has(source_id):
		return _foliage_materials_by_source[source_id] as ShaderMaterial
	var clone := source_material.duplicate(true) as ShaderMaterial
	if clone == null:
		return null
	clone.resource_name = "%s Ambient Breeze" % source_material.resource_name
	var material_entry := {
		"material": clone,
		"base_amplitude": float(source_material.get_shader_parameter("wind_amplitude")),
	}
	_foliage_materials.append(material_entry)
	_foliage_materials_by_source[source_id] = clone
	return clone


func _apply_foliage_strength() -> void:
	var effective_strength := get_effective_strength()
	for material_entry in _foliage_materials:
		var material := material_entry["material"] as ShaderMaterial
		var base_amplitude: float = material_entry["base_amplitude"]
		material.set_shader_parameter("wind_amplitude", base_amplitude * effective_strength)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var skeleton := _find_skeleton(child)
		if skeleton != null:
			return skeleton
	return null
