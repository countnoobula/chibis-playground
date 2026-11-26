class_name ChibiPoseModifier
extends SkeletonModifier3D

const GROUND_PELVIS_COMPRESSION_MAX := 0.025
const GROUND_LEG_PROTRACTION_MAX := 0.018
const BALANCE_PELVIS_COMPRESSION_MAX := 0.090
const GROUND_TARGET_AHEAD_MIN := 0.120
const GROUND_TARGET_AHEAD_MAX := 0.130
const WALL_CLIMB_BODY_INSET := 0.16
const WALL_CLIMB_POSE_BLEND_RATE := 16.0
const SWIM_POSE_BLEND_RATE := 15.0
const SWIM_SCULL_RATE := 1.8
const TOWER_HANGING_IDLE_RESET_BLEND := 0.04

## Post-AnimationTree SkeletonModifier3D porting:
## 1. ChibiLedgeAnimInstance.cpp: per-hand 2-stage FindGrip raycast, LedgeShimmy alternating lift arc,
##    3-pass iterative BodyShift, 2-bone arm IK + palm RestBasis alignment, Mantle fade-out.
## 2. ChibiLedgeAnimInstance.cpp: AddDiveArc pelvis-pivoted pitch on Slide entry.
## 3. ClimbingStation.cpp: smooth-blended 4-limb IK, spine_01 lean, neck_01 gaze counter-roll.

class GripFrame:
	var support: Node3D = null
	var local_point: Vector3 = Vector3.ZERO
	var local_inward: Vector3 = Vector3.FORWARD
	var local_normal: Vector3 = Vector3.UP

	func is_valid() -> bool:
		return is_instance_valid(support)

	func world_transform() -> Transform3D:
		var t := support.global_transform
		var forward := (t.basis * local_inward).normalized()
		var normal := (t.basis * local_normal).normalized()
		return Transform3D(TwoBoneIK.basis_from_forward_up(forward, normal), t * local_point)

	func copy_from(other: GripFrame) -> void:
		support = other.support
		local_point = other.local_point
		local_inward = other.local_inward
		local_normal = other.local_normal

	func clear() -> void:
		support = null


class ArmIKState:
	var bones: PackedInt32Array = PackedInt32Array([-1, -1, -1])
	var rest_basis: Basis = Basis.IDENTITY
	var grip: GripFrame = GripFrame.new()
	var from_grip: GripFrame = GripFrame.new()
	var wrist_world: Vector3 = Vector3.ZERO
	var hand_basis_world: Basis = Basis.IDENTITY
	var active: bool = false


class GroundFootContact:
	var support: Node3D = null
	var local_sole: Vector3 = Vector3.ZERO
	var local_ankle_to_sole: Vector3 = Vector3.ZERO
	var local_foot_basis: Basis = Basis.IDENTITY
	var world_sole: Vector3 = Vector3.ZERO
	var world_ankle_to_sole: Vector3 = Vector3.ZERO
	var world_foot_basis: Basis = Basis.IDENTITY
	var anchored: bool = false
	var planted: bool = false
	var step_emitted: bool = false
	var gait_contact_active: bool = false
	var stance_was_active: bool = false
	var blocked_until_swing: bool = false
	var weight: float = 0.0
	var releasing: bool = false
	var release_start_weight: float = 0.0
	var release_elapsed: float = 0.0

	func sole_world() -> Vector3:
		if is_instance_valid(support):
			return support.get_global_transform_interpolated() * local_sole
		return world_sole

	func ankle_to_sole_world() -> Vector3:
		if is_instance_valid(support):
			return support.get_global_transform_interpolated().basis * local_ankle_to_sole
		return world_ankle_to_sole

	func foot_basis_world() -> Basis:
		if is_instance_valid(support):
			return (support.get_global_transform_interpolated().basis * local_foot_basis).orthonormalized()
		return world_foot_basis

	func clear() -> void:
		support = null
		local_sole = Vector3.ZERO
		local_ankle_to_sole = Vector3.ZERO
		local_foot_basis = Basis.IDENTITY
		world_sole = Vector3.ZERO
		world_ankle_to_sole = Vector3.ZERO
		world_foot_basis = Basis.IDENTITY
		anchored = false
		planted = false
		step_emitted = false
		gait_contact_active = false
		stance_was_active = false
		blocked_until_swing = false
		weight = 0.0
		releasing = false
		release_start_weight = 0.0
		release_elapsed = 0.0


@export var ledge_collision_mask: int = 1 # World layer

# State fed from ParkourController each physics frame
var parkour_state: String = "Locomotion"
var runner_body: ParkourController = null
var dive_gear: ChibiDiveGear
var scarf_glider: ChibiScarfGlider
var _scarf_pose_blend := 0.0
var _scarf_pose_open := 0.0
var _scarf_body_weight := 0.0
var _scarf_motion_phase := 0.0
var wade_weight_target := 0.0
var wade_surface_y := 0.0
var ledge_edge_world: Vector3 = Vector3.ZERO
var ledge_wall_normal_world: Vector3 = Vector3.FORWARD
var mantle_alpha: float = 0.0
var shimmy_start_edge: Vector3 = Vector3.ZERO
var shimmy_end_edge: Vector3 = Vector3.ZERO
var shimmy_phase: float = 0.0

# Slide dive arc state
var slide_dive_phase: float = 1.0
var slide_dive_active: bool = false

# Climbing station 4-limb IK state (fed from ClimbingStation)
var climb_active: bool = false
var climb_weight: float = 0.0
var climb_is_rope_net: bool = false
var climb_lean_deg: float = 0.0
var climb_station_basis: Basis = Basis.IDENTITY
var climb_limb_targets_world: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]

# General wall climbing pose input. These targets are copied from the movement controller so
# it can reuse its scratch arrays. Limb order is L hand, R hand, L foot, R foot.
var _wall_pose_requested: bool = false
var _wall_pose_blend: float = 0.0
var _wall_frame_target: Basis = Basis.IDENTITY
var _wall_frame_previous: Basis = Basis.IDENTITY
var _wall_frame: Basis = Basis.IDENTITY
var _wall_targets_target: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _wall_targets_previous: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _wall_targets: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _wall_contact_bases_target: Array[Basis] = [Basis.IDENTITY, Basis.IDENTITY, Basis.IDENTITY, Basis.IDENTITY]
var _wall_contact_bases_previous: Array[Basis] = [Basis.IDENTITY, Basis.IDENTITY, Basis.IDENTITY, Basis.IDENTITY]
var _wall_contact_bases: Array[Basis] = [Basis.IDENTITY, Basis.IDENTITY, Basis.IDENTITY, Basis.IDENTITY]
var _wall_weights_target: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _wall_weights_previous: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _wall_weights: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _wall_lean_target: float = 0.0
var _wall_lean_previous: float = 0.0
var _wall_lean: float = 0.0
var _wall_look_target: Vector3 = Vector3.ZERO
var _wall_look_previous: Vector3 = Vector3.ZERO
var _wall_look: Vector3 = Vector3.ZERO
var _wall_body_weight_target: float = 0.0
var _wall_body_weight_previous: float = 0.0
var _wall_body_weight: float = 0.0
var _wall_pose_samples_valid: bool = false
var _wall_leg_motion_target: Vector4 = Vector4.ZERO # push, tuck, settle, step
var _wall_leg_motion_previous: Vector4 = Vector4.ZERO
var _wall_leg_motion: Vector4 = Vector4.ZERO
var _wall_leg_lead_hand_target: float = 0.0
var _wall_leg_lead_hand_previous: float = 0.0
var _wall_leg_lead_hand: float = 0.0
var _wall_leg_motion_enabled: bool = false
var _tower_hanging_idle_requested: bool = false
var _tower_hanging_idle_blend: float = 0.0
var _tower_hanging_idle_elapsed: float = 0.0
var _tower_hanging_idle_peek_side: float = 1.0

var _arms: Array[ArmIKState] = []
var _leg_bones: Array[PackedInt32Array] = []
var _foot_contact_rest_basis: Array[Basis] = [Basis.IDENTITY, Basis.IDENTITY]
var _balance_shoe_rest_basis: Array[Basis] = [Basis.IDENTITY, Basis.IDENTITY]
var _ball_bones: PackedInt32Array = PackedInt32Array([-1, -1])
var _ground_feet: Array[GroundFootContact] = []
var _ground_actual_sole_world: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _ground_actual_valid: Array[bool] = [false, false]
var _root_bone: int = -1
var _pelvis_bone: int = -1
var _spine_bone: int = -1
var _neck_bone: int = -1
var _head_bone: int = -1
var _wall_neck_bind_offset := Basis.IDENTITY
var _wall_head_bind_offset := Basis.IDENTITY
var _bones_ready: bool = false

var _ledge_weight: float = 0.0
var _was_holding: bool = false
var _prev_shimmy_phase: float = -1.0
var _last_delta: float = 1.0 / 60.0
var _balance_weight := 0.0
var _wade_weight := 0.0
var _wade_move := 0.0
var _wade_idle_phase := 0.0
var _wade_wrists: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _swim_pose_weight := 0.0
var _swim_turn_target := 0.0
var _swim_dive_target := 0.0
var _swim_rise_target := 0.0
var _swim_glide_target := 0.0
var _swim_turn := 0.0
var _swim_dive := 0.0
var _swim_rise := 0.0
var _swim_glide := 0.0
var _swim_scull_phase := 0.0


func _ready() -> void:
	_arms = [ArmIKState.new(), ArmIKState.new()]
	_ground_feet = [GroundFootContact.new(), GroundFootContact.new()]
	_init_bones()


func _init_bones() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	_root_bone = skel.find_bone("root")
	_pelvis_bone = skel.find_bone("pelvis")
	_spine_bone = skel.find_bone("spine_01")
	_neck_bone = skel.find_bone("neck_01")
	_head_bone = skel.find_bone("head")
	if runner_body != null:
		# The imported model is rotated relative to the runner. Express the
		# neck and head binds in the runner's forward/up frame before aiming.
		var actor_to_skeleton := (skel.global_basis.inverse() * runner_body.global_basis).orthonormalized()
		var skeleton_to_actor := actor_to_skeleton.inverse()
		if _neck_bone >= 0:
			_wall_neck_bind_offset = skeleton_to_actor * skel.get_bone_global_rest(_neck_bone).basis.orthonormalized()
		if _head_bone >= 0:
			_wall_head_bind_offset = skeleton_to_actor * skel.get_bone_global_rest(_head_bone).basis.orthonormalized()

	var arm_names := [
		["upperarm_l", "lowerarm_l", "hand_l"],
		["upperarm_r", "lowerarm_r", "hand_r"],
	]
	for side in 2:
		for i in 3:
			var idx := skel.find_bone(arm_names[side][i])
			if idx < 0:
				_bones_ready = false
				return
			_arms[side].bones[i] = idx

	_leg_bones.clear()
	var ball_names := ["ball_l", "ball_r"]
	var leg_names := [["thigh_l", "calf_l", "foot_l"], ["thigh_r", "calf_r", "foot_r"]]
	for side in 2:
		var leg: Array = leg_names[side]
		var arr := PackedInt32Array()
		for bname in leg:
			var idx := skel.find_bone(bname)
			if idx < 0:
				_bones_ready = false
				return
			arr.append(idx)
		_leg_bones.append(arr)
		_ball_bones[side] = skel.find_bone(ball_names[side])

	# Compute bind-pose palm RestBasis (mirrors ChibiLedgeAnimInstance::Initialize)
	for side in 2:
		var hand_rest := skel.get_bone_global_rest(_arms[side].bones[2])
		var other_rest := skel.get_bone_global_rest(_arms[1 - side].bones[2])
		var out_dir := (hand_rest.origin - other_rest.origin).normalized()
		var fingers := (out_dir - Vector3.UP).normalized()
		var back := (out_dir + Vector3.UP).normalized()
		var desired_rest := TwoBoneIK.basis_from_forward_up(fingers, back)
		_arms[side].rest_basis = hand_rest.basis.inverse() * desired_rest

		# Keep the shoe's toe direction and top-of-foot orientation relative to a contact
		# frame so any support can supply a stable palm/sole orientation.
		var foot_rest := skel.get_bone_global_rest(_leg_bones[side][2])
		var toe_forward := Vector3.UP
		if _ball_bones[side] >= 0:
			var ball_rest := skel.get_bone_global_rest(_ball_bones[side])
			var toe_vector := ball_rest.origin - foot_rest.origin
			if toe_vector.length_squared() > 1e-8:
				toe_forward = toe_vector.normalized()
		var foot_top := Vector3.UP - toe_forward * Vector3.UP.dot(toe_forward)
		if foot_top.length_squared() < 1e-8:
			foot_top = foot_rest.basis.y
		foot_top = (foot_top - toe_forward * foot_top.dot(toe_forward)).normalized()
		var desired_foot_rest := TwoBoneIK.basis_from_forward_up(toe_forward, foot_top)
		_foot_contact_rest_basis[side] = foot_rest.basis.inverse() * desired_foot_rest
		# The ankle-to-ball vector points down into the boot. Preserve that angle
		# when fitting the sole to the support plane.
		var flat_toe := toe_forward.slide(Vector3.UP)
		if flat_toe.length_squared() < 1e-8:
			flat_toe = Vector3.BACK
		var shoe_rest := TwoBoneIK.basis_from_forward_up(flat_toe, Vector3.UP)
		_balance_shoe_rest_basis[side] = foot_rest.basis.inverse() * shoe_rest

	_bones_ready = true


