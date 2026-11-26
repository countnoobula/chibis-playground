class_name ParkourRopeSwing
extends Node3D

## Swinging rope station (port of BP_ParkourRopeSwing). Anchor is at this node's origin.

const PALETTE := preload("res://scripts/gym/rooftop_palette.gd")
const GRAB_RADIUS := 0.65
const GRAB_HEIGHT_FRACTION := 0.85
const GRAB_CENTER_FRACTION := 0.65

@export var rope_length: float = 2.40
@export var max_swing_angle_deg: float = 56.0
@export var swing_pump_accel: float = 3.40
@export var launch_boost_up: float = 2.60

var is_ridden: bool = false
var _rope_pivot: Node3D
var _tracked_player: ParkourController = null


func _ready() -> void:
	_build_visuals_and_trigger()


func _build_visuals_and_trigger() -> void:
	_rope_pivot = Node3D.new()
	_rope_pivot.name = "RopePivot"
	add_child(_rope_pivot)

	# Rope cylinder extending downward from anchor
	var rope_mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.032
	cyl.bottom_radius = 0.032
	cyl.height = rope_length
	rope_mesh.mesh = cyl
	rope_mesh.position = Vector3(0.0, -rope_length * 0.5, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PALETTE.PEACH
	mat.roughness = 0.85
	rope_mesh.material_override = mat
	_rope_pivot.add_child(rope_mesh)

	# Bottom knot sphere
	var knot := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.09
	sph.height = 0.18
	knot.mesh = sph
	knot.position = Vector3(0.0, -rope_length, 0.0)
	var knot_mat := StandardMaterial3D.new()
	knot_mat.albedo_color = PALETTE.CORAL
	knot_mat.roughness = 0.72
	knot.material_override = knot_mat
	_rope_pivot.add_child(knot)

	# Grab trigger around lower half of rope
	var area := Area3D.new()
	area.name = "GrabTrigger"
	area.collision_layer = 8 # Layer 4 InteractiveTrigger
	area.collision_mask = 2 # Layer 2 Player
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = GRAB_RADIUS
	shape.height = rope_length * GRAB_HEIGHT_FRACTION
	col.shape = shape
	col.position = Vector3(0.0, -rope_length * GRAB_CENTER_FRACTION, 0.0)
	area.add_child(col)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	_rope_pivot.add_child(area)


func _on_body_entered(body: Node3D) -> void:
	if body is ParkourController:
		_tracked_player = body as ParkourController
		_try_attach(_tracked_player)


func _on_body_exited(body: Node3D) -> void:
	if body == _tracked_player:
		_tracked_player = null


func _try_attach(player: ParkourController) -> void:
	if is_ridden or not is_instance_valid(player):
		return
	var local_center := _rope_pivot.to_local(player.get_capsule_center())
	var padding := player.config.capsule_height * 0.5
	if Vector2(local_center.x, local_center.z).length() > GRAB_RADIUS + padding:
		return
	if absf(local_center.y + rope_length * GRAB_CENTER_FRACTION) > rope_length * GRAB_HEIGHT_FRACTION * 0.5 + padding:
		return
	player.try_enter_rope_swing(self, global_position, rope_length, max_swing_angle_deg, swing_pump_accel, launch_boost_up)


func set_ridden(ridden: bool) -> void:
	is_ridden = ridden


func set_rope_world_direction(rope_dir: Vector3, plane_fwd: Vector3) -> void:
	if _rope_pivot == null:
		return
	var down := rope_dir.normalized()
	var up := -down
	var right := plane_fwd.cross(up)
	if right.length_squared() < 1e-6:
		right = Vector3.RIGHT
	right = right.normalized()
	var fwd := up.cross(right).normalized()
	_rope_pivot.global_basis = Basis(right, up, -fwd).orthonormalized()


func _physics_process(delta: float) -> void:
	if not is_ridden:
		if _rope_pivot != null:
			_rope_pivot.basis = _rope_pivot.basis.slerp(Basis.IDENTITY, 1.0 - exp(-3.5 * delta))
		if _tracked_player != null:
			_try_attach(_tracked_player)
