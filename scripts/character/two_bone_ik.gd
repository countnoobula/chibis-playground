class_name TwoBoneIK
extends RefCounted

## Analytical 2-bone IK solver matching Unreal's AnimationCore::SolveTwoBoneIK
## and ClimbingStation::Solve (law of cosines + pole-plane projection + optional protraction).


static func quaternion_from_to(from_dir: Vector3, to_dir: Vector3) -> Quaternion:
	var f := from_dir.normalized()
	var t := to_dir.normalized()
	var d := clampf(f.dot(t), -1.0, 1.0)
	if d > 0.999999:
		return Quaternion.IDENTITY
	if d < -0.999999:
		var ortho := Vector3.UP if absf(f.y) < 0.9 else Vector3.RIGHT
		var axis := f.cross(ortho).normalized()
		return Quaternion(axis, PI)
	var axis := f.cross(t)
	var s := sqrt((1.0 + d) * 2.0)
	return Quaternion(axis.x / s, axis.y / s, axis.z / s, s * 0.5).normalized()


## Builds a right-handed orthonormal Basis with -Z (or +X) aligned cleanly.
## Mirrors Unreal FRotationMatrix::MakeFromXZ(forward_x, up_z) in Godot space:
##   basis.x = right = forward.cross(normal)
##   basis.y = normal (surface up)
##   basis.z = -forward (so -Z points inward along fingers!)
static func basis_from_forward_up(forward: Vector3, up: Vector3) -> Basis:
	var f := forward.normalized()
	var u := up.normalized()
	var r := f.cross(u)
	if r.length_squared() < 1e-8:
		var fallback := Vector3.RIGHT if absf(f.x) < 0.9 else Vector3.FORWARD
		r = f.cross(fallback)
	r = r.normalized()
	u = r.cross(f).normalized()
	return Basis(r, u, -f).orthonormalized()


## Solves a 3-joint chain (upper, lower, tip) in a common space (world or skeleton space).
## Returns Dictionary: { "upper": Transform3D, "lower": Transform3D, "tip": Transform3D }
static func solve_chain(
	upper: Transform3D,
	lower: Transform3D,
	tip: Transform3D,
	target_pos: Vector3,
	pole_dir: Vector3,
	allow_protraction: bool = false,
	max_protraction: float = 0.08
) -> Dictionary:
	var a := upper.origin
	var b := lower.origin
	var c := tip.origin

	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	if l1 < 1e-5 or l2 < 1e-5:
		return {"upper": upper, "lower": lower, "tip": tip}

	var to_target := target_pos - a
	var raw_dist := to_target.length()
	var dir := to_target / raw_dist if raw_dist > 1e-6 else Vector3.FORWARD

	# Shoulder/hip protraction supplies the last few centimetres at full extension (ClimbingStation::Solve)
	if allow_protraction:
		var excess := maxf(0.0, raw_dist - (l1 + l2) + 0.0002)
		if max_protraction > 0.0:
			excess = minf(excess, max_protraction)
		if excess > 0.0:
			var offset := dir * excess
			upper.origin += offset
			lower.origin += offset
			tip.origin += offset
			a += offset
			b += offset
			c += offset

	var min_d := absf(l1 - l2) + 0.0005
	var max_d := (l1 + l2) - 0.0005
	var d := clampf((target_pos - a).length(), min_d, max_d)
	var along := (d * d + l1 * l1 - l2 * l2) / (2.0 * d)
	var perp_len := sqrt(maxf(0.0, l1 * l1 - along * along))

	# Project pole direction onto plane perpendicular to dir
	var pole_proj := pole_dir - dir * pole_dir.dot(dir)
	if pole_proj.length_squared() < 1e-8:
		var cur_bend := (b - a) - dir * (b - a).dot(dir)
		if cur_bend.length_squared() > 1e-8:
			pole_proj = cur_bend
		else:
			pole_proj = dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT)
	pole_proj = pole_proj.normalized()

	var joint_pos := a + dir * along + pole_proj * perp_len

	# Rotate upper bone so (b - a) aligns with (joint_pos - a)
	var q_upper := quaternion_from_to(b - a, joint_pos - a)
	var rot_upper := Basis(q_upper)
	var new_upper := Transform3D((rot_upper * upper.basis).orthonormalized(), a)

	# Carry lower and tip rigidly with upper rotation
	var new_lower_origin := joint_pos
	var new_lower_basis := (rot_upper * lower.basis).orthonormalized()
	var carried_tip_origin := a + rot_upper * (c - a)
	var carried_tip_basis := (rot_upper * tip.basis).orthonormalized()

	# Rotate lower bone so (carried_tip_origin - joint_pos) aligns with (target_pos - joint_pos)
	var q_lower := quaternion_from_to(carried_tip_origin - new_lower_origin, target_pos - new_lower_origin)
	var rot_lower := Basis(q_lower)
	var new_lower := Transform3D((rot_lower * new_lower_basis).orthonormalized(), new_lower_origin)
	var final_tip_origin := new_lower_origin + rot_lower * (carried_tip_origin - new_lower_origin)
	var final_tip_basis := (rot_lower * carried_tip_basis).orthonormalized()
	var new_tip := Transform3D(final_tip_basis, final_tip_origin)

	return {"upper": new_upper, "lower": new_lower, "tip": new_tip}