## Supplies the procedural wall pose from a climbing controller. `frame` is wall-local
## (+Z outward, +Y up); `look` is a world-space gaze direction. Targets and contact bases
## are world-space and are copied here once per physics tick. Contact basis -Z faces into
## the support and +Y follows the surface up direction. Render frames interpolate adjacent
## submissions using Godot's physics interpolation fraction, keeping latched world contacts
## stationary while the actor transform is interpolated. `body_weight` controls the rest-like
## torso pose and presentation-only inset; per-limb weights blend each tip toward contact.
func set_wall_climb_pose(
	frame: Basis,
	targets: Array[Vector3],
	contact_bases: Array[Basis],
	weights: Array[float],
	lean_deg: float,
	look: Vector3,
	body_weight: float
) -> void:
	if targets.size() != 4 or contact_bases.size() != 4 or weights.size() != 4:
		return

	var fresh_pose := not _wall_pose_requested and _wall_pose_blend < 0.005
	var reset_samples := fresh_pose or not _wall_pose_samples_valid
	if not reset_samples:
		_wall_frame_previous = _wall_frame_target
		_wall_lean_previous = _wall_lean_target
		_wall_look_previous = _wall_look_target
		_wall_body_weight_previous = _wall_body_weight_target
		_wall_leg_motion_previous = _wall_leg_motion_target
		_wall_leg_lead_hand_previous = _wall_leg_lead_hand_target
		for limb in 4:
			_wall_targets_previous[limb] = _wall_targets_target[limb]
			_wall_contact_bases_previous[limb] = _wall_contact_bases_target[limb]
			_wall_weights_previous[limb] = _wall_weights_target[limb]
	_wall_frame_target = frame.orthonormalized()
	_wall_lean_target = clampf(lean_deg, -55.0, 55.0)
	_wall_look_target = look.normalized() if look.length_squared() > 1e-8 else Vector3.ZERO
	_wall_body_weight_target = clampf(body_weight, 0.0, 1.0)
	# The tower submits its leg envelopes immediately after this shared wall pose. Other
	# climb routes get zeroed here so a prior tower leap cannot affect their legs.
	_wall_leg_motion_target = Vector4.ZERO
	_wall_leg_lead_hand_target = 0.0
	_wall_leg_motion_enabled = false
	for limb in 4:
		_wall_targets_target[limb] = targets[limb]
		_wall_contact_bases_target[limb] = contact_bases[limb].orthonormalized()
		_wall_weights_target[limb] = clampf(weights[limb], 0.0, 1.0)

	# First activation starts both interpolation endpoints at the real contact frame. This
	# avoids lerping world-space targets from Vector3.ZERO or retaining a stale prior climb.
	if reset_samples:
		_wall_frame_previous = _wall_frame_target
		_wall_lean_previous = _wall_lean_target
		_wall_look_previous = _wall_look_target
		_wall_body_weight_previous = _wall_body_weight_target
		_wall_frame = _wall_frame_target
		_wall_lean = _wall_lean_target
		_wall_look = _wall_look_target
		_wall_body_weight = _wall_body_weight_target
		_wall_leg_motion_previous = Vector4.ZERO
		_wall_leg_motion = Vector4.ZERO
		_wall_leg_lead_hand_previous = 0.0
		_wall_leg_lead_hand = 0.0
		for limb in 4:
			_wall_targets_previous[limb] = _wall_targets_target[limb]
			_wall_contact_bases_previous[limb] = _wall_contact_bases_target[limb]
			_wall_weights_previous[limb] = _wall_weights_target[limb]
			_wall_targets[limb] = _wall_targets_target[limb]
			_wall_contact_bases[limb] = _wall_contact_bases_target[limb]
			_wall_weights[limb] = _wall_weights_target[limb]
		_wall_pose_samples_valid = true
	_wall_pose_requested = true


## Supplies tower-only push, tuck, catch-settle, and free-leg step envelopes. The call is
## paired with set_wall_climb_pose on each physics tick and sampled with its render poses.
func set_wall_climb_leg_motion(
	push: float,
	tuck: float,
	settle: float,
	step: float,
	lead_hand: int
) -> void:
	_wall_leg_motion_target = Vector4(
		clampf(push, 0.0, 1.0),
		clampf(tuck, 0.0, 1.0),
		clampf(settle, 0.0, 1.0),
		clampf(step, 0.0, 1.0)
	)
	_wall_leg_lead_hand_target = clampf(float(lead_hand), 0.0, 1.0)
	_wall_leg_motion_enabled = true


## Enables the tower's subtle hanging idle while the controller is settled in HOLD.
## The flag is blended on render frames so motion input can release it promptly.
func set_tower_hanging_idle(active: bool) -> void:
	if active and not _tower_hanging_idle_requested:
		# If steering released the idle only briefly, keep its cadence. Restarting at
		# the first glance here would snap the head back to the same look on re-entry.
		if _tower_hanging_idle_blend <= TOWER_HANGING_IDLE_RESET_BLEND:
			_tower_hanging_idle_elapsed = 0.0
			_tower_hanging_idle_peek_side = _wall_hanging_idle_choose_peek_side()
	_tower_hanging_idle_requested = active


## Smoothly blends the wall pose back to animation and ground-contact IK. `immediate`
## is reserved for hard resets such as respawn, where retaining world targets is unsafe.
func clear_wall_climb_pose(immediate: bool = false) -> void:
	_wall_pose_requested = false
	_tower_hanging_idle_requested = false
	if immediate:
		_wall_pose_blend = 0.0
		_tower_hanging_idle_blend = 0.0
		_tower_hanging_idle_elapsed = 0.0
		_tower_hanging_idle_peek_side = 1.0
		_wall_body_weight = 0.0
		_wall_body_weight_target = 0.0
		_wall_lean = 0.0
		_wall_lean_target = 0.0
		_wall_lean_previous = 0.0
		_wall_look = Vector3.ZERO
		_wall_look_target = Vector3.ZERO
		_wall_look_previous = Vector3.ZERO
		_wall_frame = Basis.IDENTITY
		_wall_frame_target = Basis.IDENTITY
		_wall_frame_previous = Basis.IDENTITY
		_wall_pose_samples_valid = false
		_wall_body_weight_previous = 0.0
		_wall_leg_motion = Vector4.ZERO
		_wall_leg_motion_target = Vector4.ZERO
		_wall_leg_motion_previous = Vector4.ZERO
		_wall_leg_lead_hand = 0.0
		_wall_leg_lead_hand_target = 0.0
		_wall_leg_lead_hand_previous = 0.0
		_wall_leg_motion_enabled = false
		for limb in 4:
			_wall_targets[limb] = Vector3.ZERO
			_wall_targets_target[limb] = Vector3.ZERO
			_wall_targets_previous[limb] = Vector3.ZERO
			_wall_contact_bases[limb] = Basis.IDENTITY
			_wall_contact_bases_target[limb] = Basis.IDENTITY
			_wall_contact_bases_previous[limb] = Basis.IDENTITY
			_wall_weights[limb] = 0.0
			_wall_weights_target[limb] = 0.0
			_wall_weights_previous[limb] = 0.0
	else:
		# After climbing stops there are no more physics submissions. Freeze the last
		# rendered sample so the interpolation fraction cannot replay stale motion during
		# the release blend. A quick reattach will advance from this exact pose.
		_wall_frame_previous = _wall_frame
		_wall_frame_target = _wall_frame
		_wall_lean_previous = _wall_lean
		_wall_lean_target = _wall_lean
		_wall_look_previous = _wall_look
		_wall_look_target = _wall_look
		_wall_body_weight_previous = _wall_body_weight
		_wall_body_weight_target = _wall_body_weight
		_wall_leg_motion_previous = _wall_leg_motion
		_wall_leg_motion_target = _wall_leg_motion
		_wall_leg_lead_hand_previous = _wall_leg_lead_hand
		_wall_leg_lead_hand_target = _wall_leg_lead_hand
		for limb in 4:
			_wall_targets_previous[limb] = _wall_targets[limb]
			_wall_targets_target[limb] = _wall_targets[limb]
			_wall_contact_bases_previous[limb] = _wall_contact_bases[limb]
			_wall_contact_bases_target[limb] = _wall_contact_bases[limb]
			_wall_weights_previous[limb] = _wall_weights[limb]
			_wall_weights_target[limb] = _wall_weights[limb]
		_wall_pose_samples_valid = true


## Returns upper-arm/thigh joint origins relative to the CharacterBody3D feet origin,
## in actor-local axes (+X right, +Y up, +Z outward when facing a wall).
func get_wall_climb_limb_offsets() -> Array[Vector3]:
	var result: Array[Vector3] = []
	if not _bones_ready:
		_init_bones()
	var skel := get_skeleton()
	if skel == null or not _bones_ready or runner_body == null:
		return result

	var body_from_skeleton := runner_body.global_transform.affine_inverse() * skel.global_transform
	for limb in 4:
		var bones: PackedInt32Array = _arms[limb].bones if limb < 2 else _leg_bones[limb - 2]
		result.append((body_from_skeleton * skel.get_bone_global_rest(bones[0])).origin)
	return result


## Returns total two-bone reach for L hand, R hand, L foot, R foot in actor-local metres.
func get_wall_climb_limb_lengths() -> Array[float]:
	var result: Array[float] = []
	if not _bones_ready:
		_init_bones()
	var skel := get_skeleton()
	if skel == null or not _bones_ready or runner_body == null:
		return result

	var body_from_skeleton := runner_body.global_transform.affine_inverse() * skel.global_transform
	for limb in 4:
		var bones: PackedInt32Array = _arms[limb].bones if limb < 2 else _leg_bones[limb - 2]
		var upper := (body_from_skeleton * skel.get_bone_global_rest(bones[0])).origin
		var lower := (body_from_skeleton * skel.get_bone_global_rest(bones[1])).origin
		var tip := (body_from_skeleton * skel.get_bone_global_rest(bones[2])).origin
		result.append(upper.distance_to(lower) + lower.distance_to(tip))
	return result


## Static helper usable both live and in headless unit tests.
static func find_grip_in_space(
	space: PhysicsDirectSpaceState3D,
	exclude: Array[RID],
	edge: Vector3,
	inward: Vector3,
	collision_mask: int
) -> GripFrame:
	var result := GripFrame.new()
	if space == null or inward.length_squared() < 1e-6:
		return result

	var in_dir := Vector3(inward.x, 0.0, inward.z).normalized()
	var face_hit: Dictionary = {}
	var support: Node3D = null

	# Locate the lower wall before scanning across the lip (handles beveled rims)
	for drop: float in [0.45, 0.24, 0.10]:
		var probe: Vector3 = edge - Vector3.UP * drop
		var q := PhysicsRayQueryParameters3D.create(probe - in_dir * 0.80, probe + in_dir * 0.45, collision_mask, exclude)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var n: Vector3 = hit["normal"]
			if (-n).dot(in_dir) > 0.35:
				face_hit = hit
				support = hit["collider"] as Node3D
				break

	if support == null:
		return result

	var face_n: Vector3 = face_hit["normal"]
	var facing := Vector3(-face_n.x, 0.0, -face_n.z)
	if facing.length_squared() > 1e-6:
		facing = facing.normalized()
	if facing.dot(in_dir) < 0.5:
		facing = in_dir

	var face_pt: Vector3 = face_hit["position"]
	var start := Vector3(face_pt.x, edge.y, face_pt.z)
	var best_hit: Dictionary = {}
	var found_top := false
	var best_dist_sq := INF
	var search_end := 48 # cm increments of 2 cm -> 0.02 m

	var depth := -4
	while depth <= search_end:
		var sample := start + facing * (float(depth) * 0.01)
		var hit := _raycast_specific_collider(
			space,
			sample + Vector3.UP * 0.30,
			sample - Vector3.UP * 0.65,
			collision_mask,
			exclude,
			support
		)
		if not hit.is_empty():
			var top_n: Vector3 = hit["normal"]
			if top_n.y >= 0.58:
				if not found_top:
					search_end = mini(search_end, depth + 12)
				found_top = true
				var dsq := edge.distance_squared_to(hit["position"])
				if dsq < best_dist_sq:
					best_dist_sq = dsq
					best_hit = hit
		depth += 2

	if not found_top:
		return result

	var best_n: Vector3 = best_hit["normal"].normalized()
	var tangent := (facing - best_n * facing.dot(best_n))
	tangent = tangent.normalized() if tangent.length_squared() > 1e-6 else facing
	var inv_t := support.global_transform.affine_inverse()
	result.support = support
	result.local_point = inv_t * (best_hit["position"] as Vector3)
	result.local_inward = (inv_t.basis * tangent).normalized()
	result.local_normal = (inv_t.basis * best_n).normalized()
	return result


static func _raycast_specific_collider(
	space: PhysicsDirectSpaceState3D,
	from_pos: Vector3,
	to_pos: Vector3,
	mask: int,
	base_exclude: Array[RID],
	target_collider: Object
) -> Dictionary:
	var exc := base_exclude.duplicate()
	for _attempt in 4:
		var q := PhysicsRayQueryParameters3D.create(from_pos, to_pos, mask, exc)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return {}
		if hit["collider"] == target_collider:
			return hit
		var rid: RID = hit["rid"]
		if rid.is_valid():
			exc.append(rid)
		else:
			return {}
	return {}


