class_name ChibiDiveGear
extends Node3D

## The only input is the existing water/locomotion state. The same timeline runs
## in either direction, so an aborted entry does not snap either prop or hands.
const GEAR_SCENE := preload("res://assets/characters/chibi_dive_gear.glb")
const TRANSITION_TIME := 0.74
const STOW_DEPTH := 0.27
const DIVE_STRAP_COLOR := Color("#647b65")

var progress := 0.0
var gesture_weight := 0.0
var mouthpiece_weight := 0.0
var head_bone := -1
var rest_to_head := Transform3D.IDENTITY

var _wanted := false
var _goggles: MeshInstance3D
var _mask: MeshInstance3D
var _snorkel: MeshInstance3D
var _outlet: Node3D
var _strap: MeshInstance3D
var _strap_material: BaseMaterial3D
var _strap_dry_color := Color.WHITE
var _strap_diving := -1
var _strap_around_hair := -1
var _goggles_rest := Transform3D.IDENTITY
var _mask_rest := Transform3D.IDENTITY
var _snorkel_rest := Transform3D.IDENTITY
var _travel := 0.0
var _frame := Transform3D.IDENTITY
var _materials: Dictionary[MeshInstance3D, Array] = {}


func attach_to(skeleton: Skeleton3D) -> bool:
	head_bone = skeleton.find_bone("head")
	if head_bone < 0:
		return false
	name = "ChibiDiveGear"
	var attachment := BoneAttachment3D.new()
	attachment.name = "DiveGearAttachment"
	attachment.bone_name = &"head"
	skeleton.add_child(attachment)
	attachment.add_child(self)
	rest_to_head = skeleton.get_bone_global_rest(head_bone).affine_inverse()
	transform = rest_to_head

	var gear := GEAR_SCENE.instantiate() as Node3D
	add_child(gear)
	_goggles = gear.get_node("ForeheadGoggles") as MeshInstance3D
	_mask = gear.get_node("DivingMask") as MeshInstance3D
	_snorkel = gear.get_node("Snorkel") as MeshInstance3D
	_outlet = _snorkel.get_node("SnorkelOutlet") as Node3D
	_strap = gear.get_node("HeadStrap") as MeshInstance3D
	_strap_material = _strap.mesh.surface_get_material(0).duplicate() as BaseMaterial3D
	_strap_dry_color = _strap_material.albedo_color
	_strap.set_surface_override_material(0, _strap_material)
	_strap_diving = _strap.find_blend_shape_by_name("Diving")
	_strap_around_hair = _strap.find_blend_shape_by_name("AroundHair")
	_goggles_rest = _goggles.transform
	_mask_rest = _mask.transform
	_snorkel_rest = _snorkel.transform
	for part in [_goggles, _mask, _snorkel]:
		_prepare_materials(part)
	_update_parts()
	return true


func advance(delta: float, state: String, wet_depth: float) -> void:
	# Keep both hands on an actual ledge until she is safely out.
	if state in ["LedgeHang", "LedgeShimmy", "LedgeCorner", "MantleUp"]:
		gesture_weight = 0.0
		return
	if state == "PoolSwim":
		_wanted = true
	elif state != "Locomotion" or wet_depth < STOW_DEPTH:
		_wanted = false
	var next := move_toward(progress, 1.0 if _wanted else 0.0, delta / TRANSITION_TIME)
	if next != progress:
		progress = next
		_update_parts()
	gesture_weight = smoothstep(0.05, 0.35, progress) * (1.0 - smoothstep(0.73, 0.98, progress))


func reset() -> void:
	_wanted = false
	progress = 0.0
	gesture_weight = 0.0
	_update_parts()


## Rest-model contact point at the outer frame, following the same arc as the prop.
func get_grip(side: float) -> Vector3:
	return _frame * Vector3(side * lerpf(0.16, 0.24, _travel), lerpf(0.002, -0.025, _travel), -0.013)


## The vent is usable once the snorkel has unfolded and contacted her mouth.
func get_snorkel_outlet_world() -> Vector3:
	return _outlet.global_position if mouthpiece_weight >= 0.99 else Vector3.INF


func _update_parts() -> void:
	_travel = smoothstep(0.16, 0.70, progress)
	var crossfade := smoothstep(0.38, 0.61, progress)
	var arch := sin(PI * _travel)
	var frame_position := _goggles_rest.origin.lerp(_mask_rest.origin, _travel)
	frame_position.z += 0.047 * arch
	var frame_basis := Basis(Vector3.RIGHT, -0.26 * arch)
	_frame = Transform3D(frame_basis, frame_position)
	_goggles.transform = Transform3D(frame_basis.scaled(Vector3(1.0 + 0.45 * crossfade, 1.0 + 0.14 * crossfade, 1.0)),
		frame_position)
	_mask.transform = Transform3D(frame_basis.scaled(Vector3(0.56, 0.72, 0.66).lerp(Vector3.ONE, crossfade)), frame_position)
	var extension := smoothstep(0.54, 0.94, progress)
	var swivel := Basis(Vector3.BACK, 0.74 * (1.0 - extension))
	var tube_offset := Vector3(0.035, 0.0, 0.022) * (1.0 - extension)
	_snorkel.transform = Transform3D(frame_basis * swivel.scaled(Vector3.ONE * lerpf(0.26, 1.0, extension)),
		_frame * (_snorkel_rest.origin - _mask_rest.origin + tube_offset))
	_set_opacity(_goggles, 1.0 - crossfade)
	_set_opacity(_mask, crossfade)
	_set_opacity(_snorkel, smoothstep(0.54, 0.78, progress))
	# The strap stays in the opaque pass for the entire change.
	_strap.set_blend_shape_value(_strap_diving, _travel)
	_strap.set_blend_shape_value(_strap_around_hair, arch)
	_strap_material.albedo_color = _strap_dry_color.lerp(DIVE_STRAP_COLOR, _travel)
	mouthpiece_weight = smoothstep(0.80, 0.96, progress)


func _prepare_materials(part: MeshInstance3D) -> void:
	var settings := []
	for index in part.mesh.get_surface_count():
		var original := part.mesh.surface_get_material(index) as BaseMaterial3D
		if original == null:
			continue
		var material := original.duplicate() as BaseMaterial3D
		part.set_surface_override_material(index, material)
		settings.append([material, original.albedo_color, original.transparency])
	_materials[part] = settings


func _set_opacity(part: MeshInstance3D, amount: float) -> void:
	part.visible = amount > 0.002
	if not part.visible:
		return
	for entry: Array in _materials[part]:
		var material: BaseMaterial3D = entry[0]
		var color: Color = entry[1]
		var mode: BaseMaterial3D.Transparency = entry[2]
		if mode == BaseMaterial3D.TRANSPARENCY_DISABLED and amount < 0.998:
			mode = BaseMaterial3D.TRANSPARENCY_ALPHA
		color.a *= amount
		material.transparency = mode
		material.albedo_color = color
