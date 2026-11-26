extends Node3D

## One-shot item that a player can take when it is visible and within reach.
signal picked_up(picker: PhysicsBody3D)

const GROUP := &"parkour_pickups"
const BLOCKING_MASK := 1 | 4 # World and Climbable

@export var reach: float = 1.2

var _taken := false


func _enter_tree() -> void:
	add_to_group(GROUP)


func is_reachable(picker: PhysicsBody3D, origin: Vector3) -> bool:
	if _taken or not is_visible_in_tree() or origin.distance_squared_to(global_position) > reach * reach:
		return false
	if origin.is_equal_approx(global_position):
		return true
	var ray := PhysicsRayQueryParameters3D.create(origin, global_position, BLOCKING_MASK, [picker.get_rid()])
	ray.hit_from_inside = true
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


func take(picker: PhysicsBody3D) -> void:
	if _taken:
		return
	_taken = true
	hide()
	picked_up.emit(picker)
	queue_free()