func update_ledge_targets(delta: float) -> void:
	_last_delta = delta
	if not _bones_ready:
		_init_bones()
	if not _bones_ready or runner_body == null:
		return

	# Smooth climb weight blend (replaces Unreal's hidden UPoseableMeshComponent pop!)
	var target_climb := 1.0 if climb_active else 0.0
	climb_weight = lerpf(climb_weight, target_climb, 1.0 - exp(-16.0 * delta))
	if not climb_active and climb_weight < 0.005:
		climb_weight = 0.0

	var is_hang := parkour_state == "LedgeHang"
	var is_shimmy := parkour_state == "LedgeShimmy"
	var is_mantle := parkour_state == "MantleUp"
	var on_edge := is_hang or is_shimmy

	if not on_edge and not is_mantle:
		_ledge_weight = 0.0
		_was_holding = false
		_prev_shimmy_phase = -1.0
		for arm in _arms:
			arm.grip.clear()
			arm.from_grip.clear()
			arm.active = false
		return

	var inward := Vector3(-ledge_wall_normal_world.x, 0.0, -ledge_wall_normal_world.z)
	if inward.length_squared() > 1e-6:
		inward = inward.normalized()
	else:
		return

	var target_w := 1.0 if on_edge else (1.0 - smoothstep(0.50, 0.83, mantle_alpha))
	if not _was_holding and on_edge:
		for arm in _arms:
			arm.grip.clear()
	_was_holding = on_edge
	_ledge_weight = minf(target_w, _ledge_weight + delta * 14.0)

	# Godot right-handed: across_right = inward.cross(UP) points to Chibi's RIGHT when facing inward!
	var across_right := inward.cross(Vector3.UP).normalized()
	var step_phase := shimmy_phase if is_shimmy else -1.0
	var start_edge := shimmy_start_edge if is_shimmy else ledge_edge_world
	var end_edge := shimmy_end_edge if is_shimmy else ledge_edge_world
	var new_step := is_shimmy and (_prev_shimmy_phase < 0.0 or step_phase < _prev_shimmy_phase)
	_prev_shimmy_phase = step_phase
	var lead_hand := 1 if (end_edge - start_edge).dot(across_right) >= 0.0 else 0

	var space := runner_body.get_world_3d().direct_space_state
	var exclude: Array[RID] = [runner_body.get_rid()]
	var skel := get_skeleton()
	var mesh_scale := skel.global_transform.basis.get_scale().abs().max_axis_index()
	var scale_val := skel.global_transform.basis.get_scale().abs()[mesh_scale]

	for side in 2:
		var arm := _arms[side]
		var hand_offset := across_right * (0.11 if side == 1 else -0.11)
		if on_edge and not arm.grip.is_valid():
			arm.grip = find_grip_in_space(space, exclude, start_edge + hand_offset, inward, ledge_collision_mask)

		if new_step:
			arm.from_grip.copy_from(arm.grip)
			var next_grip := find_grip_in_space(space, exclude, end_edge + hand_offset, inward, ledge_collision_mask)
			if next_grip.is_valid():
				arm.grip = next_grip
			elif arm.grip.is_valid():
				var cur_loc := arm.grip.world_transform().origin
				if absf((cur_loc - end_edge - hand_offset).dot(across_right)) > 0.15:
					arm.grip.clear()

		arm.active = arm.grip.is_valid()
		if not arm.active:
			continue

		var frame := arm.grip.world_transform()
		if is_shimmy and arm.from_grip.is_valid():
			var reach := smoothstep(0.04, 0.46, step_phase) if side == lead_hand else smoothstep(0.52, 0.94, step_phase)
			var from_t := arm.from_grip.world_transform()
			var lift := minf(0.02, 0.18 * from_t.origin.distance_to(frame.origin))
			var blended_origin := from_t.origin.lerp(frame.origin, reach)
			var blended_basis := Basis(from_t.basis.get_rotation_quaternion().slerp(frame.basis.get_rotation_quaternion(), reach))
			frame = Transform3D(blended_basis, blended_origin + blended_basis.y * (4.0 * reach * (1.0 - reach) * lift))

		var fwd := (-frame.basis.z).normalized()
		var nrm := frame.basis.y.normalized()
		arm.hand_basis_world = (frame.basis * arm.rest_basis.inverse()).orthonormalized()
		# Mitten contact marker in bind pose: 3.42 cm along fingers and 2.78 cm toward palm
		arm.wrist_world = frame.origin + (nrm * 0.0278 - fwd * 0.0342) * scale_val


## Called once after CharacterBody3D movement on the physics tick. Contact points are
## stored in support-local space so a moving floor carries a planted sole with it.
func update_ground_targets(delta: float) -> void:
	if not _bones_ready:
		_init_bones()
	if _ground_feet.size() != 2:
		_ground_feet = [GroundFootContact.new(), GroundFootContact.new()]
	if delta <= 0.0 or not _can_use_ground_contacts():
		reset_ground_contacts()
		return
	var skel := get_skeleton()
	if skel == null or runner_body == null:
		reset_ground_contacts()
		return

	var anim_ctrl := runner_body.anim_ctrl
	if anim_ctrl == null:
		reset_ground_contacts()
		return

	var phase := fposmod(anim_ctrl.get_ground_phase(), 1.0)
	var contact_duration := clampf(anim_ctrl.get_ground_contact_duration(), 0.0, 0.48)
	var gait_weight := clampf(anim_ctrl.get_ground_gait_weight(), 0.0, 1.0)
	var pivot_weight := clampf(runner_body.ground_pivot_weight, 0.0, 1.0)
	var pivot_side := runner_body.ground_pivot_side

	for side in 2:
		var foot := _ground_feet[side]
		if foot.anchored and foot.support != null and not is_instance_valid(foot.support):
			_clear_ground_foot(side)
			foot = _ground_feet[side]

		# Curves show contact starting ~0.02 cycle before each measured strike.
		var strike_phase := ChibiAnimController.LEFT_STRIKE_PHASE if side == 0 else ChibiAnimController.RIGHT_STRIKE_PHASE
		var cycle_phase := fposmod(phase - strike_phase + 0.025, 1.0)
		var stance_active := gait_weight > 0.04 and contact_duration > 0.005 and cycle_phase < contact_duration
		foot.gait_contact_active = stance_active
		var pivot_active := pivot_side == side and pivot_weight > 0.001
		if not stance_active:
			foot.blocked_until_swing = false
		elif not foot.stance_was_active:
			foot.blocked_until_swing = false
		foot.stance_was_active = stance_active

		if foot.releasing:
			var blocked := foot.blocked_until_swing and stance_active
			foot.release_elapsed += delta
			foot.weight = foot.release_start_weight * (1.0 - smoothstep(0.0, 0.055, foot.release_elapsed))
			if foot.weight <= 0.005:
				_clear_ground_foot(side)
				foot = _ground_feet[side]
				foot.blocked_until_swing = blocked
				foot.stance_was_active = stance_active
			if foot.releasing:
				continue

		var wants_contact := pivot_active or stance_active
		if not wants_contact:
			if foot.anchored:
				_clear_ground_foot(side)
			continue

		if not foot.anchored and not foot.blocked_until_swing:
			_capture_ground_foot(skel, side)

		if not foot.anchored:
			continue
		var stance_weight := _ground_stance_weight(cycle_phase, contact_duration) * gait_weight if stance_active else 0.0
		foot.weight = maxf(stance_weight, pivot_weight if pivot_active else 0.0)
		if pivot_active and foot.weight >= 0.80 and not _ground_foot_reachable(skel, side, foot):
			foot.blocked_until_swing = stance_active
			_start_ground_foot_release(side)


func reset_ground_contacts() -> void:
	if _ground_feet.size() != 2:
		_ground_feet = [GroundFootContact.new(), GroundFootContact.new()]
	for side in 2:
		_clear_ground_foot(side)
		_ground_actual_valid[side] = false


## Minimal observable contact API for focused runtime drift sampling.
func is_ground_foot_planted(side: int) -> bool:
	if side < 0 or side >= _ground_feet.size():
		return false
	var foot := _ground_feet[side]
	if not foot.planted or not foot.anchored or foot.weight < 0.85 \
		or (foot.support != null and not is_instance_valid(foot.support)) \
		or not _ground_actual_valid[side]:
		return false
	return _ground_actual_sole_world[side].distance_to(foot.sole_world()) <= 0.025


func get_ground_sole_world(side: int) -> Vector3:
	if side < 0 or side >= _ground_feet.size() or not _ground_actual_valid[side]:
		return Vector3.ZERO
	var foot := _ground_feet[side]
	if not foot.anchored or (foot.support != null and not is_instance_valid(foot.support)):
		return Vector3.ZERO
	return _ground_actual_sole_world[side]


func get_ground_contact_target_world(side: int) -> Vector3:
	if side < 0 or side >= _ground_feet.size():
		return Vector3.ZERO
	var foot := _ground_feet[side]
	if not foot.anchored or (foot.support != null and not is_instance_valid(foot.support)):
		return Vector3.ZERO
	return foot.sole_world()


func _can_use_ground_contacts() -> bool:
	return runner_body != null \
		and parkour_state == "Locomotion" \
		and not climb_active \
		and not slide_dive_active \
		and runner_body.is_on_floor() \
		and runner_body.get_floor_normal().dot(Vector3.UP) >= cos(runner_body.floor_max_angle)


func _ground_stance_weight(cycle_phase: float, contact_duration: float) -> float:
	if contact_duration <= 0.0:
		return 0.0
	var fade := contact_duration * 0.20
	var plant_in := smoothstep(0.0, fade, cycle_phase)
	var toe_out := 1.0 - smoothstep(maxf(0.0, contact_duration - fade), contact_duration, cycle_phase)
	return clampf(minf(plant_in, toe_out), 0.0, 1.0)


func _capture_ground_foot(skel: Skeleton3D, side: int) -> void:
	var bones := _leg_bones[side]
	var skel_world := skel.get_global_transform_interpolated()
	var ankle_world := skel_world * skel.get_bone_global_pose(bones[2])
	var sole_world := _raw_ground_sole_world(skel, side, ankle_world.origin, true)
	var hit := _raycast_walkable_ground(sole_world)
	if hit.is_empty():
		return
	var normal := (hit["normal"] as Vector3).normalized()

	var contact_point: Vector3 = hit["position"] + normal * 0.004
	var travel := runner_body.get_real_velocity() - runner_body.get_platform_velocity()
	travel.y = 0.0
	var travel_speed := travel.length()
	if travel_speed > 1.5:
		var travel_dir := travel / travel_speed
		var hip_world := skel_world * skel.get_bone_global_pose(bones[0])
		var ankle_to_sole := sole_world - ankle_world.origin
		var target_ankle := contact_point - ankle_to_sole
		var ahead := (target_ankle - hip_world.origin).dot(travel_dir)
		# The rendered body trails physics by up to one tick. Center the anchor in
		# the leg's reach across the visible plant and toe-off poses.
		var desired_ahead := lerpf(
			GROUND_TARGET_AHEAD_MIN,
			GROUND_TARGET_AHEAD_MAX,
			clampf(travel_speed / 7.8, 0.0, 1.0)
		) - travel_speed / float(Engine.physics_ticks_per_second)
		var forward_bias := clampf(desired_ahead - ahead, 0.0, 0.34)
		if forward_bias > 0.005:
			var biased_hit := _raycast_walkable_ground(sole_world + travel_dir * forward_bias)
			if not biased_hit.is_empty():
				hit = biased_hit
				normal = (hit["normal"] as Vector3).normalized()
				contact_point = hit["position"] + normal * 0.004

	var foot := _ground_feet[side]
	var collider := hit["collider"] as Node3D
	foot.anchored = true
	foot.planted = false
	foot.weight = 0.0
	foot.releasing = false
	foot.blocked_until_swing = false
	foot.step_emitted = false
	_ground_actual_valid[side] = false
	if collider != null:
		var support_transform := collider.global_transform
		var inv := support_transform.affine_inverse()
		foot.support = collider
		foot.local_sole = inv * contact_point
		foot.local_ankle_to_sole = support_transform.basis.inverse() * (sole_world - ankle_world.origin)
		foot.local_foot_basis = (support_transform.basis.inverse() * ankle_world.basis).orthonormalized()
	else:
		foot.support = null
		foot.world_sole = contact_point
		foot.world_ankle_to_sole = sole_world - ankle_world.origin
		foot.world_foot_basis = ankle_world.basis


func _raycast_walkable_ground(point: Vector3) -> Dictionary:
	if runner_body == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(
		point + Vector3.UP * 0.12,
		point - Vector3.UP * 0.22,
		1,
		[runner_body.get_rid()]
	)
	query.collide_with_areas = false
	var hit := runner_body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var normal := (hit["normal"] as Vector3).normalized()
	if normal.dot(Vector3.UP) < cos(runner_body.floor_max_angle):
		return {}
	return hit


