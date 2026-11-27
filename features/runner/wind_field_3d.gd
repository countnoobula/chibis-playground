class_name RunnerWindField3D
extends Node3D

## Reusable world-space wind query for runner movement and presentation.
## Wind providers override these methods to report their active field.


func contains_point(_world_position: Vector3) -> bool:
	return false


func flow_velocity_at(_world_position: Vector3) -> Vector3:
	return Vector3.ZERO


func get_flow_direction() -> Vector3:
	return Vector3.ZERO


func get_reference_speed() -> float:
	return 1.0
