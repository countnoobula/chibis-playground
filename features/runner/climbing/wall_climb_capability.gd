class_name WallClimbCapability
extends RefCounted

## Authored wall-route data queried by the reusable wall motion solver.

class LeapProfile:
	extends RefCounted

	var stride: float = 0.0
	var search_radius: float = 0.0
	var min_forward_up: float = 0.37
	var min_forward_down: float = 0.22
	var max_forward: float = 0.0
	var max_side_lateral: float = 0.24
	var max_side_cardinal: float = 0.70
	var distinct_collider: bool = true
	var short_side_hop: bool = false


var short_side_leap: LeapProfile
var leap_profiles: Array[LeapProfile] = []
var corner_point_query: Callable = Callable()
var summit_marker: Marker3D
var summit_group: StringName = &""
var summit_height_tolerance: float = 0.42
var roof_reach: float = 0.34


func get_corner_point(wall_normal: Vector3, lateral_direction: Vector3) -> Vector3:
	if not corner_point_query.is_valid():
		return Vector3.INF
	var point: Vector3 = corner_point_query.call(wall_normal, lateral_direction)
	return point


func is_summit_collider(collider: Object) -> bool:
	if summit_group == &"":
		return false
	var current := collider as Node
	while current != null:
		if current.is_in_group(summit_group):
			return true
		current = current.get_parent()
	return false