func _raw_ground_sole_world(
	skel: Skeleton3D,
	side: int,
	ankle_world: Vector3,
	use_interpolated_transform: bool = false
) -> Vector3:
	var ball_bone := _ball_bones[side]
	var skel_world := skel.get_global_transform_interpolated() if use_interpolated_transform else skel.global_transform
	var scale_vec := skel_world.basis.get_scale().abs()
	var max_axis := scale_vec.max_axis_index()
	var scale_val := scale_vec[max_axis]
	if ball_bone >= 0:
		var ball_world := skel_world * skel.get_bone_global_pose(ball_bone)
		return ball_world.origin - Vector3.UP * (0.022 * scale_val)
	return ankle_world - Vector3.UP * (0.035 * scale_val)


func _ground_foot_reachable(skel: Skeleton3D, side: int, foot: GroundFootContact) -> bool:
	var bones := _leg_bones[side]
	var skel_world := skel.get_global_transform_interpolated()
	var hip := (skel_world * skel.get_bone_global_pose(bones[0])).origin
	var knee := (skel_world * skel.get_bone_global_pose(bones[1])).origin
	var ankle := (skel_world * skel.get_bone_global_pose(bones[2])).origin
	var reach := hip.distance_to(knee) + knee.distance_to(ankle)
	var target_ankle := foot.sole_world() - foot.ankle_to_sole_world()
	hip -= Vector3.UP * _ground_pelvis_drop_required(skel, side, foot, foot.weight, true)
	var hip_to_target := target_ankle - hip
	var distance := hip_to_target.length()
	var max_reach := maxf(0.001, reach + GROUND_LEG_PROTRACTION_MAX - 0.003)
	return distance < max_reach + 0.002


func _ground_pelvis_drop_required(
	skel: Skeleton3D,
	side: int,
	foot: GroundFootContact,
	weight: float,
	use_interpolated_transform: bool = false
) -> float:
	if _pelvis_bone < 0 or weight <= 0.0:
		return 0.0
	var bones := _leg_bones[side]
	var skel_world := skel.get_global_transform_interpolated() if use_interpolated_transform else skel.global_transform
	var hip := (skel_world * skel.get_bone_global_pose(bones[0])).origin
	var knee := (skel_world * skel.get_bone_global_pose(bones[1])).origin
	var ankle := (skel_world * skel.get_bone_global_pose(bones[2])).origin
	var reach := maxf(0.001, hip.distance_to(knee) + knee.distance_to(ankle) + GROUND_LEG_PROTRACTION_MAX - 0.003)
	var target_ankle := foot.sole_world() - foot.ankle_to_sole_world()
	var horizontal_delta := target_ankle - hip
	horizontal_delta.y = 0.0
	if horizontal_delta.length() >= reach:
		return GROUND_PELVIS_COMPRESSION_MAX * clampf(weight, 0.0, 1.0)
	var max_vertical := sqrt(maxf(0.0, reach * reach - horizontal_delta.length_squared()))
	var vertical_distance := maxf(0.0, hip.y - target_ankle.y)
	var required := maxf(0.0, vertical_distance - max_vertical + 0.002)
	return minf(required, GROUND_PELVIS_COMPRESSION_MAX) * clampf(weight, 0.0, 1.0)


func _start_ground_foot_release(side: int) -> void:
	var foot := _ground_feet[side]
	if not foot.anchored:
		return
	foot.planted = false
	foot.releasing = true
	foot.release_start_weight = foot.weight
	foot.release_elapsed = 0.0


func _clear_ground_foot(side: int) -> void:
	if side < 0 or side >= _ground_feet.size():
		return
	var foot := _ground_feet[side]
	foot.clear()


func _process_modification_with_delta(_delta: float) -> void:
	if not _bones_ready:
		_init_bones()
	var skel := get_skeleton()
	if skel == null or not _bones_ready:
		return

	if dive_gear != null and runner_body != null:
		var depth := 0.0
		var water := runner_body.get_active_water()
		if is_instance_valid(water):
			depth = water.get_surface_height() - runner_body.global_position.y
		dive_gear.advance(_delta, parkour_state, depth)

	_advance_wall_climb_pose(_delta)
	var swim_active := parkour_state == "PoolSwim" and runner_body != null
	if not swim_active:
		_clear_swim_pose_target()
	var swim_alpha := 1.0 - exp(-SWIM_POSE_BLEND_RATE * maxf(_delta, 0.0))
	_swim_pose_weight = lerpf(_swim_pose_weight, 1.0 if swim_active else 0.0, swim_alpha)
	_swim_turn = lerpf(_swim_turn, _swim_turn_target if swim_active else 0.0, swim_alpha)
	_swim_dive = lerpf(_swim_dive, _swim_dive_target if swim_active else 0.0, swim_alpha)
	_swim_rise = lerpf(_swim_rise, _swim_rise_target if swim_active else 0.0, swim_alpha)
	_swim_glide = lerpf(_swim_glide, _swim_glide_target if swim_active else 0.0, swim_alpha)
	_swim_scull_phase = fposmod(_swim_scull_phase + maxf(_delta, 0.0) * SWIM_SCULL_RATE, TAU)
	if parkour_state == "Locomotion" or parkour_state == "PoolSwim":
		_wade_weight = lerpf(_wade_weight, wade_weight_target, 1.0 - exp(-12.0 * _delta))
	else:
		reset_wade_pose()
	var wall_body_weight := _wall_body_weight * _wall_pose_blend
	var max_wall_limb_weight := 0.0
	for weight in _wall_weights:
		max_wall_limb_weight = maxf(max_wall_limb_weight, weight * _wall_pose_blend)
	if wall_body_weight > 0.005 or max_wall_limb_weight > 0.005 \
		or (_wall_leg_motion_enabled and _wall_pose_blend > 0.005):
		_apply_wall_climbing_ik(skel)
		_apply_scarf_glide_pose(skel, _delta)
		return

	if climb_weight > 0.005:
		_apply_climbing_ik(skel)
		_apply_scarf_glide_pose(skel, _delta)
		return

	if slide_dive_active and slide_dive_phase < 1.0:
		_apply_dive_arc(skel, slide_dive_phase)
		_apply_scarf_glide_pose(skel, _delta)
		return

	if _ledge_weight > 0.001 and (_arms[0].active or _arms[1].active):
		_apply_ledge_ik(skel)
	if runner_body != null and runner_body.has_balance_footing():
		_balance_weight = move_toward(_balance_weight, 1.0, maxf(_delta, 0.0) * 18.0)
		_apply_balance_foot_ik(skel)
	else:
		_balance_weight = 0.0
		_apply_ground_foot_ik(skel)
	if _wade_weight > 0.002 and runner_body != null:
		_apply_wade_arms(skel, _delta)
	if _swim_pose_weight > 0.002 and runner_body != null \
		and (parkour_state == "PoolSwim" or parkour_state == "Locomotion"):
		_apply_swim_pose(skel)
	if dive_gear != null and dive_gear.gesture_weight > 0.001 \
		and (parkour_state == "Locomotion" or parkour_state == "PoolSwim"):
		_apply_dive_gear_gesture(skel)
	_apply_scarf_glide_pose(skel, _delta)


func _apply_scarf_glide_pose(skel: Skeleton3D, delta: float) -> void:
	if scarf_glider == null:
		return
	var phase: StringName = runner_body.scarf_glide_phase if runner_body != null else &"stowed"
	var progress := clampf(runner_body.scarf_glide_progress, 0.0, 1.0) if runner_body != null else 0.0
	var stow_open := clampf(runner_body.scarf_glide_stow_open, 0.0, 1.0) if runner_body != null else 0.0
	var bank := clampf(runner_body.scarf_glide_bank, -1.0, 1.0) if runner_body != null else 0.0
	var local_velocity := Vector3.ZERO
	if runner_body != null:
		var actor_basis := runner_body.global_transform.basis.orthonormalized()
		local_velocity = actor_basis.inverse() * runner_body.get_real_velocity()
	var other_hands_own_pose := parkour_state != "Locomotion" \
		or _wall_pose_blend > 0.005 or climb_weight > 0.005 \
		or (slide_dive_active and slide_dive_phase < 1.0) \
		or (_ledge_weight > 0.001 and (_arms[0].active or _arms[1].active)) \
		or _wade_weight > 0.002 or _swim_pose_weight > 0.002 \
		or (dive_gear != null and dive_gear.gesture_weight > 0.001)

	if other_hands_own_pose:
		# A catch, climb, swim stroke, or dive gesture takes the wrists immediately.
		_scarf_pose_blend = 0.0
		_scarf_pose_open = 0.0
		_scarf_body_weight = 0.0
		phase = &"stowed"
	else:
		var pose_open := 0.0
		var pose_target := 0.0
		var body_target := 0.0
		match phase:
			&"deploy":
				pose_open = smoothstep(0.0, 1.0, progress)
				pose_target = 1.0
				body_target = smoothstep(0.08, 0.48, progress)
			&"glide":
				pose_open = 1.0
				pose_target = 1.0
				body_target = 1.0
			&"stow":
				var eased_stow_open := smoothstep(0.0, 1.0, stow_open)
				pose_open = eased_stow_open * (1.0 - smoothstep(0.0, 1.0, progress))
				# Keep both hands pinned while the canopy gathers; release the throw hand first.
				pose_target = lerpf(0.55, 1.0, eased_stow_open)
				body_target = eased_stow_open * (1.0 - smoothstep(0.0, 0.48, progress))
			&"cancel":
				pose_open = smoothstep(0.0, 1.0, stow_open) * (1.0 - smoothstep(0.0, 1.0, progress))
				pose_target = 1.0 - smoothstep(0.35, 0.9, progress)

		var blend_rate := 1.0 - exp(-16.0 * maxf(delta, 0.0))
		var open_rate := 1.0 - exp(-18.0 * maxf(delta, 0.0))
		var body_rate := 1.0 - exp(-9.0 * maxf(delta, 0.0))
		if phase == &"stowed":
			_scarf_pose_blend = 0.0
			_scarf_pose_open = 0.0
		else:
			_scarf_pose_blend = lerpf(_scarf_pose_blend, pose_target, blend_rate)
			_scarf_pose_open = lerpf(_scarf_pose_open, pose_open, open_rate)
		_scarf_body_weight = lerpf(_scarf_body_weight, body_target, body_rate)
		if _scarf_body_weight > 0.001:
			_scarf_motion_phase = fposmod(_scarf_motion_phase + maxf(delta, 0.0) * 2.1, TAU)
			var leg_weight := _scarf_body_weight \
				if runner_body != null and not runner_body.is_on_floor() else 0.0
			_apply_scarf_glide_body_pose(skel, _scarf_body_weight, bank, local_velocity, leg_weight)
		if _scarf_pose_blend > 0.001:
			_apply_scarf_hand_ik(skel, _scarf_pose_open, _scarf_pose_blend, phase, progress, stow_open, bank)

	scarf_glider.update_pose(phase, progress, stow_open, bank, delta, local_velocity)
	scarf_glider.update_hand_pins()


func _apply_scarf_hand_ik(
	skel: Skeleton3D, open_amount: float, weight: float,
	phase: StringName, progress: float, stow_open: float, bank: float
) -> void:
	var skeleton_world := skel.global_transform
	var actor_basis := runner_body.global_transform.basis.orthonormalized()
	var actor_forward := -actor_basis.z.normalized()
	var skeleton_inverse := skeleton_world.affine_inverse()
	for side in 2:
		var arm := _arms[side]
		if arm.bones[2] < 0:
			continue
		var hand_weight := weight
		if phase == &"stow":
			var hand_release_start := 0.79 if side == 1 else 0.86
			hand_weight *= 1.0 - smoothstep(hand_release_start, 1.0, progress)
		elif phase == &"cancel":
			# Both hands release into the fall as the fold reaches the collar.
			hand_weight *= 1.0 - smoothstep(0.45, 1.0, progress)
		var upper := skeleton_world * skel.get_bone_global_pose(arm.bones[0])
		var elbow := skeleton_world * skel.get_bone_global_pose(arm.bones[1])
		var wrist := skeleton_world * skel.get_bone_global_pose(arm.bones[2])
		var shoulder_side := (actor_basis.inverse() * (upper.origin - runner_body.global_position)).x
		var side_sign := signf(shoulder_side)
		if is_zero_approx(side_sign):
			side_sign = 1.0 if side == 0 else -1.0

		# One hand catches the collar first; the other joins the same smooth sweep overhead.
		var hand_open := open_amount
		if phase == &"deploy":
			hand_open = smoothstep(0.0, 0.76, open_amount) if side == 0 \
				else smoothstep(0.18, 1.0, open_amount)
		var lateral := lerpf(0.12, 0.295, hand_open)
		var height := lerpf(0.535, 0.70, hand_open)
		var forward := lerpf(0.035, 0.105, hand_open)
		# A bank lets the outside hand float a little higher while the inside hand follows.
		height -= side_sign * bank * 0.014 * hand_open
		var target := runner_body.global_position \
			+ actor_basis.x * (side_sign * lateral) \
			+ actor_basis.y * height \
			+ actor_forward * forward
		if phase == &"stow" and side == 1:
			# Flick the loose end outward and up past the shoulder, clear of the bob.
			var eased_stow := smoothstep(0.0, 1.0, progress)
			var flick := smoothstep(0.02, 0.30, eased_stow) \
				* (1.0 - smoothstep(0.48, 0.82, eased_stow)) * smoothstep(0.12, 0.75, stow_open)
			target += actor_basis.x * (side_sign * 0.11 * flick) \
				+ actor_basis.y * (0.075 * flick) - actor_forward * (0.035 * flick)

		var upper_segment := elbow.origin - upper.origin
		var lower_segment := wrist.origin - elbow.origin
		var reach := upper_segment.length() + lower_segment.length()
		var extension := clampf(upper.origin.distance_to(target) - reach + 0.015, 0.0, 0.075)
		var reach_elbow := elbow
		reach_elbow.origin += upper_segment.normalized() * (extension * 0.48)
		var reach_wrist := wrist
		reach_wrist.origin += reach_elbow.origin - elbow.origin + lower_segment.normalized() * (extension * 0.52)
		var pole := actor_basis * Vector3(side_sign * 0.72, -0.20, 0.44)
		var solved := TwoBoneIK.solve_chain(upper, reach_elbow, reach_wrist, target, pole, true, 0.045)
		var hand: Transform3D = solved["tip"]
		var fingers := (actor_basis * Vector3(-0.30 * side_sign, 0.90, -0.21)).normalized()
		var palm_back := actor_basis * Vector3(0.37 * side_sign, 0.10, 0.92)
		hand.basis = TwoBoneIK.basis_from_forward_up(fingers, palm_back) * arm.rest_basis.inverse()
		skel.set_bone_global_pose(arm.bones[0], skeleton_inverse * _blend_world_pose(upper, solved["upper"] as Transform3D, hand_weight))
		skel.set_bone_global_pose(arm.bones[1], skeleton_inverse * _blend_world_pose(elbow, solved["lower"] as Transform3D, hand_weight))
		skel.set_bone_global_pose(arm.bones[2], skeleton_inverse * _blend_world_pose(wrist, hand, hand_weight))


