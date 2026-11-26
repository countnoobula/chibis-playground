extends RefCounted

## Each point stores distance along the beam, lift, and lateral radius fraction.
const STEP_LENGTH := 0.24
const FIRST_STEP_LENGTH := 0.12
const TOE_LEAD := 0.022
const SWING_HEIGHT := 0.065
const SETTLE_DURATION := 0.13
const IDLE_STAGGER := 0.045
const TURN_REACH := 0.055
const TURN_STEP_HEIGHT := 0.030

var _feet: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _previous_feet: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _support_side := 0
var _step_distance := 0.0
var _step_length := 0.0
var _swing_from := Vector3.ZERO
var _swing_to := Vector3.ZERO
var _settle_start := Vector3.ZERO
var _settle_elapsed := SETTLE_DURATION
var _settle_lift := 0.0
var _beam_length := 0.0


func reset(progress: float, direction: float, beam_length: float) -> void:
	_beam_length = beam_length
	_feet[0] = Vector3(_on_beam(progress + direction * IDLE_STAGGER), 0.0, -direction * 0.32)
	_feet[1] = Vector3(_on_beam(progress - direction * IDLE_STAGGER), 0.0, direction * 0.32)
	_previous_feet.assign(_feet)
	_step_length = 0.0
	_settle_elapsed = SETTLE_DURATION


func is_settled() -> bool:
	return _step_length == 0.0 and not is_settling()


func is_settling() -> bool:
	return _settle_elapsed < SETTLE_DURATION


func prepare_turn(progress: float) -> bool:
	if not is_settled():
		return false
	for side in 2:
		if absf(_feet[side].x - progress) <= TURN_REACH and absf(_feet[side].z) <= 0.001:
			continue
		# Bring the long stance in one foot at a time so the pivot starts in reach.
		_support_side = 1 - side
		var stagger := IDLE_STAGGER if _feet[side].x >= _feet[1 - side].x else -IDLE_STAGGER
		_begin_settle(progress + stagger, TURN_STEP_HEIGHT, 0.0)
		return false
	return true


func advance(previous_progress: float, progress: float, delta: float) -> void:
	_previous_feet.assign(_feet)
	var movement := progress - previous_progress
	if is_zero_approx(movement):
		_settle(progress, delta)
		return

	var direction := signf(movement)
	if _step_length == 0.0:
		_support_side = 0 if (_feet[0].x - _feet[1].x) * direction >= 0.0 else 1
		_start_step(previous_progress, direction, FIRST_STEP_LENGTH)
	_step_distance += absf(movement)
	if _step_distance >= _step_length:
		_feet[1 - _support_side] = _swing_to
		_support_side = 1 - _support_side
		var carry := _step_distance - _step_length
		_start_step(progress - direction * carry, direction, STEP_LENGTH)
		_step_distance = carry
		# Keep the outgoing sole down for this interpolation interval.
		return
	var phase := _step_distance / _step_length
	var swing_foot := _swing_from.lerp(_swing_to, smoothstep(0.0, 1.0, phase))
	swing_foot.y = SWING_HEIGHT * sin(PI * phase)
	_feet[1 - _support_side] = swing_foot


func walk_phase() -> float:
	var phase := _step_distance / _step_length if _step_length > 0.0 else 0.0
	# The imported balance walk passes its lowest left and right poses near 0.74 and 0.26.
	return fposmod((0.74 if _support_side == 0 else 0.24) + 0.5 * phase, 1.0)


func foot_at(side: int, interpolation: float) -> Vector3:
	return _previous_feet[side].lerp(_feet[side], interpolation)


func _start_step(progress: float, direction: float, distance: float) -> void:
	_step_distance = 0.0
	_step_length = distance
	_swing_from = _feet[1 - _support_side]
	var lateral := direction * (0.32 if _support_side == 0 else -0.32)
	var landing := progress + direction * (distance + STEP_LENGTH * 0.5 + TOE_LEAD)
	_swing_to = Vector3(_on_beam(landing), 0.0, lateral)


func _settle(progress: float, delta: float) -> void:
	var swing_side := 1 - _support_side
	if _step_length > 0.0:
		_step_length = 0.0
		var stagger := IDLE_STAGGER if progress >= _feet[_support_side].x else -IDLE_STAGGER
		_begin_settle(progress + stagger, 0.0, _feet[swing_side].z)
	if _settle_elapsed < SETTLE_DURATION:
		_settle_elapsed = minf(_settle_elapsed + delta, SETTLE_DURATION)
		var weight := smoothstep(0.0, SETTLE_DURATION, _settle_elapsed)
		_feet[swing_side] = _settle_start.lerp(_swing_to, weight)
		_feet[swing_side].y += _settle_lift * sin(PI * weight)


func _begin_settle(landing: float, lift: float, lateral: float) -> void:
	_settle_elapsed = 0.0
	_settle_lift = lift
	_settle_start = _feet[1 - _support_side]
	_swing_to = Vector3(_on_beam(landing), 0.0, lateral)


func _on_beam(progress: float) -> float:
	var margin := minf(0.055, _beam_length * 0.25)
	return clampf(progress, margin, _beam_length - margin)
