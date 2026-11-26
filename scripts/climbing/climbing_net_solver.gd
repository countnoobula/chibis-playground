class_name ClimbingNetSolver
extends RefCounted

## 6x18 Verlet particle solver ported 1:1 from Plugins/ChibiContact/Private/ClimbingNet.cpp
## converted cleanly to Godot meters + Y-up (+Z toward climber, -Z backing panel, +X across, +Y up).

const COLS := 6
const ROWS := 18
const COUNT := COLS * ROWS
const SUBSTEP := 1.0 / 90.0

var rest: PackedVector3Array = PackedVector3Array()
var position: PackedVector3Array = PackedVector3Array()
var previous: PackedVector3Array = PackedVector3Array()
var force: PackedVector3Array = PackedVector3Array()
var pinned: PackedByteArray = PackedByteArray()

# Links stored as flat arrays for fast tight-loop iteration in GDScript
var _link_a: PackedInt32Array = PackedInt32Array()
var _link_b: PackedInt32Array = PackedInt32Array()
var _link_len: PackedFloat32Array = PackedFloat32Array()
var _link_stiff: PackedFloat32Array = PackedFloat32Array()

var _time_bank: float = 0.0
var _offsets_cache: PackedVector3Array = PackedVector3Array()


static func grid_coords(p: Vector3) -> Vector2:
	# Unreal P.Z in [7..265] cm -> Godot P.y in [0.07..2.65] m
	# Unreal P.Y in [-50..+50] cm -> Godot P.x in [-0.50..+0.50] m
	var y := clampf(p.y, 0.07, 2.65)
	var row: float
	if y < 0.16:
		row = (y - 0.07) / 0.09
	elif y > 2.56:
		row = 16.0 + (y - 2.56) / 0.09
	else:
		row = 1.0 + (y - 0.16) / 0.16
	var col := clampf((p.x + 0.50) / 0.20, 0.0, 5.0)
	return Vector2(col, row)


static func idle_offset(p: Vector3) -> Vector3:
	# Unreal IdleOffset: (-3*(1-u^2) - 2*(1-v^2), 0, -5*(1-u^2) - 2*(1-v^2)) cm
	# In Godot meters: +Z is front (-Unreal X), +Y is up (+Unreal Z)
	var u := clampf(p.x / 0.50, -1.0, 1.0)
	var v := clampf((p.y - 1.36) / 1.29, -1.0, 1.0)
	var su := 1.0 - u * u
	var sv := 1.0 - v * v
	return Vector3(0.0, -0.05 * su - 0.02 * sv, 0.03 * su + 0.02 * sv)


func initialize() -> void:
	rest.resize(COUNT)
	position.resize(COUNT)
	previous.resize(COUNT)
	force.resize(COUNT)
	pinned.resize(COUNT)
	_offsets_cache.resize(COUNT)

	_link_a.clear()
	_link_b.clear()
	_link_len.clear()
	_link_stiff.clear()
	_time_bank = 0.0

	for r in ROWS:
		for c in COLS:
			var i := r * COLS + c
			var y := 0.07 if r == 0 else (2.65 if r == ROWS - 1 else 0.16 + float(r - 1) * 0.16)
			var rp := Vector3(-0.50 + 0.20 * float(c), y, 0.19)
			rest[i] = rp
			var start_p := rp + idle_offset(rp)
			position[i] = start_p
			previous[i] = start_p
			force[i] = Vector3.ZERO
			pinned[i] = 1 if ((c == 0 or c == COLS - 1) and (r == 0 or r == ROWS - 1)) else 0

			if c > 0:
				_add_link(i, i - 1, 1.035, 0.93)
			if r > 0:
				_add_link(i, i - COLS, 1.02, 0.93)
			if r > 0 and c > 0:
				_add_link(i, i - COLS - 1, 1.025, 0.12)
			if r > 0 and c + 1 < COLS:
				_add_link(i, i - COLS + 1, 1.025, 0.12)

	for _k in 180:
		_substep()
	_refresh_offsets()


func _add_link(a: int, b: int, slack: float, stiffness: float) -> void:
	_link_a.append(a)
	_link_b.append(b)
	_link_len.append(rest[a].distance_to(rest[b]) * slack)
	_link_stiff.append(stiffness)


func load_point(rest_contact: Vector3, acceleration: Vector3) -> void:
	var g := grid_coords(rest_contact)
	var x := mini(int(floor(g.x)), COLS - 2)
	var y := mini(int(floor(g.y)), ROWS - 2)
	var fx := g.x - float(x)
	var fy := g.y - float(y)
	for b in 2:
		for a in 2:
			var w := (fx if a == 1 else 1.0 - fx) * (fy if b == 1 else 1.0 - fy)
			var idx := (y + b) * COLS + (x + a)
			force[idx] += acceleration * w


func advance(delta: float) -> bool:
	_time_bank += minf(delta, 0.1)
	var changed := false
	while _time_bank >= SUBSTEP:
		_substep()
		_time_bank -= SUBSTEP
		changed = true
	for i in COUNT:
		force[i] = Vector3.ZERO
	if changed:
		_refresh_offsets()
	return changed


func _substep() -> void:
	var dt2 := SUBSTEP * SUBSTEP
	for i in COUNT:
		if pinned[i] == 1:
			continue
		var p := position[i]
		var v := (p - previous[i]) * 0.979
		previous[i] = p
		# Gravity -2.80 m/s^2 + applied limb load + weak recovery toward idle sag
		var acc := Vector3(0.0, -2.80, 0.0) + force[i] + (rest[i] + idle_offset(rest[i]) - p) * 14.0
		position[i] = p + v + acc * dt2

	var link_count := _link_a.size()
	for _pass in 8:
		for k in link_count:
			var ia := _link_a[k]
			var ib := _link_b[k]
			var pa := position[ia]
			var pb := position[ib]
			var d := pb - pa
			var length := d.length()
			var target_len := _link_len[k]
			if length <= target_len or length < 1e-6:
				continue # Slack strand transmits tension only
			var wa := 0.0 if pinned[ia] == 1 else 1.0
			var wb := 0.0 if pinned[ib] == 1 else 1.0
			var wsum := wa + wb
			if wsum <= 0.0:
				continue
			var corr := d * (_link_stiff[k] * (length - target_len) / (length * wsum))
			if wa > 0.0:
				position[ia] = pa + corr
			if wb > 0.0:
				position[ib] = pb - corr

		for i in COUNT:
			if pinned[i] == 0:
				var p := position[i]
				# Backing panel clearance: Unreal X <= -4 cm -> Godot Z >= +0.04 m; floor Y >= +0.03 m
				if p.z < 0.04:
					p.z = 0.04
				if p.y < 0.03:
					p.y = 0.03
				position[i] = p


func _refresh_offsets() -> void:
	for i in COUNT:
		_offsets_cache[i] = position[i] - rest[i]


func get_packed_offsets() -> PackedVector3Array:
	return _offsets_cache


func sample_offset(rest_contact: Vector3) -> Vector3:
	var g := grid_coords(rest_contact)
	var x := mini(int(floor(g.x)), COLS - 2)
	var y := mini(int(floor(g.y)), ROWS - 2)
	var fx := g.x - float(x)
	var fy := g.y - float(y)
	var i := y * COLS + x
	var o00 := _offsets_cache[i]
	var o10 := _offsets_cache[i + 1]
	var o01 := _offsets_cache[i + COLS]
	var o11 := _offsets_cache[i + COLS + 1]
	return o00.lerp(o10, fx).lerp(o01.lerp(o11, fx), fy)
