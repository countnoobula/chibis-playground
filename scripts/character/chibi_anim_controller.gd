class_name ChibiAnimController
extends Node

## Builds the AnimationTree over the imported GLB clips and maps gameplay actions to poses.

signal ground_foot_contact(side: StringName)

const GAIT_PATH := "parameters/LocomotionGait/"
const TRAVERSAL_STATES := ["SpeedVault", "MantleUp"]
const ROPE_CUT_STATES := ["RopeHang", "RopeClimb", "RopeDrop"]
const LEFT_STRIKE_PHASE := 0.0
const RIGHT_STRIKE_PHASE := 0.5
# The authored low-foot window is about 0.105 cycles. Include the approach and
# toe-off blends so a contact can span two rendered poses at 30 FPS.
const GROUND_CONTACT_DURATION := 0.15
const RUNNING_LANDING_DURATION := 0.14
const SWIM_GAIT_BLEND_TIME := 0.26
const SWIM_IDLE_CADENCE := 0.32
const SWIM_GLIDE_CADENCE := 0.16
const WADE_CYCLE_DISTANCE := 1.24
const WADE_MAX_CYCLES_PER_SECOND := 1.42

const LOOPING_ANIMS := [
	"Anim_Chibi_Idle", "Anim_Chibi_Run", "Anim_Chibi_Sprint",
	"Anim_Chibi_FallLoop", "Anim_Chibi_FallFlail",
	"Anim_Chibi_LedgeHang", "Anim_Chibi_ShimmyL", "Anim_Chibi_ShimmyR",
	"Anim_Chibi_WallRunL", "Anim_Chibi_WallRunR",
	"Anim_Chibi_Slide",
	"Anim_Chibi_BounceAir", "Anim_Chibi_PolePerch",
	"Anim_Chibi_BeamIdle", "Anim_Chibi_BeamWalk",
	"Anim_Chibi_SlothHang", "Anim_Chibi_SlothCrawl",
	"Anim_Chibi_ZipGlide",
	"Anim_Chibi_RopeSwing", "Anim_Chibi_RopeSwingFwd", "Anim_Chibi_RopeSwingBack",
	"Anim_Chibi_Swim", "Anim_Chibi_SurfaceSwim", "Anim_Chibi_TreadWater",
]

const STATE_TO_ANIM := {
	"JumpStart": "Anim_Chibi_JumpStart",
	"FallLoop": "Anim_Chibi_FallLoop",
	"FallFlail": "Anim_Chibi_FallFlail",
	"LandSoft": "Anim_Chibi_LandSoft",
	"SpeedVault": "Anim_Chibi_SpeedVault",
	"LedgeHang": "Anim_Chibi_LedgeHang",
	"ShimmyL": "Anim_Chibi_ShimmyL",
	"ShimmyR": "Anim_Chibi_ShimmyR",
	"CornerL": "Anim_Chibi_CornerL",
	"CornerR": "Anim_Chibi_CornerR",
	"MantleUp": "Anim_Chibi_MantleUp",
	"WallRunL": "Anim_Chibi_WallRunL",
	"WallRunR": "Anim_Chibi_WallRunR",
	"WallKick": "Anim_Chibi_WallKick",
	"Slide": "Anim_Chibi_Slide",
	"LandRoll": "Anim_Chibi_LandRoll",
	"BounceAir": "Anim_Chibi_BounceAir",
	"PolePerch": "Anim_Chibi_PolePerch",
	"BeamIdle": "Anim_Chibi_BeamIdle",
	"BeamWalk": "Anim_Chibi_BeamWalk",
	"RopeHang": "Anim_Chibi_SlothHang",
	"RopeClimb": "Anim_Chibi_SlothCrawl",
	"RopeDrop": "Anim_Chibi_SlothDrop",
	"ZipGlide": "Anim_Chibi_ZipGlide",
	"RopeSwing": "Anim_Chibi_RopeSwing",
	"RopeSwingFwd": "Anim_Chibi_RopeSwingFwd",
	"RopeSwingBack": "Anim_Chibi_RopeSwingBack",
}

var anim_tree: AnimationTree
var anim_player: AnimationPlayer
var current_state: String = "LocomotionGait"

