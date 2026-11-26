class_name ParkourPole
extends Node3D

## Perchable parkour pole with top-landing trigger and pole-to-pole hop target group.

const PALETTE := preload("res://scripts/gym/rooftop_palette.gd")
const CATCH_RADIUS := 0.48
const CATCH_HEIGHT := 0.22

@export var pole_height: float = 1.20
@export var pole_radius: float = 0.16

var _tracked_player: ParkourController = null


func _ready() -> void:
	add_to_group("parkour_poles")
	_build_pole()


func get_top_world_position() -> Vector3:
	return global_position + Vector3(0.0, pole_height, 0.0)


func _build_pole() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
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
	var cap_mat := StandardMaterial3D.new()
	cap_mat.albedo_color = PALETTE.LAVENDER
	cap_mat.roughness = 0.66
	cap.material_override = cap_mat
	body.add_child(cap)
	add_child(body)

	var area := Area3D.new()
	area.collision_layer = 8
	area.collision_mask = 2
	var tcol := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = CATCH_RADIUS
	tcol.shape = sph
	tcol.position = Vector3(0.0, pole_height + CATCH_HEIGHT, 0.0)
	area.add_child(tcol)
	area.body_entered.connect(func(b):
		if b is ParkourController:
			_tracked_player = b
			_try_perch(b)
	)
	area.body_exited.connect(func(b):
		if b == _tracked_player:
			_tracked_player = null
	)
	add_child(area)


func _try_perch(p: ParkourController) -> void:
	if not is_instance_valid(p):
		return
	var top := get_top_world_position()
	# A physics Area can report its previous overlap for a tick after a teleport.
	var offset := p.global_position - top
	var horizontal := Vector2(offset.x, offset.z).length()
	if offset.y >= -0.35 and offset.y <= CATCH_HEIGHT + CATCH_RADIUS and horizontal <= CATCH_RADIUS + p.config.capsule_radius:
		p.try_enter_pole_perch(top)


func _physics_process(_delta: float) -> void:
	if _tracked_player != null:
		_try_perch(_tracked_player)
