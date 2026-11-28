class_name ParkourTrampoline
extends Node3D

## Spring trampoline pad with SuperBounce grace window and squish animation.

const PALETTE := preload("res://features/stations/station_palette.gd")

@export var base_bounce_velocity: float = 10.40
@export var super_bounce_multiplier: float = 1.22
@export_group("Appearance")
@export var frame_material: Material
@export var pad_material: Material

var _pad_mesh: MeshInstance3D
var _squish_timer: float = 0.0

const PAD_RADIUS := 0.98
const PAD_TOP := 0.32
const LANDING_HEIGHT_TOLERANCE := 0.08


func _ready() -> void:
	_build_trampoline()


func _build_trampoline() -> void:
	var frame := StaticBody3D.new()
	frame.collision_layer = 1
	var fcol := CollisionShape3D.new()
	var fcyl := CylinderShape3D.new()
	fcyl.radius = 1.15
	fcyl.height = 0.28
	fcol.shape = fcyl
	fcol.position = Vector3(0.0, 0.14, 0.0)
	frame.add_child(fcol)

	var ring := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 1.18
	rm.bottom_radius = 1.24
	rm.height = 0.24
	ring.mesh = rm
	ring.position = Vector3(0.0, 0.12, 0.0)
	var rmat: Material = frame_material
	if rmat == null:
		var default_frame := StandardMaterial3D.new()
		default_frame.albedo_color = PALETTE.PORCELAIN
		default_frame.roughness = 0.78
		rmat = default_frame
	ring.material_override = rmat
	frame.add_child(ring)
	add_child(frame)

	# Separate collision body marks only the spring surface as a bounce target.
	var pad_body := StaticBody3D.new()
	pad_body.name = "TrampolinePadTop"
	pad_body.collision_layer = 1
	pad_body.set_meta(&"parkour_top_station", self)
	var pad_collision := CollisionShape3D.new()
	var pad_shape := CylinderShape3D.new()
	pad_shape.radius = PAD_RADIUS
	pad_shape.height = 0.10
	pad_collision.shape = pad_shape
	pad_collision.position = Vector3(0.0, 0.27, 0.0)
	pad_body.add_child(pad_collision)
	add_child(pad_body)

	_pad_mesh = MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = PAD_RADIUS
	pm.bottom_radius = PAD_RADIUS
	pm.height = 0.10
	_pad_mesh.mesh = pm
	_pad_mesh.position = Vector3(0.0, 0.27, 0.0)
	var top_material: Material = pad_material
	if top_material == null:
		var default_pad := StandardMaterial3D.new()
		default_pad.albedo_color = PALETTE.MINT
		default_pad.roughness = 0.73
		top_material = default_pad
	_pad_mesh.material_override = top_material
	add_child(_pad_mesh)


func land_on_top(player: ParkourController, impact_velocity: float, was_on_floor: bool) -> bool:
	if not is_instance_valid(player) or player.current_state != "Locomotion":
		return false
	if was_on_floor or impact_velocity >= -0.1:
		return false
	var local_feet := to_local(player.global_position)
	if absf(local_feet.y - PAD_TOP) > LANDING_HEIGHT_TOLERANCE:
		return false
	if Vector2(local_feet.x, local_feet.z).length() > PAD_RADIUS + player.config.capsule_radius + 0.025:
		return false
	if player.trigger_trampoline_bounce(base_bounce_velocity, super_bounce_multiplier):
		_squish_timer = 0.32
		return true
	return false


func _process(delta: float) -> void:
	if _squish_timer > 0.0 and _pad_mesh != null:
		_squish_timer = maxf(0.0, _squish_timer - delta)
		var u := 1.0 - (_squish_timer / 0.32)
		var bounce := sin(u * PI * 3.0) * (1.0 - u) * 0.35
		_pad_mesh.scale = Vector3(1.0 + bounce * 0.35, maxf(0.35, 1.0 - bounce), 1.0 + bounce * 0.35)
	elif _pad_mesh != null:
		_pad_mesh.scale = Vector3.ONE
