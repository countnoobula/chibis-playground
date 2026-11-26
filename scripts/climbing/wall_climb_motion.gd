extends RefCounted

## Contact planning and capsule motion for an upright, static climbable wall.
const Geometry := preload("res://scripts/climbing/wall_climb_geometry.gd")

enum Phase { IDLE, ATTACH, HOLD, REACH, JUMP, CORNER }
enum Result { CONTINUE, CAUGHT, FALL }

const WORLD_MASK := 1
const SKIN := 0.006
const HAND_CLEARANCE := 0.025
const SHOE_CLEARANCE := 0.037
const MIN_DIRECTION := 0.27
const HANG_IDLE_DELAY := 0.075
const LEGACY_WALL_PUSH_TIME := 0.10
const CORNER_DURATION := 0.62
const CORNER_CLEARANCE_SAMPLES := 16
const PATH_CLEARANCE_SAMPLES := 12
const GAZE_CATCH_SETTLE_SECONDS := 0.34

var phase: Phase = Phase.IDLE
var frame := Basis.IDENTITY
var contacts: Array[Dictionary] = [{}, {}, {}, {}]
var outward_velocity := Vector3.ZERO
var body_weight := 0.0

var _runner: CharacterBody3D
var _collider: CollisionShape3D
var _face: Dictionary = {}
var _corner_face: Dictionary = {}
var _corner_frame := Basis.IDENTITY
var _corner_controls: Array[Vector3] = []
var _offsets: Array[Vector3] = []
var _lengths: Array[float] = []
var _body_inset: float
var _start: Vector3
var _finish: Vector3
var _elapsed := 0.0
var _duration := 0.0
var _planned: Array[Dictionary] = [{}, {}, {}, {}]
var _lead := 0
var _next_lead := 0
var _arc_height := 0.0
var _short_side_hop := false
var _gaze_carry_direction := Vector3.ZERO
var _gaze_carry_strength := 0.0
var _input_retry := 0.0
var _neutral_hold_time := 0.0
var _last_direction := Vector3.ZERO


func setup(runner: CharacterBody3D, collider: CollisionShape3D, offsets: Array[Vector3], lengths: Array[float], inset: float) -> void:
	_runner = runner
	_collider = collider
	_offsets = offsets
	_lengths = lengths
	_body_inset = inset


func reset() -> void:
	phase = Phase.IDLE
	_face.clear()
	_corner_face.clear()
	_corner_controls.clear()
	contacts = [{}, {}, {}, {}]
	_planned = [{}, {}, {}, {}]
	_next_lead = 0
	_elapsed = 0.0
	_duration = 0.0
	_short_side_hop = false
	_gaze_carry_direction = Vector3.ZERO
	_gaze_carry_strength = 0.0
	_input_retry = 0.0
	_neutral_hold_time = 0.0
	_last_direction = Vector3.ZERO
	outward_velocity = Vector3.ZERO
	body_weight = 0.0


func try_attach(direction: Vector3, manual: bool, grounded_approach: bool = false) -> bool:
	if phase != Phase.IDLE or _collider == null or _offsets.size() != 4 or _lengths.size() != 4:
		return false
	var reach := 0.83 if manual else 0.59
	if grounded_approach:
		reach = (_collider.shape as CapsuleShape3D).radius + 0.11
	var face := Geometry.find_face(_runner, direction, reach)
	if face.is_empty():
		return false
	if grounded_approach and (face["normal"] as Vector3).dot(direction.normalized()) > -0.86:
		return false
	_face = face
	frame = Basis(_face["right"], _face["up"], _face["normal"]).orthonormalized()
	var center := _runner.global_position + Vector3.UP * ((_offsets[0].y + _offsets[1].y) * 0.5 + 0.11)
	var candidates := Geometry.find_contacts(_runner, _face, center, 0.56)
	var pick := _select_stance(candidates, center, Vector3.ZERO, false)
	if pick.is_empty():
		return false
	_begin(pick, Phase.ATTACH, 0.22)
	return true


func try_jump(input: Vector2) -> bool:
	if phase != Phase.HOLD:
		return false
	var heading := _direction(input) if input.length() > MIN_DIRECTION else frame.y
	if _is_tower_route():
		return _try_tower_leap(heading)
	var origin := _hand_center()
	var desired_stride := 0.66
	var search_radius := 0.66
	var center := origin + heading * desired_stride
	var candidates := Geometry.find_contacts(_runner, _face, center, search_radius)
	var pick := _select_stance(candidates, origin, heading, true)
	if pick.is_empty():
		return false
	_begin_leap(pick, origin, heading)
	return true


func _try_tower_leap(heading: Vector3) -> bool:
	var origin := _hand_center()
	var short_side_hop := _is_short_side_hop_heading(heading)
	var lateral_input := absf(heading.dot(frame.x)) > 0.84
	if short_side_hop:
		# Keep the familiar nearby lateral hop as the first choice.
		var short_profile := {
			"stride": 0.48, "radius": 0.54, "min_forward": 0.24,
			"max_forward": 0.86, "max_side": 0.24, "short_side_hop": true,
		}
		var short_candidates := Geometry.find_contacts(
			_runner, _face, origin + heading * float(short_profile["stride"]), float(short_profile["radius"])
		)
		var short_pick := _select_stance(
			short_candidates, origin, heading, true, false, true, short_profile
		)
		if not short_pick.is_empty():
			short_pick["short_side_hop"] = true
			_begin_leap(short_pick, origin, heading)
			return true
	# If the close move is unavailable, search a measured wider window. The
	# separate side allowance lets a cardinal input reach offset masonry lanes.
	var downward := heading.dot(frame.y) < -0.84
	var max_side := 0.24 if lateral_input else 0.70
	var profiles: Array[Dictionary] = [
		{
		"stride": 0.66,
		"min_forward": 0.22 if downward else 0.37,
		"max_forward": 0.92, "max_side": max_side, "distinct_collider": true,
		"short_side_hop": false,
		},
		{
		"stride": 0.88,
		"min_forward": 0.22 if downward else 0.37,
		"max_forward": 1.24, "max_side": max_side, "distinct_collider": true,
		"short_side_hop": false,
		},
		{
		"stride": 1.20,
		"min_forward": 0.22 if downward else 0.37,
		"max_forward": 1.60, "max_side": max_side, "distinct_collider": true,
		"short_side_hop": false,
		},
	]
	# One broad scan covers every measured fallback bound. Progressively relax the
	# stance limits over that same real-contact set instead of repeating ray grids.
	var candidates := Geometry.find_contacts(_runner, _face, origin + heading * 0.88, 0.72)
	for profile in profiles:
		var pick := _select_stance(
			candidates, origin, heading, true, false, bool(profile["short_side_hop"]), profile
		)
		if pick.is_empty():
			continue
		pick["short_side_hop"] = bool(profile["short_side_hop"])
		_begin_leap(pick, origin, heading)
		return true
	return false


