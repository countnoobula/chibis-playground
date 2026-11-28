class_name ParkourLine
extends Node3D

## Unified ZipLine & SlothCrawl (RopeLine) station ported 1:1 from BP_ParkourLine:
## 12-segment dynamically sagging rope (tent+parabola blend), Unreal spring rebound,
## forgiving grab envelope, and hanging handlebar pulley for ZipLine.

const SEGMENTS := 12
const PALETTE := preload("res://features/stations/station_palette.gd")
const CONNECTOR_REACH := 0.65

@export var end_offset: Vector3 = Vector3(0.0, 0.0, -9.0)
@export var is_zip_line: bool = false
@export var rest_sag: float = 0.10
@export var loaded_sag: float = 0.42
@export var zip_speed_min: float = 3.80
@export var zip_speed_max: float = 7.40

var _has_rider: bool = false
var _rider_t: float = 0.5
var _current_sag: float = 0.10
var _sag_vel: float = 0.0

var _seg_meshes: Array[MeshInstance3D] = []
var _pulley: Node3D = null
var _tracked_player: ParkourController = null


func _ready() -> void:
	_current_sag = 0.0 if is_zip_line else rest_sag
	_build_visuals_and_trigger()
	_update_rope_visual()


func _build_visuals_and_trigger() -> void:
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = PALETTE.SUPPORT
	post_mat.roughness = 0.72

	for end_pt in [Vector3.ZERO, end_offset]:
		var cap := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.10
		sph.height = 0.20
		cap.mesh = sph
		cap.position = end_pt
		cap.material_override = post_mat
		add_child(cap)

	var rope_mat := StandardMaterial3D.new()
	rope_mat.albedo_color = PALETTE.MINT if is_zip_line else PALETTE.PEACH
	rope_mat.roughness = 0.80

	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.032
	cyl.bottom_radius = 0.032
	cyl.height = 1.0
	for i in SEGMENTS:
		var m := MeshInstance3D.new()
		m.name = "RopeSeg_%02d" % i
		m.mesh = cyl
		m.material_override = rope_mat
		add_child(m)
		_seg_meshes.append(m)

	if is_zip_line:
		_pulley = Node3D.new()
		_pulley.name = "ZipPulley"
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = PALETTE.PEACH
		pmat.roughness = 0.65

		# Exact BP_ParkourLine proportions: PulleyWheel at Y=0, PulleyStrap down to -0.76 m, PulleyHandle T-bar at -0.76 m
		var wheel := MeshInstance3D.new()
		wheel.name = "PulleyWheel"
		var wcyl := CylinderMesh.new()
		wcyl.top_radius = 0.08
		wcyl.bottom_radius = 0.08
		wcyl.height = 0.10
		wheel.mesh = wcyl
		wheel.rotation.z = PI * 0.5
		wheel.material_override = pmat
		_pulley.add_child(wheel)

		var strap := MeshInstance3D.new()
		strap.name = "PulleyStrap"
		var scyl := CylinderMesh.new()
		scyl.top_radius = 0.02
		scyl.bottom_radius = 0.02
		scyl.height = 0.76
		strap.mesh = scyl
		strap.position = Vector3(0.0, -0.38, 0.0)
		strap.material_override = post_mat
		_pulley.add_child(strap)

		var handle := MeshInstance3D.new()
		handle.name = "PulleyHandle"
		var hcyl := CylinderMesh.new()
		hcyl.top_radius = 0.03
		hcyl.bottom_radius = 0.03
		hcyl.height = 0.44
		handle.mesh = hcyl
		handle.position = Vector3(0.0, -0.76, 0.0)
		handle.rotation.z = PI * 0.5
		handle.material_override = pmat
		_pulley.add_child(handle)
		add_child(_pulley)

	# Generous trigger volume matching Unreal's capture envelope (extra downward reach for 0.76 m zip strap)
	var area := Area3D.new()
	area.name = "LineTrigger"
	area.collision_layer = 8
	area.collision_mask = 2
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.85, 2.20 if is_zip_line else 1.90, end_offset.length() + 0.90)
	col.shape = shape
	var mid := end_offset * 0.5
	var dir := end_offset.normalized()
	col.position = mid - Vector3(0.0, 0.55 if is_zip_line else 0.45, 0.0)
	col.basis = Basis.looking_at(dir, Vector3.UP)
	area.add_child(col)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	add_child(area)


func _on_body_entered(body: Node3D) -> void:
	if body is ParkourController:
		_tracked_player = body as ParkourController


func _on_body_exited(body: Node3D) -> void:
	if body == _tracked_player:
		_tracked_player = null


