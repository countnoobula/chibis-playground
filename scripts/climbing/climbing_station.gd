class_name ClimbingStation
extends Node3D

## Unified Bouldering Wall (wall_route.json + PlaceFoot smearing + spine/neck lean)
## and Dynamic Deforming Rope Net (6x18 Verlet solver + continuous 2D analog movement),
## ported from Plugins/ChibiContact/Private/ClimbingStation.cpp.

@export var is_rope_net: bool = false
@export var route_json_path: String = "res://assets/stations/wall_route.json"
@export var surface_mesh: MeshInstance3D

const NET_DEFORM_SHADER := preload("res://shaders/rope_net_deform.gdshader")
const PALETTE := preload("res://scripts/gym/rooftop_palette.gd")

var net_solver: ClimbingNetSolver = null
var _net_materials: Array[ShaderMaterial] = []

var _runner: ParkourController = null
var _auto_grab_after: float = 0.0

# Wall route data (local Godot meters: +X right, +Y up, +Z toward climber)
var _bands: Array = []
var _foot_supports: Array[Vector3] = []
var _cell: Vector2i = Vector2i.ZERO
var _step: Vector2i = Vector2i.ZERO
var _phase: float = 0.0
var _lead: int = 0
var _next_lead: int = 0

var _contacts: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _contact_locked: Array[bool] = [true, true, true, true]
var _foot_goal: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _foot_from: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _foot_phase: Array[float] = [1.0, 1.0]

# Rope net continuous climb state
var _net_stance: Vector2 = Vector2.ZERO
var _net_reach_target: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _net_contact: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _net_load_weight: Array[float] = [1.0, 1.0, 1.0, 1.0]
var _net_swing_foot: int = 3
var _net_body_pos: Vector3 = Vector3.ZERO


func _ready() -> void:
	if surface_mesh == null:
		surface_mesh = _find_first_mesh(self)
	_apply_surface_palette()
	if is_rope_net:
		net_solver = ClimbingNetSolver.new()
		net_solver.initialize()
		_upload_net()
	else:
		_load_route_json()


func _find_first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_first_mesh(c)
		if r != null:
			return r
	return null


func _apply_surface_palette() -> void:
	_net_materials.clear()
	if surface_mesh == null or surface_mesh.mesh == null:
		return
	# The imported materials keep their surface names, but all have the same gray albedo.
	var colors := {
		"Ink": PALETTE.SUPPORT.darkened(0.22),
		"Petrol": PALETTE.SUPPORT,
		"Basalt": PALETTE.SUPPORT.darkened(0.11),
		"Coral": PALETTE.CORAL,
		"Mint": PALETTE.MINT,
		"Ochre": PALETTE.PEACH,
		"Flax": PALETTE.PORCELAIN,
		"Binding": PALETTE.LIGHT_SUPPORT,
		"Steel": PALETTE.LIGHT_SUPPORT,
	}
	for s in surface_mesh.mesh.get_surface_count():
		var base_mat := surface_mesh.get_active_material(s) as StandardMaterial3D
		if base_mat == null or not colors.has(base_mat.resource_name):
			continue
		var mat_name := base_mat.resource_name
		var col: Color = colors[mat_name]
		if is_rope_net and mat_name in ["Flax", "Ochre", "Binding"]:
			var rope_mat := ShaderMaterial.new()
			rope_mat.shader = NET_DEFORM_SHADER
			rope_mat.set_shader_parameter("albedo_color", col)
			surface_mesh.set_surface_override_material(s, rope_mat)
			_net_materials.append(rope_mat)
		else:
			var mat := base_mat.duplicate() as StandardMaterial3D
			mat.albedo_color = col
			mat.roughness = 0.78
			surface_mesh.set_surface_override_material(s, mat)


func _upload_net() -> void:
	if net_solver == null:
		return
	var packed := net_solver.get_packed_offsets()
	for sm in _net_materials:
		sm.set_shader_parameter("net_offsets", packed)


