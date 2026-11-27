class_name ChibiRigBinder
extends Node

const GlideWindWispsScript := preload("res://scripts/vfx/glide_wind_wisps.gd")
const ChibiScarfTailScript := preload("res://scripts/character/chibi_scarf_tail.gd")
const SCARF_TOSS_GUARD_DURATION := 0.68
const SCARF_TAIL_MIN_STOW_OPEN := 0.72
const SCARF_WIND_FORCE_SCALE := 0.28
const SCARF_WIND_FORCE_MAX := 2.6
const SCARF_WIND_RESPONSE := 8.0

## Runtime initializer for ChibiRunner: binds the instanced chibi_runner.glb Skeleton3D,
## MeshInstance3D, AnimationPlayer -> AnimationTree, ChibiPoseModifier, and Godot 4.7's
## native SpringBoneSimulator3D for scarf, ahoge, hood, and cheek secondary motion.

@export var controller: ParkourController
@export var visual_pivot: Node3D
@export var anim_tree: AnimationTree
@export var anim_ctrl: ChibiAnimController
@export var juice: ChibiJuice

var skeleton: Skeleton3D
var mesh_inst: MeshInstance3D
var anim_player: AnimationPlayer
var pose_mod: ChibiPoseModifier
var spring_sim: SpringBoneSimulator3D
var scarf_spring_sim: SpringBoneSimulator3D
var scarf_glider: ChibiScarfGlider
var _last_wind_reset_serial := -1
var _previous_scarf_glide_phase: StringName = &"stowed"
var _scarf_toss_guard_remaining := 0.0
var _scarf_stow_was_active := false
var _scarf_wind_force := Vector3.ZERO


func _ready() -> void:
	set_process(true)
	if visual_pivot == null:
		return
	skeleton = _find_type(visual_pivot, "Skeleton3D") as Skeleton3D
	mesh_inst = _find_type(visual_pivot, "MeshInstance3D") as MeshInstance3D
	anim_player = _find_type(visual_pivot, "AnimationPlayer") as AnimationPlayer

	if anim_ctrl != null and anim_player != null and anim_tree != null:
		anim_tree.process_priority = -20
		anim_ctrl.setup(anim_player, anim_tree)

	if juice != null and mesh_inst != null:
		juice.bind_mesh(mesh_inst)

	if skeleton != null:
		# Ensure Skeleton3D modifiers (ChibiPoseModifier + SpringBoneSimulator3D) ALWAYS run AFTER AnimationTree!
		skeleton.process_priority = 20
		skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE
		# Attach ChibiPoseModifier BEFORE SpringBoneSimulator3D so IK drives spring follow-through!
		pose_mod = ChibiPoseModifier.new()
		pose_mod.name = "ChibiPoseModifier"
		pose_mod.runner_body = controller
		skeleton.add_child(pose_mod)
		if controller != null:
			controller.pose_mod = pose_mod

		scarf_glider = ChibiScarfGlider.new()
		scarf_glider.name = "ChibiScarfGlider"
		add_child(scarf_glider)
		var model_root := visual_pivot.get_node_or_null("ChibiModel") as Node3D
		if model_root == null:
			model_root = visual_pivot
		if scarf_glider.attach_to(model_root, skeleton, mesh_inst):
			pose_mod.scarf_glider = scarf_glider
		else:
			push_warning("Chibi scarf glider could not bind; stowed scarf remains visible.")
			scarf_glider.queue_free()
			scarf_glider = null

		_setup_spring_bones(skeleton)
		var scarf_tail := ChibiScarfTailScript.new()
		scarf_tail.name = "ChibiScarfTail"
		scarf_tail.runner_body = controller
		skeleton.add_child(scarf_tail)

		var gear := ChibiDiveGear.new()
		if gear.attach_to(skeleton):
			pose_mod.dive_gear = gear
			if juice != null:
				juice.dive_gear = gear
		else:
			gear.free()

	if controller != null:
		_last_wind_reset_serial = controller.wind_reset_serial
		var wisps := GlideWindWispsScript.new()
		wisps.name = "GlideWindWisps"
		wisps.bind_controller(controller)
		add_child(wisps)