func _begin_leap(pick: Dictionary, origin: Vector3, heading: Vector3) -> void:
	var grip: Vector3 = pick["contacts"][pick["lead"]]["point"]
	var feet: Vector3 = pick["feet"]
	_short_side_hop = bool(pick.get("short_side_hop", _is_short_side_hop_heading(heading)))
	_arc_height = _jump_arc_height(feet, grip, origin, _short_side_hop)
	var duration := 0.54
	if _is_tower_route():
		var planar_distance := (grip - origin - frame.z * (grip - origin).dot(frame.z)).length()
		var rise := maxf(0.0, feet.y - _runner.global_position.y)
		if _short_side_hop:
			duration = clampf(0.40 + planar_distance * 0.10 + rise * 0.08, 0.44, 0.56)
		else:
			duration = clampf(0.43 + planar_distance * 0.12 + rise * 0.08, 0.50, 0.68)
	_begin(pick, Phase.JUMP, duration)
	# Keep the chest loaded over the planted contacts during the brief push. The
	# wall pose already locks their IK, while the gaze and shoulder roll show the
	# intended direction before the capsule leaves the old stance.


func _jump_arc_height(finish: Vector3, grip: Vector3, origin: Vector3, short_side_hop: bool = false) -> float:
	if not _is_tower_route():
		return 0.14 + minf(0.12, maxf(0.0, finish.y - _runner.global_position.y) * 0.17)
	var planar_distance := (grip - origin - frame.z * (grip - origin).dot(frame.z)).length()
	var rise := maxf(0.0, finish.y - _runner.global_position.y)
	if short_side_hop:
		return clampf(0.08 + planar_distance * 0.05 + rise * 0.04, 0.10, 0.14)
	return clampf(0.14 + planar_distance * 0.11 + rise * 0.10, 0.15, 0.36)


func _is_short_side_hop_heading(heading: Vector3) -> bool:
	return _is_tower_route() and absf(heading.dot(frame.x)) > 0.84 and absf(heading.dot(frame.y)) < 0.42


func find_mantle_edge(summit_only: bool = false) -> Dictionary:
	if phase != Phase.HOLD:
		return {}
	var center := _hand_center()
	var wall := _face.get("wall") as Node3D
	if wall == null or not is_instance_valid(wall):
		return {}
	if summit_only:
		# Keep the controller's per-frame summit probe cheap along the lower route.
		# The tower marker is a direct child so this does not scan climbing geometry.
		if not wall.is_in_group("tower_corner_route"):
			return {}
		var launch_marker := wall.get_node_or_null("LaunchMarker") as Marker3D
		if launch_marker == null or absf(launch_marker.global_position.y - center.y) > 0.42:
			return {}
	var options := Geometry.find_contacts(_runner, _face, center + Vector3.UP * 0.20, 0.36)
	var roof_reach := 0.34 if wall.is_in_group("tower_corner_route") else 0.27
	var best: Dictionary = {}
	var best_dist := INF
	for option in options:
		var point: Vector3 = option["point"]
		if absf((point - center).dot(frame.x)) > 0.28 or point.y < center.y - 0.09 or point.y > center.y + roof_reach:
			continue
		# A mantle needs a deep floor beyond the lip, and room for the full capsule.
		var edge := point + frame.z * 0.028
		var retreat := edge - frame.z * 0.44
		var ground := _ray(retreat + Vector3.UP * 0.21, retreat - Vector3.UP * 0.06)
		if ground.is_empty() or (ground["normal"] as Vector3).y < 0.75:
			continue
		if summit_only:
			var landing_collider := ground.get("collider") as Node
			if landing_collider == null or not landing_collider.is_in_group("tower_summit"):
				continue
		if absf((ground["position"] as Vector3).y - edge.y) > 0.05:
			continue
		var landing := retreat + Vector3.UP * 0.055
		var lift := Vector3(_runner.global_position.x, landing.y, _runner.global_position.z)
		if not _clear_segment(_runner.global_position, lift) or not _clear_segment(lift, landing):
			continue
		var dist := point.distance_squared_to(center)
		if dist < best_dist:
			best_dist = dist
			best = {"edge": edge, "lift": lift, "landing": landing}
	return best


