extends SceneTree

## Headless scene builder that generates valid Godot 4.7 .tscn scenes for:
##   - scenes/vfx/{dust_puff, flow_sparkle, super_bounce_wind}.tscn
##   - scenes/character/chibi_runner.tscn
##   - scenes/stations/{climbing_wall, climbing_net}.tscn
##   - scenes/gym/rooftop_parkour_gym.tscn

const CHIBI_GLB := preload("res://assets/characters/chibi_runner.glb")
const HOLDS_GLB := preload("res://assets/stations/rooftop_holds.glb")
const NET_GLB := preload("res://assets/stations/rooftop_net.glb")

const STATE_CHART_SCRIPT := preload("res://addons/godot_state_charts/state_chart.gd")
const COMPOUND_STATE_SCRIPT := preload("res://addons/godot_state_charts/compound_state.gd")
const ATOMIC_STATE_SCRIPT := preload("res://addons/godot_state_charts/atomic_state.gd")
const TRANSITION_SCRIPT := preload("res://addons/godot_state_charts/transition.gd")

const PCAM_3D_SCRIPT := preload("res://addons/phantom_camera/scripts/phantom_camera/phantom_camera_3d.gd")
const PCAM_HOST_SCRIPT := preload("res://addons/phantom_camera/scripts/phantom_camera_host/phantom_camera_host.gd")
const PCAM_TWEEN_SCRIPT := preload("res://addons/phantom_camera/scripts/resources/tween_resource.gd")
const CAM_RES_SCRIPT := preload("res://addons/phantom_camera/scripts/resources/camera_3d_resource.gd")
const PALETTE := preload("res://scripts/gym/rooftop_palette.gd")
const POOL_SCRIPT := preload("res://scripts/stations/chibi_pool.gd")
const DROP_COURSE_SCRIPT := preload("res://scripts/stations/drop_well_tunnel.gd")
const DROP_COURSE_SCENE := preload("res://scenes/stations/drop_well_tunnel.tscn")
const CLIMB_TOWER_SCENE := preload("res://scenes/stations/rooftop_climb_tower.tscn")
const WIND_TUNNEL_SCENE := preload("res://scenes/stations/rooftop_wind_tunnel.tscn")
const WIND_LAUNCH_PERCH_SCENE := preload("res://scenes/stations/rooftop_wind_launch_perch.tscn")
const TOWER_METER_SCRIPT := preload("res://scripts/gym/tower_fall_meter.gd")
const ROOFTOP_POOL_POSITION := Vector3(24.0, 0.0, -22.0)
const CLIMB_TOWER_POSITION := Vector3(38.5, 0.0, -28.2)
const WIND_TUNNEL_POSITION := Vector3(16.0, 0.0, 15.0)
const WIND_LAUNCH_PERCH_POSITION := Vector3(18.9, 0.0, 19.45)


func _init() -> void:
	if "--rooftop-only" in OS.get_cmdline_user_args():
		_build_rooftop_gym_scene()
		quit(0)
		return

	DirAccess.make_dir_recursive_absolute("res://scenes/vfx")
	DirAccess.make_dir_recursive_absolute("res://scenes/character")
	DirAccess.make_dir_recursive_absolute("res://scenes/stations")
	DirAccess.make_dir_recursive_absolute("res://scenes/gym")

	_build_vfx_scenes()
	_build_chibi_runner_scene()
	_build_climbing_station_scene("res://scenes/stations/climbing_wall.tscn", false)
	_build_climbing_station_scene("res://scenes/stations/climbing_net.tscn", true)
	_build_rooftop_gym_scene()
	print("[BuildScenes] All scenes built cleanly.")
	quit(0)


