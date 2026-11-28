class_name FirstStepsAmbientBreezeModifier
extends SkeletonModifier3D

## Applies a subtle pose-space response after animation and secondary springs.
## It never writes to the runner body, its velocity, wind field, or collision.

const SCARF_MAX_BEND_DEGREES := 5.2
const SHORT_SCARF_MAX_BEND_DEGREES := 3.8
const AHOGE_MAX_BEND_DEGREES := 5.8
const CHARACTER_RESPONSE := 8.0

var breeze_source: Node
var runner_body: ParkourController
var applied_strength := 0.0

var _scarf_chain := PackedInt32Array()
var _short_scarf_chain := PackedInt32Array()
var _ahoge_bone := -1
var _scarf_transition_weight := 0.0


func configure(source: Node, runner: ParkourController) -> void:
	breeze_source = source
	runner_body = runner


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	_scarf_chain = _find_bone_chain(skeleton, ["scarf_01", "scarf_02", "scarf_03", "scarf_04", "scarf_05"])
	_short_scarf_chain = _find_bone_chain(skeleton, ["scarf_b_01", "scarf_b_02", "scarf_b_03"])
	_ahoge_bone = skeleton.find_bone("ahoge_01")


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or breeze_source == null or runner_body == null:
		applied_strength = 0.0
		_scarf_transition_weight = 0.0
		return

	var target_strength: float = breeze_source.get_effective_strength()
	var response := 1.0 - exp(-CHARACTER_RESPONSE * maxf(delta, 0.0))
	applied_strength = lerpf(applied_strength, target_strength, response)
	var scarf_target := 1.0 if runner_body.scarf_glide_phase == &"stowed" else 0.0
	_scarf_transition_weight = lerpf(_scarf_transition_weight, scarf_target, response)
	if applied_strength <= 0.001:
		return

	var runner_basis := runner_body.global_basis.orthonormalized()
	var actor_in_skeleton := (
		skeleton.global_basis.orthonormalized().inverse() * runner_basis
	).orthonormalized()
	var actor_up := (actor_in_skeleton * Vector3.UP).normalized()
	var actor_right := (actor_in_skeleton * Vector3.RIGHT).normalized()
	var local_wind: Vector3 = runner_basis.inverse() * breeze_source.get_breeze_vector_world()
	var character_strength := applied_strength

	_bend_chain(
		skeleton, _scarf_chain, actor_right, actor_up, local_wind,
		SCARF_MAX_BEND_DEGREES, character_strength * _scarf_transition_weight
	)
	_bend_chain(
		skeleton, _short_scarf_chain, actor_right, actor_up, local_wind,
		SHORT_SCARF_MAX_BEND_DEGREES, character_strength * _scarf_transition_weight
	)
	_bend_ahoge(skeleton, actor_right, actor_up, local_wind, character_strength)


func _find_bone_chain(skeleton: Skeleton3D, bone_names: Array[String]) -> PackedInt32Array:
	var result := PackedInt32Array()
	for bone_name in bone_names:
		var bone := skeleton.find_bone(bone_name)
		if bone < 0:
			return PackedInt32Array()
		result.append(bone)
	return result


func _bend_chain(
		skeleton: Skeleton3D,
		chain: PackedInt32Array,
		actor_right: Vector3,
		actor_up: Vector3,
		local_wind: Vector3,
		max_degrees: float,
		strength: float
) -> void:
	if chain.size() < 2 or strength <= 0.001:
		return
	for index in range(1, chain.size()):
		var tip_weight := float(index) / float(chain.size() - 1)
		var yaw := deg_to_rad(max_degrees * local_wind.x * tip_weight * strength)
		var pitch := deg_to_rad(max_degrees * 0.62 * local_wind.z * tip_weight * strength)
		_apply_global_bend(skeleton, chain[index], actor_right, actor_up, yaw, pitch)


func _bend_ahoge(
		skeleton: Skeleton3D,
		actor_right: Vector3,
		actor_up: Vector3,
		local_wind: Vector3,
		strength: float
) -> void:
	if _ahoge_bone < 0 or strength <= 0.001:
		return
	var yaw := deg_to_rad(AHOGE_MAX_BEND_DEGREES * local_wind.x * strength)
	var pitch := deg_to_rad(AHOGE_MAX_BEND_DEGREES * 0.62 * local_wind.z * strength)
	_apply_global_bend(skeleton, _ahoge_bone, actor_right, actor_up, yaw, pitch)


func _apply_global_bend(
		skeleton: Skeleton3D,
		bone: int,
		actor_right: Vector3,
		actor_up: Vector3,
		yaw: float,
		pitch: float
) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	var yaw_rotation := Quaternion(actor_up, yaw)
	var pitch_rotation := Quaternion(actor_right, pitch)
	pose.basis = (Basis(yaw_rotation * pitch_rotation) * pose.basis).orthonormalized()
	skeleton.set_bone_global_pose(bone, pose)