var _playback: AnimationNodeStateMachinePlayback
var _swim_gait_blend_curve: Curve
var _ground_weight: float = 0.0
var _sprint_blend: float = 0.0
var _run_clip_length: float = 1.0
var _sprint_clip_length: float = 1.0
var _ground_phase_previous: float = 0.0
var _ground_phase: float = 0.0
var _running_landing_elapsed: float = RUNNING_LANDING_DURATION
var _running_landing_strength: float = 0.0
var _skeleton: Skeleton3D
var _pelvis_bone: int = -1
var _spine_bone: int = -1
var _phase_state: String = ""
var _beam_clip_length := 0.0
var _beam_phase := 0.0
var _previous_beam_phase := 0.0
var _phase_length: float = 0.0
var _previous_action_phase: float = 0.0
var _action_phase: float = 0.0


func setup(player: AnimationPlayer, tree: AnimationTree) -> void:
	anim_player = player
	anim_tree = tree
	if anim_player == null or anim_tree == null:
		return
	var search_root: Node = anim_player
	while search_root != null and _skeleton == null:
		_skeleton = _find_skeleton(search_root)
		search_root = search_root.get_parent()
	if _skeleton == null:
		search_root = anim_tree
		while search_root != null and _skeleton == null:
			_skeleton = _find_skeleton(search_root)
			search_root = search_root.get_parent()
	if _skeleton != null:
		_pelvis_bone = _skeleton.find_bone("pelvis")
		_spine_bone = _skeleton.find_bone("spine_01")

	# Ensure loop modes and continuous quaternion hemispheres on every imported clip
	for anim_name in anim_player.get_animation_list():
		var anim := anim_player.get_animation(anim_name)
		if anim != null:
			anim.loop_mode = Animation.LOOP_LINEAR if (anim_name in LOOPING_ANIMS) else Animation.LOOP_NONE
			_rectify_anim_quaternions(anim)
	var run_clip := anim_player.get_animation(&"Anim_Chibi_Run")
	var sprint_clip := anim_player.get_animation(&"Anim_Chibi_Sprint")
	if run_clip != null:
		_run_clip_length = maxf(run_clip.length, 0.001)
	if sprint_clip != null:
		_sprint_clip_length = maxf(sprint_clip.length, 0.001)

	var root_sm := AnimationNodeStateMachine.new()
	_swim_gait_blend_curve = Curve.new()
	_swim_gait_blend_curve.add_point(Vector2.ZERO)
	_swim_gait_blend_curve.add_point(Vector2.ONE)

	root_sm.add_node("LocomotionGait", _make_ground_gait(), Vector2.ZERO)

	# Keep the underwater idle on the horizontal swim pose. Blend2 sync keeps both
	# branches advancing during transitions; the slower idle cadence can still drift in phase.
	var swim_tree := AnimationNodeBlendTree.new()
	var n_swim := AnimationNodeAnimation.new()
	n_swim.animation = "Anim_Chibi_Swim"
	var n_idle_swim := AnimationNodeAnimation.new()
	n_idle_swim.animation = "Anim_Chibi_Swim"
	var n_surface := AnimationNodeAnimation.new()
	n_surface.animation = "Anim_Chibi_SurfaceSwim"
	var n_tread := AnimationNodeAnimation.new()
	n_tread.animation = "Anim_Chibi_TreadWater"
	var b_tread := AnimationNodeBlend2.new()
	b_tread.sync = true
	var b_deep_idle := AnimationNodeBlend2.new()
	b_deep_idle.sync = true
	var b_surface := AnimationNodeBlend2.new()
	b_surface.sync = true
	var t_idle := AnimationNodeTimeScale.new()
	var t_tread := AnimationNodeTimeScale.new()
	var t_scale := AnimationNodeTimeScale.new()

	swim_tree.add_node("SwimClip", n_swim, Vector2(-420, -80))
	swim_tree.add_node("DeepIdleClip", n_idle_swim, Vector2(-420, 0))
	swim_tree.add_node("SurfaceClip", n_surface, Vector2(-420, 60))
	swim_tree.add_node("TreadClip", n_tread, Vector2(-420, 180))
	swim_tree.add_node("DeepIdleSpeed", t_idle, Vector2(-220, -20))
	swim_tree.add_node("TreadSpeed", t_tread, Vector2(-220, 210))
	swim_tree.add_node("DeepIdleBlend", b_deep_idle, Vector2(0, -100))
	swim_tree.add_node("TreadBlend", b_tread, Vector2(0, 130))
	swim_tree.add_node("SurfaceBlend", b_surface, Vector2(220, 0))
	swim_tree.add_node("SwimSpeed", t_scale, Vector2(180, 0))
	swim_tree.connect_node("DeepIdleSpeed", 0, "DeepIdleClip")
	swim_tree.connect_node("TreadSpeed", 0, "TreadClip")
	swim_tree.connect_node("DeepIdleBlend", 0, "SwimClip")
	swim_tree.connect_node("DeepIdleBlend", 1, "DeepIdleSpeed")
	swim_tree.connect_node("TreadBlend", 0, "SurfaceClip")
	swim_tree.connect_node("TreadBlend", 1, "TreadSpeed")
	swim_tree.connect_node("SurfaceBlend", 0, "DeepIdleBlend")
	swim_tree.connect_node("SurfaceBlend", 1, "TreadBlend")
	swim_tree.connect_node("SwimSpeed", 0, "SurfaceBlend")
	swim_tree.connect_node("output", 0, "SwimSpeed")
	root_sm.add_node("Swim", swim_tree, Vector2(0, 180))

	# Single-clip states can be retimed without changing the imported animations.
	var row := 0
	for state_key in STATE_TO_ANIM:
		var clip_name: String = STATE_TO_ANIM[state_key]
		if not anim_player.has_animation(clip_name):
			continue
		var sub := AnimationNodeBlendTree.new()
		var clip := AnimationNodeAnimation.new()
		clip.animation = clip_name
		var ts := AnimationNodeTimeScale.new()
		sub.add_node("Clip", clip, Vector2(-180, 0))
		sub.add_node("Scale", ts, Vector2(0, 0))
		sub.connect_node("Scale", 0, "Clip")
		if state_key in TRAVERSAL_STATES or state_key == "BeamWalk":
			var seek := AnimationNodeTimeSeek.new()
			sub.add_node("Phase", seek, Vector2(160, 0))
			sub.connect_node("Phase", 0, "Scale")
			sub.connect_node("output", 0, "Phase")
		else:
			sub.connect_node("output", 0, "Scale")
		root_sm.add_node(state_key, sub, Vector2(260 + (row % 4) * 180, (row / 4) * 90))
		row += 1

	# Default entry transition into LocomotionGait
	var start_tr := AnimationNodeStateMachineTransition.new()
	start_tr.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	root_sm.add_transition("Start", "LocomotionGait", start_tr)

	anim_tree.tree_root = root_sm
	anim_tree.anim_player = anim_tree.get_path_to(anim_player)
	anim_tree.active = true
	_playback = anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	process_priority = anim_tree.process_priority - 1
	anim_tree.mixer_applied.connect(_on_animation_applied)
	for state_key: String in TRAVERSAL_STATES:
		if root_sm.has_node(state_key):
			anim_tree.set("parameters/%s/Scale/scale" % state_key, 0.0)

	if root_sm.has_node("BeamWalk"):
		_beam_clip_length = anim_player.get_animation(STATE_TO_ANIM["BeamWalk"]).length
		anim_tree.set("parameters/BeamWalk/Scale/scale", 0.0)
	# Apply Unreal's rope-climb clip speed.
	if anim_tree.get("parameters/RopeClimb/Scale/scale") != null:
		anim_tree.set("parameters/RopeClimb/Scale/scale", 3.2)
	reset_for_respawn()