func _save_scene(root: Node, path: String) -> void:
	_set_owner_recursive(root, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	assert(err == OK, "Failed to pack %s: %d" % [path, err])
	err = ResourceSaver.save(ps, path)
	assert(err == OK, "Failed to save %s: %d" % [path, err])
	print("[BuildScenes] Saved ", path)
	root.free()


func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	for c in node.get_children():
		# Do not steal ownership of nodes inside instanced child PackedScenes
		if c.scene_file_path != "":
			c.owner = owner_node
			continue
		c.owner = owner_node
		_set_owner_recursive(c, owner_node)


func _build_vfx_scenes() -> void:
	_make_burst_vfx("res://scenes/vfx/dust_puff.tscn", Color(0.91, 0.84, 0.78, 0.58), 6, 0.27, 0.055, 0.90)
	_make_burst_vfx("res://scenes/vfx/flow_sparkle.tscn", Color(0.28, 0.95, 0.85, 0.92), 18, 0.55, 0.08, 3.2)
	_make_burst_vfx("res://scenes/vfx/super_bounce_wind.tscn", Color(0.85, 0.98, 1.0, 0.85), 24, 0.60, 0.12, 4.8)


func _make_burst_vfx(path: String, col: Color, amount: int, lifetime: float, radius: float, speed: float) -> void:
	var p := GPUParticles3D.new()
	p.name = path.get_file().get_basename().to_pascal_case()
	p.set_script(preload("res://scripts/vfx/one_shot_particles.gd"))
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.88

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 85.0
	pm.initial_velocity_min = speed * 0.5
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0.0, -2.5, 0.0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.color = col
	p.process_material = pm

	var sph := SphereMesh.new()
	sph.radius = radius
	sph.height = radius * 2.0
	sph.radial_segments = 8
	sph.rings = 4
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	sph.material = mat
	p.draw_pass_1 = sph
	_save_scene(p, path)


func _build_chibi_runner_scene() -> void:
	var root := CharacterBody3D.new()
	root.name = "ChibiRunner"
	root.set_script(preload("res://scripts/character/parkour_controller.gd"))
	root.collision_layer = 2 # Layer 2: Player
	root.collision_mask = 1 | 4 # World + Climbable
	root.add_to_group("player", true)

	var cfg := ParkourConfig.new()
	root.set("config", cfg)

	# Capsule collider (feet at Y=0, center at Y=0.60)
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var cap := CapsuleShape3D.new()
	cap.radius = cfg.capsule_radius
	cap.height = cfg.capsule_height
	col.shape = cap
	col.position = Vector3(0.0, cfg.capsule_height * 0.5, 0.0)
	root.add_child(col)

	# AnimationTree placed BEFORE VisualPivot with priority -20 so animations evaluate before Skeleton3D modifiers!
	var anim_tree := AnimationTree.new()
	anim_tree.name = "AnimationTree"
	anim_tree.process_priority = -20
	root.add_child(anim_tree)

	# Visual pivot holding Chibi GLB
	var pivot := Node3D.new()
	pivot.name = "VisualPivot"
	root.add_child(pivot)

	var model := CHIBI_GLB.instantiate()
	model.name = "ChibiModel"
	# ChibiRunner.blend faces -Y (glTF +Z); rotate 180 deg around Y inside VisualPivot so she faces Godot -Z forward!
	model.rotation.y = PI
	pivot.add_child(model)

	# WindRibbon attached near pelvis height
	var ribbon_anchor := Node3D.new()
	ribbon_anchor.name = "RibbonAnchor"
	ribbon_anchor.position = Vector3(0.0, 0.55, 0.12)
	pivot.add_child(ribbon_anchor)
	var ribbon := MeshInstance3D.new()
	ribbon.name = "WindRibbon"
	ribbon.set_script(preload("res://scripts/vfx/wind_ribbon.gd"))
	ribbon_anchor.add_child(ribbon)

	# Subsystems
	var input_node := Node.new()
	input_node.name = "ChibiInput"
	input_node.set_script(preload("res://scripts/character/chibi_input.gd"))
	root.add_child(input_node)

	var anim_ctrl := Node.new()
	anim_ctrl.name = "ChibiAnimController"
	anim_ctrl.set_script(preload("res://scripts/character/chibi_anim_controller.gd"))
	root.add_child(anim_ctrl)

	var sfx_player := AudioStreamPlayer3D.new()
	sfx_player.name = "SFXPlayer"
	sfx_player.max_distance = 25.0
	sfx_player.bus = &"SFX"
	root.add_child(sfx_player)

	var voice_player := AudioStreamPlayer3D.new()
	voice_player.name = "VoicePlayer"
	voice_player.max_distance = 25.0
	voice_player.bus = &"Voice"
	root.add_child(voice_player)

	var juice := Node.new()
	juice.name = "ChibiJuice"
	juice.set_script(preload("res://scripts/character/chibi_juice.gd"))
	juice.set("config", cfg)
	juice.set("visual_pivot", pivot)
	juice.set("sfx_player", sfx_player)
	juice.set("voice_player", voice_player)
	juice.set("wind_ribbon", ribbon)
	juice.set("dust_puff_scene", load("res://scenes/vfx/dust_puff.tscn"))
	juice.set("flow_sparkle_scene", load("res://scenes/vfx/flow_sparkle.tscn"))
	juice.set("super_bounce_wind_scene", load("res://scenes/vfx/super_bounce_wind.tscn"))
	root.add_child(juice)

	# Hierarchical Godot State Chart
	var sc := _build_state_chart()
	root.add_child(sc)

	# Phantom Camera 3D Rig (ParkourPCam + ClimbPCam + Camera3D/Host)
	var parkour_pcam := Node3D.new()
	parkour_pcam.name = "ParkourPCam"
	parkour_pcam.set_script(PCAM_3D_SCRIPT)
	parkour_pcam.set("priority", 10)
	parkour_pcam.set("follow_mode", 6) # THIRD_PERSON
	parkour_pcam.set("tween_on_load", false)
	parkour_pcam.set("follow_target", root)
	parkour_pcam.set("follow_damping", true)
	parkour_pcam.set("follow_damping_value", Vector3(0.06, 0.11, 0.06))
	parkour_pcam.set("follow_offset", Vector3(cfg.base_shoulder_offset_x, cfg.base_socket_offset_y, 0.0))
	parkour_pcam.set("spring_length", cfg.base_arm_length)
	parkour_pcam.set("collision_mask", 1) # World only (ignores Player layer 2!)
	parkour_pcam.set("margin", 0.18)
	var cam_res := Resource.new()
	cam_res.set_script(CAM_RES_SCRIPT)
	cam_res.set("keep_aspect", Camera3D.KEEP_HEIGHT)
	cam_res.set("fov", cfg.base_fov)
	parkour_pcam.set("camera_3d_resource", cam_res)
	var tw := Resource.new()
	tw.set_script(PCAM_TWEEN_SCRIPT)
	tw.set("duration", 0.27)
	parkour_pcam.set("tween_resource", tw)
	root.add_child(parkour_pcam)

	var climb_pcam := Node3D.new()
	climb_pcam.name = "ClimbPCam"
	climb_pcam.set_script(PCAM_3D_SCRIPT)
	climb_pcam.set("follow_mode", 6) # THIRD_PERSON
	climb_pcam.set("follow_target", root)
	climb_pcam.set("follow_damping", true)
	climb_pcam.set("follow_damping_value", Vector3(0.12, 0.12, 0.12))
	climb_pcam.set("follow_offset", Vector3(0.0, 0.85, 0.0))
	climb_pcam.set("spring_length", 2.85)
	climb_pcam.set("collision_mask", 1)
	var ctw := Resource.new()
	ctw.set_script(PCAM_TWEEN_SCRIPT)
	ctw.set("duration", 0.32)
	climb_pcam.set("tween_resource", ctw)
	root.add_child(climb_pcam)

	var cam := Camera3D.new()
	cam.name = "MainCamera3D"
	cam.current = true
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.fov = cfg.base_fov
	var host := Node.new()
	host.name = "PhantomCameraHost"
	host.set_script(PCAM_HOST_SCRIPT)
	cam.add_child(host)
	root.add_child(cam)

	var cam_ctrl := Node.new()
	cam_ctrl.name = "ChibiCameraController"
	cam_ctrl.set_script(preload("res://scripts/character/chibi_camera_controller.gd"))
	cam_ctrl.set("config", cfg)
	cam_ctrl.set("parkour_pcam", parkour_pcam)
	cam_ctrl.set("climb_pcam", climb_pcam)
	cam_ctrl.set("active_camera", cam)
	root.add_child(cam_ctrl)

	# Touch HUD + StateChartDebugger
	var hud := CanvasLayer.new()
	hud.name = "TouchControlsHUD"
	hud.set_script(preload("res://scripts/ui/touch_controls.gd"))
	hud.set("chibi_input", input_node)
	hud.set("state_chart", sc)
	root.add_child(hud)

	# Rig Binder (binds Skeleton3D, AnimationTree, ChibiPoseModifier, SpringBoneSimulator3D)
	var binder := Node.new()
	binder.name = "ChibiRigBinder"
	binder.set_script(preload("res://scripts/character/chibi_rig_binder.gd"))
	binder.set("controller", root)
	binder.set("visual_pivot", pivot)
	binder.set("anim_tree", anim_tree)
	binder.set("anim_ctrl", anim_ctrl)
	binder.set("juice", juice)
	root.add_child(binder)

	# Wire controller exports
	root.set("state_chart", sc)
	root.set("chibi_input", input_node)
	root.set("camera_ctrl", cam_ctrl)
	root.set("anim_ctrl", anim_ctrl)
	root.set("juice", juice)
	root.set("collision_shape", col)
	root.set("visual_pivot", pivot)
	root.set("touch_hud", hud)

	_save_scene(root, "res://scenes/character/chibi_runner.tscn")


func _build_state_chart() -> Node:
	var sc := Node.new()
	sc.name = "StateChart"
	sc.set_script(STATE_CHART_SCRIPT)
	sc.set("warn_on_sending_unknown_events", false)

	var root_state := Node.new()
	root_state.name = "ParkourRoot"
	root_state.set_script(COMPOUND_STATE_SCRIPT)
	sc.add_child(root_state)

	var leaf_map: Dictionary = {}

	# Top-level atomic states
	for sname in ["Locomotion", "SpeedVault", "WallRun", "Slide", "LandRoll", "PoolSwim"]:
		var st := Node.new()
		st.name = sname
		st.set_script(ATOMIC_STATE_SCRIPT)
		root_state.add_child(st)
		leaf_map[sname.to_snake_case()] = st

	# Ledge compound state
	var ledge_comp := Node.new()
	ledge_comp.name = "Ledge"
	ledge_comp.set_script(COMPOUND_STATE_SCRIPT)
	root_state.add_child(ledge_comp)
	for sname in ["LedgeHang", "LedgeShimmy", "LedgeCorner", "MantleUp"]:
		var st := Node.new()
		st.name = sname
		st.set_script(ATOMIC_STATE_SCRIPT)
		ledge_comp.add_child(st)
		leaf_map[sname.to_snake_case()] = st
	ledge_comp.set("initial_state", ledge_comp.get_path_to(leaf_map["ledge_hang"]))

	# Climbing compound state
	var climb_comp := Node.new()
	climb_comp.name = "Climbing"
	climb_comp.set_script(COMPOUND_STATE_SCRIPT)
	root_state.add_child(climb_comp)
	for sname in ["ClimbWall", "ClimbNet"]:
		var st := Node.new()
		st.name = sname
		st.set_script(ATOMIC_STATE_SCRIPT)
		climb_comp.add_child(st)
		leaf_map[sname.to_snake_case()] = st
	climb_comp.set("initial_state", climb_comp.get_path_to(leaf_map["climb_wall"]))

	# Interactive compound state
	var inter_comp := Node.new()
	inter_comp.name = "Interactive"
	inter_comp.set_script(COMPOUND_STATE_SCRIPT)
	root_state.add_child(inter_comp)
	for sname in ["PolePerch", "PoleHop", "BalanceBeam", "RopeLine", "ZipLine", "RopeSwing"]:
		var st := Node.new()
		st.name = sname
		st.set_script(ATOMIC_STATE_SCRIPT)
		inter_comp.add_child(st)
		leaf_map[sname.to_snake_case()] = st
	inter_comp.set("initial_state", inter_comp.get_path_to(leaf_map["pole_perch"]))

	root_state.set("initial_state", root_state.get_path_to(leaf_map["locomotion"]))

	# Global root-level transitions keyed by "to_<state_snake_case>" so any state can cleanly transition
	for key in leaf_map:
		var tr := Node.new()
		tr.name = "To_" + key
		tr.set_script(TRANSITION_SCRIPT)
		tr.set("event", StringName("to_" + key))
		tr.set("to", tr.get_path_to(leaf_map[key]) if tr.is_inside_tree() else NodePath())
		root_state.add_child(tr)
		tr.set("to", tr.get_path_to(leaf_map[key]))

	return sc


func _build_climbing_station_scene(path: String, is_net: bool) -> void:
	var root := Node3D.new()
	root.name = "ClimbingNet" if is_net else "ClimbingWall"
	root.set_script(preload("res://scripts/climbing/climbing_station.gd"))
	root.set("is_rope_net", is_net)

	var visual := (NET_GLB if is_net else HOLDS_GLB).instantiate()
	visual.name = "VisualMesh"
	root.add_child(visual)

	# Backing panel StaticBody3D matching Unreal ClimbingStation::OnConstruction
	# Unreal Backing: loc=(7, 0, 138) cm, extent=(6, 70 or 150, 138) cm
	# Godot local: pos=(0, 1.38, -0.07) m, size=(1.40 or 3.00, 2.76, 0.12) m
	var backing := StaticBody3D.new()
	backing.name = "PanelCollision"
	backing.collision_layer = 1 | 4 # World + Climbable
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.40 if is_net else 3.00, 2.76, 0.12)
	col.shape = box
	col.position = Vector3(0.0, 1.38, -0.07)
	backing.add_child(col)
	root.add_child(backing)

	_save_scene(root, path)


