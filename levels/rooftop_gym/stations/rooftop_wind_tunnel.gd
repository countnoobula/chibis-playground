class_name RooftopWindTunnel
extends "res://features/runner/wind_field_3d.gd"

## Open rooftop gust lane. The authored flow points along local -Z; all query
## positions are world-space and the returned flow is world-space metres/sec.
## The fixture meshes are decorative only, leaving the whole volume overhead-free.

const PALETTE := preload("res://levels/rooftop_gym/rooftop_palette.gd")
const WIND_AUDIO := preload("res://assets/audio/SFX_TowerWind.wav")

const HALF_WIDTH := 2.25
const HALF_LENGTH := 7.0
const HEIGHT := 3.0
const GUST_PERIOD := 4.2
const LULL_SPEED := 3.0
const PEAK_SPEED := 9.0
const RISE_DURATION := 0.55
const PEAK_HOLD_DURATION := 0.55
const DECAY_DURATION := 1.0
const EDGE_EASE_DISTANCE := 0.42

## Public physics elapsed time makes the gust phase reproducible. Set this to
## a known value before a sample/replay, or call set_phase_elapsed().
var elapsed_physics: float = 0.0
var _visual_elapsed: float = 0.0

var _ivory_material: StandardMaterial3D
var _mint_material: StandardMaterial3D
var _peach_material: StandardMaterial3D
var _support_material: StandardMaterial3D
var _streamer_mesh: ImmediateMesh
var _streamer_instance: MeshInstance3D
var _breeze: AudioStreamPlayer3D
var _flow_distance: float = 0.0

const STREAMER_ANCHORS: Array[Vector3] = [
	Vector3(-2.08, 2.12, 5.70),
	Vector3(-2.08, 2.22, 1.14), Vector3(2.08, 1.95, -1.14),
	Vector3(-2.08, 2.28, -3.42), Vector3(2.08, 2.06, -5.70),
]


func _ready() -> void:
	# A bound runner samples us in its own physics tick. Run first even if the
	# scene insertion order changes during level-authored station assembly.
	process_priority = -10
	process_physics_priority = -10
	_ivory_material = _make_matte(PALETTE.PORCELAIN)
	_mint_material = _make_matte(PALETTE.MINT)
	_peach_material = _make_matte(PALETTE.PEACH)
	_support_material = _make_matte(PALETTE.SUPPORT)
	_build_render_only_fixtures()
	_create_streamers()
	_create_breeze()
	_update_streamers()
	_update_breeze()


func _physics_process(delta: float) -> void:
	var safe_delta := maxf(delta, 0.0)
	_flow_distance += gust_speed_at(elapsed_physics) * safe_delta
	_visual_elapsed += safe_delta
	elapsed_physics = fposmod(elapsed_physics + safe_delta, GUST_PERIOD)
	_update_breeze()


func _process(_delta: float) -> void:
	_update_streamers()


## Inclusive hard volume membership, independent of the feathered wind field.
func contains_point(world_position: Vector3) -> bool:
	var local_position := to_local(world_position)
	return absf(local_position.x) <= HALF_WIDTH \
		and absf(local_position.z) <= HALF_LENGTH \
		and local_position.y >= 0.0 and local_position.y <= HEIGHT


## Instantaneous world-space air velocity. The interior tracks the full gust
## curve; a soft 42 cm fade keeps the sampling field calm at the hard boundary.
func flow_velocity_at(world_position: Vector3) -> Vector3:
	if not contains_point(world_position):
		return Vector3.ZERO
	var local_position := to_local(world_position)
	var x_weight := _edge_weight(absf(local_position.x), HALF_WIDTH)
	var z_weight := _edge_weight(absf(local_position.z), HALF_LENGTH)
	var y_edge := minf(local_position.y, HEIGHT - local_position.y)
	var y_weight := smoothstep(0.0, EDGE_EASE_DISTANCE, y_edge)
	var spatial_weight := x_weight * z_weight * y_weight
	return get_flow_direction() * gust_speed_at(elapsed_physics) * spatial_weight


## World-space direction of the authored local -Z airflow.
func get_flow_direction() -> Vector3:
	return (global_basis.orthonormalized() * Vector3.FORWARD).normalized()


func get_reference_speed() -> float:
	return PEAK_SPEED


## Sample the deterministic 4.2 second cycle without changing its live phase.
## 0..2.1s is a 3 m/s lull; 2.1..2.65s rises to 9, 2.65..3.2s holds,
## and 3.2..4.2s eases back to 3 m/s.
func gust_speed_at(elapsed: float) -> float:
	var phase := fposmod(elapsed, GUST_PERIOD)
	if phase < 2.1:
		return LULL_SPEED
	phase -= 2.1
	if phase < RISE_DURATION:
		var rise := smoothstep(0.0, 1.0, phase / RISE_DURATION)
		return lerpf(LULL_SPEED, PEAK_SPEED, rise)
	phase -= RISE_DURATION
	if phase < PEAK_HOLD_DURATION:
		return PEAK_SPEED
	phase -= PEAK_HOLD_DURATION
	var decay := smoothstep(0.0, 1.0, clampf(phase / DECAY_DURATION, 0.0, 1.0))
	return lerpf(PEAK_SPEED, LULL_SPEED, decay)