func _make_ground_gait() -> AnimationNodeBlendTree:
	var tree := AnimationNodeBlendTree.new()
	var idle := AnimationNodeAnimation.new()
	idle.animation = &"Anim_Chibi_Idle"
	var run := AnimationNodeAnimation.new()
	run.animation = &"Anim_Chibi_Run"
	run.use_custom_timeline = true
	run.timeline_length = 1.0
	run.stretch_time_scale = true
	run.loop_mode = Animation.LOOP_LINEAR
	var sprint := AnimationNodeAnimation.new()
	sprint.animation = &"Anim_Chibi_Sprint"
	sprint.use_custom_timeline = true
	sprint.timeline_length = 1.0
	sprint.stretch_time_scale = true
	sprint.loop_mode = Animation.LOOP_LINEAR
	var strides := AnimationNodeBlendSpace1D.new()
	strides.min_space = 0.0
	strides.max_space = 1.0
	strides.sync_mode = AnimationNodeBlendSpace1D.SYNC_MODE_CYCLIC_MUTABLE
	strides.add_blend_point(run, 0.0, -1, "Run")
	strides.add_blend_point(sprint, 1.0, -1, "Sprint")
	var idle_blend := AnimationNodeBlend2.new()
	idle_blend.sync = true
	var ground_phase := AnimationNodeTimeSeek.new()
	ground_phase.explicit_elapse = false
	tree.add_node("Idle", idle, Vector2(-420, -60))
	tree.add_node("Strides", strides, Vector2(-420, 100))
	tree.add_node("GroundPhase", ground_phase, Vector2(-230, 100))
	tree.add_node("IdleBlend", idle_blend, Vector2(-50, 0))
	tree.connect_node("GroundPhase", 0, "Strides")
	tree.connect_node("IdleBlend", 0, "Idle")
	tree.connect_node("IdleBlend", 1, "GroundPhase")
	tree.connect_node("output", 0, "IdleBlend")
	return tree