func _build_rooftop_gym_scene() -> void:
	var root := Node3D.new()
	root.name = "RooftopParkourGym"
	root.set_script(preload("res://scripts/gym/rooftop_gym_controller.gd"))

	# Low evening sun and lavender fill keep shaded route cues readable.
	var env := Environment.new()
	var sky := Sky.new()
	# The visible sky animates; the cubemap pass uses the inexpensive atmosphere.
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/rooftop_sky.gdshader")
	var cloud_noise := FastNoiseLite.new()
	cloud_noise.seed = 4137
	cloud_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cloud_noise.frequency = 0.055
	cloud_noise.fractal_octaves = 4
	var cloud_texture := NoiseTexture3D.new()
	cloud_texture.noise = cloud_noise
	cloud_texture.seamless = true
	sky_mat.set_shader_parameter("cloud_noise", cloud_texture)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e9ddf2")
	env.ambient_light_energy = 0.56
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.87
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color("efc4ae")
	env.fog_density = 0.24
	env.fog_depth_begin = 32.0
	env.fog_depth_end = 112.0
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.rotation_degrees = Vector3(-23.0, -125.0, 0.0)
	sun.light_color = Color("ffdfb2")
	sun.light_energy = 1.12
	sun.shadow_enabled = true
	sun.shadow_blur = 2.7
	sun.directional_shadow_max_distance = 58.0
	sky_mat.set_shader_parameter("sun_direction", sun.transform.basis.z.normalized())
	root.add_child(sun)

	# Soft sky bounce shapes the character even under the tall obstacles.
	var fill := DirectionalLight3D.new()
	fill.name = "SkyFill"
	fill.rotation_degrees = Vector3(-38.0, 28.0, 0.0)
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	fill.light_color = Color("f2e9fa")
	fill.light_energy = 0.28
	fill.light_specular = 0.0
	root.add_child(fill)

	var mat_floor := _make_grid_mat(PALETTE.SURFACE, Color("cfc5c1"), 2.0, 0.85)
	var mat_lane := _make_mat(Color("eee4dc"), 0.86)
	var mat_white := _make_mat(PALETTE.PORCELAIN, 0.82)
	var mat_coral := _make_mat(PALETTE.CORAL, 0.73)
	var mat_mint := _make_mat(PALETTE.MINT, 0.73)
	var mat_lavender := _make_mat(PALETTE.LAVENDER, 0.73)
	var mat_peach := _make_mat(PALETTE.PEACH, 0.73)
	var mat_support := _make_mat(PALETTE.LIGHT_SUPPORT, 0.82)

	# Keep a deck opening so the deep end uses the basin floor for both rendering and collision.
	var floor_grp := Node3D.new()
	floor_grp.name = "RooftopDeck"
	root.add_child(floor_grp)
	var basin_bounds := POOL_SCRIPT.deck_opening_bounds()
	var pool_left := ROOFTOP_POOL_POSITION.x + basin_bounds.position.y
	var pool_right := ROOFTOP_POOL_POSITION.x + basin_bounds.end.y
	var pool_north := ROOFTOP_POOL_POSITION.z - basin_bounds.end.x
	var pool_south := ROOFTOP_POOL_POSITION.z - basin_bounds.position.x
	_add_deck_section(floor_grp, "MainDeck", Vector2(-35.0, -47.0), Vector2(pool_left, 27.0), mat_floor)
	var well_bounds := Rect2(
		DROP_COURSE_SCRIPT.WELL_MIN_X, DROP_COURSE_SCRIPT.WELL_MIN_Z,
		DROP_COURSE_SCRIPT.WELL_MAX_X - DROP_COURSE_SCRIPT.WELL_MIN_X,
		DROP_COURSE_SCRIPT.WELL_MAX_Z - DROP_COURSE_SCRIPT.WELL_MIN_Z
	)
	_add_deck_around_tunnel(floor_grp, pool_right, well_bounds, DROP_COURSE_SCRIPT.get_cap_deck_rows(), mat_floor)
	_add_deck_section(floor_grp, "MainDeckPoolNorth", Vector2(pool_left, -47.0), Vector2(pool_right, pool_north), mat_floor)
	_add_deck_section(floor_grp, "MainDeckPoolSouth", Vector2(pool_left, pool_south), Vector2(pool_right, 27.0), mat_floor)
	# Perimeter low parapet walls
	_add_box(floor_grp, "ParapetNorth", Vector3(6.0, 0.45, -47.0), Vector3(82.0, 0.9, 0.6), mat_support, mat_white, 0.10)
	_add_box(floor_grp, "ParapetSouth", Vector3(6.0, 0.45, 27.0), Vector3(82.0, 0.9, 0.6), mat_support, mat_white, 0.10)
	_add_box(floor_grp, "ParapetWest", Vector3(-35.0, 0.45, -10.0), Vector3(0.6, 0.9, 74.0), mat_support, mat_white, 0.10)
	_add_box(floor_grp, "ParapetEast", Vector3(47.0, 0.45, -10.0), Vector3(0.6, 0.9, 74.0), mat_support, mat_white, 0.10)

	# =========================================================================
	# ZONE 1: Flow, Speed Vaults, Slide Gates, Downhill Ramp & Roll Drop
	# =========================================================================
	var z1 := Node3D.new()
	z1.name = "Zone1_FlowAndSlides"
	root.add_child(z1)
	var berry := preload("res://scenes/items/strawberry_pickup.tscn").instantiate() as Node3D
	berry.position = Vector3(3.35, 0.24, 3.7)
	z1.add_child(berry)
	_add_box_visual(z1, "VaultLane", Vector3(0.0, 0.003, -3.45), Vector3(5.5, 0.012, 16.4), mat_lane, 0.0)
	_add_box_visual(z1, "VaultStartStripe", Vector3(0.0, 0.013, 4.45), Vector3(4.9, 0.018, 0.23), mat_coral, 0.008)
	# 3 progressive SpeedVault barriers along -Z runway
	_add_box(z1, "VaultBar_Low", Vector3(0.0, 0.32, 0.0), Vector3(4.5, 0.64, 0.55), mat_coral)
	_add_box(z1, "VaultBar_Med", Vector3(0.0, 0.44, -5.0), Vector3(4.5, 0.88, 0.60), mat_coral)
	_add_box(z1, "VaultBar_High", Vector3(0.0, 0.52, -10.0), Vector3(4.5, 1.04, 0.65), mat_coral)
	# Sequential Slide Gates (0.78 m bottom clearance — requires sliding!)
	for i in 3:
		var gz := -1.5 - float(i) * 4.5
		_add_box(z1, "SlideGatePostL_%d" % i, Vector3(4.0, 1.2, gz), Vector3(0.45, 2.4, 0.45), mat_white)
		_add_box(z1, "SlideGatePostR_%d" % i, Vector3(8.5, 1.2, gz), Vector3(0.45, 2.4, 0.45), mat_white)
		_add_box(z1, "SlideGateBeam_%d" % i, Vector3(6.25, 1.38, gz), Vector3(4.9, 1.20, 0.50), mat_lavender)
	# Downhill Slide Ramp + Roll Drop Platform (mantle steps <= 1.50 m for 16.17 m/s^2 gravity)
	_add_ramp(z1, "SlideSlopeRamp", Vector3(-6.5, 1.2, -5.0), Vector3(4.0, 0.4, 9.0), 16.0, mat_white, mat_lavender)
	_add_box(z1, "RollDropTower", Vector3(-6.5, 2.1, 2.5), Vector3(4.5, 4.2, 4.5), mat_white, mat_lavender, 0.13)
	_add_box(z1, "RollDropStep1", Vector3(-6.5, 0.6, 6.2), Vector3(3.0, 1.2, 1.8), mat_white, mat_peach, 0.14)
	_add_box(z1, "RollDropStep2", Vector3(-6.5, 1.35, 5.2), Vector3(3.0, 2.7, 1.5), mat_white, mat_peach, 0.14)

	# =========================================================================
	# ZONE 2: Wall-Run Corridor & Beveled/Corner Ledge Contact Tower
	# =========================================================================
	var z2 := Node3D.new()
	z2.name = "Zone2_WallRunAndLedges"
	root.add_child(z2)
	# Parallel Wall-Run corridor (2.50 m clear width tuned for Unreal 16.17 m/s^2 wall-kick transfers)
	_add_box(z2, "WallRun_Left1", Vector3(-19.5, 2.2, -5.0), Vector3(0.5, 4.4, 9.5), mat_white, mat_mint, 0.13, Vector3.AXIS_X)
	_add_box(z2, "WallRun_Right1", Vector3(-16.5, 2.2, -9.5), Vector3(0.5, 4.4, 9.5), mat_white, mat_mint, -0.13, Vector3.AXIS_X)
	_add_box(z2, "WallRun_LandingPad", Vector3(-18.0, 1.0, -16.5), Vector3(5.5, 2.0, 4.5), mat_white, mat_mint, 0.12)
	# Ledge Contact Showcase: Flat ledge (1.65 m), Beveled trimesh ledge (1.65 m), and 90-deg corner block (+step)
	_add_box(z2, "LedgeFlat_180", Vector3(-24.0, 0.825, 2.0), Vector3(4.5, 1.65, 2.5), mat_white, mat_mint, 0.12)
	_add_box(z2, "LedgeCorner_220", Vector3(-25.5, 1.05, -4.0), Vector3(3.6, 2.10, 3.6), mat_white, mat_mint, 0.12)
	_add_box(z2, "LedgeCorner_Step", Vector3(-25.5, 0.275, -1.5), Vector3(2.4, 0.55, 1.2), mat_white, mat_peach, 0.13)
	_add_beveled_ledge(z2, "LedgeBeveled_Trimesh", Vector3(-24.0, 0.0, 7.5), Vector3(4.2, 1.65, 2.2), 0.24, mat_white, mat_mint)

	# =========================================================================
	# ZONE 3: Dynamic Climbing Plaza + Deforming Rope Net
	# =========================================================================
	var z3 := Node3D.new()
	z3.name = "Zone3_ClimbingPlaza"
	root.add_child(z3)
	var wall_scene: PackedScene = load("res://scenes/stations/dynamic_climbing_wall.tscn")
	var wall := wall_scene.instantiate() as Node3D
	wall.name = "Climb_HandholdWall"
	wall.position = Vector3(14.5, 0.0, -4.0)
	z3.add_child(wall)

	var net_scene: PackedScene = load("res://scenes/stations/climbing_net.tscn")
	var net := net_scene.instantiate() as Node3D
	net.name = "Climb_RopeNet"
	net.position = Vector3(19.5, 0.0, -4.0)
	z3.add_child(net)

	# Top mantle-off deck behind both climbing stations
	_add_box(z3, "ClimbTopDeck", Vector3(17.0, 1.38, -6.2), Vector3(10.5, 2.76, 4.2), mat_white, mat_mint, 0.12)
	_add_ramp(z3, "ClimbReturnRamp", Vector3(23.5, 1.38, -6.2), Vector3(2.8, 0.3, 7.5), 22.0, mat_white, mat_mint)

	# =========================================================================
	# ZONE 4: Aerial Apparatus Circuit
	# =========================================================================
	var z4 := Node3D.new()
	z4.name = "Zone4_AerialCircuit"
	root.add_child(z4)

	# Trampoline -> Elevated Launch Deck (4.2 m top: super bounce 4.98 m clears cleanly, normal bounce 3.34 m grabs ledge)
	var tramp := Node3D.new()
	tramp.name = "Trampoline_01"
	tramp.set_script(preload("res://scripts/stations/parkour_trampoline.gd"))
	tramp.position = Vector3(-5.0, 0.0, -25.0)
	z4.add_child(tramp)
	_add_box(z4, "TrampolineHighDeck", Vector3(-5.0, 2.1, -31.0), Vector3(5.0, 4.2, 4.5), mat_white, mat_mint, 0.13)

	# Raised starter lets a running jump land from above the first pole cap.
	_add_box(z4, "PoleStartStep", Vector3(0.0, 0.30, -23.0), Vector3(2.2, 0.60, 1.4), mat_white, mat_lavender, 0.11)
	var pole_offsets := [
		Vector3(0.0, 0.0, -25.0),
		Vector3(0.5, 0.3, -28.0),
		Vector3(-0.4, 0.6, -31.0),
		Vector3(0.4, 0.9, -34.0),
		Vector3(0.0, 1.2, -37.0),
	]
	for i in pole_offsets.size():
		var pole := Node3D.new()
		pole.name = "ParkourPole_%02d" % (i + 1)
		pole.set_script(preload("res://scripts/stations/parkour_pole.gd"))
		pole.position = pole_offsets[i]
		z4.add_child(pole)
	_add_box(z4, "PoleEndDeck", Vector3(0.0, 1.2, -41.0), Vector3(5.0, 2.4, 3.5), mat_white, mat_lavender, 0.12)

	# Balance Beam
	_add_box(z4, "BeamStartPad", Vector3(6.5, 0.8, -24.5), Vector3(3.0, 1.6, 2.8), mat_white, mat_lavender, 0.11)
	var beam := Node3D.new()
	beam.name = "BalanceBeam_01"
	beam.set_script(preload("res://scripts/stations/parkour_balance_beam.gd"))
	beam.position = Vector3(6.5, 1.6, -26.0)
	z4.add_child(beam)
	_add_box(z4, "BeamEndPad", Vector3(6.5, 0.8, -35.5), Vector3(3.0, 1.6, 2.8), mat_white, mat_lavender, 0.11)

	# SlothCrawl Line (+1.10 m side step to climb onto 2.20 m tower)
	_add_box(z4, "SlothStartStep", Vector3(12.0, 0.55, -21.8), Vector3(2.4, 1.10, 1.4), mat_white, mat_peach, 0.11)
	_add_box(z4, "SlothStartTower", Vector3(12.0, 1.1, -24.0), Vector3(3.0, 2.2, 2.8), mat_white, mat_peach, 0.12)
	var sloth := Node3D.new()
	sloth.name = "SlothLine_01"
	sloth.set_script(preload("res://scripts/stations/parkour_line.gd"))
	sloth.set("is_zip_line", false)
	sloth.set("end_offset", Vector3(0.0, 0.0, -9.0))
	sloth.position = Vector3(12.0, 3.25, -25.4)
	z4.add_child(sloth)
	_add_box(z4, "SlothEndTower", Vector3(12.0, 1.1, -35.8), Vector3(3.0, 2.2, 2.8), mat_white, mat_peach, 0.12)

	# ZipLine (Unreal Lvl_ParkourGym proportions: 2.90 m start deck + walkable approach ramp + gantry frames + 0.50 m landing pad)
	_add_ramp(z4, "ZipStartRamp", Vector3(16.5, 1.34, -18.95), Vector3(2.6, 0.24, 7.42), 23.1, mat_white, mat_mint)
	_add_box(z4, "ZipStartTower", Vector3(16.5, 1.45, -24.0), Vector3(3.4, 2.90, 3.2), mat_white, mat_mint, 0.12)
	_add_box(z4, "ZipStartPostL", Vector3(15.1, 3.775, -25.55), Vector3(0.20, 1.75, 0.20), mat_support)
	_add_box(z4, "ZipStartPostR", Vector3(17.9, 3.775, -25.55), Vector3(0.20, 1.75, 0.20), mat_support)
	_add_box(z4, "ZipStartBar", Vector3(16.5, 4.60, -25.55), Vector3(3.0, 0.20, 0.20), mat_support)
	var zipline := Node3D.new()
	zipline.name = "ZipLine_01"
	zipline.set_script(preload("res://scripts/stations/parkour_line.gd"))
	zipline.set("is_zip_line", true)
	zipline.set("end_offset", Vector3(0.0, -2.30, -11.0))
	zipline.position = Vector3(16.5, 4.50, -25.55)
	z4.add_child(zipline)
	_add_box(z4, "ZipEndPostL", Vector3(14.9, 1.425, -36.55), Vector3(0.20, 1.85, 0.20), mat_support)
	_add_box(z4, "ZipEndPostR", Vector3(18.1, 1.425, -36.55), Vector3(0.20, 1.85, 0.20), mat_support)
	_add_box(z4, "ZipEndBar", Vector3(16.5, 2.30, -36.55), Vector3(3.4, 0.20, 0.20), mat_support)
	_add_box(z4, "ZipEndTower", Vector3(16.5, 0.25, -38.5), Vector3(4.4, 0.50, 4.4), mat_white, mat_mint, 0.12)

	# Rope Swing (+1.10 m side step to climb onto 2.20 m pad)
	_add_box(z4, "SwingStartStep", Vector3(-11.5, 0.55, -22.2), Vector3(2.4, 1.10, 1.4), mat_white, mat_peach, 0.11)
	_add_box(z4, "SwingStartPad", Vector3(-11.5, 1.1, -24.5), Vector3(3.4, 2.2, 3.0), mat_white, mat_coral, 0.12)
	_add_box(z4, "SwingGantry", Vector3(-11.5, 5.5, -30.0), Vector3(4.2, 0.35, 0.35), mat_support)
	var swing := Node3D.new()
	swing.name = "RopeSwing_01"
	swing.set_script(preload("res://scripts/stations/parkour_rope_swing.gd"))
	swing.position = Vector3(-11.5, 5.3, -30.0)
	z4.add_child(swing)
	_add_box(z4, "SwingEndPad", Vector3(-11.5, 1.1, -35.5), Vector3(4.0, 2.2, 3.5), mat_white, mat_coral, 0.12)

	# =========================================================================
	# ZONE 5: Training Basin (ChibiPool)
	# =========================================================================
	var pool := Node3D.new()
	pool.name = "Zone5_SlopedSwimPool"
	pool.set_script(POOL_SCRIPT)
	pool.set("deck_material", mat_floor)
	pool.set("underwater_east_opening", true)
	pool.position = ROOFTOP_POOL_POSITION
	pool.rotation_degrees = Vector3(0.0, 90.0, 0.0) # Approach faces +Z, deep end extends toward -Z
	root.add_child(pool)

	var drop_course := DROP_COURSE_SCENE.instantiate() as Node3D
	drop_course.name = "TowerDropCourse"
	root.add_child(drop_course)

	var tower := CLIMB_TOWER_SCENE.instantiate() as Node3D
	tower.name = "ClimbTower"
	tower.position = CLIMB_TOWER_POSITION
	root.add_child(tower)

	var wind_tunnel := WIND_TUNNEL_SCENE.instantiate() as Node3D
	wind_tunnel.name = "WindTunnel"
	wind_tunnel.position = WIND_TUNNEL_POSITION
	root.add_child(wind_tunnel)

	var wind_launch := WIND_LAUNCH_PERCH_SCENE.instantiate() as Node3D
	wind_launch.position = WIND_LAUNCH_PERCH_POSITION
	root.add_child(wind_launch)

	# 3D Zone Signposts for instant orientation
	_add_zone_sign(root, "Zone 1: Flow, Vaults & Slides", Vector3(2.5, 3.2, 1.5))
	_add_zone_sign(root, "Zone 2: Wall-Run & Beveled Ledges", Vector3(-18.0, 4.8, 0.0))
	_add_zone_sign(root, "Zone 3: Dynamic Climb & Rope Net", Vector3(17.0, 3.6, -4.0))
	_add_zone_sign(root, "Zone 4: Aerial Apparatus", Vector3(2.0, 4.8, -24.5))
	_add_zone_sign(root, "Zone 5: Swim Training Basin", Vector3(24.0, 3.2, -22.0))
	_add_zone_sign(root, "Climb Tower", CLIMB_TOWER_POSITION + Vector3(3.4, 2.1, 3.0))

	# Spawn ChibiRunner at Zone 1 Plaza
	var chibi_scene: PackedScene = load("res://scenes/character/chibi_runner.tscn")
	var chibi := chibi_scene.instantiate() as Node3D
	chibi.name = "ChibiRunner"
	chibi.position = Vector3(0.0, 0.1, 6.0)
	root.add_child(chibi)

	var fall_meter := Node.new()
	fall_meter.name = "TowerFallMeter"
	fall_meter.set_script(TOWER_METER_SCRIPT)
	fall_meter.set("player_path", NodePath("../ChibiRunner"))
	fall_meter.set("launch_marker_path", NodePath("../ClimbTower/LaunchMarker"))
	fall_meter.set("drop_water_path", NodePath("../TowerDropCourse/DropWater"))
	root.add_child(fall_meter)

	_save_scene(root, "res://scenes/gym/rooftop_parkour_gym.tscn")