## Set a replay/test phase in seconds. The next physics tick resumes the loop.
func set_phase_elapsed(seconds: float) -> void:
	elapsed_physics = fposmod(seconds, GUST_PERIOD)
	_visual_elapsed = maxf(seconds, 0.0)
	_flow_distance = _integrated_gust_distance(seconds)
	_update_breeze()
	_update_streamers()


func _integrated_gust_distance(elapsed: float) -> float:
	# Exact travel for a phase seek keeps the lane ribbons deterministic too.
	var safe_elapsed := maxf(elapsed, 0.0)
	var cycle_count := floorf(safe_elapsed / GUST_PERIOD)
	var phase := fposmod(safe_elapsed, GUST_PERIOD)
	var distance := cycle_count * 20.55
	if phase < 2.1:
		return distance + LULL_SPEED * phase
	distance += 6.3
	phase -= 2.1
	if phase < RISE_DURATION:
		var u := phase / RISE_DURATION
		return distance + 3.0 * phase + 6.0 * RISE_DURATION * (pow(u, 3.0) - 0.5 * pow(u, 4.0))
	distance += 3.3
	phase -= RISE_DURATION
	if phase < PEAK_HOLD_DURATION:
		return distance + PEAK_SPEED * phase
	distance += PEAK_SPEED * PEAK_HOLD_DURATION
	phase -= PEAK_HOLD_DURATION
	return distance + 9.0 * phase - 6.0 * (pow(phase, 3.0) - 0.5 * pow(phase, 4.0))


func _edge_weight(abs_coordinate: float, half_extent: float) -> float:
	return smoothstep(0.0, EDGE_EASE_DISTANCE, half_extent - abs_coordinate)


func _build_render_only_fixtures() -> void:
	# Continuous low mint borders and six pairs of slim open-side masts frame the
	# lane. Nothing spans above the player and none of these meshes has collision.
	_add_box_visual("FlowBorderLeft", Vector3(-2.12, 0.022, 0.0), Vector3(0.055, 0.026, 13.55), _mint_material)
	_add_box_visual("FlowBorderRight", Vector3(2.12, 0.022, 0.0), Vector3(0.055, 0.026, 13.55), _mint_material)
	_add_box_visual("EntryLip", Vector3(0.0, 0.026, 6.72), Vector3(3.88, 0.032, 0.12), _peach_material)
	_add_box_visual("ExitLip", Vector3(0.0, 0.026, -6.72), Vector3(3.88, 0.032, 0.12), _peach_material)

	for arrow_index in 7:
		var arrow_z := 5.35 - float(arrow_index) * 1.76
		_add_flow_chevron(arrow_index, arrow_z)

	for post_index in 6:
		var z := 5.7 - float(post_index) * 2.28
		for side: float in [-1.0, 1.0]:
			# Keep the launch camera's east-side sightline clear across Chibi's scarf.
			if post_index == 1 and side > 0.0:
				continue
			var x: float = side * 2.08
			_add_box_visual("SideMast_%02d_%s" % [post_index, "L" if side < 0.0 else "R"],
				Vector3(x, 1.36, z), Vector3(0.085, 2.72, 0.085), _support_material)
			_add_box_visual("MastMintFoot_%02d_%s" % [post_index, "L" if side < 0.0 else "R"],
				Vector3(x, 0.12, z), Vector3(0.19, 0.09, 0.19), _mint_material)
			_add_box_visual("MastPeachCap_%02d_%s" % [post_index, "L" if side < 0.0 else "R"],
				Vector3(x, 2.74, z), Vector3(0.125, 0.07, 0.125), _peach_material)

	# Small floor-mounted plaque outside the west border communicates wind by
	# color and a single forward mark, without using text or blocking the lane.
	_add_box_visual("WindCueBase", Vector3(-2.43, 0.035, 0.0), Vector3(0.30, 0.07, 1.00), _ivory_material)
	_add_box_visual("WindCueMint", Vector3(-2.43, 0.076, 0.0), Vector3(0.20, 0.018, 0.72), _mint_material)
	_add_flow_chevron(99, 0.0, -2.43, 0.088, 0.54)


