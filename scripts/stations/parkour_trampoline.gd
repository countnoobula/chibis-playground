class_name ParkourTrampoline
extends Node3D

## Spring trampoline pad with SuperBounce grace window and squish animation.

const PALETTE := preload("res://scripts/gym/rooftop_palette.gd")

@export var base_bounce_velocity: float = 10.40
@export var super_bounce_multiplier: float = 1.22

var _pad_mesh: MeshInstance3D
var _squish_timer: float = 0.0


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
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = PALETTE.PORCELAIN
	rmat.roughness = 0.78
	ring.material_override = rmat
	frame.add_child(ring)
	add_child(frame)

	_pad_mesh = MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.98
	pm.bottom_radius = 0.98
	pm.height = 0.10
	_pad_mesh.mesh = pm
	_pad_mesh.position = Vector3(0.0, 0.27, 0.0)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = PALETTE.MINT
	pmat.roughness = 0.73
	_pad_mesh.material_override = pmat
	add_child(_pad_mesh)

	var area := Area3D.new()
	area.collision_layer = 8
	area.collision_mask = 2
	var tcol := CollisionShape3D.new()
	var tcyl := CylinderShape3D.new()
	tcyl.radius = 1.02
	tcyl.height = 0.45
	tcol.shape = tcyl
	tcol.position = Vector3(0.0, 0.40, 0.0)
	area.add_child(tcol)
	area.body_entered.connect(_on_body_entered)
	add_child(area)


func _on_body_entered(body: Node3D) -> void:
	if body is ParkourController:
		var p := body as ParkourController
		if p.trigger_trampoline_bounce(base_bounce_velocity, super_bounce_multiplier):
			_squish_timer = 0.32


func _process(delta: float) -> void:
	if _squish_timer > 0.0 and _pad_mesh != null:
		_squish_timer = maxf(0.0, _squish_timer - delta)
		var u := 1.0 - (_squish_timer / 0.32)
		var bounce := sin(u * PI * 3.0) * (1.0 - u) * 0.35
		_pad_mesh.scale = Vector3(1.0 + bounce * 0.35, maxf(0.35, 1.0 - bounce), 1.0 + bounce * 0.35)
	elif _pad_mesh != null:
		_pad_mesh.scale = Vector3.ONE