func _apply_scarf_glide_body_pose(
	skel: Skeleton3D, weight: float, bank: float, local_velocity: Vector3, leg_weight: float
) -> void:
	if runner_body == null:
		return
	var actor_basis := runner_body.global_transform.basis.orthonormalized()
	var actor_forward := -actor_basis.z
	var skeleton_world := skel.global_transform
	var skeleton_inverse := skeleton_world.affine_inverse()
	var forward_ratio := clampf(-local_velocity.z / 7.8, 0.0, 1.0)
	var descent_ratio := clampf(-local_velocity.y / 8.0, 0.0, 1.0)
	var pitch := deg_to_rad(1.2 + 1.3 * forward_ratio + 0.3 * descent_ratio) * weight
	var roll := deg_to_rad(bank * 2.6) * weight
	var pitch_follow := Basis(Quaternion(actor_basis.x, -pitch))
	var bank_follow := Basis(Quaternion(actor_forward, roll))
	if _spine_bone >= 0:
		var spine_world := skeleton_world * skel.get_bone_global_pose(_spine_bone)
		spine_world.basis = (bank_follow * pitch_follow * spine_world.basis).orthonormalized()
		spine_world.origin += actor_basis.y * (sin(_scarf_motion_phase * 0.5) * 0.0025 * weight)
		skel.set_bone_global_pose(_spine_bone, skeleton_inverse * spine_world)
	if leg_weight > 0.001 and _pelvis_bone >= 0 and absf(roll) > 0.001:
		var pelvis_world := skeleton_world * skel.get_bone_global_pose(_pelvis_bone)
		var counter_roll := Basis(Quaternion(actor_forward, -roll * 0.22))
		pelvis_world.basis = (counter_roll * pelvis_world.basis).orthonormalized()
		skel.set_bone_global_pose(_pelvis_bone, skeleton_inverse * pelvis_world)

	# Keep the airborne legs soft and the boots just behind the forward path.
	if leg_weight <= 0.001:
		return
	for side in 2:
		var thigh_bone := _leg_bones[side][0]
		var calf_bone := _leg_bones[side][1]
		var foot_bone := _leg_bones[side][2]
		var sway := sin(_scarf_motion_phase + PI * side)
		var thigh_pose := skel.get_bone_pose_rotation(thigh_bone)
		var calf_pose := skel.get_bone_pose_rotation(calf_bone)
		var foot_pose := skel.get_bone_pose_rotation(foot_bone)
		var thigh_delta := -1.7 * forward_ratio + 0.55 * sway
		var calf_delta := 3.4 + 2.6 * descent_ratio + 0.65 * sway
		var foot_delta := -2.0 * forward_ratio
		skel.set_bone_pose_rotation(
			thigh_bone,
			(thigh_pose * Quaternion(Vector3.RIGHT, deg_to_rad(thigh_delta) * leg_weight)).normalized()
		)
		skel.set_bone_pose_rotation(
			calf_bone,
			(calf_pose * Quaternion(Vector3.RIGHT, deg_to_rad(calf_delta) * leg_weight)).normalized()
		)
		skel.set_bone_pose_rotation(
			foot_bone,
			(foot_pose * Quaternion(Vector3.RIGHT, deg_to_rad(foot_delta) * leg_weight)).normalized()
		)

func _apply_dive_gear_gesture(skel: Skeleton3D) -> void:
	var weight := dive_gear.gesture_weight
	var head := skel.get_bone_global_pose(dive_gear.head_bone)
	# Meet her hands halfway with a small nod while the frame passes her eyes.
	head.origin += head.basis * Vector3(0.0, -0.028, 0.015) * weight
	head.basis *= Basis(Vector3.RIGHT, 0.19 * weight)
	skel.set_bone_global_pose(dive_gear.head_bone, head)
	var face := head * dive_gear.rest_to_head
	for side in 2:
		var arm := _arms[side]
		var lateral := 1.0 if side == 0 else -1.0
		var upper := skel.get_bone_global_pose(arm.bones[0])
		var elbow := skel.get_bone_global_pose(arm.bones[1])
		var wrist := skel.get_bone_global_pose(arm.bones[2])
		var fingers := face.basis * Vector3(-0.30 * lateral, 0.90, -0.21).normalized()
		var palm_back := face.basis * Vector3(0.37 * lateral, 0.10, 0.92)
		var grip := face * dive_gear.get_grip(lateral)
		var target := grip - fingers * 0.044 + face.basis * Vector3(lateral * 0.02, 0.0, 0.017)
		var pole := face.basis * Vector3(lateral * 0.75, -0.50, 0.29)
		var upper_segment := elbow.origin - upper.origin
		var lower_segment := wrist.origin - elbow.origin
		var reach := upper_segment.length() + lower_segment.length()
		var extension := clampf(upper.origin.distance_to(target) - reach - 0.032, 0.0, 0.075)
		var reach_elbow := elbow
		reach_elbow.origin += upper_segment.normalized() * (extension * 0.48)
		var reach_wrist := wrist
		reach_wrist.origin += reach_elbow.origin - elbow.origin + lower_segment.normalized() * (extension * 0.52)
		var solved := TwoBoneIK.solve_chain(upper, reach_elbow, reach_wrist, target, pole, true, 0.038)
		var hand: Transform3D = solved["tip"]
		hand.basis = TwoBoneIK.basis_from_forward_up(fingers, palm_back) * arm.rest_basis.inverse()
		skel.set_bone_global_pose(arm.bones[0], _blend_world_pose(upper, solved["upper"] as Transform3D, weight))
		skel.set_bone_global_pose(arm.bones[1], _blend_world_pose(elbow, solved["lower"] as Transform3D, weight))
		skel.set_bone_global_pose(arm.bones[2], _blend_world_pose(wrist, hand, weight))


func reset_wade_pose() -> void:
	wade_weight_target = 0.0
	_wade_weight = 0.0
	_wade_move = 0.0
	_wade_idle_phase = 0.0


func get_wade_wrist_world(side: int) -> Vector3:
	return _wade_wrists[side] if _wade_weight > 0.25 else Vector3.INF


func set_swim_pose(turn: float, dive: float, rise: float, glide: float) -> void:
	if parkour_state != "PoolSwim":
		_clear_swim_pose_target()
		return
	_swim_turn_target = clampf(turn, -1.0, 1.0)
	_swim_dive_target = clampf(dive, 0.0, 1.0)
	_swim_rise_target = clampf(rise, 0.0, 1.0)
	_swim_glide_target = clampf(glide, 0.0, 1.0)


func _clear_swim_pose_target() -> void:
	_swim_turn_target = 0.0
	_swim_dive_target = 0.0
	_swim_rise_target = 0.0
	_swim_glide_target = 0.0


func reset_swim_pose() -> void:
	if dive_gear != null:
		dive_gear.reset()
	_clear_swim_pose_target()
	_swim_pose_weight = 0.0
	_swim_turn = 0.0
	_swim_dive = 0.0
	_swim_rise = 0.0
	_swim_glide = 0.0
	_swim_scull_phase = 0.0


func _apply_wade_arms(skel: Skeleton3D, delta: float) -> void:
	var speed := Vector2(runner_body.velocity.x, runner_body.velocity.z).length()
	_wade_move = lerpf(_wade_move, smoothstep(0.07, 0.92, speed), 1.0 - exp(-9.0 * delta))
	_wade_idle_phase = fposmod(_wade_idle_phase + delta * 2.6, TAU)
	var stride := runner_body.anim_ctrl.get_interpolated_ground_phase() * TAU if runner_body.anim_ctrl != null else 0.0
	var actor := runner_body.get_global_transform_interpolated().basis.orthonormalized()
	var skel_world := skel.global_transform

	for side in 2:
		var arm := _arms[side]
		var sign_side := -1.0 if side == 0 else 1.0
		var upper := skel_world * skel.get_bone_global_pose(arm.bones[0])
		var lower := skel_world * skel.get_bone_global_pose(arm.bones[1])
		var wrist := skel_world * skel.get_bone_global_pose(arm.bones[2])
		# Short alternating pushes. At rest the wrists trace smaller, slower arcs.
		var walk_phase := stride + PI * side
		var idle_phase := _wade_idle_phase + 1.1 * side
		var outward := lerpf(0.19 + 0.035 * cos(idle_phase), 0.21 + 0.070 * cos(walk_phase), _wade_move)
		var ahead := lerpf(0.055 + 0.045 * sin(idle_phase), 0.035 + 0.14 * sin(walk_phase), _wade_move)
		var ripple_height := lerpf(0.016 * sin(idle_phase + 0.6), 0.027 * cos(walk_phase), _wade_move)
		var target := upper.origin + actor.x * (sign_side * outward) - actor.z * ahead
		target.y = clampf(wade_surface_y + 0.018 + ripple_height, upper.origin.y - 0.30, upper.origin.y - 0.045)

		var elbow := actor * Vector3(sign_side * 0.58, -0.60, 0.52)
		var solved := TwoBoneIK.solve_chain(upper, lower, wrist, target, elbow)
		var solved_upper: Transform3D = solved["upper"]
		var solved_lower: Transform3D = solved["lower"]
		var fingers := actor * Vector3(sign_side * (0.82 - 0.24 * sin(walk_phase) * _wade_move), -0.06, -0.62)
		var palm := TwoBoneIK.basis_from_forward_up(fingers, Vector3.UP) * arm.rest_basis.inverse()
		var parent := skel_world * skel.get_bone_global_pose(skel.get_bone_parent(arm.bones[0]))
		# Blend the solved rotations in local space so partial influence keeps limb lengths.
		var local_bases: Array[Basis] = [
			parent.basis.inverse() * solved_upper.basis,
			solved_upper.basis.inverse() * solved_lower.basis,
			solved_lower.basis.inverse() * palm,
		]
		for joint in 3:
			var bone := arm.bones[joint]
			var pose := skel.get_bone_pose_rotation(bone)
			var target_rotation := local_bases[joint].orthonormalized().get_rotation_quaternion()
			skel.set_bone_pose_rotation(bone, pose.slerp(target_rotation, _wade_weight))
		_wade_wrists[side] = skel_world * skel.get_bone_global_pose(arm.bones[2]).origin