func tick(input: Vector2, delta: float) -> Result:
	if phase == Phase.HOLD and input.length_squared() <= MIN_DIRECTION * MIN_DIRECTION:
		_neutral_hold_time = minf(_neutral_hold_time + delta, HANG_IDLE_DELAY)
	else:
		_neutral_hold_time = 0.0
	if phase == Phase.IDLE:
		return Result.FALL
	var wall := _face.get("wall") as Node3D
	if not is_instance_valid(wall) or not wall.is_in_group("climbable_wall"):
		return Result.FALL

	if phase == Phase.HOLD:
		outward_velocity = Vector3.ZERO
		for limb in 4:
			if not contacts[limb].is_empty() and not _contact_is_live(contacts[limb]):
				contacts[limb] = {}
		if contacts[0].is_empty() and contacts[1].is_empty():
			return Result.FALL
		var heading := _direction(input)
		_input_retry = maxf(0.0, _input_retry - delta)
		if input.length() > MIN_DIRECTION and (_input_retry <= 0.0 or heading.dot(_last_direction) < 0.78):
			var started := _try_reach(heading)
			if not started:
				started = _try_corner_transfer(heading)
			if not started:
				var wall_root := _face.get("wall") as Node3D
				if wall_root != null and wall_root.is_in_group("tower_corner_route"):
					_try_tower_leap(heading)
				elif input.y < -MIN_DIRECTION:
					# Keep the established upward-only fallback on ordinary walls.
					try_jump(input)
			_input_retry = 0.13
			_last_direction = heading
		elif input.length() <= MIN_DIRECTION:
			_input_retry = 0.0
		return Result.CONTINUE

	if phase == Phase.CORNER:
		if not _contact_is_live(_planned[_lead]):
			return _cancel_corner_transfer()
		_elapsed = minf(_elapsed + delta, _duration)
		var corner_t := _elapsed / _duration
		var corner_destination := _corner_path_position(corner_t)
		var corner_before := _runner.global_position
		var corner_motion := corner_destination - corner_before
		if corner_motion.length_squared() > 0.000001:
			_runner.move_and_collide(corner_motion, false, 0.001)
		outward_velocity = (_runner.global_position - corner_before) / maxf(delta, 0.001)
		if _runner.global_position.distance_to(corner_destination) > 0.02:
			return _cancel_corner_transfer()
		if corner_t < 1.0:
			return Result.CONTINUE
		contacts = _planned
		_face = _corner_face
		_corner_face = {}
		_corner_controls.clear()
		frame = _corner_frame
		phase = Phase.HOLD
		_next_lead = 1 - _lead
		_input_retry = 0.0
		outward_velocity = Vector3.ZERO
		return Result.CAUGHT

	if not _contact_is_live(_planned[_lead]):
		return _cancel_transfer()
	if phase == Phase.REACH and _elapsed < _duration * 0.55 and not _contact_is_live(contacts[1 - _lead]):
		return _cancel_transfer()
	_elapsed = minf(_elapsed + delta, _duration)
	var t := _elapsed / _duration
	var destination := _path_position(t)
	var before := _runner.global_position
	var motion := destination - before
	if motion.length_squared() > 0.000001:
		_runner.move_and_collide(motion, false, 0.001)
	outward_velocity = (_runner.global_position - before) / maxf(delta, 0.001)
	if _runner.global_position.distance_to(destination) > 0.02:
		return _cancel_transfer()
	if t < 1.0:
		return Result.CONTINUE
	contacts = _planned
	phase = Phase.HOLD
	_next_lead = 1 - _lead
	_input_retry = 0.0
	outward_velocity = Vector3.ZERO
	return Result.CAUGHT


func _try_reach(heading: Vector3) -> bool:
	var origin := _hand_center()
	var candidates := Geometry.find_contacts(_runner, _face, origin + heading * 0.28, 0.55)
	var pick := _select_stance(candidates, origin, heading, false)
	if pick.is_empty():
		return false
	var side_step := absf(heading.dot(frame.y)) < 0.25
	_begin(pick, Phase.REACH, 0.32 if side_step else 0.41)
	return true


## Only the authored tower route may switch to an adjoining wall face. The
## regular wall path stays a single static face and keeps its existing logic.
func _try_corner_transfer(heading: Vector3) -> bool:
	var wall := _face.get("wall") as Node3D
	if wall == null or not wall.is_in_group("tower_corner_route") or not wall.has_method("get_corner_point"):
		return false
	var lateral := heading.dot(frame.x)
	if absf(lateral) < 0.80 or absf(heading.dot(frame.y)) > 0.42:
		return false
	var tangent := frame.x * signf(lateral)
	var wall_normal: Vector3 = _face.get("normal", frame.z)
	var corner: Vector3 = wall.call("get_corner_point", wall_normal, tangent)
	var capsule := _collider.shape as CapsuleShape3D
	var clearance := capsule.radius + 0.09
	var relative := _runner.global_position - corner
	var along := relative.dot(tangent)
	var outward := relative.dot(wall_normal)
	if along < -0.95 or along > 0.16 or outward < capsule.radius - 0.12 or outward > capsule.radius + 0.75:
		return false
	if _hand_center().distance_to(corner + Vector3.UP * _hand_center().y) > 0.78:
		return false

	var next_normal := tangent.normalized()
	var next_frame := Basis(Vector3.UP.cross(next_normal).normalized(), Vector3.UP, next_normal).orthonormalized()
	var target_origin := corner + next_normal * clearance - wall_normal * clearance
	target_origin.y = _runner.global_position.y + 0.60
	var next_face := Geometry.find_face_from(_runner, target_origin, -next_normal, capsule.radius + 0.22, wall)
	if next_face.is_empty():
		return false
	var target_center := corner - wall_normal * 0.22
	target_center.y = _hand_center().y
	var candidates := Geometry.find_contacts(_runner, next_face, target_center, 0.58)
	var pick := _select_corner_stance(candidates, next_frame, next_face)
	if pick.is_empty():
		return false

	var finish: Vector3 = pick["feet"]
	var waypoint := corner + tangent * clearance + wall_normal * clearance
	waypoint.y = lerpf(_runner.global_position.y, finish.y, 0.5)
	var start := _runner.global_position
	var corner_controls := _make_corner_controls(start, waypoint, finish)
	if not _corner_curve_is_clear(corner_controls):
		return false
	_corner_frame = next_frame
	_corner_face = next_face
	_corner_controls = corner_controls
	_lead = int(pick["lead"])
	_start = _runner.global_position
	_finish = finish
	_planned = pick["contacts"]
	_elapsed = 0.0
	_duration = CORNER_DURATION
	phase = Phase.CORNER
	_last_direction = heading
	return true