func _process(delta: float) -> void:
	if controller == null or scarf_spring_sim == null:
		return
	if _last_wind_reset_serial != controller.wind_reset_serial:
		_last_wind_reset_serial = controller.wind_reset_serial
		_scarf_wind_force = Vector3.ZERO
		_scarf_toss_guard_remaining = 0.0
		_scarf_stow_was_active = false
		_previous_scarf_glide_phase = controller.scarf_glide_phase
		scarf_spring_sim.external_force = Vector3.ZERO
		scarf_spring_sim.reset()
		if spring_sim != null:
			spring_sim.reset()
		return

	var phase: StringName = controller.scarf_glide_phase
	if phase == &"stow":
		_scarf_stow_was_active = controller.scarf_glide_stow_open >= SCARF_TAIL_MIN_STOW_OPEN
	elif phase == &"stowed" and _previous_scarf_glide_phase == &"stow" and _scarf_stow_was_active:
		_scarf_stow_was_active = false
		_scarf_toss_guard_remaining = SCARF_TOSS_GUARD_DURATION
	elif phase in [&"deploy", &"glide", &"cancel"]:
		_scarf_stow_was_active = false
		_scarf_toss_guard_remaining = 0.0
	_previous_scarf_glide_phase = phase

	_scarf_toss_guard_remaining = maxf(_scarf_toss_guard_remaining - maxf(delta, 0.0), 0.0)
	var scarf_is_stowed := phase == &"stowed" and _scarf_toss_guard_remaining <= 0.0
	var target_force := controller.wind_velocity * SCARF_WIND_FORCE_SCALE if scarf_is_stowed else Vector3.ZERO
	target_force = target_force.limit_length(SCARF_WIND_FORCE_MAX)
	_scarf_wind_force = _scarf_wind_force.lerp(
		target_force,
		1.0 - exp(-SCARF_WIND_RESPONSE * maxf(delta, 0.0))
	)
	scarf_spring_sim.external_force = _scarf_wind_force


func _setup_spring_bones(skel: Skeleton3D) -> void:
	var chains := [
		["scarf_01", "scarf_05", 0.55, 0.35, 0.45],
		["scarf_b_01", "scarf_b_03", 0.60, 0.38, 0.40],
		["ahoge_01", "ahoge_01", 1.20, 0.32, 0.15],
		["hood_01", "hood_01", 1.40, 0.45, 0.25],
		["cheek_jiggle_l", "cheek_jiggle_l", 2.00, 0.55, 0.05],
		["cheek_jiggle_r", "cheek_jiggle_r", 2.00, 0.55, 0.05],
	]
	var scarf_chains: Array = []
	var other_chains: Array = []
	for ch in chains:
		if str(ch[0]).begins_with("scarf_"):
			scarf_chains.append(ch)
		else:
			other_chains.append(ch)

	spring_sim = _create_spring_simulator(skel, "SpringBoneSimulator3D", other_chains)
	scarf_spring_sim = _create_spring_simulator(skel, "ScarfSpringBoneSimulator3D", scarf_chains)


func _create_spring_simulator(
	skel: Skeleton3D, simulator_name: String, chains: Array
) -> SpringBoneSimulator3D:
	var simulator := SpringBoneSimulator3D.new()
	simulator.name = simulator_name
	var valid_chains: Array = []
	for ch in chains:
		if skel.find_bone(ch[0]) >= 0 and skel.find_bone(ch[1]) >= 0:
			valid_chains.append(ch)
	simulator.setting_count = valid_chains.size()
	for i in valid_chains.size():
		var ch: Array = valid_chains[i]
		simulator.set_root_bone_name(i, ch[0])
		simulator.set_end_bone_name(i, ch[1])
		simulator.set_extend_end_bone(i, ch[0] == ch[1])
		if ch[0] == ch[1]:
			simulator.set_end_bone_length(i, 0.08)
		simulator.set_stiffness(i, ch[2])
		simulator.set_drag(i, ch[3])
		simulator.set_gravity(i, ch[4])
	skel.add_child(simulator)
	return simulator


func _find_type(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find_type(c, cls)
		if r != null:
			return r
	return null
