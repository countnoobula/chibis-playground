class_name RopeSwingSolver
extends RefCounted

## 120Hz substepped energy-capped pendulum solver ported verbatim from ChibiRopeSwing.cpp
## (converted to meters: g = 9.8 m/s^2).


## Returns Vector2(next_angle_rad, next_angular_velocity_rad_s)
static func advance(
	delta_seconds: float,
	angle: float,
	angular_velocity: float,
	rope_length: float,
	input: float,
	pump_accel: float,
	max_angle: float
) -> Vector2:
	var gravity := 9.8 / maxf(0.1, rope_length)
	var arc := clampf(max_angle + deg_to_rad(20.0), 0.1, deg_to_rad(85.0))
	var arc_energy := gravity * (1.0 - cos(arc))
	var drive := clampf(input, -1.0, 1.0) * clampf(pump_accel, 0.0, 0.24 * gravity)

	var time := clampf(delta_seconds, 0.0, 0.25)
	var steps := maxi(1, int(ceil(time * 120.0)))
	var dt := time / float(steps)

	for _i in steps:
		var energy := 0.5 * angular_velocity * angular_velocity + gravity * (1.0 - cos(angle))
		var ratio := energy / maxf(1e-6, arc_energy)
		var assist := 1.0 - smoothstep(0.72, 1.0, ratio)
		var drag := 0.12 + 3.0 * maxf(0.0, ratio - 1.0)
		angular_velocity += dt * (drive * assist * cos(angle) - gravity * sin(angle) - drag * angular_velocity)
		angle += dt * angular_velocity

	return Vector2(angle, angular_velocity)