func _select_corner_stance(candidates: Array[Dictionary], next_frame: Basis, next_face: Dictionary) -> Dictionary:
	if candidates.size() < 2:
		return {}
	var previous_frame := frame
	var previous_face := _face
	var previous_contacts := contacts
	frame = next_frame
	_face = next_face
	contacts = [{}, {}, {}, {}]
	var best: Dictionary = {}
	var best_cost := INF
	for left_index in candidates.size():
		var left: Dictionary = candidates[left_index]
		for right_index in range(left_index + 1, candidates.size()):
			var right: Dictionary = candidates[right_index]
			var left_point: Vector3 = left["point"]
			var right_point: Vector3 = right["point"]
			if absf(left_point.y - right_point.y) > 0.18:
				continue
			if absf((left_point - right_point).dot(frame.x)) < 0.26:
				continue
			var left_contact := left
			var right_contact := right
			if (left_point - right_point).dot(frame.x) > 0.0:
				left_contact = right
				right_contact = left
			for lead in 2:
				var lead_contact: Dictionary = left_contact if lead == 0 else right_contact
				var feet := _feet_for_grip(lead_contact["point"], lead)
				if absf(feet.y - _runner.global_position.y) > 0.44:
					continue
				var planned: Array[Dictionary] = [{}, {}, {}, {}]
				planned[0] = left_contact
				planned[1] = right_contact
				if not _can_reach(planned[0], 0, feet) or not _can_reach(planned[1], 1, feet) or not _point_clear(feet):
					continue
				var shoe_center := feet + frame.z * -0.22 + Vector3.UP * 0.17
				var footholds := Geometry.find_contacts(_runner, next_face, shoe_center, 0.42)
				for foot in [2, 3]:
					planned[foot] = _best_contact(footholds, planned, foot, feet, feet.y + 0.09)
				var cost := feet.distance_squared_to(_runner.global_position) + absf(left_point.y - right_point.y) * 0.7
				if cost < best_cost:
					best_cost = cost
					best = {"feet": feet, "contacts": planned, "lead": lead}
	frame = previous_frame
	_face = previous_face
	contacts = previous_contacts
	return best


func _cancel_corner_transfer() -> Result:
	if _stance_is_live(contacts) and _clear_segment(_runner.global_position, _start):
		phase = Phase.HOLD
		_planned = contacts
		_corner_face = {}
		_corner_controls.clear()
		_elapsed = 0.0
		_duration = 0.0
		outward_velocity = Vector3.ZERO
		return Result.CONTINUE
	return Result.FALL


func _corner_path_position(t: float) -> Vector3:
	return _corner_curve_position(_corner_controls, t)


func _make_corner_controls(start: Vector3, waypoint: Vector3, finish: Vector3) -> Array[Vector3]:
	var incoming := waypoint - start
	var outgoing := finish - waypoint
	if incoming.length_squared() < 0.0001 or outgoing.length_squared() < 0.0001:
		return []
	var incoming_direction := incoming.normalized()
	var outgoing_direction := outgoing.normalized()
	var shared_direction := incoming_direction + outgoing_direction
	if shared_direction.length_squared() < 0.001:
		shared_direction = outgoing_direction
	var shared_tangent := shared_direction.normalized() * minf(0.27, minf(incoming.length(), outgoing.length()) * 0.55)
	var first_handle := minf(0.34, incoming.length() * 0.34)
	var second_handle := minf(0.34, outgoing.length() * 0.34)
	return [
		start,
		start + incoming_direction * first_handle,
		waypoint - shared_tangent / 3.0,
		waypoint,
		waypoint + shared_tangent / 3.0,
		finish - outgoing_direction * second_handle,
		finish,
	]


func _corner_curve_position(controls: Array[Vector3], t: float) -> Vector3:
	if controls.size() != 7:
		return _start.lerp(_finish, smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0)))
	var progress := _corner_progress(t)
	if progress <= 0.5:
		return _cubic_bezier(controls[0], controls[1], controls[2], controls[3], progress * 2.0)
	return _cubic_bezier(controls[3], controls[4], controls[5], controls[6], (progress - 0.5) * 2.0)


func _corner_curve_is_clear(controls: Array[Vector3]) -> bool:
	if controls.size() != 7:
		return false
	var previous: Vector3 = controls[0]
	for sample in range(1, CORNER_CLEARANCE_SAMPLES + 1):
		var t := float(sample) / float(CORNER_CLEARANCE_SAMPLES)
		var next := _corner_curve_position(controls, t)
		if not _clear_segment(previous, next):
			return false
		previous = next
	return true


func _corner_progress(t: float) -> float:
	return smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0))


func _cubic_bezier(start: Vector3, control_a: Vector3, control_b: Vector3, finish: Vector3, t: float) -> Vector3:
	var a := start.lerp(control_a, t)
	var b := control_a.lerp(control_b, t)
	var c := control_b.lerp(finish, t)
	return a.lerp(b, t).lerp(b.lerp(c, t), t)


func _begin(pick: Dictionary, next_phase: Phase, duration: float) -> void:
	phase = next_phase
	_start = _runner.global_position
	_finish = pick["feet"]
	_planned = pick["contacts"]
	_lead = pick["lead"]
	_elapsed = 0.0
	_duration = duration
	outward_velocity = Vector3.ZERO


func _cancel_transfer() -> Result:
	var cancel_window := _duration * 0.12 if _is_tower_route() else LEGACY_WALL_PUSH_TIME
	if phase == Phase.JUMP and _elapsed <= cancel_window and _stance_is_live(contacts):
		phase = Phase.HOLD
		_planned = contacts
		return Result.CONTINUE
	# If the supported stance is still available, return to it after a blocked reach.
	if phase == Phase.REACH and _stance_is_live(contacts) and _clear_segment(_runner.global_position, _start):
		var fallback: Array[Dictionary] = contacts.duplicate()
		_begin({"feet": _start, "contacts": fallback, "lead": 1 - _lead}, Phase.ATTACH, 0.16)
		return Result.CONTINUE
	return Result.FALL


func _path_position(t: float) -> Vector3:
	if phase == Phase.JUMP:
		if _is_tower_route():
			return _jump_position(_start, _finish, t, _arc_height, _short_side_hop)
		if _elapsed < LEGACY_WALL_PUSH_TIME:
			return _start
		var legacy_t := (_elapsed - LEGACY_WALL_PUSH_TIME) / maxf(_duration - LEGACY_WALL_PUSH_TIME, 0.001)
		return _legacy_jump_position(_start, _finish, legacy_t, _arc_height)
	if phase == Phase.REACH:
		# Shift enough to place the lead hand before bringing the second arm across.
		return _reach_position(_start, _finish, t)
	return _start.lerp(_finish, smoothstep(0.0, 1.0, t))


