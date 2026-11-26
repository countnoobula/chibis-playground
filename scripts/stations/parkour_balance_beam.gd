class_name ParkourBalanceBeam
extends Node3D

## Narrow balance beam (runs along local -Z from 0 to beam_length).

const PALETTE := preload("res://scripts/gym/rooftop_palette.gd")
const CATCH_HALF_WIDTH := 0.325
const CATCH_END_INSET := 0.15

@export var beam_length: float = 8.0
@export var beam_radius: float = 0.14

var _tracked_player: ParkourController = null


func _ready() -> void:
	_build_beam()


func foot_surface(at: Vector3) -> Transform3D:
	var lateral := at.z * beam_radius
	var height := sqrt(maxf(0.0, beam_radius * beam_radius - lateral * lateral))
	var local := Transform3D(Basis(Vector3.BACK, atan2(-lateral, height)), Vector3(lateral, height + at.y, -at.x))
	return get_global_transform_interpolated() * local


func _build_beam() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(beam_radius * 2.0, beam_radius * 2.0, beam_length)
	col.shape = box
	col.position = Vector3(0.0, 0.0, -beam_length * 0.5)
	body.add_child(col)

	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = beam_radius
	cyl.bottom_radius = beam_radius
	cyl.height = beam_length
	mesh.mesh = cyl
	mesh.position = Vector3(0.0, 0.0, -beam_length * 0.5)
	mesh.rotation.x = PI * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PALETTE.LAVENDER
	mat.roughness = 0.72
	mesh.material_override = mat
	body.add_child(mesh)
	add_child(body)

	var area := Area3D.new()
	area.collision_layer = 8
	area.collision_mask = 2
	var tcol := CollisionShape3D.new()
	var tbox := BoxShape3D.new()
	tbox.size = Vector3(CATCH_HALF_WIDTH * 2.0, 0.55, beam_length - CATCH_END_INSET * 2.0)
	tcol.shape = tbox
	tcol.position = Vector3(0.0, beam_radius + 0.25, -beam_length * 0.5)
	area.add_child(tcol)
	area.body_entered.connect(func(b):
		if b is ParkourController:
			_tracked_player = b
			_try_mount(b)
	)
	area.body_exited.connect(func(b):
		if b == _tracked_player:
			_tracked_player = null
	)
	add_child(area)


func _try_mount(p: ParkourController) -> void:
	if not is_instance_valid(p):
		return
	var local_feet := to_local(p.global_position)
	var radius := p.config.capsule_radius
	if absf(local_feet.x) > CATCH_HALF_WIDTH + radius:
		return
	if local_feet.z > radius - CATCH_END_INSET or local_feet.z < -beam_length + CATCH_END_INSET - radius:
		return
	var top_y := global_position.y + beam_radius
	if absf(p.global_position.y - top_y) <= 0.42:
		p.try_enter_balance_beam(self)


func _physics_process(_delta: float) -> void:
	if _tracked_player != null:
		_try_mount(_tracked_player)
