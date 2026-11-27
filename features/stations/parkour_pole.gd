class_name ParkourPole
extends Node3D

## Perchable parkour pole with a collision-confirmed top mount and hop target group.

const PALETTE := preload("res://features/stations/station_palette.gd")
const TOP_HEIGHT_TOLERANCE := 0.08

@export var pole_height: float = 1.20
@export var pole_radius: float = 0.16

func _ready() -> void:
	add_to_group("parkour_poles")
	_build_pole()


func get_top_world_position() -> Vector3:
	return global_position + Vector3(0.0, pole_height, 0.0)


func _build_pole() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.set_meta(&"parkour_top_station", self)
	var col := CollisionShape3D.new()
	var cyl_shape := CylinderShape3D.new()
	cyl_shape.radius = pole_radius
	cyl_shape.height = pole_height
	col.shape = cyl_shape
	col.position = Vector3(0.0, pole_height * 0.5, 0.0)
	body.add_child(col)

	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = pole_radius
	cyl.bottom_radius = pole_radius * 1.15
	cyl.height = pole_height
	mesh.mesh = cyl
	mesh.position = Vector3(0.0, pole_height * 0.5, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PALETTE.PORCELAIN
	mat.roughness = 0.72
	mesh.material_override = mat
	body.add_child(mesh)

	# Cap ring for readability
	var cap := MeshInstance3D.new()
	var cap_m := CylinderMesh.new()
	cap_m.top_radius = pole_radius * 1.18
	cap_m.bottom_radius = pole_radius * 1.18
	cap_m.height = 0.06
	cap.mesh = cap_m
	cap.position = Vector3(0.0, pole_height - 0.03, 0.0)
	var cap_collision := CollisionShape3D.new()
	var cap_shape := CylinderShape3D.new()
	cap_shape.radius = cap_m.top_radius
	cap_shape.height = cap_m.height
	cap_collision.shape = cap_shape
	cap_collision.position = cap.position
	body.add_child(cap_collision)
	var cap_mat := StandardMaterial3D.new()
	cap_mat.albedo_color = PALETTE.LAVENDER
	cap_mat.roughness = 0.66
	cap.material_override = cap_mat
	body.add_child(cap)
	add_child(body)


func land_on_top(player: ParkourController, impact_velocity: float, was_on_floor: bool) -> bool:
	if not is_instance_valid(player) or player.current_state != "Locomotion":
		return false
	if not was_on_floor and impact_velocity > 1.8:
		return false
	var local_feet := to_local(player.global_position)
	var lateral_distance := Vector2(local_feet.x, local_feet.z).length()
	if absf(local_feet.y - pole_height) > TOP_HEIGHT_TOLERANCE:
		return false
	if lateral_distance > pole_radius * 1.18 + player.config.capsule_radius + 0.025:
		return false
	return player.try_enter_pole_perch(get_top_world_position())
