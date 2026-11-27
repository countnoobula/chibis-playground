class_name ChibiScarfTail
extends SkeletonModifier3D

## Short post-spring follow-through for the long scarf tail after a grounded glide stow.
## The rotation bias keeps the collar and segment lengths intact. The native
## spring simulator remains responsible for the tail's ongoing motion and settle.

const EFFECT_DURATION := 0.68
const EFFECT_FADE_START := 0.34
const TELEPORT_DISTANCE := 1.75
const MIN_RUN_SPEED := 0.75
const LAG_RESPONSE := 3.4
const MOTION_RISE_RESPONSE := 9.0
const MOTION_FALL_RESPONSE := 15.0
const TOSS_YAW_STEPS := [14.0, 4.0, 4.0, 4.0, 2.0]
const LIFT_PITCH_STEPS := [-9.0, -3.0, -3.0, -3.0, -1.0]
const MAX_TURN_LAG_YAW := 0.20

@export var runner_body: ParkourController

var _tail_bones := PackedInt32Array()
var _age := -1.0
var _motion_weight := 0.0
var _toss_open_weight := 0.0
var _lagged_world_velocity := Vector3.ZERO
var _stow_triggered := false
var _last_body_position := Vector3.ZERO
var _has_last_body_position := false
var _last_reset_serial := -1


func _ready() -> void:
	_cache_tail_bones()


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or runner_body == null:
		_reset_effect()
		return
	if _tail_bones.size() != 5:
		_cache_tail_bones()
		if _tail_bones.size() != 5:
			_reset_effect()
			return

	var phase := runner_body.scarf_glide_phase
	var reset_serial := runner_body.wind_reset_serial
	if reset_serial != _last_reset_serial or phase in [&"deploy", &"glide", &"cancel"]:
		_reset_effect()
		_last_reset_serial = reset_serial
		_stow_triggered = false
		_has_last_body_position = false
		return

	var body_position := runner_body.global_position
	if _has_last_body_position and body_position.distance_to(_last_body_position) > TELEPORT_DISTANCE:
		_last_body_position = body_position
		_reset_effect()
		return
	_last_body_position = body_position
	_has_last_body_position = true

	if not _is_valid_grounded_run():
		_reset_effect()
		return

	if _age < 0.0:
		if _stow_triggered or phase != &"stow" or not runner_body.scarf_glide_touchdown:
			return
		if ChibiScarfGlider.touchdown_hand_release(runner_body.scarf_glide_progress, 1) < 0.06:
			return
		_toss_open_weight = smoothstep(0.12, 0.84, runner_body.scarf_glide_stow_open)
		if _toss_open_weight <= 0.001:
			return
		_begin_effect()

	var frame_delta := maxf(delta, 0.0)
	_age += frame_delta
	if _age >= EFFECT_DURATION:
		_reset_effect()
		return

	var actor_basis := runner_body.global_basis.orthonormalized()
	var world_velocity := runner_body.get_real_velocity() - runner_body.get_platform_velocity()
	var planar_speed := Vector2(world_velocity.x, world_velocity.z).length()
	var target_motion := smoothstep(0.20, MIN_RUN_SPEED, planar_speed)
	var response := MOTION_RISE_RESPONSE if target_motion > _motion_weight else MOTION_FALL_RESPONSE
	_motion_weight = lerpf(_motion_weight, target_motion, 1.0 - exp(-response * frame_delta))

	if planar_speed > 0.25:
		_lagged_world_velocity = _lagged_world_velocity.lerp(
			Vector3(world_velocity.x, 0.0, world_velocity.z),
			1.0 - exp(-LAG_RESPONSE * frame_delta)
		)
	else:
		_lagged_world_velocity = _lagged_world_velocity.lerp(
			Vector3.ZERO, 1.0 - exp(-MOTION_FALL_RESPONSE * frame_delta)
		)

	var age_fade := 1.0 - smoothstep(EFFECT_FADE_START, EFFECT_DURATION, _age)
	var envelope := smoothstep(0.0, 0.10, _age) * age_fade
	if envelope <= 0.001:
		return

	var actor_to_skeleton := (skel.global_basis.inverse() * actor_basis).orthonormalized()
	var actor_right := (actor_to_skeleton * Vector3.RIGHT).normalized()
	var actor_up := (actor_to_skeleton * Vector3.UP).normalized()
	var local_lag_velocity := actor_basis.inverse() * _lagged_world_velocity
	var lag_heading := 0.0
	if local_lag_velocity.length_squared() > 0.08:
		lag_heading = atan2(local_lag_velocity.x, -local_lag_velocity.z)
	var turn_lag_yaw := clampf(lag_heading, -MAX_TURN_LAG_YAW, MAX_TURN_LAG_YAW)
	var strength := envelope * _motion_weight * _toss_open_weight

	for i in _tail_bones.size():
		var pose := skel.get_bone_global_pose(_tail_bones[i])
		var yaw_degrees: float = TOSS_YAW_STEPS[i] * strength
		if i == 0:
			yaw_degrees += rad_to_deg(turn_lag_yaw * strength)
		var pitch_degrees: float = LIFT_PITCH_STEPS[i] * strength
		var yaw_rotation := Quaternion(actor_up, deg_to_rad(yaw_degrees))
		var pitch_rotation := Quaternion(actor_right, deg_to_rad(pitch_degrees))
		pose.basis = (Basis(yaw_rotation * pitch_rotation) * pose.basis).orthonormalized()
		skel.set_bone_global_pose(_tail_bones[i], pose)


func _cache_tail_bones() -> void:
	_tail_bones.clear()
	var skel := get_skeleton()
	if skel == null:
		return
	for bone_name in ["scarf_01", "scarf_02", "scarf_03", "scarf_04", "scarf_05"]:
		var bone_index := skel.find_bone(bone_name)
		if bone_index < 0:
			_tail_bones.clear()
			return
		_tail_bones.append(bone_index)


func _is_valid_grounded_run() -> bool:
	return runner_body.current_state == "Locomotion" \
		and runner_body.is_on_floor() \
		and runner_body.get_active_water() == null


func _begin_effect() -> void:
	_age = 0.0
	_motion_weight = 0.0
	_stow_triggered = true
	var velocity := runner_body.get_real_velocity() - runner_body.get_platform_velocity()
	_lagged_world_velocity = Vector3(velocity.x, 0.0, velocity.z)


func _reset_effect() -> void:
	_age = -1.0
	_motion_weight = 0.0
	_toss_open_weight = 0.0
	_lagged_world_velocity = Vector3.ZERO