func _reach_position(start: Vector3, finish: Vector3, t: float) -> Vector3:
	return start.lerp(finish, _reach_progress(t))


func _reach_progress(t: float) -> float:
	var normalized_t := clampf(t, 0.0, 1.0)
	var smooth := smoothstep(0.0, 1.0, normalized_t)
	var bias := normalized_t * normalized_t * (1.0 - normalized_t) * (1.0 - normalized_t)
	return clampf(smooth + bias * 2.56, 0.0, 1.0)


func _jump_position(start: Vector3, finish: Vector3, t: float, height: float, short_side_hop: bool = false) -> Vector3:
	var normalized_t := clampf(t, 0.0, 1.0)
	var progress := smoothstep(0.0, 1.0, normalized_t)
	var arc := 4.0 * progress * (1.0 - progress)
	var outward_arc := 0.075 if short_side_hop else 0.155
	return start.lerp(finish, progress) + (Vector3.UP * height + frame.z * outward_arc) * arc


func _legacy_jump_position(start: Vector3, finish: Vector3, t: float, height: float) -> Vector3:
	var arc := 4.0 * t * (1.0 - t)
	return start.lerp(finish, t) + (Vector3.UP * height + frame.z * 0.155) * arc


func _select_stance(
	candidates: Array[Dictionary], origin: Vector3, heading: Vector3,
	jump: bool, require_pair: bool = false, short_side_hop: bool = false,
	gap_profile: Dictionary = {}
) -> Dictionary:
	var ranked: Array[Dictionary] = []
	var is_mount := phase == Phase.IDLE
	var weighted_tower_move := not is_mount and _is_tower_route()
	var use_short_side_hop := short_side_hop and jump and weighted_tower_move
	var side_limit := 0.19
	if jump:
		side_limit = 0.38 if use_short_side_hop else (0.55 if heading.dot(frame.y) > 0.86 else 0.34)
		if gap_profile.has("max_side"):
			side_limit = float(gap_profile["max_side"])
	var lead_preference := _next_lead
	if not is_mount and absf(heading.dot(frame.x)) > 0.45:
		lead_preference = 1 if heading.dot(frame.x) > 0.0 else 0
	for candidate in candidates:
		if weighted_tower_move and absf(heading.dot(frame.x)) > 0.45 and _is_tower_summit_contact(candidate):
			continue
		var point: Vector3 = candidate["point"]
		if (use_short_side_hop or bool(gap_profile.get("distinct_collider", false))) and _shares_hand_collider(candidate):
			continue
		var diff := point - origin
		var plane_diff := diff - frame.z * diff.dot(frame.z)
		var score := plane_diff.length_squared() + absf(diff.dot(frame.z)) * 0.10
		if not is_mount:
			if _conflicts_with(candidate, contacts):
				continue
			var forward := plane_diff.dot(heading)
			var side := (plane_diff - heading * forward).length()
			var limit := 0.86 if use_short_side_hop else (0.90 if jump else (0.46 if weighted_tower_move else 0.37))
			var minimum := 0.24 if use_short_side_hop else (0.37 if jump else 0.075)
			if jump and gap_profile.has("max_forward"):
				limit = float(gap_profile["max_forward"])
			if jump and gap_profile.has("min_forward"):
				minimum = float(gap_profile["min_forward"])
			if forward < minimum or forward > limit or plane_diff.length() > limit + 0.09:
				continue
			if side > side_limit or plane_diff.normalized().dot(heading) < 0.63:
				continue
			var desired_stride := 0.48 if use_short_side_hop else (0.66 if jump else 0.26)
			if jump and gap_profile.has("stride"):
				desired_stride = float(gap_profile["stride"])
			score = absf(forward - desired_stride) + side * 1.35
		ranked.append({"score": score, "grip": candidate})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] < b["score"])

	var fallback: Dictionary = {}
	var best: Dictionary = {}
	var best_cost := INF
	var count := mini(18, ranked.size())
	for index in count:
		var candidate: Dictionary = ranked[index]["grip"]
		var grip: Vector3 = candidate["point"]
		for side: int in [lead_preference, 1 - lead_preference]:
			var feet := _feet_for_grip(grip, side)
			if is_mount and feet.y < _runner.global_position.y:
				feet.y = _runner.global_position.y + SKIN
			if is_mount and feet.distance_to(_runner.global_position) > 0.55:
				continue
			if use_short_side_hop:
				var body_delta := feet - _runner.global_position
				var body_forward := body_delta.dot(heading)
				var body_vertical := body_delta.dot(frame.y)
				var body_outward := body_delta.dot(frame.z)
				if body_forward < 0.22 or body_forward > 0.70 or absf(body_vertical) > 0.075 or absf(body_outward) > 0.14:
					continue
			if not _point_clear(feet) or not _can_reach(candidate, side, feet):
				continue
			if not is_mount and not jump:
				var support := 1 - side
				var midpoint := _reach_position(_runner.global_position, feet, 0.5)
				if contacts[support].is_empty() or not _can_reach(contacts[support], support, midpoint) or not _can_reach(candidate, side, midpoint):
					continue
			if not _clear_path(feet, jump, is_mount, candidate["point"], origin, use_short_side_hop):
				continue
			var hands := _make_hand_contacts(candidate, candidates, feet, side)
			var result := {"feet": feet, "contacts": hands, "lead": side}
			var paired := not hands[1 - side].is_empty()
			if not paired:
				if not require_pair and fallback.is_empty():
					fallback = result
				continue
			_add_foot_contacts(hands, feet)
			if not weighted_tower_move:
				return result
			var movement_cost := _tower_stance_cost(
				candidate, side, feet, origin, heading, jump, hands, use_short_side_hop
			)
			var cost: float = float(ranked[index]["score"]) + movement_cost
			if cost < best_cost:
				best_cost = cost
				best = result
	if not best.is_empty():
		return best
	if not fallback.is_empty():
		_add_foot_contacts(fallback["contacts"], fallback["feet"])
		return fallback
	return {}