func _add_flow_chevron(index: int, z: float, x: float = 0.0, y: float = 0.052, scale: float = 1.0) -> void:
	# The narrow stem and V arms point toward local -Z.
	_add_box_visual("FlowCueStem_%02d" % index, Vector3(x, y, z - 0.12 * scale),
		Vector3(0.055 * scale, 0.012, 0.34 * scale), _mint_material)
	_add_rotated_box_visual("FlowCueArmA_%02d" % index, Vector3(x - 0.10 * scale, y, z - 0.17 * scale),
		Vector3(0.045 * scale, 0.012, 0.22 * scale), -0.70, _mint_material)
	_add_rotated_box_visual("FlowCueArmB_%02d" % index, Vector3(x + 0.10 * scale, y, z - 0.17 * scale),
		Vector3(0.045 * scale, 0.012, 0.22 * scale), 0.70, _mint_material)


func _create_streamers() -> void:
	_streamer_mesh = ImmediateMesh.new()
	_streamer_instance = MeshInstance3D.new()
	_streamer_instance.name = "FlowStreamers"
	_streamer_instance.mesh = _streamer_mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.roughness = 1.0
	material.no_depth_test = false
	_streamer_instance.material_override = material
	_streamer_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_streamer_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_streamer_instance)


func _update_streamers() -> void:
	if _streamer_mesh == null:
		return
	_streamer_mesh.clear_surfaces()
	_streamer_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var speed := gust_speed_at(elapsed_physics)
	var gust_weight := clampf((speed - LULL_SPEED) / (PEAK_SPEED - LULL_SPEED), 0.0, 1.0)
	var wave_time := _visual_elapsed * 3.1
	for streamer_index in STREAMER_ANCHORS.size():
		var anchor: Vector3 = STREAMER_ANCHORS[streamer_index]
		var length := 0.82 + gust_weight * 0.68
		var width := 0.12 + gust_weight * 0.055
		var flutter := 0.035 + gust_weight * 0.13
		var segment_count := 7
		for segment in segment_count:
			var t0 := float(segment) / float(segment_count)
			var t1 := float(segment + 1) / float(segment_count)
			var a0 := _streamer_point(anchor, t0, length, flutter, wave_time, streamer_index)
			var a1 := _streamer_point(anchor, t1, length, flutter, wave_time, streamer_index)
			var edge0 := Vector3(width * (0.5 + 0.15 * sin(wave_time + t0 * TAU + streamer_index)), 0.018 * sin(wave_time + t0 * 5.0), 0.0)
			var edge1 := Vector3(width * (0.5 + 0.15 * sin(wave_time + t1 * TAU + streamer_index)), 0.018 * sin(wave_time + t1 * 5.0), 0.0)
			var fade0 := (1.0 - t0 * 0.62) * (0.30 + gust_weight * 0.35)
			var fade1 := (1.0 - t1 * 0.62) * (0.30 + gust_weight * 0.35)
			var color0 := Color(0.99, 0.945, 0.855, fade0)
			var color1 := Color(0.99, 0.945, 0.855, fade1)
			_add_streamer_triangle(a0 - edge0, color0, a0 + edge0, color0, a1 - edge1, color1)
			_add_streamer_triangle(a0 + edge0, color0, a1 + edge1, color1, a1 - edge1, color1)
	_draw_lane_gust(wave_time, gust_weight)
	_streamer_mesh.surface_end()


