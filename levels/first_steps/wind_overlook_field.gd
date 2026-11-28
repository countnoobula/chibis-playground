extends "res://features/runner/wind_field_3d.gd"

## Strong, bounded tailwind for the First Steps overlook glide.

@export var half_extents := Vector3(4.8, 3.95, 3.0)
@export var local_flow_direction := Vector3.RIGHT
@export_range(0.0, 16.0, 0.1) var flow_speed := 8.2
@export_range(0.0, 1.5, 0.05) var edge_fade_distance := 0.5


func contains_point(world_position: Vector3) -> bool:
	var point := to_local(world_position)
	return absf(point.x) <= half_extents.x \
		and absf(point.y) <= half_extents.y \
		and absf(point.z) <= half_extents.z


func flow_velocity_at(world_position: Vector3) -> Vector3:
	if not contains_point(world_position):
		return Vector3.ZERO
	var point := to_local(world_position)
	var edge_distance := minf(
		minf(half_extents.x - absf(point.x), half_extents.y - absf(point.y)),
		half_extents.z - absf(point.z)
	)
	var weight := 1.0
	if edge_fade_distance > 0.001:
		weight = smoothstep(0.0, edge_fade_distance, edge_distance)
	return get_flow_direction() * flow_speed * weight


func get_flow_direction() -> Vector3:
	var direction := global_basis.orthonormalized() * local_flow_direction
	direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 0.0001 else Vector3.ZERO


func get_reference_speed() -> float:
	return maxf(flow_speed, 0.001)