func _tower_stance_cost(
	candidate: Dictionary,
	limb: int,
	feet: Vector3,
	origin: Vector3,
	heading: Vector3,
	jump: bool,
	planned: Array[Dictionary],
	short_side_hop: bool = false
) -> float:
	var point: Vector3 = candidate["point"]
	var diff := point - origin
	var plane_diff := diff - frame.z * diff.dot(frame.z)
	var forward := maxf(0.0, plane_diff.dot(heading))
	var side_distance := (plane_diff - heading * plane_diff.dot(heading)).length()
	var target := _tip(candidate, limb)
	var extension := (target - _joint_origin(limb, feet)).length() / maxf(0.1, _lengths[limb])
	var desired_stride := 0.27 if not jump else (0.48 if short_side_hop else 0.66)
	# Bias for comfortable limb extension and a balanced landing. The weight grows
	# with requested stride so long crossings are chosen only when their stance
	# gives a cleaner catch than other physically reachable candidates.
	var stride_weight := 0.90 if not jump else (0.92 if short_side_hop else 0.72 + 0.30 * clampf(forward / 0.90, 0.0, 1.0))
	var extension_weight := 0.20 if not jump else (0.24 if short_side_hop else 0.28 + 0.24 * clampf(forward / 0.90, 0.0, 1.0))
	var cost := absf(forward - desired_stride) * stride_weight
	cost += side_distance * (1.35 if not jump else (1.45 if short_side_hop else 1.55))
	cost += extension * extension * extension_weight
	var rise := maxf(0.0, feet.y - _runner.global_position.y)
	cost += rise * (0.12 if not jump else (0.14 if short_side_hop else 0.19))
	if short_side_hop:
		var body_delta := feet - _runner.global_position
		cost += absf(body_delta.dot(heading) - 0.48) * 0.65
		cost += absf(body_delta.dot(frame.y)) * 0.60 + absf(body_delta.dot(frame.z)) * 0.45
	var foot_count := int(not planned[2].is_empty()) + int(not planned[3].is_empty())
	cost += float(2 - foot_count) * (0.035 if jump else 0.0)
	return cost


func _feet_for_grip(point: Vector3, limb: int) -> Vector3:
	var capsule := _collider.shape as CapsuleShape3D
	# The sensor hits slightly inside the lip, so allow that inset outside the wall.
	var offset := Vector3(-_offsets[limb].x, -_offsets[limb].y - 0.03, capsule.radius + 0.053)
	return point + frame * offset


func _make_hand_contacts(lead: Dictionary, candidates: Array[Dictionary], feet: Vector3, side: int) -> Array[Dictionary]:
	var planned: Array[Dictionary] = [{}, {}, {}, {}]
	planned[side] = lead
	var other := 1 - side
	if not contacts[other].is_empty() and _can_reach(contacts[other], other, feet):
		if (contacts[other]["point"] as Vector3).distance_to(lead["point"]) >= 0.09:
			planned[other] = contacts[other]
	if planned[other].is_empty():
		planned[other] = _best_contact(candidates, planned, other, feet, (lead["point"] as Vector3).y)
	return planned


func _add_foot_contacts(planned: Array[Dictionary], feet: Vector3) -> void:
	var shoe_center := feet + frame.z * -0.22 + Vector3.UP * 0.17
	var footholds := Geometry.find_contacts(_runner, _face, shoe_center, 0.42)
	for foot in [2, 3]:
		if not contacts[foot].is_empty() and _can_reach(contacts[foot], foot, feet):
			if not _conflicts_with(contacts[foot], planned):
				planned[foot] = contacts[foot]
		if planned[foot].is_empty():
			planned[foot] = _best_contact(footholds, planned, foot, feet, feet.y + 0.09)


func _best_contact(candidates: Array[Dictionary], used: Array[Dictionary], limb: int, feet: Vector3, height: float) -> Dictionary:
	var anchor := _joint_origin(limb, feet)
	var best: Dictionary = {}
	var best_cost := INF
	for candidate in candidates:
		var point: Vector3 = candidate["point"]
		if not _can_reach(candidate, limb, feet) or _conflicts_with(candidate, used):
			continue
		var lateral := absf((point - anchor).dot(frame.x))
		var cost := lateral * 1.3 + absf(point.y - height)
		if cost < best_cost:
			best_cost = cost
			best = candidate
	return best


func _conflicts_with(candidate: Dictionary, used: Array[Dictionary]) -> bool:
	var point: Vector3 = candidate["point"]
	for contact in used:
		if not contact.is_empty() and (contact["point"] as Vector3).distance_squared_to(point) < 0.009:
			return true
	return false


func _shares_hand_collider(candidate: Dictionary) -> bool:
	var collider := candidate.get("collider") as StaticBody3D
	if collider == null:
		return false
	for hand in 2:
		if not contacts[hand].is_empty() and contacts[hand].get("collider") == collider:
			return true
	return false


func _is_tower_summit_contact(candidate: Dictionary) -> bool:
	var current := candidate.get("collider") as Node
	while current != null:
		if current.is_in_group("tower_summit"):
			return true
		current = current.get_parent()
	return false


func _joint_origin(limb: int, feet: Vector3) -> Vector3:
	return feet + frame * _offsets[limb] - frame.z * _body_inset


func _tip(contact: Dictionary, limb: int) -> Vector3:
	var support_normal: Vector3 = contact["top_normal"]
	var outward_normal: Vector3 = contact.get("normal", frame.z)
	if outward_normal.length_squared() < 0.0001:
		outward_normal = frame.z
	return (contact["point"] as Vector3) + support_normal * (HAND_CLEARANCE if limb < 2 else SHOE_CLEARANCE) + outward_normal.normalized() * 0.023


func _can_reach(contact: Dictionary, limb: int, feet: Vector3) -> bool:
	var target := _tip(contact, limb)
	var relative := target - _joint_origin(limb, feet)
	var side := -1.0 if limb % 2 == 0 else 1.0
	if side * (target - feet).dot(frame.x) < -0.11:
		return false
	var extra := 0.052 if limb < 2 else 0.014
	return relative.length() <= _lengths[limb] + extra