func _load_route_json() -> void:
	_bands.clear()
	_foot_supports.clear()
	if not FileAccess.file_exists(route_json_path):
		return
	var txt := FileAccess.get_file_as_string(route_json_path)
	var data = JSON.parse_string(txt)
	if not (data is Dictionary):
		return
	for band_raw in data.get("bands", []):
		var band: Array[Vector3] = []
		for pt in band_raw:
			var v := Vector3(float(pt[0]), float(pt[1]), float(pt[2]))
			band.append(v)
			_foot_supports.append(v)
		if band.size() >= 2:
			_bands.append(band)
	for pt in data.get("toe_chips", []):
		_foot_supports.append(Vector3(float(pt[0]), float(pt[1]), float(pt[2])))


func _nearest_pair(row: int, x_pos: float) -> int:
	var best := -1
	var best_d := INF
	var band: Array = _bands[row]
	for i in band.size() - 1:
		var a: Vector3 = band[i]
		var b: Vector3 = band[i + 1]
		if a.distance_to(b) > 0.46:
			continue
		var d := absf(0.5 * (a.x + b.x) - x_pos)
		if d < best_d:
			best_d = d
			best = i
	return best


func _anchor(limb: int, stance: Vector2i) -> Vector3:
	if not is_rope_net:
		var grip: Vector3 = _bands[stance.y + 1][stance.x + (limb % 2)]
		if limb >= 2:
			var ideal := grip - Vector3(0.0, 0.35, 0.0)
			var lower: Array = _bands[stance.y]
			var best_g: Vector3 = lower[0]
			var best_dsq := INF
			for p in lower:
				var dsq := (p as Vector3).distance_squared_to(ideal)
				if dsq < best_dsq:
					best_dsq = dsq
					best_g = p
			grip = best_g
		var off := Vector3(-0.022 if limb == 0 else (0.022 if limb == 1 else 0.0), 0.01 if limb < 2 else 0.05, 0.03 if limb < 2 else 0.05)
		return grip + off

	var col := stance.x + (0 if (limb % 2 == 1) else -1)
	var row := stance.y + (2 if limb < 2 else -1)
	var x := 0.20 * float(col) + 0.10
	var rope_y := 0.07 if row < 0 else (0.16 + 0.16 * float(row))
	return Vector3(x, rope_y + (0.01 if limb < 2 else 0.06), 0.19 + (0.028 if limb < 2 else 0.05))