func _apply_swim_pose(skel: Skeleton3D) -> void:
	if runner_body == null:
		return
	var speed := runner_body.get_real_velocity().length()
	var idle_weight := 1.0 - smoothstep(0.08, 0.85, speed)
	var skel_world := skel.get_global_transform_interpolated()
	var skel_inv := skel_world.affine_inverse()
	var actor := skel_world.basis.orthonormalized()
	var forward := -actor.z
	var pose_strength := clampf(_swim_pose_weight, 0.0, 1.0)

	# Add short wrist arcs to the slow horizontal idle and small asymmetric pulls into turns.
	# The target offsets stay local to the animated wrist so the existing stroke remains readable.
	var arm_intent := maxf(idle_weight, maxf(absf(_swim_turn), maxf(_swim_dive, maxf(_swim_rise, _swim_glide))))
	var arm_weight := pose_strength * clampf(arm_intent, 0.0, 1.0) * 0.82
	if arm_weight > 0.001:
		for side in 2:
			var arm := _arms[side]
			var sign_side := -1.0 if side == 0 else 1.0
			var upper := skel_world * skel.get_bone_global_pose(arm.bones[0])
			var lower := skel_world * skel.get_bone_global_pose(arm.bones[1])
			var wrist := skel_world * skel.get_bone_global_pose(arm.bones[2])
			var phase := _swim_scull_phase + PI * side
			var lateral := sign_side * (0.016 * idle_weight + 0.020 * _swim_rise - 0.018 * _swim_dive)
			var ahead := 0.014 * cos(phase) * idle_weight
			ahead += 0.043 * _swim_dive + 0.040 * _swim_glide + 0.025 * _swim_rise
			ahead += 0.040 * _swim_turn * sign_side
			var lift := 0.010 * sin(phase + 0.45) * idle_weight + 0.025 * _swim_rise
			var target := wrist.origin + actor.x * lateral + forward * ahead + actor.y * lift
			var current_pole := (lower.origin - upper.origin).normalized()
			var target_pole := (actor * Vector3(sign_side * 0.58, -0.48, 0.68)).normalized()
			var directed_intent := maxf(absf(_swim_turn), maxf(_swim_dive, maxf(_swim_rise, _swim_glide)))
			var pole_blend := clampf(0.18 * idle_weight + 0.42 * directed_intent, 0.0, 0.55)
			var pole := current_pole.lerp(target_pole, pole_blend).normalized()
			var solved := TwoBoneIK.solve_chain(upper, lower, wrist, target, pole)
			var solved_upper := _blend_world_pose(upper, solved["upper"] as Transform3D, arm_weight)
			var solved_lower := _blend_world_pose(lower, solved["lower"] as Transform3D, arm_weight)
			var solved_wrist := _blend_world_pose(wrist, solved["tip"] as Transform3D, arm_weight)
			skel.set_bone_global_pose(arm.bones[0], skel_inv * solved_upper)
			skel.set_bone_global_pose(arm.bones[1], skel_inv * solved_lower)
			skel.set_bone_global_pose(arm.bones[2], skel_inv * solved_wrist)

	# Soft knees at rest; the first dive kick curls each leg in turn, then rise and glide
	# lengthen the legs again without changing Chibi's horizontal body orientation.
	var leg_intent := maxf(idle_weight, maxf(_swim_dive, maxf(_swim_rise, _swim_glide)))
	var leg_weight := pose_strength * clampf(leg_intent, 0.0, 1.0)
	if leg_weight <= 0.001:
		return
	for side in 2:
		var phase := _swim_scull_phase * 3.0 + PI * side
		var kick := _swim_dive * (0.5 + 0.5 * sin(phase))
		var thigh_bone := _leg_bones[side][0]
		var calf_bone := _leg_bones[side][1]
		var thigh_pose := skel.get_bone_pose_rotation(thigh_bone)
		var calf_pose := skel.get_bone_pose_rotation(calf_bone)
		var thigh_delta := 3.0 * idle_weight + 5.0 * kick - 2.0 * _swim_rise - 3.0 * _swim_glide
		var calf_delta := 6.0 * idle_weight + 11.0 * kick - 6.0 * _swim_rise - 3.0 * _swim_glide
		var thigh_target := (thigh_pose * Quaternion(Vector3.RIGHT, deg_to_rad(thigh_delta))).normalized()
		var calf_target := (calf_pose * Quaternion(Vector3.RIGHT, deg_to_rad(calf_delta))).normalized()
		skel.set_bone_pose_rotation(thigh_bone, thigh_pose.slerp(thigh_target, leg_weight))
		skel.set_bone_pose_rotation(calf_bone, calf_pose.slerp(calf_target, leg_weight))


func _advance_wall_climb_pose(delta: float) -> void:
	# SkeletonModifier3D runs on render frames while the climbing planner submits once
	# per physics tick. Sample the same previous/current interval Godot uses for the actor
	# and skeleton transforms so planted world contacts do not acquire render-rate steps.
	var safe_delta := maxf(delta, 0.0)
	if _tower_hanging_idle_requested or _tower_hanging_idle_blend > TOWER_HANGING_IDLE_RESET_BLEND:
		_tower_hanging_idle_elapsed += safe_delta
	else:
		_tower_hanging_idle_elapsed = 0.0
	var idle_rate := 5.0 if _tower_hanging_idle_requested else 15.0
	var idle_alpha := 1.0 - exp(-idle_rate * safe_delta)
	_tower_hanging_idle_blend = lerpf(
		_tower_hanging_idle_blend,
		1.0 if _tower_hanging_idle_requested else 0.0,
		idle_alpha
	)
	var alpha := 1.0 - exp(-WALL_CLIMB_POSE_BLEND_RATE * safe_delta)
	if _wall_pose_samples_valid and (_wall_pose_requested or _wall_pose_blend > 0.001):
		var fraction := clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
		var frame_q := _wall_frame_previous.get_rotation_quaternion().slerp(
			_wall_frame_target.get_rotation_quaternion(), fraction
		)
		_wall_frame = Basis(frame_q).orthonormalized()
		# Gaze and shoulder roll can ease through a change in intent while the
		# world-space hand and foot targets stay aligned to the sampled body.
		_wall_lean = lerpf(_wall_lean, lerpf(_wall_lean_previous, _wall_lean_target, fraction), alpha)
		_wall_look = _wall_look.lerp(_wall_look_previous.lerp(_wall_look_target, fraction), alpha)
		_wall_body_weight = lerpf(_wall_body_weight_previous, _wall_body_weight_target, fraction)
		_wall_leg_motion = _wall_leg_motion.lerp(
			_wall_leg_motion_previous.lerp(_wall_leg_motion_target, fraction), alpha
		)
		_wall_leg_lead_hand = lerpf(
			_wall_leg_lead_hand,
			lerpf(_wall_leg_lead_hand_previous, _wall_leg_lead_hand_target, fraction),
			alpha
		)
		for limb in 4:
			_wall_targets[limb] = _wall_targets_previous[limb].lerp(
				_wall_targets_target[limb], fraction
			)
			var contact_q := _wall_contact_bases_previous[limb].get_rotation_quaternion().slerp(
				_wall_contact_bases_target[limb].get_rotation_quaternion(), fraction
			)
			_wall_contact_bases[limb] = Basis(contact_q).orthonormalized()
			_wall_weights[limb] = lerpf(
				_wall_weights_previous[limb], _wall_weights_target[limb], fraction
			)

	_wall_pose_blend = lerpf(_wall_pose_blend, 1.0 if _wall_pose_requested else 0.0, alpha)


func _apply_ground_foot_ik(skel: Skeleton3D) -> void:
	var skel_world := skel.get_global_transform_interpolated()
	var skel_inv := skel_world.affine_inverse()
	var actor_basis := runner_body.get_global_transform_interpolated().basis if runner_body != null else skel_world.basis
	var pelvis_drop := 0.0
	for side in 2:
		var foot := _ground_feet[side]
		if foot.anchored and foot.weight > 0.001:
			pelvis_drop = maxf(pelvis_drop, _ground_pelvis_drop_required(skel, side, foot, foot.weight, true))
	if _pelvis_bone >= 0 and pelvis_drop > 0.001:
		var pelvis_world := skel_world * skel.get_bone_global_pose(_pelvis_bone)
		pelvis_world.origin -= Vector3.UP * pelvis_drop
		skel.set_bone_global_pose(_pelvis_bone, skel_inv * pelvis_world)

	for side in 2:
		var foot := _ground_feet[side]
		if not foot.anchored or (foot.support != null and not is_instance_valid(foot.support)):
			_ground_actual_valid[side] = false
			continue

		var bones := _leg_bones[side]
		var chain: Array[Transform3D] = []
		for bone in bones:
			chain.append(skel_world * skel.get_bone_global_pose(bone))
		if foot.weight > 0.001:
			var target_ankle := foot.sole_world() - foot.ankle_to_sole_world()
			var side_sign := -1.0 if side == 0 else 1.0
			var pole_world := (actor_basis * Vector3(side_sign * 0.36, -0.08, -1.0)).normalized()
			var solved := TwoBoneIK.solve_chain(
				chain[0], chain[1], chain[2], target_ankle, pole_world, true, GROUND_LEG_PROTRACTION_MAX
			)
			var blend := clampf(foot.weight, 0.0, 1.0)
			var upper := _blend_world_pose(chain[0], solved["upper"] as Transform3D, blend)
			var lower := _blend_world_pose(chain[1], solved["lower"] as Transform3D, blend)
			var ankle := _blend_world_pose(chain[2], solved["tip"] as Transform3D, blend)
			ankle.basis = Basis(chain[2].basis.get_rotation_quaternion().slerp(
				foot.foot_basis_world().get_rotation_quaternion(), blend
			)).orthonormalized()
			skel.set_bone_global_pose(bones[0], skel_inv * upper)
			skel.set_bone_global_pose(bones[1], skel_inv * lower)
			skel.set_bone_global_pose(bones[2], skel_inv * ankle)

		_ground_actual_sole_world[side] = _raw_ground_sole_world(
			skel,
			side,
			(skel_world * skel.get_bone_global_pose(bones[2])).origin,
			true
		)
		_ground_actual_valid[side] = true
		var actual_error := _ground_actual_sole_world[side].distance_to(foot.sole_world())
		if foot.planted and (foot.weight < 0.85 or actual_error > 0.025):
			foot.planted = false
		if not foot.planted and foot.weight >= 0.85 and actual_error <= 0.025:
			foot.planted = true
			if foot.gait_contact_active and not foot.step_emitted and runner_body != null and runner_body.anim_ctrl != null:
				runner_body.anim_ctrl.ground_foot_contact.emit(&"foot_l" if side == 0 else &"foot_r")
				foot.step_emitted = true


func _apply_balance_foot_ik(skel: Skeleton3D) -> void:
	var skel_world := skel.get_global_transform_interpolated()
	var skel_inv := skel_world.affine_inverse()
	var actor_basis := runner_body.get_global_transform_interpolated().basis
	var facing := -actor_basis.z.normalized()
	var ankle_targets: Array[Transform3D] = []
	var pelvis_drop := 0.0
	for side in 2:
		var bones := _leg_bones[side]
		var hip := (skel_world * skel.get_bone_global_pose(bones[0])).origin
		var knee := (skel_world * skel.get_bone_global_pose(bones[1])).origin
		var ankle := skel_world * skel.get_bone_global_pose(bones[2])
		var surface := runner_body.get_balance_foot_target(side)
		var normal := surface.basis.y.normalized()
		var contacts_forward := facing.slide(normal).normalized()
		var contact_basis := TwoBoneIK.basis_from_forward_up(contacts_forward, normal)
		var shoe_basis := (contact_basis * _balance_shoe_rest_basis[side].inverse()).orthonormalized()

		var ball := _ball_bones[side]
		var sole_depth := 0.035
		var ankle_to_ball := Vector3.ZERO
		if ball >= 0:
			var ball_position := (skel_world * skel.get_bone_global_pose(ball)).origin
			ankle_to_ball = ankle.basis.orthonormalized().inverse() * (ball_position - ankle.origin)
			sole_depth = 0.022
		var scale_value := skel_world.basis.get_scale().abs().length() / sqrt(3.0)
		var target := surface.origin + normal * (sole_depth * scale_value) - shoe_basis * ankle_to_ball
		ankle_targets.append(Transform3D(shoe_basis, target))

		var reach := hip.distance_to(knee) + knee.distance_to(ankle.origin) - 0.008
		var hip_offset := hip - target
		var max_height := sqrt(maxf(0.0, reach * reach - Vector2(hip_offset.x, hip_offset.z).length_squared()))
		pelvis_drop = maxf(pelvis_drop, hip_offset.y - max_height)

	if _pelvis_bone >= 0 and pelvis_drop > 0.0:
		var pelvis := skel_world * skel.get_bone_global_pose(_pelvis_bone)
		pelvis.origin.y -= minf(pelvis_drop, BALANCE_PELVIS_COMPRESSION_MAX) * _balance_weight
		skel.set_bone_global_pose(_pelvis_bone, skel_inv * pelvis)

	for side in 2:
		var bones := _leg_bones[side]
		var hip := skel_world * skel.get_bone_global_pose(bones[0])
		var knee := skel_world * skel.get_bone_global_pose(bones[1])
		var ankle := skel_world * skel.get_bone_global_pose(bones[2])
		var pole := (facing + actor_basis.x * (-0.20 if side == 0 else 0.20)).normalized()
		var target := ankle_targets[side]
		var solved := TwoBoneIK.solve_chain(hip, knee, ankle, target.origin, pole, true, GROUND_LEG_PROTRACTION_MAX)
		var corrected_foot: Transform3D = solved["tip"]
		corrected_foot.basis = target.basis
		skel.set_bone_global_pose(bones[0], skel_inv * _blend_world_pose(hip, solved["upper"], _balance_weight))
		skel.set_bone_global_pose(bones[1], skel_inv * _blend_world_pose(knee, solved["lower"], _balance_weight))
		skel.set_bone_global_pose(bones[2], skel_inv * _blend_world_pose(ankle, corrected_foot, _balance_weight))


func _blend_world_pose(from_pose: Transform3D, to_pose: Transform3D, weight: float) -> Transform3D:
	var basis := Basis(from_pose.basis.get_rotation_quaternion().slerp(
		to_pose.basis.get_rotation_quaternion(), weight
	))
	return Transform3D(basis, from_pose.origin.lerp(to_pose.origin, weight))