func _stance_is_live(stance: Array[Dictionary]) -> bool:
	for side in 2:
		if _contact_is_live(stance[side]):
			return true
	return false


func _contact_is_live(contact: Dictionary) -> bool:
	if contact.is_empty():
		return false
	var collider := contact.get("collider") as StaticBody3D
	if not is_instance_valid(collider) or not collider.is_inside_tree():
		return false
	var point: Vector3 = contact["point"]
	if collider.to_global(contact["collider_local_point"]).distance_squared_to(point) > 0.0009:
		return false
	var hit := _ray(point + Vector3.UP * 0.024, point - Vector3.UP * 0.024)
	return hit.get("collider") == collider and (hit.get("normal", Vector3.ZERO) as Vector3).y >= 0.55


func _clear_path(
	finish: Vector3, jump: bool, mount: bool, grip: Vector3, origin: Vector3,
	short_side_hop: bool = false
) -> bool:
	var previous := _runner.global_position
	var height := _jump_arc_height(finish, grip, origin, short_side_hop) if jump else 0.14 + minf(0.12, maxf(0.0, (finish - previous).y) * 0.17)
	for section in range(1, PATH_CLEARANCE_SAMPLES + 1):
		var t := float(section) / float(PATH_CLEARANCE_SAMPLES)
		var next := _runner.global_position.lerp(finish, t)
		if jump:
			if _is_tower_route():
				next = _jump_position(_runner.global_position, finish, t, height, short_side_hop)
			else:
				next = _legacy_jump_position(_runner.global_position, finish, t, height)
		elif not mount:
			next = _reach_position(_runner.global_position, finish, t)
		if not _clear_segment(previous, next):
			return false
		previous = next
	return true


func _shape_at(feet: Vector3) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _collider.shape
	query.transform = Transform3D(_collider.global_basis, feet + _collider.global_position - _runner.global_position)
	query.exclude = [_runner.get_rid()]
	query.collision_mask = WORLD_MASK
	return query


func _point_clear(feet: Vector3) -> bool:
	return _runner.get_world_3d().direct_space_state.intersect_shape(_shape_at(feet), 1).is_empty()


func _clear_segment(from: Vector3, to: Vector3) -> bool:
	var query := _shape_at(from)
	query.motion = to - from
	var safe := _runner.get_world_3d().direct_space_state.cast_motion(query)
	return safe.size() == 2 and safe[0] >= 0.985 and _point_clear(to)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	return _runner.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK, [_runner.get_rid()])
	)


func _direction(input: Vector2) -> Vector3:
	return (frame.x * input.x - frame.y * input.y).normalized()


func _is_tower_route() -> bool:
	var wall := _face.get("wall") as Node3D
	return wall != null and is_instance_valid(wall) and wall.is_in_group("tower_corner_route")


func get_tower_leap_duration() -> float:
	if phase == Phase.JUMP and _is_tower_route():
		return _duration
	return 0.0


func get_presentation_normal() -> Vector3:
	if phase != Phase.CORNER:
		return frame.z
	var turn_t := _corner_progress(_elapsed / maxf(_duration, 0.001))
	return frame.slerp(_corner_frame, turn_t).orthonormalized().z.normalized()


func _hand_center() -> Vector3:
	if contacts[0].is_empty():
		return contacts[1]["point"]
	if contacts[1].is_empty():
		return contacts[0]["point"]
	return ((contacts[0]["point"] as Vector3) + (contacts[1]["point"] as Vector3)) * 0.5


func present(modifier: Node) -> void:
	var targets: Array[Vector3] = []
	var orientations: Array[Basis] = []
	var weights: Array[float] = []
	var t := clampf(_elapsed / maxf(_duration, 0.001), 0.0, 1.0)
	var pose_frame := frame
	var leap_preload := 0.0
	var tower_jump := phase == Phase.JUMP and _is_tower_route()
	body_weight = 1.0
	if phase == Phase.ATTACH:
		body_weight = smoothstep(0.0, 0.65, t)
	elif phase == Phase.JUMP:
		if tower_jump:
			body_weight = 1.0 - smoothstep(0.20, 0.40, t) + smoothstep(0.72, 0.86, t)
			leap_preload = 1.0 - smoothstep(0.0, _duration * 0.18, _elapsed)
		else:
			# Preserve the existing pose weight curve for ordinary climb walls.
			body_weight = 1.0 - smoothstep(0.13, 0.37, t) + smoothstep(0.78, 1.0, t)
	elif phase == Phase.CORNER:
		pose_frame = frame.slerp(_corner_frame, _corner_progress(t)).orthonormalized()
	for limb in 4:
		var from := contacts[limb]
		var to := _planned[limb]
		var blend := 0.0
		if phase == Phase.ATTACH:
			blend = smoothstep(0.15, 0.85, t)
		elif phase == Phase.REACH:
			if limb == _lead:
				blend = smoothstep(0.05, 0.51, t)
			elif limb < 2:
				blend = smoothstep(0.53, 0.92, t)
			else:
				blend = smoothstep(0.30 + 0.12 * (limb % 2), 0.85 + 0.12 * (limb % 2), t)
		elif phase == Phase.JUMP:
			if tower_jump:
				if limb == _lead:
					blend = smoothstep(0.56, 0.74, t)
				elif limb < 2:
					blend = smoothstep(0.78, 0.93, t)
				else:
					blend = smoothstep(0.84, 0.99, t)
			else:
				blend = smoothstep(0.64, 0.96, t)
		elif phase == Phase.CORNER:
			blend = smoothstep(0.04, 0.96, t)
		var a := _tip(from, limb) if not from.is_empty() else _joint_origin(limb, _runner.global_position)
		var b := _tip(to, limb) if not to.is_empty() else _joint_origin(limb, _runner.global_position)
		var weight := lerpf(0.0 if from.is_empty() else 1.0, 0.0 if to.is_empty() else 1.0, blend)
		var lift := sin(PI * blend) * 0.055 if a.distance_squared_to(b) > 0.002 else 0.0
		if phase == Phase.JUMP:
			weight *= body_weight
		var orientation := _contact_basis(from) if not from.is_empty() else frame
		if not to.is_empty():
			orientation = orientation.slerp(_contact_basis(to), blend)
		targets.append(a.lerp(b, blend) + frame.z * lift)
		orientations.append(orientation)
		weights.append(weight)
	var lead_delta := targets[1] - targets[0]
	var lean := clampf(rad_to_deg(atan2(lead_delta.y, maxf(0.18, lead_delta.dot(frame.x)))), -22.0, 22.0)
	if phase == Phase.JUMP and leap_preload > 0.0:
		# Shift the shoulders toward the hand that remains planted for the push.
		lean += (1.0 if _lead == 0 else -1.0) * 7.0 * leap_preload
		lean = clampf(lean, -28.0, 28.0)
	if weights[0] + weights[1] < 1.6:
		lean = 0.0
	var head_origin := _runner.global_position + pose_frame.y * 0.55 - pose_frame.z * _body_inset
	var look_direction := _wall_climb_gaze_direction(head_origin, pose_frame)
	modifier.set_wall_climb_pose(pose_frame, targets, orientations, weights, lean, look_direction, body_weight)
	if _is_tower_route():
		_present_tower_legs(modifier, t)
		modifier.set_tower_hanging_idle(phase == Phase.HOLD and _neutral_hold_time >= HANG_IDLE_DELAY)