func _draw_lane_gust(wave_time: float, gust_weight: float) -> void:
	# A small set of broad, crossed ribbons makes the airflow legible down the
	# full lane. Their travel distance integrates the same 3-to-9 m/s gust curve;
	# edge fades avoid a visible wrap at either open end.
	const RIBBON_COUNT := 6
	const SEGMENT_COUNT := 6
	const RIBBON_LENGTH := 2.35
	var half_width := lerpf(0.12, 0.20, gust_weight)
	var half_height := lerpf(0.035, 0.075, gust_weight)
	var peak_alpha := lerpf(0.06, 0.20, gust_weight)
	var wrap_distance := HALF_LENGTH * 2.0 + RIBBON_LENGTH * 2.0
	var spacing := wrap_distance / float(RIBBON_COUNT)
	for ribbon_index in RIBBON_COUNT:
		var travel := fposmod(_flow_distance + float(ribbon_index) * spacing, wrap_distance)
		var head_z := HALF_LENGTH + RIBBON_LENGTH - travel
		var tail_z := head_z + RIBBON_LENGTH
		var before_entry := maxf(tail_z - HALF_LENGTH, 0.0)
		var beyond_exit := maxf(-HALF_LENGTH - head_z, 0.0)
		var edge_fade := (1.0 - smoothstep(0.0, RIBBON_LENGTH * 0.55, before_entry)) \
			* (1.0 - smoothstep(0.0, RIBBON_LENGTH, beyond_exit))
		if edge_fade <= 0.001:
			continue
		var lane_column := float(ribbon_index) - float(RIBBON_COUNT - 1) * 0.5
		var anchor_x := lane_column * 0.57
		var anchor_y: float = [0.66, 1.12, 0.84, 1.18, 0.72, 1.03][ribbon_index]
		var tint := Color(0.99, 0.955, 0.88) if ribbon_index % 2 == 0 else Color(0.72, 0.92, 0.84)
		var centers: Array[Vector3] = []
		for sample in SEGMENT_COUNT + 1:
			var t := float(sample) / float(SEGMENT_COUNT)
			var ripple := sin(wave_time * 0.74 + t * 6.5 + float(ribbon_index) * 1.3)
			var sway := sin(wave_time * 0.52 + t * 4.0 + float(ribbon_index) * 0.9)
			centers.append(Vector3(
				anchor_x + sway * 0.10 * (0.35 + gust_weight),
				anchor_y + ripple * 0.045 * (0.40 + gust_weight),
					head_z + t * RIBBON_LENGTH
			))
		for segment in SEGMENT_COUNT:
			var t := float(segment) / float(SEGMENT_COUNT)
			var taper := lerpf(0.45, 1.0, t) * edge_fade
			var alpha := peak_alpha * taper
			var color := Color(tint.r, tint.g, tint.b, alpha)
			var a: Vector3 = centers[segment]
			var b: Vector3 = centers[segment + 1]
			var wa := half_width * taper
			var wb := half_width * lerpf(0.45, 1.0, t + 1.0 / SEGMENT_COUNT) * edge_fade
			var ha := half_height * taper
			var hb := half_height * lerpf(0.45, 1.0, t + 1.0 / SEGMENT_COUNT) * edge_fade
			# The horizontal blade reads from chase view; its crossed vertical
			# partner keeps the same flowing shape visible from the side.
			_add_streamer_triangle(a - Vector3(wa, 0.0, 0.0), color, a + Vector3(wa, 0.0, 0.0), color,
				b - Vector3(wb, 0.0, 0.0), color)
			_add_streamer_triangle(a + Vector3(wa, 0.0, 0.0), color, b + Vector3(wb, 0.0, 0.0), color,
				b - Vector3(wb, 0.0, 0.0), color)
			_add_streamer_triangle(a - Vector3(0.0, ha, 0.0), color, a + Vector3(0.0, ha, 0.0), color,
				b - Vector3(0.0, hb, 0.0), color)
			_add_streamer_triangle(a + Vector3(0.0, ha, 0.0), color, b + Vector3(0.0, hb, 0.0), color,
				b - Vector3(0.0, hb, 0.0), color)


func _streamer_point(anchor: Vector3, t: float, length: float, flutter: float, wave_time: float, index: int) -> Vector3:
	var wave := sin(wave_time + t * 7.0 + float(index) * 1.17)
	var second_wave := sin(wave_time * 1.47 + t * 11.0 + float(index) * 0.71)
	return anchor + Vector3(wave * flutter * t, second_wave * flutter * 0.34 * t, -length * t)


func _add_streamer_triangle(a: Vector3, color_a: Color, b: Vector3, color_b: Color, c: Vector3, color_c: Color) -> void:
	_streamer_mesh.surface_set_color(color_a)
	_streamer_mesh.surface_add_vertex(a)
	_streamer_mesh.surface_set_color(color_b)
	_streamer_mesh.surface_add_vertex(b)
	_streamer_mesh.surface_set_color(color_c)
	_streamer_mesh.surface_add_vertex(c)


func _create_breeze() -> void:
	_breeze = AudioStreamPlayer3D.new()
	_breeze.name = "RooftopBreeze"
	_breeze.stream = WIND_AUDIO
	_breeze.position = Vector3(0.0, 1.6, 0.0)
	_breeze.volume_db = -37.0
	_breeze.unit_size = 7.0
	_breeze.max_distance = 24.0
	_breeze.autoplay = false
	add_child(_breeze)
	_breeze.play()


func _update_breeze() -> void:
	if _breeze == null:
		return
	var speed := gust_speed_at(elapsed_physics)
	var gust_weight := clampf((speed - LULL_SPEED) / (PEAK_SPEED - LULL_SPEED), 0.0, 1.0)
	# Keep the tower breeze as a quiet bed and let the crest be only a little louder.
	_breeze.volume_db = lerpf(-37.0, -31.0, gust_weight)


func _add_box_visual(node_name: String, position: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = node_name
	visual.position = position
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	return visual


func _add_rotated_box_visual(node_name: String, position: Vector3, size: Vector3, yaw: float, material: Material) -> MeshInstance3D:
	var visual := _add_box_visual(node_name, position, size, material)
	visual.rotation.y = yaw
	return visual


func _make_matte(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	material.metallic_specular = 0.08
	return material