func _physics_process(delta: float) -> void:
	_update_net(delta)
	var now := Time.get_ticks_msec() * 0.001

	if _runner == null:
		var player := get_tree().get_first_node_in_group("player") as ParkourController
		if player == null or player.current_state != "Locomotion":
			return
		var local_p := to_local(player.get_capsule_center())
		# Climber approaches from +Z toward Z=0 backing panel
		var half_w := 0.60 if is_rope_net else 1.40
		if local_p.z <= -0.04 or local_p.z >= 0.95 or absf(local_p.x) >= half_w or local_p.y <= 0.0:
			return
		var grab_depth := player.config.capsule_radius + (0.23 if is_rope_net else 0.08)
		var wall_inward := (-global_transform.basis.z).normalized()
		var approaching := player.velocity.dot(wall_inward) > 0.05
		if not approaching and player.chibi_input != null and player.camera_ctrl != null:
			var stick := player.chibi_input.move_vec
			var wish := player.camera_ctrl.get_right_xz() * stick.x - player.camera_ctrl.get_forward_xz() * stick.y
			approaching = wish.dot(wall_inward) > 0.18
		var auto_grab := local_p.z <= grab_depth and local_p.y <= 2.64 and now >= _auto_grab_after and approaching
		if auto_grab:
			_mount(player, local_p)
		return

	if _runner.chibi_input != null and _runner.chibi_input.jump_just_pressed:
		_release()
		return

	var move_in := _runner.chibi_input.move_vec if _runner.chibi_input else Vector2.ZERO
	# move_vec.y is negative when pressing W/Up -> invert so +Y is climbing UP!
	var climb_in := Vector2(move_in.x, -move_in.y)

	if is_rope_net:
		_move_on_net(climb_in, delta)
		_apply_pose(delta)
		return

	var vert := (1 if climb_in.y > 0.35 else (-1 if climb_in.y < -0.35 else 0))
	var horiz := (1 if climb_in.x > 0.35 else (-1 if climb_in.x < -0.35 else 0))

	if _step == Vector2i.ZERO:
		var req := Vector2i(horiz if vert == 0 else 0, vert)
		var dest := _cell + req
		var valid := false
		if req != Vector2i.ZERO and dest.y >= 0 and dest.y + 1 < _bands.size():
			var band: Array = _bands[dest.y + 1]
			if vert != 0:
				var mid_x := (_anchor(0, _cell).x + _anchor(1, _cell).x) * 0.5
				dest.x = _nearest_pair(dest.y + 1, mid_x)
			valid = dest.x >= 0 and dest.x + 1 < band.size() and (band[dest.x + 1] as Vector3).distance_to(band[dest.x]) < 0.46
			if valid and vert != 0:
				var span := minf(
					_anchor(0, dest).distance_to(_anchor(1, _cell)),
					_anchor(1, dest).distance_to(_anchor(0, _cell))
				)
				valid = span < 0.55 and _anchor(0, dest).distance_to(_anchor(0, _cell)) < 0.58 and _anchor(1, dest).distance_to(_anchor(1, _cell)) < 0.58
		if valid:
			_step = dest - _cell
			_lead = _next_lead if vert != 0 else (1 if horiz < 0 else 0)
			if vert != 0:
				var left_d := _anchor(0, dest).distance_to(_anchor(1, _cell))
				var right_d := _anchor(1, dest).distance_to(_anchor(0, _cell))
				if absf(left_d - right_d) > 0.04:
					_lead = 1 if right_d < left_d else 0
			_phase = 0.0

	if _step != Vector2i.ZERO:
		_phase = minf(1.0, _phase + delta / 0.94)
		if _phase >= 1.0:
			_cell += _step
			_step = Vector2i.ZERO
			_phase = 0.0
			_next_lead = 1 - _lead
			for i in 4:
				_contacts[i] = _anchor(i, _cell)

	_apply_pose(delta)


func _mount(player: ParkourController, local_p: Vector3) -> void:
	if not is_rope_net and _bands.size() < 2:
		_load_route_json()
		if _bands.size() < 2:
			return
	if is_rope_net:
		var best := INF
		for r in range(0, 14):
			for c in range(-2, 3):
				var cand := Vector2i(c, r)
				var knot := _anchor(0, cand) + Vector3(0.10, -0.01, 0.0)
				var center := knot + (net_solver.sample_offset(knot) if net_solver else Vector3.ZERO)
				var d := pow(local_p.x - center.x, 2.0) + pow(local_p.y - center.y - 0.10, 2.0)
				if d < best:
					best = d
					_cell = cand
	else:
		var best := INF
		for r in range(1, _bands.size()):
			var c := _nearest_pair(r, local_p.x)
			if c < 0:
				continue
			var mid: Vector3 = (_bands[r][c] + _bands[r][c + 1]) * 0.5
			var d := pow(mid.x - local_p.x, 2.0) + pow(mid.y - (local_p.y - 0.10), 2.0)
			if d < best:
				best = d
				_cell = Vector2i(c, r - 1)
		if best == INF:
			return

	_runner = player
	_step = Vector2i.ZERO
	_phase = 0.0
	_next_lead = 0
	for i in 4:
		_contacts[i] = _anchor(i, _cell)
		_contact_locked[i] = true
	if is_rope_net:
		_net_stance = Vector2(_cell.x, _cell.y)
		_phase = 1.0
		_lead = 0
		_net_swing_foot = 3
		for i in 4:
			_net_reach_target[i] = _contacts[i]
			_net_load_weight[i] = 1.0
	for i in 2:
		_foot_goal[i] = _contacts[2 + i]
		_foot_from[i] = _foot_goal[i]
		_foot_phase[i] = 1.0

	var wall_normal_world := global_transform.basis.z.normalized() # +Z faces climber
	_runner.enter_climbing_station(self, is_rope_net, wall_normal_world)
	if _runner.juice:
		_runner.juice.play_sfx("LedgeGrab")
	_apply_pose(0.0)