func _wall_climb_gaze_direction(head_origin: Vector3, pose_frame: Basis) -> Vector3:
	var inward := -pose_frame.z.normalized()
	var raised_neutral := inward + pose_frame.y.normalized() * 0.18
	if phase == Phase.HOLD:
		# Keep the catch intent briefly, then let the gaze settle toward a softly raised rest.
		var physics_delta := 1.0 / maxf(1.0, float(Engine.physics_ticks_per_second))
		_gaze_carry_strength = maxf(
			0.0, _gaze_carry_strength - physics_delta / GAZE_CATCH_SETTLE_SECONDS
		)
		var carried := _gaze_carry_direction if _gaze_carry_direction.length_squared() > 0.0001 else raised_neutral
		return raised_neutral.lerp(carried, _gaze_carry_strength).normalized()

	var intent := _wall_climb_traversal_intent(head_origin, pose_frame)
	var side_lead := clampf(intent.x, -1.0, 1.0) * 0.82
	var vertical_lead := 0.18 + maxf(0.0, intent.y) * 0.53 + minf(0.0, intent.y) * 0.25
	# This is a world-space direction from the head: inward to the wall, with signed
	# lateral lead and positive lead for an upward transfer.
	var direction := inward + pose_frame.x * side_lead + pose_frame.y * vertical_lead
	_gaze_carry_direction = direction.normalized()
	_gaze_carry_strength = 1.0
	return _gaze_carry_direction


func _wall_climb_traversal_intent(head_origin: Vector3, pose_frame: Basis) -> Vector2:
	if phase == Phase.CORNER:
		# The corner's Bezier tangent follows the transfer around either side. Project it
		# onto the same interpolated face used by the pose so gaze and wall axes agree.
		var progress := clampf(_elapsed / maxf(_duration, 0.001), 0.0, 1.0)
		var sample_delta := 0.045
		var from := _corner_path_position(maxf(0.0, progress - sample_delta))
		var to := _corner_path_position(minf(1.0, progress + sample_delta))
		var tangent := to - from
		var corner_intent := Vector2(tangent.dot(pose_frame.x), tangent.dot(pose_frame.y))
		if corner_intent.length_squared() > 0.0001:
			return corner_intent.normalized()

	var hold_origin := head_origin
	if not contacts[0].is_empty() or not contacts[1].is_empty():
		hold_origin = _hand_center()
	var hold_intent := Vector2.ZERO
	if _lead >= 0 and _lead < _planned.size() and not _planned[_lead].is_empty():
		var next_hold: Vector3 = _planned[_lead]["point"]
		var hold_delta := next_hold - hold_origin
		hold_intent = Vector2(hold_delta.dot(pose_frame.x), hold_delta.dot(pose_frame.y))
	var body_delta := _finish - _start
	var body_intent := Vector2(body_delta.dot(pose_frame.x), body_delta.dot(pose_frame.y))
	if hold_intent.length_squared() > 0.0001:
		hold_intent = hold_intent.normalized()
		if body_intent.length_squared() > 0.0001:
			hold_intent = (hold_intent * 0.65 + body_intent.normalized() * 0.35).normalized()
		return hold_intent
	if body_intent.length_squared() > 0.0001:
		return body_intent.normalized()
	var input_intent := Vector2(_last_direction.dot(pose_frame.x), _last_direction.dot(pose_frame.y))
	return input_intent.normalized() if input_intent.length_squared() > 0.0001 else Vector2.UP


func _present_tower_legs(modifier: Node, progress: float) -> void:
	var push := 0.0
	var tuck := 0.0
	var settle := 0.0
	var step := 0.0
	if phase == Phase.JUMP:
		push = sin(PI * smoothstep(0.0, 0.29, progress))
		tuck = smoothstep(0.16, 0.43, progress) * (1.0 - smoothstep(0.62, 0.90, progress))
		if _short_side_hop:
			tuck *= 0.72
		settle = sin(PI * smoothstep(0.70, 1.0, progress))
	elif phase == Phase.REACH or phase == Phase.CORNER:
		step = sin(PI * smoothstep(0.10, 0.94, progress))
	modifier.set_wall_climb_leg_motion(push, tuck, settle, step, _lead)


func _contact_basis(contact: Dictionary) -> Basis:
	var up: Vector3 = contact["top_normal"]
	var normal: Vector3 = contact.get("normal", frame.z)
	normal.y = 0.0
	if normal.length_squared() < 0.0001:
		normal = frame.z
	normal = normal.normalized()
	var right := up.cross(normal).normalized()
	return Basis(right, up, normal).orthonormalized()