func _rectify_anim_quaternions(anim: Animation) -> void:
	for ti in anim.get_track_count():
		if anim.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
			continue
		var kc := anim.track_get_key_count(ti)
		if kc < 2:
			continue
		var prev_q: Quaternion = anim.track_get_key_value(ti, 0)
		for ki in range(1, kc):
			var q: Quaternion = anim.track_get_key_value(ti, ki)
			if prev_q.dot(q) < 0.0:
				q = -q
				anim.track_set_key_value(ti, ki, q)
			prev_q = q


func set_locomotion_gait(planar_speed: float, config: ParkourConfig, delta: float, wade_weight: float = 0.0) -> String:
	var response := 1.0 - exp(-15.0 * delta)
	var move_weight := smoothstep(config.run_anim_threshold, config.base_run_speed * 0.55, planar_speed)
	move_weight = lerpf(move_weight, 0.60 * smoothstep(0.08, 1.45, planar_speed), wade_weight)
	_ground_weight = lerpf(_ground_weight, move_weight, response)
	var sprint_weight := smoothstep(config.sprint_anim_threshold, config.max_flow_speed, planar_speed)
	_sprint_blend = lerpf(_sprint_blend, sprint_weight, response)
	# One shared phase follows traveled distance. Normalize each clip to a one-second
	# timeline, while its authored length × reference speed defines its cycle distance.
	var run_cycle_distance := _run_clip_length * config.base_run_speed
	var sprint_cycle_distance := _sprint_clip_length * config.max_flow_speed
	var cycle_distance := lerpf(run_cycle_distance, sprint_cycle_distance, _sprint_blend)
	var wade_cycle_distance := maxf(WADE_CYCLE_DISTANCE, planar_speed / WADE_MAX_CYCLES_PER_SECOND)
	cycle_distance = lerpf(cycle_distance, wade_cycle_distance, wade_weight)
	var phase_advance := planar_speed * delta / maxf(cycle_distance, 0.001)
	_ground_phase_previous = _ground_phase
	_ground_phase = fposmod(_ground_phase + phase_advance, 1.0)
	_apply_ground_gait()
	play_state("LocomotionGait", SWIM_GAIT_BLEND_TIME if current_state == "Swim" else 0.13)
	if _ground_weight < 0.12:
		return "Idle"
	return "Sprint" if _sprint_blend > 0.5 else "Run"


func _apply_ground_gait() -> void:
	if anim_tree == null:
		return
	anim_tree.set(GAIT_PATH + "IdleBlend/blend_amount", _ground_weight)
	anim_tree.set(GAIT_PATH + "Strides/blend_position", _sprint_blend)


