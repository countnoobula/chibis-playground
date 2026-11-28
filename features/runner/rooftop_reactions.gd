extends Node

## Maps the runner's live gameplay state to the approved automatic expressions.
## This node runs after ParkourController so it sees the state and animation label
## selected for the current physics frame.

const FACE_NEUTRAL := 0
const FACE_GENTLE_NEUTRAL := 1
const FACE_OPEN_SMILE := 2
const FACE_BRIGHT_SMILE := 3
const FACE_DELIGHTED := 4
const FACE_SOFT_DETERMINATION := 6
const FACE_FOCUSED_DETERMINATION := 7
const FACE_TINY_POUT := 8
const FACE_BRAVE_LITTLE_SMILE := 9
const FACE_LITTLE_GASP := 11
const FACE_FREE_FALL_SQUEAL := 14

const FALL_SQUEAL_DELAY := 0.35
const RESCUE_HOLD_DURATION := 0.60
const IDLE_CUE_HOLD_DURATION := 0.75
const SETTLE_DELAY := 0.15
const BRIGHT_SMILE_ENTER_FLOW := 0.68
const BRIGHT_SMILE_EXIT_FLOW := 0.54
const LOW_SPEED_NEUTRAL_LIMIT := 2.20
const SWING_SMILE_MIN_SPEED := 0.75

var _runner: ParkourController
var _juice: ChibiJuice

var _previous_state := ""
var _previous_anim_label := ""
var _state_elapsed := 0.0
var _context_elapsed := 0.0

var _fall_sequence_active := false
var _fall_flail_elapsed := 0.0
var _fall_cancelled_this_airtime := false
var _fall_suppressed_until_exit := false
var _rescue_remaining := 0.0

var _hmm_remaining := 0.0
var _giggle_remaining := 0.0
var _previous_hmm := false
var _previous_giggle := false
var _bright_smile_active := false
var _swing_moving := false
var _last_position := Vector3.ZERO

func setup(player: ParkourController) -> void:
	_runner = player
	_juice = player.juice
	player.expression_director.prepare_rooftop()
	process_physics_priority = player.process_physics_priority + 1
	reset()


func reset() -> void:
	_fall_sequence_active = false
	_fall_flail_elapsed = 0.0
	_fall_cancelled_this_airtime = false
	_rescue_remaining = 0.0
	_hmm_remaining = 0.0
	_giggle_remaining = 0.0
	_bright_smile_active = false
	_swing_moving = false
	_last_position = _runner.global_position
	_state_elapsed = 0.0
	_context_elapsed = 0.0
	_previous_state = str(_runner.current_state) if is_instance_valid(_runner) else ""
	_previous_anim_label = str(_runner.current_anim_label) if is_instance_valid(_runner) else ""
	_fall_suppressed_until_exit = (
		_previous_state == "Locomotion" and _previous_anim_label == "FallFlail"
	)
	_sync_idle_cue_edges()
	_runner.expression_director.set_automatic(-1)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_runner):
		return
	var state := str(_runner.current_state)
	var anim_label := str(_runner.current_anim_label)
	if state != _previous_state:
		_state_elapsed = 0.0
	else:
		_state_elapsed += delta
	if state != _previous_state or anim_label != _previous_anim_label:
		_context_elapsed = 0.0
	else:
		_context_elapsed += delta

	# Rope traversal positions the runner directly. Latch once the swing moves
	# so the smile survives the moment of stillness at either end of its arc.
	if state != "RopeSwing":
		_swing_moving = false
	elif _previous_state == state and _runner.global_position.distance_to(_last_position) >= SWING_SMILE_MIN_SPEED * delta:
		_swing_moving = true
	_last_position = _runner.global_position
	var on_floor := _runner.is_on_floor()
	var flow_level := float(_runner.flow_level)
	var planar_speed := float(_runner.resolved_planar_speed)
	var scarf_phase: StringName = _runner.scarf_glide_phase
	_rescue_remaining = maxf(0.0, _rescue_remaining - delta)
	_advance_idle_cues(delta, state, anim_label)
	_advance_fall_reaction(delta, state, anim_label, on_floor, scarf_phase)
	_update_bright_smile(state, anim_label, on_floor, flow_level)

	var automatic := _select_automatic(state, anim_label, on_floor, planar_speed)
	_runner.expression_director.set_automatic(automatic)
	_previous_state = state
	_previous_anim_label = anim_label