func _release() -> void:
	if _runner == null:
		return
	var push_out := global_transform.basis.z.normalized()
	_runner.exit_climbing_station(push_out)
	_runner = null
	_auto_grab_after = Time.get_ticks_msec() * 0.001 + 0.40


func _update_net(delta: float) -> void:
	if net_solver == null:
		return
	if _runner != null:
		var total_w := 0.0
		for i in 4:
			total_w += _net_load_weight[i] * (0.32 if i < 2 else 0.18)
		if total_w > 0.0:
			for i in 4:
				if _net_load_weight[i] > 0.0:
					var share := _net_load_weight[i] * (0.32 if i < 2 else 0.18) / total_w
					# Unreal Load(-4300, 0, -4800) cm/s^2 -> Godot (0, -48.0, +43.0) m/s^2
					net_solver.load_point(_net_contact[i], Vector3(0.0, -48.0, 43.0) * share)
	if net_solver.advance(delta):
		_upload_net()


func _move_on_net(input: Vector2, delta: float) -> void:
	_net_stance += input * (delta / 0.68)
	_net_stance.x = clampf(_net_stance.x, -2.0, 2.0)
	_net_stance.y = clampf(_net_stance.y, 0.0, 13.0)
	if _phase < 1.0:
		_phase = minf(1.0, _phase + delta / 0.32)
		if _phase < 1.0:
			return
		_contacts[_lead] = _net_reach_target[_lead]
		_contacts[_net_swing_foot] = _net_reach_target[_net_swing_foot]
		_next_lead = 1 - _lead

	var nearest := Vector2i(int(round(_net_stance.x)), int(round(_net_stance.y)))
	for attempt in 2:
		var hand := (1 - _next_lead) if attempt == 1 else _next_lead
		var other := 1 - hand
		var side_err := _anchor(hand, nearest).x - _contacts[hand].x
		if absf(side_err) > 0.01 and absf(_anchor(hand, nearest).x - _contacts[other].x) < 0.01 and absf(_anchor(other, nearest).x - _contacts[other].x) > 0.01:
			continue
		var foot := 2 + (hand if absf(side_err) > 0.01 else other)
		var hand_t := _anchor(hand, nearest)
		var foot_t := _anchor(foot, nearest)
		if _contacts[hand].is_equal_approx(hand_t) and _contacts[foot].is_equal_approx(foot_t):
			continue
		_lead = hand
		_net_swing_foot = foot
		_net_reach_target[hand] = hand_t
		_net_reach_target[foot] = foot_t
		_phase = 0.0
		break


func _net_limb_target(limb: int) -> Vector3:
	var moving := (limb == _lead or limb == _net_swing_foot) and _phase < 1.0 and not _contacts[limb].is_equal_approx(_net_reach_target[limb])
	var swing := clampf((_phase - (0.0 if limb < 2 else 0.1)) / 0.9, 0.0, 1.0) if moving else 0.0
	var t := smoothstep(0.0, 1.0, swing)
	var target := _contacts[limb].lerp(_net_reach_target[limb], t)
	target.z += 0.03 * sin(PI * t)
	_contact_locked[limb] = (swing == 0.0 or swing == 1.0)
	_net_load_weight[limb] = 1.0 - smoothstep(0.0, 0.14, swing) + smoothstep(0.86, 1.0, swing)
	_net_contact[limb] = target - Vector3(0.0, 0.01 if limb < 2 else 0.06, 0.0)
	return target + (net_solver.sample_offset(_net_contact[limb]) if net_solver else Vector3.ZERO)