func get_ground_phase() -> float:
	## Normalized shared stride phase. Left strike is 0; right strike is 0.5.
	return fposmod(_ground_phase, 1.0)


func get_interpolated_ground_phase() -> float:
	var phase_delta := fposmod(_ground_phase - _ground_phase_previous, 1.0)
	var fraction := clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	return fposmod(_ground_phase_previous + phase_delta * fraction, 1.0)


func get_ground_contact_duration() -> float:
	## Fraction of one stride reserved for ground contact and its blends.
	return GROUND_CONTACT_DURATION


func get_ground_gait_weight() -> float:
	if current_state != "LocomotionGait" or _playback == null or _playback.get_current_node() != &"LocomotionGait":
		return 0.0
	return clampf(_ground_weight, 0.0, 1.0)


func begin_running_landing(impact_speed: float) -> void:
	## Enter locomotion immediately and blend a brief compression over its advancing gait.
	_running_landing_elapsed = 0.0
	_running_landing_strength = clampf(impact_speed / 8.0, 0.45, 1.0)
	play_state("LocomotionGait", 0.08)


func get_running_landing_weight() -> float:
	if _running_landing_elapsed >= RUNNING_LANDING_DURATION:
		return 0.0
	var t := clampf(_running_landing_elapsed / RUNNING_LANDING_DURATION, 0.0, 1.0)
	return _running_landing_strength * (1.0 - smoothstep(0.0, 1.0, t))


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _apply_running_landing_pose() -> void:
	var weight := get_running_landing_weight()
	if weight <= 0.001 or _skeleton == null:
		return
	# These are local pose deltas applied after AnimationTree sampling. The following
	# sample replaces them, so the overlay does not accumulate or affect root motion.
	if _pelvis_bone >= 0:
		var pelvis := _skeleton.get_bone_pose(_pelvis_bone)
		var down_in_skeleton := _skeleton.global_transform.basis.inverse() * Vector3.DOWN
		var pelvis_parent := _skeleton.get_bone_parent(_pelvis_bone)
		var parent_basis := Basis.IDENTITY
		if pelvis_parent >= 0:
			parent_basis = _skeleton.get_bone_global_pose(pelvis_parent).basis
		pelvis.origin += parent_basis.inverse() * down_in_skeleton * (0.055 * weight)
		_skeleton.set_bone_pose(_pelvis_bone, pelvis)
	if _spine_bone >= 0:
		var spine := _skeleton.get_bone_pose(_spine_bone)
		spine.basis = (spine.basis * Basis(Vector3.RIGHT, deg_to_rad(-7.0 * weight))).orthonormalized()
		_skeleton.set_bone_pose(_spine_bone, spine)


func _on_animation_applied() -> void:
	_apply_running_landing_pose()


func set_swim_blend(surface_weight: float, tread_weight: float, speed_scale: float, glide_weight: float = 0.0) -> void:
	play_state("Swim", SWIM_GAIT_BLEND_TIME)
	if anim_tree == null:
		return
	var glide := clampf(glide_weight, 0.0, 1.0)
	var playback_scale := maxf(0.01, lerpf(speed_scale, SWIM_GLIDE_CADENCE, glide))
	var idle_scale := SWIM_IDLE_CADENCE / playback_scale
	anim_tree.set("parameters/Swim/SurfaceBlend/blend_amount", clampf(surface_weight, 0.0, 1.0))
	anim_tree.set("parameters/Swim/TreadBlend/blend_amount", clampf(tread_weight, 0.0, 1.0))
	anim_tree.set("parameters/Swim/DeepIdleBlend/blend_amount", clampf(tread_weight, 0.0, 1.0))
	anim_tree.set("parameters/Swim/SwimSpeed/scale", playback_scale)
	anim_tree.set("parameters/Swim/DeepIdleSpeed/scale", idle_scale)
	anim_tree.set("parameters/Swim/TreadSpeed/scale", idle_scale)