func _advance_idle_cues(delta: float, state: String, anim_label: String) -> void:
	_hmm_remaining = maxf(0.0, _hmm_remaining - delta)
	_giggle_remaining = maxf(0.0, _giggle_remaining - delta)
	if not is_instance_valid(_juice):
		_previous_hmm = false
		_previous_giggle = false
		_hmm_remaining = 0.0
		_giggle_remaining = 0.0
		return

	var hmm_now := _juice.played_hmm
	var giggle_now := _juice.played_giggle
	var settled_idle := state == "Locomotion" and anim_label == "Idle"
	if settled_idle:
		if hmm_now and not _previous_hmm:
			_hmm_remaining = IDLE_CUE_HOLD_DURATION
		if giggle_now and not _previous_giggle:
			_giggle_remaining = IDLE_CUE_HOLD_DURATION
	else:
		_hmm_remaining = 0.0
		_giggle_remaining = 0.0
	_previous_hmm = hmm_now
	_previous_giggle = giggle_now


func _advance_fall_reaction(
	delta: float,
	state: String,
	anim_label: String,
	on_floor: bool,
	scarf_phase: StringName
) -> void:
	var flail_active := (
		state == "Locomotion" and anim_label == "FallFlail" and not on_floor
	)
	var scarf_deployed := scarf_phase in [&"deploy", &"glide"]
	if on_floor:
		_fall_cancelled_this_airtime = false
		_rescue_remaining = 0.0
	if scarf_deployed:
		if not on_floor:
			_fall_cancelled_this_airtime = true
		_clear_fall_sequence()
		_rescue_remaining = 0.0
		return

	if _fall_suppressed_until_exit:
		if not flail_active:
			_fall_suppressed_until_exit = false
		else:
			_clear_fall_sequence()
			return

	if flail_active and not _fall_cancelled_this_airtime:
		if not _fall_sequence_active:
			_fall_sequence_active = true
			_fall_flail_elapsed = 0.0
		_fall_flail_elapsed += delta
		return

	if _fall_sequence_active:
		var real_rescue_catch := (
			state == "LedgeHang" and _previous_state == "Locomotion" and not on_floor
		)
		_clear_fall_sequence()
		if real_rescue_catch:
			_rescue_remaining = RESCUE_HOLD_DURATION

	if _rescue_remaining > 0.0 and state not in ["LedgeHang", "LedgeShimmy", "LedgeCorner", "MantleUp"]:
		_rescue_remaining = 0.0


func _clear_fall_sequence() -> void:
	_fall_sequence_active = false
	_fall_flail_elapsed = 0.0


func _update_bright_smile(
	state: String,
	anim_label: String,
	on_floor: bool,
	flow_level: float
) -> void:
	var sustained_sprint := state == "Locomotion" and anim_label == "Sprint" and on_floor
	if _bright_smile_active:
		if not sustained_sprint or flow_level <= BRIGHT_SMILE_EXIT_FLOW:
			_bright_smile_active = false
	elif sustained_sprint and _context_elapsed >= SETTLE_DELAY and flow_level >= BRIGHT_SMILE_ENTER_FLOW:
		_bright_smile_active = true


func _select_automatic(
	state: String,
	anim_label: String,
	on_floor: bool,
	planar_speed: float
) -> int:
	if _runner.scarf_glide_phase in [&"deploy", &"glide"]:
		return FACE_GENTLE_NEUTRAL
	if _rescue_remaining > 0.0:
		return FACE_BRAVE_LITTLE_SMILE
	if _fall_sequence_active:
		if _fall_flail_elapsed >= FALL_SQUEAL_DELAY:
			return FACE_FREE_FALL_SQUEAL
		return FACE_LITTLE_GASP

	if _state_elapsed >= SETTLE_DELAY:
		match state:
			"MantleUp":
				if anim_label == "MantleUp":
					return FACE_TINY_POUT
			"WallRun":
				if anim_label in ["WallRunL", "WallRunR"]:
					return FACE_FOCUSED_DETERMINATION
			"BalanceBeam", "Climbing":
				return FACE_SOFT_DETERMINATION

	if _giggle_remaining > 0.0:
		return FACE_DELIGHTED
	if _hmm_remaining > 0.0:
		return FACE_GENTLE_NEUTRAL
	if _bright_smile_active:
		return FACE_BRIGHT_SMILE

	if _state_elapsed >= SETTLE_DELAY:
		if state == "ZipLine":
			return FACE_OPEN_SMILE
		if state == "RopeSwing" and _swing_moving:
			return FACE_OPEN_SMILE

	if state == "Locomotion" and on_floor and anim_label == "Idle" and _context_elapsed >= 1.0:
		return FACE_GENTLE_NEUTRAL
	if state == "Locomotion" and on_floor \
		and (anim_label == "Idle" or planar_speed <= LOW_SPEED_NEUTRAL_LIMIT):
		return FACE_NEUTRAL
	return -1


func _sync_idle_cue_edges() -> void:
	_previous_hmm = is_instance_valid(_juice) and _juice.played_hmm
	_previous_giggle = is_instance_valid(_juice) and _juice.played_giggle


func _exit_tree() -> void:
	if is_instance_valid(_runner) and is_instance_valid(_runner.expression_director):
		_runner.expression_director.set_automatic(-1)