func _apply_dive_arc(skel: Skeleton3D, phase: float) -> void:
	if _root_bone < 0 or _pelvis_bone < 0 or runner_body == null:
		return
	var pelvis_pose := skel.get_bone_global_pose(_pelvis_bone)
	var pivot := pelvis_pose.origin
	var skel_inv_basis := skel.global_transform.basis.inverse().orthonormalized()
	var actor_basis := runner_body.global_transform.basis
	var local_right := (skel_inv_basis * actor_basis.x).normalized()
	var local_fwd := (skel_inv_basis * (-actor_basis.z)).normalized()
	var local_up := (skel_inv_basis * Vector3.UP).normalized()
	var arc := sin(PI * clampf(phase, 0.0, 1.0))
	arc = arc * arc
	var pitch_q := Quaternion(local_right, deg_to_rad(-34.0 * arc))
	var root_pose := skel.get_bone_global_pose(_root_bone)
	var new_origin := pivot + pitch_q * (root_pose.origin - pivot) + (local_fwd * 0.13 + local_up * 0.10) * arc
	var new_basis := (Basis(pitch_q) * root_pose.basis).orthonormalized()
	skel.set_bone_global_pose(_root_bone, Transform3D(new_basis, new_origin))


func _wall_hanging_idle_weight_shift(time: float) -> float:
	return 0.68 * sin(time * 0.72 + 0.45) + 0.32 * sin(time * 0.43 + 2.1)


func _wall_hanging_idle_breath(time: float) -> float:
	return sin(time * 1.32 + 0.16 * sin(time * 0.29 + 0.7))


func _wall_hanging_idle_choose_peek_side() -> float:
	var lateral_gaze := _wall_look.dot(_wall_frame.x)
	if absf(lateral_gaze) > 0.05:
		return -1.0 if lateral_gaze > 0.0 else 1.0
	# Near center, alternate between fresh holds instead of letting tiny gaze noise
	# choose a side or replaying the same large first glance on every entry.
	return -_tower_hanging_idle_peek_side


func _wall_hanging_idle_pulse(
	time: float, cycle: float, rise_start: float, rise_end: float,
	fall_start: float, fall_end: float
) -> float:
	var phase := fposmod(time, cycle)
	return smoothstep(rise_start, rise_end, phase) * (1.0 - smoothstep(fall_start, fall_end, phase))


func _apply_wall_climbing_ik(skel: Skeleton3D) -> void:
	# The modifier runs for rendered frames while anchors are authored on physics ticks.
	# Use the interpolated skeleton root so world-space contacts stay aligned to the view.
	var skel_world := skel.get_global_transform_interpolated()
	# Convert solved world poses back through the same interpolated transform. Mixing this
	# with the raw inverse makes rendered contacts drift whenever the actor is moving.
	var skel_inv := skel_world.affine_inverse()
	var wall_mix := clampf(_wall_pose_blend, 0.0, 1.0)
	var body_weight := clampf(_wall_body_weight * wall_mix, 0.0, 1.0)
	var wall_frame := _wall_frame.orthonormalized()
	var wall_right := wall_frame.x.normalized()
	var wall_up := wall_frame.y.normalized()
	var wall_outward := wall_frame.z.normalized()
	var lean_weighted := _wall_lean * body_weight
	var lean_ratio := clampf(_wall_lean / 55.0, -1.0, 1.0)
	var idle_weight := clampf(_tower_hanging_idle_blend, 0.0, 1.0)
	var idle_time := _tower_hanging_idle_elapsed
	var idle_shift := _wall_hanging_idle_weight_shift(idle_time)
	var idle_breath := _wall_hanging_idle_breath(idle_time)
	var idle_settle := _wall_hanging_idle_pulse(idle_time, 18.4, 0.025, 0.14, 0.52, 0.88)

	# Rest-like body pose prevents the locomotion clip from fighting the contacts. This
	# inset moves only the visual skeleton toward the surface; CharacterBody3D stays put.
	if body_weight > 0.001:
		for i in skel.get_bone_count():
			var rest := skel.get_bone_rest(i)
			var cur := skel.get_bone_pose(i)
			if body_weight >= 0.999:
				skel.set_bone_pose(i, rest)
			else:
				skel.set_bone_pose(i, Transform3D(
					Basis(cur.basis.get_rotation_quaternion().slerp(rest.basis.get_rotation_quaternion(), body_weight)),
					cur.origin.lerp(rest.origin, body_weight)
				))

		if _root_bone >= 0:
			var root_world := skel_world * skel.get_bone_global_pose(_root_bone)
			root_world.origin -= wall_outward * (WALL_CLIMB_BODY_INSET * body_weight)
			skel.set_bone_global_pose(_root_bone, skel_inv * root_world)

	# Hips counterbalance the shoulder roll. The shoulder line rolls toward the higher
	# hand, while a small lateral/down shift keeps the torso visually loaded on the wall.
	if _pelvis_bone >= 0 and body_weight > 0.001:
		var pelvis_world := skel_world * skel.get_bone_global_pose(_pelvis_bone)
		var idle_load := idle_weight * body_weight
		pelvis_world.origin += wall_right * (-0.014 * lean_ratio * body_weight \
			+ 0.020 * idle_shift * idle_load + 0.008 * idle_settle * idle_load) \
			- wall_up * (0.008 * body_weight) \
			+ wall_up * (0.005 * idle_breath * idle_load) \
			+ wall_outward * (0.004 * idle_shift * idle_load + 0.003 * idle_settle * idle_load)
		var pelvis_roll := Quaternion(
			wall_outward,
			deg_to_rad(-lean_weighted * 0.14 - 1.8 * idle_shift * idle_weight
				- 2.2 * idle_settle * idle_weight)
		)
		pelvis_world.basis = (Basis(pelvis_roll) * pelvis_world.basis).orthonormalized()
		skel.set_bone_global_pose(_pelvis_bone, skel_inv * pelvis_world)

	# A softly lowered pelvis gives a supported shoe a little knee bend while the
	# contact IK keeps its ankle on the authored hold. Keep this tower-only and ease it
	# as the foot weight comes on so a catch cannot tick the pelvis.
	var brace_drop := 0.0
	var brace_contact_weight := 0.0
	if _wall_leg_motion_enabled and body_weight > 0.001:
		for side in 2:
			var limb := side + 2
			var limb_weight := clampf(_wall_weights[limb] * wall_mix, 0.0, 1.0)
			var brace_weight := smoothstep(0.63, 0.91, limb_weight)
			if brace_weight <= 0.001:
				continue
			brace_contact_weight = maxf(brace_contact_weight, brace_weight)
			var bones := _leg_bones[side]
			var hip := (skel_world * skel.get_bone_global_pose(bones[0])).origin
			var knee := (skel_world * skel.get_bone_global_pose(bones[1])).origin
			var ankle := (skel_world * skel.get_bone_global_pose(bones[2])).origin
			var reach := hip.distance_to(knee) + knee.distance_to(ankle)
			var to_target := _wall_targets[limb] - hip
			if reach < 0.001 or to_target.dot(wall_up) > -0.06:
				continue
			var direction := to_target.normalized()
			var downward_gain := maxf(0.55, -direction.dot(wall_up))
			var needed := maxf(0.0, to_target.length() - reach * 0.978)
			brace_drop = maxf(brace_drop, minf(0.028, needed / downward_gain) * brace_weight)
	if _pelvis_bone >= 0 and (brace_drop > 0.001 or brace_contact_weight > 0.001):
		var pelvis_world := skel_world * skel.get_bone_global_pose(_pelvis_bone)
		var push_rise := 0.008 * _wall_leg_motion.x * brace_contact_weight * wall_mix
		pelvis_world.origin += wall_up * (push_rise - brace_drop * body_weight)
		skel.set_bone_global_pose(_pelvis_bone, skel_inv * pelvis_world)

	if _spine_bone >= 0 and (absf(lean_weighted) > 0.01 or idle_weight > 0.001):
		var spine_world := skel_world * skel.get_bone_global_pose(_spine_bone)
		var spine_roll := Quaternion(
			wall_outward,
			deg_to_rad(lean_weighted + 3.4 * idle_shift * idle_weight
				+ 3.2 * idle_settle * idle_weight)
		)
		spine_world.basis = (Basis(spine_roll) * spine_world.basis).orthonormalized()
		spine_world.origin += wall_right * (0.006 * lean_ratio * body_weight \
			- 0.006 * idle_shift * idle_weight * body_weight - 0.008 * idle_settle * idle_weight * body_weight) \
			+ wall_outward * (0.008 * idle_breath * idle_weight * body_weight) \
			+ wall_up * (0.003 * idle_breath * idle_weight * body_weight \
				+ 0.002 * idle_settle * idle_weight * body_weight)
		skel.set_bone_global_pose(_spine_bone, skel_inv * spine_world)

	_apply_wall_climb_gaze(skel, skel_world, skel_inv, wall_frame, wall_mix, body_weight, lean_weighted)

	# Solve each limb independently so locked contacts, reaches, and airborne limbs can
	# carry different weights. Contact bases orient palms and shoes to their real support.
	for limb in 4:
		var limb_weight := clampf(_wall_weights[limb] * wall_mix, 0.0, 1.0)
		var free_leg_pose := limb >= 2 and _wall_leg_motion_enabled and wall_mix > 0.001
		if limb_weight <= 0.001 and not free_leg_pose:
			continue

		var bones: PackedInt32Array = _arms[limb].bones if limb < 2 else _leg_bones[limb - 2]
		var upper := skel_world * skel.get_bone_global_pose(bones[0])
		var lower := skel_world * skel.get_bone_global_pose(bones[1])
		var tip := skel_world * skel.get_bone_global_pose(bones[2])
		var target := tip.origin.lerp(_wall_targets[limb], limb_weight)
		var side_sign := 1.0 if (limb % 2) == 1 else -1.0
		var pole_local := Vector3(side_sign, -1.0, 0.6) if limb < 2 else Vector3(side_sign * 0.72, 0.08, 1.0)
		var free_idle_weight := 0.0
		if limb >= 2 and free_leg_pose:
			var reach := upper.origin.distance_to(lower.origin) + lower.origin.distance_to(tip.origin)
			free_idle_weight = idle_weight * (1.0 - smoothstep(0.20, 0.55, limb_weight))
			var free_target := _wall_climb_free_foot_target(
				upper.origin, reach, limb - 2, wall_right, wall_up, wall_outward,
				free_idle_weight
			)
			var free_blend := (1.0 - smoothstep(0.62, 0.88, limb_weight)) * wall_mix
			target = target.lerp(free_target, free_blend)
		var pole_world := (wall_frame * pole_local).normalized()
		var allow_protract := true
		var max_protract := 0.06 if limb < 2 else 0.02
		var solved := TwoBoneIK.solve_chain(upper, lower, tip, target, pole_world, allow_protract, max_protract)

		var contact_basis := _wall_contact_bases[limb].orthonormalized()
		var desired_tip_basis: Basis
		if limb < 2:
			desired_tip_basis = contact_basis * _arms[limb].rest_basis.inverse()
		else:
			var foot_side := limb - 2
			# Plant the toe into the lip, with the shoe top following the support's up axis.
			var foot_frame := TwoBoneIK.basis_from_forward_up(-contact_basis.z, contact_basis.y)
			desired_tip_basis = foot_frame * _foot_contact_rest_basis[foot_side].inverse()
		var solved_tip: Transform3D = solved["tip"]
		solved_tip.basis = Basis(tip.basis.get_rotation_quaternion().slerp(
			desired_tip_basis.get_rotation_quaternion(), limb_weight
		)).orthonormalized()
		if limb >= 2 and free_idle_weight > 0.001:
			# A loose shoe softly points and rolls at the ankle. Contact-weighted
			# gating above leaves a planted shoe's authored basis completely alone.
			var ankle_phase := idle_time * (1.08 if limb == 2 else 0.79) \
				+ (0.45 if limb == 2 else 2.20)
			var ankle_pitch := 5.5 * sin(ankle_phase + 0.28) \
				+ 2.0 * pow(maxf(0.0, sin(ankle_phase * 0.71 + 1.1)), 2.0)
			var ankle_roll := side_sign * (2.0 * sin(ankle_phase * 0.63 + 0.9) \
				+ 1.1 * pow(maxf(0.0, sin(ankle_phase * 1.17 + 0.4)), 2.0))
			var ankle_accent := Quaternion(wall_right, deg_to_rad(ankle_pitch * free_idle_weight)) \
				* Quaternion(wall_up, deg_to_rad(ankle_roll * free_idle_weight))
			solved_tip.basis = (Basis(ankle_accent) * solved_tip.basis).orthonormalized()

		skel.set_bone_global_pose(bones[0], skel_inv * (solved["upper"] as Transform3D))
		skel.set_bone_global_pose(bones[1], skel_inv * (solved["lower"] as Transform3D))
		skel.set_bone_global_pose(bones[2], skel_inv * solved_tip)