func play_state(state_key: String, xfade: float = 0.12, restart: bool = false) -> void:
	if _playback == null or anim_tree == null:
		return
	if current_state == state_key and not restart:
		return
	var sm := anim_tree.tree_root as AnimationNodeStateMachine
	if sm == null or not sm.has_node(state_key):
		return
	var from_state := _playback.get_current_node()
	current_state = state_key
	# Blending inverted sloth poses can rotate the pelvis upright through the rope.
	var rope_cut := state_key in ROPE_CUT_STATES or from_state in [&"RopeHang", &"RopeClimb"]
	# Gameplay actions must start on entry even if the previous fade is still active.
	if rope_cut or from_state.is_empty() or (restart and (from_state == state_key or not _playback.get_fading_from_node().is_empty())):
		_playback.start(state_key, true)
		return
	if from_state != state_key:
		var transition: AnimationNodeStateMachineTransition
		if sm.has_transition(from_state, state_key):
			for i in sm.get_transition_count():
				if sm.get_transition_from(i) == from_state and sm.get_transition_to(i) == state_key:
					transition = sm.get_transition(i)
					break
		else:
			transition = AnimationNodeStateMachineTransition.new()
			sm.add_transition(from_state, state_key, transition)
		if transition != null:
			transition.xfade_time = xfade
		var swim_handoff := (from_state == &"LocomotionGait" and state_key == "Swim") \
			or (from_state == &"Swim" and state_key == "LocomotionGait")
		if swim_handoff:
			transition.xfade_curve = _swim_gait_blend_curve
	_playback.travel(state_key)


func play_action(state_key: String, duration: float, xfade: float = 0.06, clip_fraction: float = 1.0) -> void:
	if anim_tree == null or not STATE_TO_ANIM.has(state_key):
		return
	var clip_name: String = STATE_TO_ANIM[state_key]
	if not anim_player.has_animation(clip_name):
		return
	var clip := anim_player.get_animation(clip_name)
	if state_key in TRAVERSAL_STATES:
		_phase_state = state_key
		_phase_length = clip.length
		_previous_action_phase = 0.0
		_action_phase = 0.0
	else:
		anim_tree.set("parameters/%s/Scale/scale" % state_key, clip.length * clip_fraction / maxf(duration, 0.001))
	play_state(state_key, xfade, true)


func set_traversal_phase(state_key: String, phase: float) -> void:
	if state_key == _phase_state:
		_previous_action_phase = _action_phase
		_action_phase = phase


func set_balance_walk_phase(phase: float, starting: bool) -> void:
	_previous_beam_phase = phase if starting else _beam_phase
	_beam_phase = phase


func _process(delta: float) -> void:
	if _running_landing_elapsed < RUNNING_LANDING_DURATION:
		_running_landing_elapsed = minf(_running_landing_elapsed + delta, RUNNING_LANDING_DURATION)
	if anim_tree != null:
		# TimeSeek is downstream from a one-second normalized blend space, so this
		# render sample interpolates the same physics phase exposed to the foot solver.
		anim_tree.set(GAIT_PATH + "GroundPhase/seek_request", get_interpolated_ground_phase())
		if current_state == "BeamWalk" and _beam_clip_length > 0.0:
			var advance := fposmod(_beam_phase - _previous_beam_phase, 1.0)
			var phase := fposmod(_previous_beam_phase + advance * Engine.get_physics_interpolation_fraction(), 1.0)
			anim_tree.set("parameters/BeamWalk/Phase/seek_request", phase * _beam_clip_length)
	if _phase_state.is_empty():
		return
	var phase := _action_phase
	if current_state == _phase_state:
		phase = lerpf(_previous_action_phase, _action_phase, Engine.get_physics_interpolation_fraction())
	anim_tree.set("parameters/%s/Phase/seek_request" % _phase_state, phase * _phase_length)
	if current_state != _phase_state:
		_phase_state = ""


func reset_for_respawn() -> void:
	_ground_weight = 0.0
	_sprint_blend = 0.0
	_ground_phase_previous = 0.0
	_ground_phase = 0.0
	_running_landing_elapsed = RUNNING_LANDING_DURATION
	_running_landing_strength = 0.0
	_phase_state = ""
	current_state = "LocomotionGait"
	_apply_ground_gait()
	if _playback != null:
		_playback.start("LocomotionGait", true)