func _add_deck_section(parent: Node, section_name: String, corner: Vector2, opposite: Vector2, mat: Material) -> void:
	var center := (corner + opposite) * 0.5
	var size := opposite - corner
	_add_box(parent, section_name, Vector3(center.x, -0.5, center.y), Vector3(size.x, 1.0, size.y), mat)


func _add_deck_trapezoid(parent: Node3D, section_name: String, outline: Array[Vector2], mat: Material) -> void:
	var top: Array[Vector3] = []
	var bottom: Array[Vector3] = []
	for point in outline:
		top.append(Vector3(point.x, 0.0, point.y))
		bottom.append(Vector3(point.x, -1.0, point.y))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_mesh_face(surface, top.duplicate(), Vector3.UP)
	_add_mesh_face(surface, bottom.duplicate(), Vector3.DOWN)
	for i in top.size():
		var next := (i + 1) % top.size()
		var normal := Vector3.UP.cross(top[next] - top[i])
		_add_mesh_face(surface, [top[i], top[next], bottom[next], bottom[i]], normal)

	var body := StaticBody3D.new()
	body.name = section_name
	var collision := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array(top + bottom)
	collision.shape = shape
	body.add_child(collision)
	var visual := MeshInstance3D.new()
	visual.mesh = surface.commit()
	visual.material_override = mat
	body.add_child(visual)
	parent.add_child(body)


