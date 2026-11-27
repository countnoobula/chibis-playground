class_name ParkourBalanceBeam
extends Node3D

## Narrow balance beam (runs along local -Z from 0 to beam_length).

const PALETTE := preload("res://features/stations/station_palette.gd")
const TOP_HEIGHT_TOLERANCE := 0.10

@export var beam_length: float = 8.0
@export var beam_radius: float = 0.14

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
	body.set_meta(&"parkour_top_station", self)
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


func land_on_top(player: ParkourController, impact_velocity: float, was_on_floor: bool) -> bool:
	if not is_instance_valid(player) or player.current_state != "Locomotion":
		return false
	if not was_on_floor and impact_velocity > 1.5:
		return false
	var local_feet := to_local(player.global_position)
	var radius := player.config.capsule_radius
	if absf(local_feet.y - beam_radius) > TOP_HEIGHT_TOLERANCE:
		return false
	if absf(local_feet.x) > beam_radius + radius + 0.025:
		return false
	if local_feet.z > radius + 0.025 or local_feet.z < -beam_length - radius - 0.025:
		return false
	# A floor-supported walk-on is valid too; the controller reports this only
	# when the beam itself supplied the current floor contact.
	return player.try_enter_balance_beam(self)