func _place_foot(side: int, delta: float, hip_local: Vector3) -> Vector3:
	var ideal := hip_local + Vector3(0.02 if side == 1 else -0.02, -0.11, -0.07)
	if _foot_phase[side] >= 1.0 and (
		_foot_goal[side].distance_to(hip_local) > 0.187
		or _foot_goal[side].z < 0.06
		or _foot_goal[side].distance_to(_foot_goal[1 - side]) < 0.10
	):
		var best := Vector3(ideal.x, ideal.y, 0.045) # Wall friction smear fallback
		var best_score := INF
		for grip in _foot_supports:
			var ankle := grip + Vector3(0.0, 0.05, 0.05)
			if ankle.distance_to(_foot_goal[1 - side]) < 0.10 or ankle.distance_to(hip_local) > 0.185 or ankle.y > hip_local.y + 0.08:
				continue
			var dsq := ankle.distance_squared_to(ideal)
			if dsq < best_score:
				best_score = dsq
				best = ankle
		if best.distance_to(_foot_goal[side]) > 0.025:
			_foot_from[side] = _foot_goal[side]
			_foot_goal[side] = best
			_foot_phase[side] = 0.0

	_foot_phase[side] = minf(1.0, _foot_phase[side] + delta / 0.18)
	var t := smoothstep(0.0, 1.0, _foot_phase[side])
	return _foot_from[side].lerp(_foot_goal[side], t) + Vector3(0.0, 0.0, 0.02 * sin(PI * t))


func _apply_pose(delta: float) -> void:
	if _runner == null:
		return
	var targets: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	for i in 4:
		if is_rope_net:
			targets[i] = _net_limb_target(i)
		else:
			var first := ((i % 2) == _lead) != (i >= 2)
			var reach := clampf(_phase * 2.0 - (0.0 if first else 1.0), 0.0, 1.0)
			var t := smoothstep(0.12, 0.86, reach)
			targets[i] = _contacts[i].lerp(_anchor(i, _cell + _step), t)
			targets[i].z += 0.05 * sin(PI * t)
			_contact_locked[i] = (t == 0.0 or t == 1.0)

	var mid := (targets[0] + targets[1]) * 0.5
	var pulse := sin(_phase * 2.0 * PI)
	var lean_deg := 0.0
	if not is_rope_net:
		lean_deg = clampf(rad_to_deg(atan2(targets[1].y - targets[0].y, maxf(0.17, targets[1].x - targets[0].x))), -42.0, 42.0)

	# Roll shoulder line toward higher grip; hips counterbalance beneath it
	var tilt := Basis(Vector3.FORWARD, deg_to_rad(lean_deg))
	var shoulder_off := tilt * Vector3(0.0, 0.22, 0.0)
	# Godot feet position = center - 0.60 m -> mid.y - shoulder_off.y - 0.33 m
	var base := Vector3(
		mid.x - shoulder_off.x,
		mid.y - shoulder_off.y - 0.33 - (0.05 if is_rope_net else 0.0),
		mid.z + (0.10 if is_rope_net else 0.12)
	)
	base.x += (-1.0 if _lead == 1 else 1.0) * pulse * (0.017 if is_rope_net else 0.036)
	base.y -= (0.0065 if is_rope_net else 0.028) * pulse * pulse

	if is_rope_net:
		var rest_mid := Vector3(0.20 * _net_stance.x, 0.49 + 0.16 * _net_stance.y, 0.218)
		var hand_mid := (_net_contact[0] + _net_contact[1]) * 0.5 + Vector3(0.0, 0.01, 0.0)
		base += rest_mid - hand_mid
		_net_body_pos = base if delta <= 0.0 else _net_body_pos.lerp(base, 1.0 - exp(-16.0 * delta))
		base = _net_body_pos

	_runner.global_position = to_global(base)
	var face := (-global_transform.basis.z).normalized()
	_runner.rotation.y = atan2(-face.x, -face.z)

	if not is_rope_net:
		for side in 2:
			var hip_approx := base + Vector3(0.082 if side == 1 else -0.082, 0.252, 0.0)
			targets[2 + side] = _place_foot(side, delta, hip_approx)

	if _runner.pose_mod != null:
		_runner.pose_mod.climb_lean_deg = lean_deg
		_runner.pose_mod.climb_station_basis = global_transform.basis
		for i in 4:
			_runner.pose_mod.climb_limb_targets_world[i] = to_global(targets[i])