func _add_deck_around_tunnel(deck: Node3D, first_x: float, well: Rect2, cap_rows: PackedVector3Array, mat: Material) -> void:
	_add_deck_section(deck, "MainDeckEast", Vector2(well.end.x, -47.0), Vector2(47.0, 27.0), mat)
	_add_deck_section(deck, "MainDeckDropNorth", Vector2(well.position.x, -47.0), Vector2(well.end.x, well.position.y), mat)
	_add_deck_section(deck, "MainDeckDropSouth", Vector2(well.position.x, well.end.y), Vector2(well.end.x, 27.0), mat)
	for i in range(cap_rows.size() - 1):
		var a := cap_rows[i]
		var b := cap_rows[i + 1]
		if b.x <= first_x or a.x >= well.position.x:
			continue
		var left := a.lerp(b, clampf(inverse_lerp(a.x, b.x, first_x), 0.0, 1.0))
		var right := a.lerp(b, clampf(inverse_lerp(a.x, b.x, well.position.x), 0.0, 1.0))
		_add_deck_trapezoid(deck, "MainDeckTunnelNorth%d" % i, [
			Vector2(left.x, -47.0), Vector2(right.x, -47.0), Vector2(right.x, right.y), Vector2(left.x, left.y),
		], mat)
		_add_deck_trapezoid(deck, "MainDeckTunnelSouth%d" % i, [
			Vector2(left.x, left.z), Vector2(right.x, right.z), Vector2(right.x, 27.0), Vector2(left.x, 27.0),
		], mat)