func _try_attach(player: ParkourController) -> void:
	if _has_rider or not is_instance_valid(player):
		return
	if player.is_on_floor():
		return
	var line_len := end_offset.length()
	if line_len < (1.20 if is_zip_line else 0.80):
		return
	var local_center := to_local(player.get_capsule_center())
	var dir := end_offset / line_len
	var raw_dist := local_center.dot(dir)
	var dist := 0.0
	if is_zip_line:
		# Exact Unreal TryEnterZipLine along-line bounds: (-0.40, line_len - 0.95)
		if raw_dist <= -0.40 or raw_dist >= line_len - 0.95:
			return
		dist = clampf(raw_dist, 0.15, maxf(0.15, line_len - 0.95))
	else:
		dist = clampf(raw_dist, 0.28, maxf(0.28, line_len - 0.28))
	var t := clampf(dist / line_len, 0.0, 1.0)
	var rope_pt := get_rope_local_pos_at_u(t)
	var connector_world := to_global(rope_pt)
	if is_zip_line:
		var line_direction := get_line_direction()
		var line_xz := Vector3(line_direction.x, 0.0, line_direction.z).normalized()
		# The rider's hands meet the moving handle, below and slightly behind the cable.
		connector_world -= line_xz * 0.29 + Vector3.UP * 0.76
	if player.get_capsule_center().distance_to(connector_world) > CONNECTOR_REACH:
		return
	player.try_enter_parkour_line(self, is_zip_line, t, line_len, zip_speed_min, zip_speed_max)


func notify_rider_attach(t: float) -> void:
	_has_rider = true
	_rider_t = clampf(t, 0.0, 1.0)
	_update_pulley_visual()


func set_rider_progress(t: float) -> void:
	_rider_t = clampf(t, 0.0, 1.0)
	_update_pulley_visual()


func notify_rider_release() -> void:
	_has_rider = false
	if is_zip_line:
		_rider_t = 0.0
		_update_pulley_visual()


func get_pulley_handle_world_pos() -> Vector3:
	if _pulley != null:
		return _pulley.to_global(Vector3(0.0, -0.76, 0.0))
	return get_rope_world_pos_at_t(_rider_t) - Vector3(0.0, 0.76, 0.0)


func get_line_direction() -> Vector3:
	return (to_global(end_offset) - global_position).normalized()


func get_rope_local_pos_at_u(u_raw: float) -> Vector3:
	var u := clampf(u_raw, 0.0, 1.0)
	var base := end_offset * u
	if is_zip_line:
		return base
	# Exact port of Unreal BP_ParkourLine::GetRopeLocalPosAtU (68% tent at rider_t + 32% parabola)
	var sag_t := clampf(_rider_t, 0.08, 0.92)
	var amp := _current_sag * (4.0 * sag_t * (1.0 - sag_t))
	var tent := (u / sag_t) if u <= sag_t else ((1.0 - u) / (1.0 - sag_t))
	var para := 4.0 * u * (1.0 - u)
	base.y -= amp * (0.68 * tent + 0.32 * para)
	return base


func get_rope_world_pos_at_t(t: float) -> Vector3:
	return to_global(get_rope_local_pos_at_u(t))


func _physics_process(delta: float) -> void:
	if not is_zip_line:
		# Exact Unreal BP_ParkourLine::EventTick spring-damped sag rebound
		var dt := minf(delta, 0.033)
		var target_sag := loaded_sag if _has_rider else rest_sag
		var k := 120.0 if _has_rider else 230.0
		var damp := 11.0 if _has_rider else 4.0
		if not _has_rider:
			# Let the bend return from the release point as the unloaded cable rebounds.
			_rider_t = lerpf(_rider_t, 0.5, 1.0 - exp(-damp * dt))
		_sag_vel += ((target_sag - _current_sag) * k - damp * _sag_vel) * dt
		_current_sag = clampf(_current_sag + _sag_vel * dt, -0.55, 0.75)
		_update_rope_visual()
	else:
		_update_pulley_visual()
	if not _has_rider and _tracked_player != null:
		_try_attach(_tracked_player)


func _update_pulley_visual() -> void:
	if _pulley == null:
		return
	var pt := _rider_t if _has_rider else 0.0
	_pulley.position = get_rope_local_pos_at_u(pt)
	var dir := Vector3(end_offset.x, 0.0, end_offset.z).normalized()
	if dir.length_squared() > 0.01:
		_pulley.basis = Basis.looking_at(dir, Vector3.UP)


func _update_rope_visual() -> void:
	for i in SEGMENTS:
		var u0 := float(i) / float(SEGMENTS)
		var u1 := float(i + 1) / float(SEGMENTS)
		var p0 := get_rope_local_pos_at_u(u0)
		var p1 := get_rope_local_pos_at_u(u1)
		var seg_vec := p1 - p0
		var seg_len := seg_vec.length()
		var m := _seg_meshes[i]
		m.position = (p0 + p1) * 0.5
		if seg_len > 1e-4:
			var up_dir := seg_vec / seg_len
			var ref := Vector3.RIGHT if absf(up_dir.x) < 0.9 else Vector3.FORWARD
			var x_ax := up_dir.cross(ref).normalized()
			var z_ax := x_ax.cross(up_dir).normalized()
			m.basis = Basis(x_ax, up_dir, z_ax)
			m.scale = Vector3(1.0, seg_len + 0.025, 1.0)
	_update_pulley_visual()
