class_name ChibiJuice
extends Node

## Port of UpdateJuice, UpdateChibiExpressions, UpdateFootsteps, PlayParkourSFX, and VFX hooks.

@export var config: ParkourConfig
@export var visual_pivot: Node3D
@export var character_mesh: MeshInstance3D
@export var sfx_player: AudioStreamPlayer3D
@export var voice_player: AudioStreamPlayer3D
@export var wind_ribbon: WindRibbon
@export var dust_puff_scene: PackedScene
@export var flow_sparkle_scene: PackedScene
@export var super_bounce_wind_scene: PackedScene

var current_mesh_scale: Vector3 = Vector3.ONE
var blink_timer: float = 2.5
var blink_progress: float = 0.0
var idle_fidget_timer: float = 0.0
var played_hmm: bool = false
var played_giggle: bool = false

var morph_happy: float = 0.0
var morph_focused: float = 0.0
var morph_effort: float = 0.0
var morph_surprised: float = 0.0

var footstep_timer: float = 0.0
var step_index: int = 0
var slide_dust_cooldown: float = 0.0

var dive_gear: ChibiDiveGear

var _sfx_map: Dictionary = {}
var _tower_foley: Dictionary[String, AudioStreamPlayer3D] = {}
var _bs_indices: Dictionary = {}


func _ready() -> void:
	if config == null:
		config = ParkourConfig.new()
	_load_sfx()
	_cache_blend_shapes()


func _load_sfx() -> void:
	var mapping := {
		"Jump": "res://assets/audio/SFX_Jump.wav",
		"Land": "res://assets/audio/SFX_LandSoft.wav",
		"LedgeGrab": "res://assets/audio/SFX_LedgeGrab.wav",
		"Shimmy": "res://assets/audio/SFX_ShimmyPat.wav",
		"TowerCloth": "res://assets/audio/SFX_TowerCloth.wav",
		"Mantle": "res://assets/audio/SFX_Chibi_Hup.wav",
		"Vault": "res://assets/audio/SFX_Chibi_Whoop.wav",
		"WallKick": "res://assets/audio/SFX_WallKick.wav",
		"Slide": "res://assets/audio/SFX_SlideWhoosh.wav",
		"Roll": "res://assets/audio/SFX_RollTumble.wav",
		"FlowChime": "res://assets/audio/SFX_FlowChime.wav",
		"Whee": "res://assets/audio/SFX_Chibi_Whee.wav",
		"IdleHmm": "res://assets/audio/SFX_Chibi_Hmm.wav",
		"IdleGiggle": "res://assets/audio/SFX_Chibi_Giggle.wav",
		"Step1": "res://assets/audio/SFX_Step_01.wav",
		"Step2": "res://assets/audio/SFX_Step_02.wav",
		"Step3": "res://assets/audio/SFX_Step_03.wav",
	}
	for k in mapping:
		var path: String = mapping[k]
		if ResourceLoader.exists(path):
			_sfx_map[k] = load(path)


func _cache_blend_shapes() -> void:
	_bs_indices.clear()
	if character_mesh == null:
		return
	for bs_name in ["Blink_L", "Blink_R", "Expr_Happy", "Expr_Focused", "Expr_Effort", "Expr_Surprised"]:
		var idx := character_mesh.find_blend_shape_by_name(bs_name)
		if idx >= 0:
			_bs_indices[bs_name] = idx


func bind_mesh(mesh: MeshInstance3D) -> void:
	character_mesh = mesh
	_cache_blend_shapes()


func trigger_squash(xz_scale: float, y_scale: float) -> void:
	current_mesh_scale = Vector3(xz_scale, y_scale, xz_scale)


func clear_wind_trail() -> void:
	if wind_ribbon != null:
		wind_ribbon.clear_trail()


func play_sfx(key: String, pitch_jitter: float = 0.06) -> void:
	if not _sfx_map.has(key):
		return
	var is_voice := key in ["Mantle", "Vault", "Whee", "IdleHmm", "IdleGiggle"]
	var player := voice_player if (is_voice and voice_player != null) else sfx_player
	if player == null:
		return
	player.stream = _sfx_map[key]
	player.pitch_scale = randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
	player.play()


func play_tower_foley(key: String, world_position: Vector3, gain_db: float) -> void:
	if not _sfx_map.has(key):
		return
	var player := _tower_foley.get(key) as AudioStreamPlayer3D
	if player == null:
		player = AudioStreamPlayer3D.new()
		player.name = "TowerFoley_" + key
		player.top_level = true
		player.stream = _sfx_map[key]
		player.unit_size = 3.5
		player.max_distance = 13.0
		add_child(player)
		_tower_foley[key] = player
	player.global_position = world_position
	player.volume_db = gain_db
	player.pitch_scale = randf_range(0.95, 1.05)
	player.play()


func spawn_dust(world_pos: Vector3) -> void:
	if dust_puff_scene == null or get_tree() == null or get_tree().current_scene == null:
		return
	var vfx := dust_puff_scene.instantiate() as Node3D
	get_tree().current_scene.add_child(vfx)
	vfx.global_position = world_pos


func spawn_flow_sparkle(world_pos: Vector3) -> void:
	if flow_sparkle_scene == null or get_tree() == null or get_tree().current_scene == null:
		return
	var vfx := flow_sparkle_scene.instantiate() as Node3D
	get_tree().current_scene.add_child(vfx)
	vfx.global_position = world_pos