func _wall_climb_free_foot_target(
	hip: Vector3, reach: float, side: int,
	wall_right: Vector3, wall_up: Vector3, wall_outward: Vector3,
	idle_weight: float
) -> Vector3:
	var side_sign := -1.0 if side == 0 else 1.0
	# Keep this left/right difference steady when the lead hand changes. Only the
	# movement envelopes below alternate the stepping leg.
	var hang_direction := (-wall_up * 0.98 + wall_outward * 0.15 + wall_right * side_sign * 0.08).normalized()
	var hang_ratio := 0.958 if side == 0 else 0.970
	var hanging := hip + hang_direction * (reach * hang_ratio)
	var lead_foot := 1.0 - clampf(_wall_leg_lead_hand, 0.0, 1.0)
	var lead_match := clampf(1.0 - absf(float(side) - lead_foot), 0.0, 1.0)

	var push_direction := (-wall_up * 0.985 + wall_outward * 0.13 + wall_right * side_sign * 0.05).normalized()
	var pushed := hip + push_direction * (reach * 0.982)
	hanging = hanging.lerp(pushed, _wall_leg_motion.x * (0.72 + 0.28 * lead_match))

	var tuck_direction := (-wall_up * 0.78 + wall_outward * 0.57 + wall_right * side_sign * 0.17).normalized()
	var tucked := hip + tuck_direction * (reach * 0.930)
	hanging = hanging.lerp(tucked, _wall_leg_motion.y * (0.76 + 0.24 * lead_match))

	var step_direction := (-wall_up * 0.80 + wall_outward * 0.48 + wall_right * side_sign * 0.36).normalized()
	var stepping := hip + step_direction * (reach * 0.945)
	hanging = hanging.lerp(stepping, _wall_leg_motion.w * lead_match)
	hanging = hanging.lerp(hip + hang_direction * (reach * hang_ratio), _wall_leg_motion.z)
	if idle_weight > 0.001:
		# Let each loose shoe search on a different lazy rhythm. The supported shoe is
		# excluded by the contact-weighted blend above and keeps its world-space anchor.
		var idle_time := _tower_hanging_idle_elapsed
		var phase := idle_time * (0.84 if side == 0 else 0.67) \
			+ 0.13 * sin(idle_time * 0.23 + float(side) * 1.4) \
			+ (0.65 if side == 0 else 2.05)
		var sway := sin(phase) * 0.62 + sin(phase * 0.53 + float(side) * 0.8) * 0.38
		var kick := pow(maxf(0.0, sin(phase * 0.70 + 1.1)), 2.0)
		var secondary_kick := pow(maxf(0.0, sin(phase * 1.23 + float(side) * 1.7)), 3.0)
		var idle_offset := wall_right * (side_sign * 0.016 * sway) \
			+ wall_outward * (0.026 * kick + 0.007 * secondary_kick) \
			+ wall_up * (0.014 * kick + 0.005 * secondary_kick)
		hanging += idle_offset * idle_weight
	return hanging


func _apply_wall_climb_gaze(
	skel: Skeleton3D, skel_world: Transform3D, skel_inv: Transform3D,
	wall_frame: Basis, wall_mix: float, body_weight: float, lean: float
) -> void:
	var inward := -wall_frame.z
	var look := _wall_look if _wall_look.length_squared() > 1e-8 else inward + wall_frame.y * 0.2
	var idle_weight := clampf(_tower_hanging_idle_blend, 0.0, 1.0)
	var idle_yaw_offset := 0.0
	var idle_pitch_offset := 0.0
	if idle_weight > 0.001:
		# Let Chibi look away from the current route gaze as her grip settles, then
		# vary the side, height, and length of later checks instead of twitching.
		var time := _tower_hanging_idle_elapsed
		var settle_glance := _wall_hanging_idle_pulse(time, 18.4, 0.07, 0.22, 0.58, 1.05)
		var nearby_check := _wall_hanging_idle_pulse(time, 18.4, 2.55, 2.92, 3.50, 4.02)
		var opposite_check := _wall_hanging_idle_pulse(time, 18.4, 5.42, 5.78, 6.44, 7.04)
		var look_up := _wall_hanging_idle_pulse(time, 18.4, 8.82, 9.18, 9.90, 10.56)
		var over_shoulder := _wall_hanging_idle_pulse(time, 18.4, 12.56, 12.94, 13.96, 14.68)
		var final_check := _wall_hanging_idle_pulse(time, 18.4, 16.22, 16.48, 16.98, 17.42)
		var peek_side := _tower_hanging_idle_peek_side
		idle_yaw_offset = peek_side * (
			28.0 * settle_glance - 16.0 * nearby_check + 13.0 * opposite_check
			- 7.0 * look_up - 30.0 * over_shoulder + 14.0 * final_check
		) * idle_weight
		idle_pitch_offset = (
			6.0 * settle_glance + 4.0 * nearby_check - 2.0 * opposite_check
			+ 15.0 * look_up + 3.0 * over_shoulder + 8.0 * final_check
		) * idle_weight
	var lateral := look.dot(wall_frame.x)
	var ahead := maxf(0.10, look.dot(inward))
	var yaw := clampf(atan2(lateral, ahead), deg_to_rad(-52.0), deg_to_rad(52.0))
	var pitch := clampf(
		atan2(look.dot(wall_frame.y), Vector2(lateral, ahead).length()),
		deg_to_rad(-22.0), deg_to_rad(43.0)
	)
	yaw = clampf(yaw + deg_to_rad(idle_yaw_offset), deg_to_rad(-52.0), deg_to_rad(52.0))
	pitch = clampf(pitch + deg_to_rad(idle_pitch_offset), deg_to_rad(-22.0), deg_to_rad(43.0))
	var level := inward * cos(yaw) + wall_frame.x * sin(yaw)
	var facing := level * cos(pitch) + wall_frame.y * sin(pitch)
	var gaze_up := wall_frame.y.rotated(facing.normalized(), deg_to_rad(-lean * 0.22))
	var gaze_basis := TwoBoneIK.basis_from_forward_up(facing, gaze_up)
	if _neck_bone >= 0:
		var neck_world := skel_world * skel.get_bone_global_pose(_neck_bone)
		var neck_goal := gaze_basis * _wall_neck_bind_offset
		var neck_weight := wall_mix * (0.38 if _head_bone >= 0 else 1.0)
		neck_world.basis = neck_world.basis.orthonormalized().slerp(neck_goal, neck_weight)
		neck_world.origin += wall_frame.z * (0.018 * body_weight)
		skel.set_bone_global_pose(_neck_bone, skel_inv * neck_world)
	if _head_bone >= 0:
		var head_world := skel_world * skel.get_bone_global_pose(_head_bone)
		var head_goal := gaze_basis * _wall_head_bind_offset
		if idle_weight > 0.001:
			var time := _tower_hanging_idle_elapsed
			var shift := _wall_hanging_idle_weight_shift(time)
			var breath := _wall_hanging_idle_breath(time)
			var settle := _wall_hanging_idle_pulse(time, 18.4, 0.025, 0.14, 0.52, 0.88)
			var roll := deg_to_rad((1.8 * sin(time * 0.47 + 0.7) + 0.6 * sin(time * 0.21 + 2.2) \
				+ 0.9 * shift + 0.7 * settle) * idle_weight)
			var nod := deg_to_rad((0.5 + 0.5 * breath) * idle_weight)
			var head_tilt := Quaternion(facing.normalized(), roll) \
				* Quaternion(wall_frame.x.normalized(), nod)
			head_goal = Basis(head_tilt) * head_goal
		head_world.basis = head_world.basis.orthonormalized().slerp(head_goal, wall_mix)
		skel.set_bone_global_pose(_head_bone, skel_inv * head_world)


func _apply_ledge_ik(skel: Skeleton3D) -> void:
	var skel_world := skel.global_transform
	var skel_inv := skel_world.affine_inverse()

	var chains: Array = [[], []]
	var arm_reach := [0.0, 0.0]
	for side in 2:
		if not _arms[side].active:
			continue
		var c: Array[Transform3D] = []
		for i in 3:
			c.append(skel_world * skel.get_bone_global_pose(_arms[side].bones[i]))
		chains[side] = c
		var length := c[0].origin.distance_to(c[1].origin) + c[1].origin.distance_to(c[2].origin)
		arm_reach[side] = 0.95 * length

	# 3-pass chest reach projection so rounded corners never leave a hand hovering
	var body_shift := Vector3.ZERO
	for _pass in 3:
		for side in 2:
			if not _arms[side].active:
				continue
			var shoulder_pos: Vector3 = chains[side][0].origin
			var reach_vec := _arms[side].wrist_world - shoulder_pos - body_shift
			var dist := reach_vec.length()
			if dist > arm_reach[side] and dist > 1e-6:
				body_shift += (reach_vec / dist) * (dist - arm_reach[side])

	var max_shift := 3.5 * maxf(arm_reach[0], arm_reach[1])
	if body_shift.length() > max_shift and max_shift > 0.0:
		body_shift = body_shift.normalized() * max_shift
	body_shift *= _ledge_weight

	if _root_bone >= 0 and body_shift.length_squared() > 1e-8:
		var root_pose := skel.get_bone_global_pose(_root_bone)
		root_pose.origin += skel_inv.basis * body_shift
		skel.set_bone_global_pose(_root_bone, root_pose)

	var actor_basis := runner_body.global_transform.basis if runner_body else skel_world.basis
	for side in 2:
		if not _arms[side].active:
			continue
		var c: Array = chains[side]
		for i in 3:
			var t: Transform3D = c[i]
			t.origin += body_shift
			c[i] = t

		var wrist_target := (c[2] as Transform3D).origin.lerp(_arms[side].wrist_world, _ledge_weight)
		# Elbow pole points back (+Z), outward (+/-X), and slightly down (-Y) in Godot actor space
		var pole_local := Vector3(0.13 if side == 1 else -0.13, -0.09, 0.10)
		var pole_world := actor_basis * pole_local

		var solved := TwoBoneIK.solve_chain(c[0], c[1], c[2], wrist_target, pole_world, false)
		var hand_q := (c[2] as Transform3D).basis.get_rotation_quaternion().slerp(
			_arms[side].hand_basis_world.get_rotation_quaternion(), _ledge_weight
		)
		var tip_t: Transform3D = solved["tip"]
		tip_t.basis = Basis(hand_q).orthonormalized()

		skel.set_bone_global_pose(_arms[side].bones[0], skel_inv * (solved["upper"] as Transform3D))
		skel.set_bone_global_pose(_arms[side].bones[1], skel_inv * (solved["lower"] as Transform3D))
		skel.set_bone_global_pose(_arms[side].bones[2], skel_inv * tip_t)


func _apply_climbing_ik(skel: Skeleton3D) -> void:
	var skel_world := skel.global_transform
	var skel_inv := skel_world.affine_inverse()
	var w := climb_weight

	# Start from rest pose blended with animated pose so climbing never accumulates twist
	for i in skel.get_bone_count():
		var rest := skel.get_bone_rest(i)
		var cur := skel.get_bone_pose(i)
		if w >= 0.999:
			skel.set_bone_pose(i, rest)
		else:
			skel.set_bone_pose(i, Transform3D(
				Basis(cur.basis.get_rotation_quaternion().slerp(rest.basis.get_rotation_quaternion(), w)),
				cur.origin.lerp(rest.origin, w)
			))

	# Roll spine_01 toward higher grip (around wall forward -Z axis)
	if _spine_bone >= 0 and absf(climb_lean_deg) > 0.01:
		var spine_w := skel_world * skel.get_bone_global_pose(_spine_bone)
		var wall_fwd := (-climb_station_basis.z).normalized()
		var roll_q := Quaternion(wall_fwd, deg_to_rad(climb_lean_deg * w))
		spine_w.basis = (Basis(roll_q) * spine_w.basis).orthonormalized()
		skel.set_bone_global_pose(_spine_bone, skel_inv * spine_w)

	# Keep gaze up the route while ribcage rolls underneath head
	if _neck_bone >= 0:
		var neck_w := skel_world * skel.get_bone_global_pose(_neck_bone)
		var wall_fwd := (-climb_station_basis.z).normalized()
		var wall_right := climb_station_basis.x.normalized()
		neck_w.origin -= wall_fwd * (0.025 * w)
		var gaze_q := Quaternion(wall_right, deg_to_rad(22.0 * w)) * Quaternion(wall_fwd, deg_to_rad(-climb_lean_deg * 0.75 * w))
		neck_w.basis = (Basis(gaze_q) * neck_w.basis).orthonormalized()
		skel.set_bone_global_pose(_neck_bone, skel_inv * neck_w)

	# Solve all 4 limbs (0=L hand, 1=R hand, 2=L foot, 3=R foot)
	for limb in 4:
		var bones: PackedInt32Array = _arms[limb].bones if limb < 2 else _leg_bones[limb - 2]
		var upper := skel_world * skel.get_bone_global_pose(bones[0])
		var lower := skel_world * skel.get_bone_global_pose(bones[1])
		var tip := skel_world * skel.get_bone_global_pose(bones[2])
		var target := tip.origin.lerp(climb_limb_targets_world[limb], w)

		# Pole vectors in station space (+Z toward climber, -Z into wall, +X right, +Y up)
		var side_sign := 1.0 if (limb % 2 == 1) else -1.0
		var pole_local := Vector3(side_sign * 1.0, -1.0, 0.6) if limb < 2 else Vector3(side_sign * 0.65, 0.15, -0.8)
		var pole_world := (climb_station_basis * pole_local).normalized()

		var allow_protract := (limb < 2) or (not climb_is_rope_net)
		var max_protract := 0.06 if limb < 2 else 0.02
		var solved := TwoBoneIK.solve_chain(upper, lower, tip, target, pole_world, allow_protract, max_protract)

		var tip_t: Transform3D = solved["tip"]
		tip_t.basis = tip.basis
		skel.set_bone_global_pose(bones[0], skel_inv * (solved["upper"] as Transform3D))
		skel.set_bone_global_pose(bones[1], skel_inv * (solved["lower"] as Transform3D))
		skel.set_bone_global_pose(bones[2], skel_inv * tip_t)