func _make_mat(col: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic_specular = 0.25
	return m


func _make_grid_mat(col: Color, line_col: Color, grid_scale: float, rough: float) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/gym_grid.gdshader")
	sm.set_shader_parameter("base_color", col)
	sm.set_shader_parameter("line_color", line_col)
	sm.set_shader_parameter("grid_scale", grid_scale)
	sm.set_shader_parameter("line_width", 0.018)
	sm.set_shader_parameter("roughness_val", rough)
	return sm


func _add_zone_sign(parent: Node, text: String, pos: Vector3) -> void:
	var lbl := Label3D.new()
	lbl.name = "Sign_" + text.left(6).replace(" ", "")
	lbl.text = text
	lbl.position = pos
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 40
	lbl.outline_size = 6
	lbl.modulate = Color("4f4657")
	lbl.outline_modulate = PALETTE.PORCELAIN
	lbl.visibility_range_end = 24.0
	parent.add_child(lbl)


func _add_box(
	parent: Node, box_name: String, pos: Vector3, size: Vector3, mat: Material,
	cap_mat: Material = null, cap_thickness: float = 0.0, cap_axis: int = Vector3.AXIS_Y
) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = box_name
	sb.collision_layer = 1
	sb.position = pos
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var sh := BoxShape3D.new()
	sh.size = size
	col.shape = sh
	sb.add_child(col)
	parent.add_child(sb)

	if cap_mat == null:
		_add_box_visual(sb, "Body", Vector3.ZERO, size, mat, 0.035)
		return sb

	# Split the visual volume along the marked face. The box collider stays continuous.
	var extent := absf(cap_thickness)
	var direction := signf(cap_thickness)
	var body_size := size
	body_size[cap_axis] -= extent
	var body_offset := Vector3.ZERO
	body_offset[cap_axis] = -direction * extent * 0.5
	_add_box_visual(sb, "Body", body_offset, body_size, mat, 0.018)

	var cap_size := size
	cap_size[cap_axis] = extent
	var cap_offset := Vector3.ZERO
	cap_offset[cap_axis] = direction * body_size[cap_axis] * 0.5
	_add_box_visual(sb, "RouteCap", cap_offset, cap_size, cap_mat, 0.016)
	return sb


func _add_ramp(
	parent: Node, ramp_name: String, pos: Vector3, size: Vector3,
	pitch_deg: float, mat: Material, cap_mat: Material
) -> void:
	var ramp := _add_box(parent, ramp_name, pos, size, mat, cap_mat, 0.06)
	ramp.rotation_degrees.x = pitch_deg


func _add_box_visual(parent: Node, mesh_name: String, pos: Vector3, size: Vector3, mat: Material, bevel: float) -> void:
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.position = pos
	mi.mesh = _chamfered_box_mesh(size, bevel)
	mi.material_override = mat
	if size.y < 0.025:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _chamfered_box_mesh(size: Vector3, bevel: float) -> Mesh:
	if bevel == 0.0:
		var box := BoxMesh.new()
		box.size = size
		return box
	var half := size * 0.5
	var inset := half - Vector3.ONE * minf(bevel, minf(half.x, minf(half.y, half.z)) * 0.48)
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in 3:
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for sign_value: float in [-1.0, 1.0]:
			var face_normal := Vector3.ZERO
			face_normal[axis] = sign_value
			var face: Array[Vector3] = []
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var point := Vector3.ZERO
				point[axis] = sign_value * half[axis]
				point[u] = corner.x * inset[u]
				point[v] = corner.y * inset[v]
				face.append(point)
			_add_mesh_face(mesh, face, face_normal)

		for u_sign: float in [-1.0, 1.0]:
			for v_sign: float in [-1.0, 1.0]:
				var a := Vector3.ZERO
				a[axis] = -inset[axis]
				a[u] = u_sign * half[u]
				a[v] = v_sign * inset[v]
				var b := a
				b[u] = u_sign * inset[u]
				b[v] = v_sign * half[v]
				var c := b
				c[axis] = inset[axis]
				var d := a
				d[axis] = inset[axis]
				var edge_normal := Vector3.ZERO
				edge_normal[u] = u_sign
				edge_normal[v] = v_sign
				_add_mesh_face(mesh, [a, b, c, d], edge_normal)

	for x_sign: float in [-1.0, 1.0]:
		for y_sign: float in [-1.0, 1.0]:
			for z_sign: float in [-1.0, 1.0]:
				var corner_sign := Vector3(x_sign, y_sign, z_sign)
				var corner := inset * corner_sign
				var lengths := (half - inset) * corner_sign
				_add_mesh_face(mesh, [
					corner + Vector3(lengths.x, 0, 0),
					corner + Vector3(0, lengths.y, 0),
					corner + Vector3(0, 0, lengths.z),
				], corner_sign)
	mesh.index()
	return mesh.commit()


func _add_mesh_face(mesh: SurfaceTool, points: Array[Vector3], normal: Vector3) -> void:
	var outward := normal.normalized()
	if (points[1] - points[0]).cross(points[2] - points[0]).dot(outward) > 0.0:
		points.reverse() # Godot front faces are clockwise.
	for i in range(1, points.size() - 1):
		for vertex in [points[0], points[i], points[i + 1]]:
			mesh.set_normal(outward)
			mesh.add_vertex(vertex)


func _add_beveled_ledge(
	parent: Node, ledge_name: String, pos: Vector3, size: Vector3, bevel: float,
	mat: Material, cap_mat: Material
) -> void:
	## Builds a static chamfered/beveled block with ConcavePolygonShape3D (trimesh)
	## so ChibiPoseModifier.find_grip_in_space() showcases real per-hand beveled rim sampling!
	var sb := StaticBody3D.new()
	sb.name = ledge_name
	sb.collision_layer = 1
	sb.position = pos

	var hw := size.x * 0.5
	var hd := size.z * 0.5
	var h := size.y
	var b := minf(bevel, minf(hd * 0.45, h * 0.45))

	# 2D cross-section in YZ extruded along X (-hw..+hw)
	var profile: Array[Vector2] = [
		Vector2(-hd, 0.0),
		Vector2(hd, 0.0),
		Vector2(hd, h - b),
		Vector2(hd - b, h),
		Vector2(-hd + b, h),
		Vector2(-hd, h - b),
	]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cap := SurfaceTool.new()
	cap.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := profile.size()
	for i in n:
		var a := profile[i]
		var c := profile[(i + 1) % n]
		var p0 := Vector3(-hw, a.y, a.x)
		var p1 := Vector3(hw, a.y, a.x)
		var p2 := Vector3(hw, c.y, c.x)
		var p3 := Vector3(-hw, c.y, c.x)
		var face := cap if i >= 2 and i <= 4 else st
		# Clockwise front-face winding in Godot so trimesh normals face outward!
		face.add_vertex(p0); face.add_vertex(p2); face.add_vertex(p1)
		face.add_vertex(p0); face.add_vertex(p3); face.add_vertex(p2)
	# End caps (fan from profile centroid)
	var cy := h * 0.5
	for side_x in [-hw, hw]:
		var center := Vector3(side_x, cy, 0.0)
		for i in n:
			var a := profile[i]
			var c := profile[(i + 1) % n]
			var va := Vector3(side_x, a.y, a.x)
			var vc := Vector3(side_x, c.y, c.x)
			if side_x > 0.0:
				st.add_vertex(center); st.add_vertex(va); st.add_vertex(vc)
			else:
				st.add_vertex(center); st.add_vertex(vc); st.add_vertex(va)
	st.generate_normals()
	var arr_mesh := st.commit()
	cap.generate_normals()
	cap.commit(arr_mesh)
	arr_mesh.surface_set_material(0, mat)
	arr_mesh.surface_set_material(1, cap_mat)

	var mi := MeshInstance3D.new()
	mi.mesh = arr_mesh
	sb.add_child(mi)

	var col := CollisionShape3D.new()
	col.shape = arr_mesh.create_trimesh_shape()
	sb.add_child(col)
	parent.add_child(sb)