func spawn_super_bounce_wind(world_pos: Vector3) -> void:
	if super_bounce_wind_scene == null or get_tree() == null or get_tree().current_scene == null:
		return
	var vfx := super_bounce_wind_scene.instantiate() as Node3D
	get_tree().current_scene.add_child(vfx)
	vfx.global_position = world_pos


func update_juice(
	delta: float,
	state_name: String,
	anim_name: String,
	flow_level: float,
	planar_speed: float,
	super_bounce_active: bool,
	bounce_timer: float
) -> void:
	var ret_speed := config.squash_return_speed if config else 14.0
	current_mesh_scale = current_mesh_scale.lerp(Vector3.ONE, 1.0 - exp(-ret_speed * delta))
	if visual_pivot != null:
		visual_pivot.scale = current_mesh_scale

	slide_dust_cooldown = maxf(0.0, slide_dust_cooldown - delta)

	# Wind ribbon activation matches Unreal UpdateJuice
	if wind_ribbon != null:
		var want_ribbon := (
			state_name == "ZipLine"
			or (flow_level > 0.55 and planar_speed > 4.4)
			or (super_bounce_active and bounce_timer > 0.12)
		)
		wind_ribbon.set_emitting(want_ribbon)

	_update_wall_run_footsteps(delta, state_name, planar_speed)
	_update_expressions(delta, state_name, anim_name, flow_level)


func play_ground_footstep(_foot: StringName) -> void:
	_play_footstep()


func _update_wall_run_footsteps(delta: float, state_name: String, planar_speed: float) -> void:
	if state_name != "WallRun":
		footstep_timer = 0.07
		return
	footstep_timer -= delta
	if footstep_timer <= 0.0:
		_play_footstep()
		footstep_timer = clampf(1.25 / maxf(planar_speed, 2.0), 0.17, 0.34)


func _play_footstep() -> void:
	step_index = (step_index % 3) + 1
	play_sfx("Step%d" % step_index, 0.08)


func _update_expressions(delta: float, state_name: String, anim_name: String, flow_level: float) -> void:
	if character_mesh == null:
		return

	# Idle fidgets (exact Unreal timers: 2.85s Hmm, 4.15s Giggle, 6.0s reset)
	if anim_name == "Idle":
		idle_fidget_timer += delta
		if idle_fidget_timer >= 2.85 and not played_hmm:
			played_hmm = true
			play_sfx("IdleHmm", 0.04)
		if idle_fidget_timer >= 4.15 and not played_giggle:
			played_giggle = true
			play_sfx("IdleGiggle", 0.04)
		if idle_fidget_timer >= 6.0:
			idle_fidget_timer = 0.0
			played_hmm = false
			played_giggle = false
	else:
		idle_fidget_timer = 0.0
		played_hmm = false
		played_giggle = false

	# Random blink cycle (0.15s triangle wave every 2.4–5.2s)
	var blink_val := 0.0
	if blink_progress > 0.0:
		blink_val = clampf(1.0 - absf((blink_progress / 0.15) * 2.0 - 1.0), 0.0, 1.0)
		blink_progress = maxf(0.0, blink_progress - delta)
	else:
		blink_timer -= delta
		if blink_timer <= 0.0:
			blink_progress = 0.15
			blink_timer = randf_range(2.4, 5.2)

	var want_happy := (
		(anim_name == "Idle" and idle_fidget_timer >= 4.0 and idle_fidget_timer <= 5.5)
		or (anim_name == "Sprint" and flow_level > 0.65)
		or anim_name == "BounceAir"
		or state_name in ["SpeedVault", "Slide", "LandRoll", "PoleHop", "ZipLine", "RopeSwing", "PoolSwim"]
	)
	var want_focused := (
		anim_name == "WallKick"
		or state_name in ["WallRun", "LedgeShimmy", "LedgeCorner", "PolePerch", "BalanceBeam", "Climbing"]
	)
	var want_effort := state_name in ["LedgeHang", "MantleUp", "RopeLine"]
	var want_surprised := anim_name == "FallFlail"

	morph_happy = lerpf(morph_happy, 1.0 if want_happy else 0.0, 1.0 - exp(-10.0 * delta))
	morph_focused = lerpf(morph_focused, 1.0 if want_focused else 0.0, 1.0 - exp(-10.0 * delta))
	morph_effort = lerpf(morph_effort, 1.0 if want_effort else 0.0, 1.0 - exp(-10.0 * delta))
	morph_surprised = lerpf(morph_surprised, 1.0 if want_surprised else 0.0, 1.0 - exp(-12.0 * delta))

	_set_bs("Blink_L", blink_val)
	_set_bs("Blink_R", blink_val)
	# Keep the mouth around the bite valve while the normal blink continues.
	var bite := dive_gear.mouthpiece_weight if dive_gear != null else 0.0
	_set_bs("Expr_Happy", morph_happy * (1.0 - bite))
	_set_bs("Expr_Focused", morph_focused * (1.0 - bite))
	_set_bs("Expr_Effort", morph_effort * (1.0 - bite))
	_set_bs("Expr_Surprised", lerpf(morph_surprised, 0.92, bite))


func _set_bs(bs_name: String, val: float) -> void:
	if _bs_indices.has(bs_name):
		character_mesh.set_blend_shape_value(_bs_indices[bs_name], val)
