class_name ParkourController
extends CharacterBody3D

const ExpressionDirector := preload("res://features/runner/expression_director.gd")

## Full 15-state Parkour controller ported 1:1 from Unreal AC_ParkourComponent,
## orchestrated through Godot State Charts, Phantom Camera, AnimationTree, and ChibiPoseModifier.

const WORLD_MASK := 1 # Layer 1: World
const TRAVERSAL_SOLID_MASK := WORLD_MASK | (1 << 2) # World and Climbable
const TRAVERSAL_CONTACT_SLOP := 0.002
const TRAVERSAL_PATH_SECTIONS := 24
const TOP_STATION_META := &"parkour_top_station"
const JUMP_POSE_DURATION := 0.27
const GROUND_PIVOT_DURATION := 0.18
const MIN_SOFT_LAND_IMPACT_SPEED := 2.1
const LEDGE_DROP_COAST_DURATION := 0.18
const LEDGE_DROP_LATERAL_BRAKE_SCALE := 0.30
const VAULT_PHASES := [0.0, 0.24, 0.42, 0.72, 1.0]
const WallClimbMotion := preload("res://features/runner/climbing/wall_climb_motion.gd")
const WallClimbGeometry := preload("res://features/runner/climbing/wall_climb_geometry.gd")
const RunnerWindField3D := preload("res://features/runner/wind_field_3d.gd")
const PickupItem := preload("res://features/items/pickup_item.gd")
const BALANCE_WALK_SPEED := 1.70
const BALANCE_TURN_SPEED := 10.5
const WIND_MAX_BACKSTEP_SPEED := 0.8
const WIND_TAILWIND_BONUS_RATIO := 0.12
const WIND_IDLE_CARRY_SPEED := 1.45
const WIND_SLIDE_CARRY_SPEED := 2.4
const WIND_SLIDE_MIN_SPEED := 3.5
const WIND_SLIDE_TURN_DURATION := 0.68
const WIND_SLIDE_SPEED_LIMIT := 8.2
const WIND_SCARF_GLIDE_MAX_CARRY_SPEED := 3.0
const WIND_SCARF_GLIDE_CARRY_ACCEL := 15.0
const WIND_SCARF_GLIDE_RELEASE_ACCEL := 4.5
const SCARF_RUNNING_LANDING_MIN_SPEED := 1.0

@export var config: ParkourConfig
@export var state_chart: StateChart
@export var chibi_input: ChibiInput
@export var camera_ctrl: ChibiCameraController
@export var anim_ctrl: ChibiAnimController
@export var pose_mod: ChibiPoseModifier
@export var juice: ChibiJuice
@export var collision_shape: CollisionShape3D
@export var visual_pivot: Node3D
@export var touch_hud: TouchControlsHUD

var current_state: String = "Locomotion"
var current_anim_label: String = "Idle"
var flow_level: float = 0.0
var external_walk_speed_cap: float = 99.0 # Used by ChibiPool wading slowdown
var resolved_planar_speed: float = 0.0
# Read-only by convention: the active field sample and pose response shared with
# ChibiPoseModifier. A scene or station supplies any RunnerWindField3D provider.
var wind_field: RunnerWindField3D
var wind_velocity: Vector3 = Vector3.ZERO
var wind_brace_weight: float = 0.0
var wind_recoil_weight: float = 0.0
var wind_reset_serial: int = 0
var scarf_wind_load: float = 0.0
var scarf_wind_velocity: Vector3 = Vector3.ZERO
var _wind_field_inside: bool = false
var _wind_field_slide_latched: bool = false
var _wind_slide_elapsed: float = 0.0
var _scarf_wind_carry_velocity: Vector3 = Vector3.ZERO
var _scarf_wind_flow_attribution_velocity: Vector3 = Vector3.ZERO
var ground_pivot_weight: float = 0.0
var ground_pivot_side: int = 0
var _ground_pivot_elapsed: float = GROUND_PIVOT_DURATION

# Public scarf telemetry consumed by the character pose and touch HUD.
var scarf_glide_phase: StringName = &"stowed"
var scarf_glide_progress: float = 0.0
var scarf_glide_stow_open: float = 0.0
var scarf_glide_bank: float = 0.0
## True while an opened scarf is wrapping from a dry grounded touchdown.
## It remains latched through an immediate hop so the hand/cloth timeline can finish.
var scarf_glide_touchdown: bool = false
var _scarf_glide_used_this_airtime: bool = false
var _scarf_glide_clearance := BoxShape3D.new()
var _scarf_glide_cancel_action_frame: int = -1

# Core timers & feel buffers
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var air_time: float = 0.0
var peak_fall_speed: float = 0.0
var was_falling: bool = false
var land_anim_timer: float = 0.0
var _air_anim_timer: float = 0.0
var bounce_anim_timer: float = 0.0
var roll_buffer_timer: float = 0.0
var super_bounce_active: bool = false
var super_bounce_grace_timer: float = 0.0
var last_trampoline_velocity: float = 0.0
var last_trampoline_super_mult: float = 1.22
var suppress_auto_roll: bool = false

# Cooldowns
var ledge_grab_cooldown: float = 0.0
var wall_run_cooldown: float = 0.0
var corner_turn_cooldown: float = 0.0
var trampoline_cooldown: float = 0.0
var pole_cooldown: float = 0.0
var beam_cooldown: float = 0.0
var line_cooldown: float = 0.0
var swing_cooldown: float = 0.0

# SpeedVault state
var _vault_alpha: float = 0.0
var _vault_duration: float = 0.80
var _vault_points := PackedVector3Array()
var _vault_exit_velocity := Vector3.ZERO

# Ledge / Shimmy / Corner / Mantle state
var ledge_edge_point: Vector3 = Vector3.ZERO
var ledge_wall_normal: Vector3 = Vector3.FORWARD
var ledge_hang_time: float = 0.0
var mantle_alpha: float = 0.0
var _mantle_duration: float = 0.88
var _mantle_start: Vector3 = Vector3.ZERO
var _mantle_hang: Vector3 = Vector3.ZERO
var _mantle_lift: Vector3 = Vector3.ZERO
var _mantle_end: Vector3 = Vector3.ZERO
var shimmy_phase: float = 0.0
var shimmy_start_edge: Vector3 = Vector3.ZERO
var shimmy_end_edge: Vector3 = Vector3.ZERO
var _ledge_travel_velocity := Vector3.ZERO
var _ledge_drop_coast_axis := Vector3.ZERO
var _ledge_drop_coast_time := 0.0
var _corner_alpha: float = 0.0
var _corner_start_pos: Vector3 = Vector3.ZERO
var _corner_ctrl_pos: Vector3 = Vector3.ZERO
var _corner_end_pos: Vector3 = Vector3.ZERO
var _corner_start_yaw: float = 0.0
var _corner_end_yaw: float = 0.0
var _corner_new_edge: Vector3 = Vector3.ZERO
var _corner_new_normal: Vector3 = Vector3.FORWARD

# WallRun state
var _wall_run_entry_armed: bool = false
var _wall_run_timer: float = 0.0
var _wall_run_side: float = 1.0
var _wall_run_normal: Vector3 = Vector3.RIGHT
var _wall_run_dir: Vector3 = Vector3.FORWARD

# Slide & LandRoll state
var _slide_timer: float = 0.0
var _slide_dir: Vector3 = Vector3.FORWARD
var _slide_speed: float = 0.0
var _slide_dive_time: float = 0.0
var _standing_clearance := CapsuleShape3D.new()
var _traversal_capsule := CapsuleShape3D.new()
var _roll_timer: float = 0.0
var _roll_dir: Vector3 = Vector3.FORWARD

# Interactive states
var _pole_top_pos: Vector3 = Vector3.ZERO
var _pole_hold_time: float = 0.0
var _pole_hop_start: Vector3 = Vector3.ZERO
var _pole_hop_end: Vector3 = Vector3.ZERO
var _pole_hop_alpha: float = 0.0
var _pole_hop_duration: float = 0.48
var _pole_hop_arc: float = 0.65

var _beam: ParkourBalanceBeam
var _beam_footing := preload("res://features/runner/balance_footing.gd").new()
var _beam_progress: float = 0.0
var _beam_direction := 1.0

var _active_line: Node3D = null
var _line_distance: float = 0.0
var _line_length: float = 9.0
var _line_is_zip: bool = false
var _line_facing_sign: float = 1.0
var _line_time: float = 0.0
var _rope_climb_sfx_timer: float = 0.0
var _zip_speed: float = 4.0
var _zip_min: float = 3.8
var _zip_max: float = 7.4

var _active_swing: Node3D = null
var _swing_anchor: Vector3 = Vector3.ZERO
var _swing_length: float = 2.4
var _swing_plane_fwd: Vector3 = Vector3.FORWARD
var _swing_angle: float = 0.0
var _swing_ang_vel: float = 0.0
var _swing_max_angle: float = deg_to_rad(56.0)
var _swing_pump_accel: float = 3.4
var _swing_launch_boost_up: float = 2.6
var _swing_time: float = 0.0

# External controllers (Water / Climbing)
var _active_water_body: WaterBody3D = null
var _swim_controller := ChibiSwimController.new()
var _wall_climb := WallClimbMotion.new()
var _wall_climb_rig: ChibiPoseModifier
var _wall_climb_cooldown := 0.0
var _wall_climb_probe_timer := 0.0
var _air_wall_approach := Vector3.ZERO
var _wall_jump_buffer := 0.0
var _wall_jump_direction := Vector2.ZERO
var _wall_upward_leap := false
var _wall_mantle_active := false
var _pool_surface_y: float = 0.0
var _pool_underwater_weight: float = 0.0
var _swim_recovery_time := 0.0
var _swim_exit_pose := Transform3D.IDENTITY

var _visual_rest_transform: Transform3D = Transform3D.IDENTITY


var expression_director: ExpressionDirector


func _ready() -> void:
	expression_director = ExpressionDirector.new()
	expression_director.name = "ExpressionDirector"
	add_child(expression_director)
	_swim_controller.setup(self)
	if config == null:
		config = ParkourConfig.new()
	floor_max_angle = deg_to_rad(config.walkable_floor_angle_deg)
	floor_snap_length = 0.16
	var capsule := collision_shape.shape as CapsuleShape3D if collision_shape != null else null
	_standing_clearance.radius = capsule.radius if capsule != null else config.capsule_radius
	_standing_clearance.height = config.capsule_height
	if visual_pivot != null:
		_visual_rest_transform = visual_pivot.transform
	if pose_mod != null:
		pose_mod.runner_body = self
	if anim_ctrl != null and juice != null:
		anim_ctrl.ground_foot_contact.connect(juice.play_ground_footstep)
	if touch_hud != null and state_chart != null:
		touch_hud.bind_state_chart(state_chart)


func get_capsule_center() -> Vector3:
	return global_position + Vector3(0.0, _current_half_height(), 0.0)


func _current_half_height() -> float:
	if collision_shape != null and collision_shape.shape is CapsuleShape3D:
		return (collision_shape.shape as CapsuleShape3D).height * 0.5
	return config.capsule_height * 0.5


func _set_capsule_slide(sliding: bool) -> void:
	if collision_shape == null or not (collision_shape.shape is CapsuleShape3D):
		return
	var cap := collision_shape.shape as CapsuleShape3D
	var target_h := config.slide_capsule_height if sliding else config.capsule_height
	cap.height = target_h
	collision_shape.position.y = target_h * 0.5


func _set_world_collision(enabled: bool) -> void:
	set_collision_mask_value(1, enabled)


func traversal_segment_clear(from_feet: Vector3, to_feet: Vector3) -> bool:
	if collision_shape == null or not collision_shape.shape is CapsuleShape3D:
		return false
	var active := collision_shape.shape as CapsuleShape3D
	# Keep touching a floor or perch legal within the solver's contact tolerance.
	_traversal_capsule.radius = active.radius - TRAVERSAL_CONTACT_SLOP
	_traversal_capsule.height = active.height - TRAVERSAL_CONTACT_SLOP * 2.0
	var offset := collision_shape.global_position - global_position
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _traversal_capsule
	query.transform = Transform3D(collision_shape.global_basis, from_feet + offset)
	query.collision_mask = TRAVERSAL_SOLID_MASK
	query.exclude = [get_rid()]
	var space := get_world_3d().direct_space_state
	var motion := to_feet - from_feet
	if motion.length_squared() > 0.00000001:
		if not space.intersect_shape(query, 1).is_empty():
			return false
		query.motion = motion
		var travel := space.cast_motion(query)
		if travel.size() != 2 or travel[0] < 0.999:
			return false
		query.motion = Vector3.ZERO
	query.transform = Transform3D(query.transform.basis, to_feet + offset)
	return space.intersect_shape(query, 1).is_empty()


func try_move_traversal(target_feet: Vector3) -> bool:
	if not traversal_segment_clear(global_position, target_feet):
		return false
	global_position = target_feet
	return true


func _traversal_path_clear(path: Callable) -> bool:
	var previous := global_position
	for step in range(1, TRAVERSAL_PATH_SECTIONS + 1):
		var target: Vector3 = path.call(float(step) / TRAVERSAL_PATH_SECTIONS)
		if not traversal_segment_clear(previous, target):
			return false
		previous = target
	return true


func _has_dedicated_traversal(collider: Object) -> bool:
	return collider.has_meta(TOP_STATION_META) or WallClimbGeometry.owns_collider(collider)


func add_flow_boost(amount: float) -> void:
	var prev := flow_level
	flow_level = clampf(flow_level + amount, 0.0, 1.0)
	if camera_ctrl != null:
		camera_ctrl.pop_fov(clampf(amount * 14.0, 0.8, 3.0))
	if juice != null and prev < 0.7 and flow_level >= 0.7:
		juice.play_sfx("FlowChime", 0.03)
		juice.spawn_flow_sparkle(get_capsule_center())


func transition_to(new_state: String) -> void:
	if current_state == new_state:
		return
	_wall_run_entry_armed = false
	if current_state == "Locomotion" and new_state != "Locomotion":
		_ledge_drop_coast_time = 0.0
		# Keep the velocity already imparted by the gust, but do not carry its
		# Flow bookkeeping into an unrelated movement state.
		_scarf_wind_flow_attribution_velocity = Vector3.ZERO
		_scarf_wind_carry_velocity = Vector3.ZERO
	elif current_state != "Locomotion" and new_state == "Locomotion":
		_scarf_wind_carry_velocity = Vector3.ZERO
		_scarf_wind_flow_attribution_velocity = Vector3.ZERO
	if new_state == "PoolSwim":
		_clear_scarf_glide_phase()
	elif new_state != "Locomotion":
		_stow_scarf_glide()
		scarf_glide_touchdown = false
	# Cleanup previous state visuals/collision
	if current_state == "Slide":
		_wind_field_slide_latched = false
		_wind_slide_elapsed = 0.0
		_set_capsule_slide(false)
		if pose_mod != null:
			pose_mod.slide_dive_active = false
	elif current_state == "WallRun" and camera_ctrl != null:
		camera_ctrl.target_roll_deg = 0.0
	elif current_state == "RopeSwing" and visual_pivot != null:
		visual_pivot.transform = _visual_rest_transform
	elif current_state == "BalanceBeam":
		_beam = null
	if current_state == "Climbing" and is_wall_climbing():
		_clear_wall_climb(_wall_mantle_active)
	if current_state == "MantleUp" and _wall_mantle_active:
		_wall_mantle_active = false
		if camera_ctrl != null:
			camera_ctrl.set_climbing_camera(false)

	if _swim_recovery_time > 0.0 and new_state != "Locomotion":
		_swim_recovery_time = 0.0
		visual_pivot.transform = _visual_rest_transform
	current_state = new_state
	if new_state != "Locomotion":
		land_anim_timer = 0.0
		_air_anim_timer = 0.0
		_clear_ground_pivot()
	if state_chart != null:
		state_chart.send_event("to_" + new_state.to_snake_case())


func reset_for_respawn(spawn_position: Vector3) -> void:
	if expression_director != null:
		expression_director.clear_requests()
	wind_reset_serial += 1
	wind_velocity = Vector3.ZERO
	wind_brace_weight = 0.0
	wind_recoil_weight = 0.0
	scarf_wind_load = 0.0
	scarf_wind_velocity = Vector3.ZERO
	_scarf_wind_carry_velocity = Vector3.ZERO
	_scarf_wind_flow_attribution_velocity = Vector3.ZERO
	_wind_field_inside = false
	_wind_field_slide_latched = false
	_wind_slide_elapsed = 0.0
	_swim_controller.reset_for_respawn()
	_swim_recovery_time = 0.0
	if pose_mod != null:
		pose_mod.reset_wade_pose()
		pose_mod.reset_swim_pose()
	if is_instance_valid(_active_line):
		_active_line.call("notify_rider_release")
	if is_instance_valid(_active_swing):
		_active_swing.call("set_ridden", false)
	_active_line = null
	_active_swing = null
	_active_water_body = null
	transition_to("Locomotion")
	_set_world_collision(true)
	_set_capsule_slide(false)
	velocity = Vector3.ZERO
	resolved_planar_speed = 0.0
	_clear_ground_pivot()
	flow_level = 0.0
	external_walk_speed_cap = 99.0
	_pool_surface_y = 0.0
	_pool_underwater_weight = 0.0
	air_time = 0.0
	peak_fall_speed = 0.0
	was_falling = false
	suppress_auto_roll = false
	coyote_timer = 0.0
	jump_buffer_timer = 0.0
	scarf_glide_phase = &"stowed"
	scarf_glide_progress = 0.0
	scarf_glide_stow_open = 0.0
	scarf_glide_bank = 0.0
	scarf_glide_touchdown = false
	_scarf_glide_used_this_airtime = false
	_scarf_glide_cancel_action_frame = -1
	roll_buffer_timer = 0.0
	_air_anim_timer = 0.0
	land_anim_timer = 0.0
	bounce_anim_timer = 0.0
	super_bounce_grace_timer = 0.0
	super_bounce_active = false
	ledge_grab_cooldown = 0.0
	_ledge_travel_velocity = Vector3.ZERO
	_ledge_drop_coast_time = 0.0
	_wall_climb_cooldown = 0.0
	_wall_climb_probe_timer = 0.0
	_air_wall_approach = Vector3.ZERO
	wall_run_cooldown = 0.0
	_wall_run_entry_armed = false
	corner_turn_cooldown = 0.0
	trampoline_cooldown = 0.0
	pole_cooldown = 0.0
	beam_cooldown = 0.0
	line_cooldown = 0.0
	swing_cooldown = 0.0
	current_anim_label = "Idle"
	if pose_mod != null:
		pose_mod.clear_wall_climb_pose(true)
		pose_mod.slide_dive_active = false
		pose_mod.reset_ground_contacts()
		_sync_pose_modifier(0.0)
	if juice != null:
		juice.trigger_squash(1.0, 1.0)
		juice.clear_wind_trail()
	if visual_pivot != null:
		visual_pivot.transform = _visual_rest_transform
	if anim_ctrl != null:
		anim_ctrl.reset_for_respawn()
	global_position = spawn_position
	reset_physics_interpolation()
	if touch_hud != null:
		touch_hud.set_pickup_available(false)


func _physics_process(delta: float) -> void:
	if chibi_input != null:
		chibi_input.poll(delta)
	if camera_ctrl != null and chibi_input != null:
		camera_ctrl.apply_look(chibi_input.look_delta)
	_swim_controller.prepare_physics()
	_sample_wind_field()

	_tick_cooldowns(delta)
	_handle_global_actions()
	_advance_scarf_glide(delta)

	match current_state:
		"Locomotion":
			_update_locomotion(delta)
		"SpeedVault":
			_update_speed_vault(delta)
		"LedgeHang":
			_update_ledge_hang(delta)
		"LedgeShimmy":
			_update_ledge_shimmy(delta)
		"LedgeCorner":
			_update_ledge_corner(delta)
		"MantleUp":
			_update_mantle(delta)
		"WallRun":
			_update_wall_run(delta)
		"Slide":
			_update_slide(delta)
		"LandRoll":
			_update_land_roll(delta)
		"PolePerch":
			_update_pole_perch(delta)
		"PoleHop":
			_update_pole_hop(delta)
		"BalanceBeam":
			_update_balance_beam(delta)
		"RopeLine":
			_update_rope_line(delta)
		"ZipLine":
			_update_zip_line(delta)
		"RopeSwing":
			_update_rope_swing(delta)
		"PoolSwim":
			_swim_controller.swim_physics(delta)
		"Climbing":
			if is_wall_climbing():
				_update_wall_climb(delta)

	var attribution_decel := 0.0
	if not _is_scarf_wind_glide_active():
		attribution_decel = maxf(config.air_decel, 0.0)
		if is_on_floor():
			attribution_decel = maxf(config.ground_decel, 0.0)
	elif not _wind_field_inside:
		# Outside the field the carry becomes normal glide momentum. Let the usual
		# steering/coast rates dissolve its Flow attribution instead of braking it.
		var opening := _scarf_glide_open_amount()
		attribution_decel = config.scarf_glide_coast_decel * maxf(opening, 0.10)
		if chibi_input != null and chibi_input.move_vec.length_squared() > 0.0001:
			attribution_decel = config.scarf_glide_steer_accel * opening
	if attribution_decel > 0.0:
		_scarf_wind_carry_velocity = _scarf_wind_carry_velocity.move_toward(
			Vector3.ZERO, attribution_decel * delta
		)
		_scarf_wind_flow_attribution_velocity = _scarf_wind_flow_attribution_velocity.move_toward(
			Vector3.ZERO, attribution_decel * delta
		)

	_swim_controller.finish_physics(delta)
	_update_swim_recovery(delta)
	_sample_wind_field()
	_sync_pose_modifier(delta)

	var planar_speed := resolved_planar_speed if current_state == "Locomotion" else Vector2(velocity.x, velocity.z).length()
	if camera_ctrl != null:
		camera_ctrl.update_camera(delta, flow_level, velocity.y, _pool_surface_y, _pool_underwater_weight)
	if juice != null:
		juice.update_juice(delta, current_state, current_anim_label, flow_level, planar_speed, super_bounce_active, bounce_anim_timer)
	if touch_hud != null:
		touch_hud.update_hud(
			current_state, flow_level, planar_speed, is_wall_climbing(), can_deploy_scarf(),
			scarf_glide_phase in [&"deploy", &"glide"]
		)
		touch_hud.set_pickup_available(_nearest_pickup() != null)


func _tick_cooldowns(delta: float) -> void:
	ledge_grab_cooldown = maxf(0.0, ledge_grab_cooldown - delta)
	_ledge_drop_coast_time = maxf(0.0, _ledge_drop_coast_time - delta)
	_wall_climb_cooldown = maxf(0.0, _wall_climb_cooldown - delta)
	_wall_climb_probe_timer = maxf(0.0, _wall_climb_probe_timer - delta)
	_wall_jump_buffer = maxf(0.0, _wall_jump_buffer - delta)
	wall_run_cooldown = maxf(0.0, wall_run_cooldown - delta)
	corner_turn_cooldown = maxf(0.0, corner_turn_cooldown - delta)
	_air_anim_timer = maxf(0.0, _air_anim_timer - delta)
	roll_buffer_timer = maxf(0.0, roll_buffer_timer - delta)
	trampoline_cooldown = maxf(0.0, trampoline_cooldown - delta)
	bounce_anim_timer = maxf(0.0, bounce_anim_timer - delta)
	pole_cooldown = maxf(0.0, pole_cooldown - delta)
	beam_cooldown = maxf(0.0, beam_cooldown - delta)
	line_cooldown = maxf(0.0, line_cooldown - delta)
	swing_cooldown = maxf(0.0, swing_cooldown - delta)
	super_bounce_grace_timer = maxf(0.0, super_bounce_grace_timer - delta)
	land_anim_timer = maxf(0.0, land_anim_timer - delta)


func _sample_wind_field() -> void:
	var sample_position := get_capsule_center()
	var field := wind_field if is_instance_valid(wind_field) else null
	var inside := field != null and field.contains_point(sample_position)
	_wind_field_inside = inside
	if inside:
		wind_velocity = field.flow_velocity_at(sample_position)
		wind_velocity.y = 0.0
		if current_state == "Slide" and not _wind_field_slide_latched:
			_wind_field_slide_latched = true
			_wind_slide_elapsed = 0.0
	else:
		wind_velocity = Vector3.ZERO
		if _wind_field_slide_latched:
			_wind_field_slide_latched = false
			_wind_slide_elapsed = 0.0
			if current_state == "Slide":
				_try_end_slide()
	_update_scarf_wind_readouts()
	_update_wind_pose_weights()


func _is_scarf_wind_glide_active() -> bool:
	return current_state == "Locomotion" and not is_on_floor() \
		and scarf_glide_phase in [&"deploy", &"glide"]


func _update_scarf_wind_readouts() -> void:
	scarf_wind_load = 0.0
	scarf_wind_velocity = Vector3.ZERO
	if not _is_scarf_wind_glide_active():
		return
	var opening := _scarf_glide_open_amount()
	if opening <= 0.0:
		return
	scarf_wind_load = _wind_gust_weight() * opening
	scarf_wind_velocity = wind_velocity * opening


func _wind_flow_direction() -> Vector3:
	if not is_instance_valid(wind_field):
		return Vector3.ZERO
	var direction := wind_field.get_flow_direction()
	direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 1e-5 else Vector3.ZERO


func _wind_gust_weight() -> float:
	if not _wind_field_inside or not is_instance_valid(wind_field):
		return 0.0
	# Lull flow remains gameplay-relevant: it braces and slows an upwind walk,
	# while the peak still brings a full push to the specified 0.8 m/s backstep.
	return clampf(wind_velocity.length() / maxf(wind_field.get_reference_speed(), 0.001), 0.0, 1.0)


func _update_wind_pose_weights() -> void:
	wind_brace_weight = 0.0
	wind_recoil_weight = 0.0
	if not _wind_field_inside or current_state != "Locomotion" or not is_on_floor() \
		or chibi_input == null:
		return
	var gust_weight := _wind_gust_weight()
	if gust_weight <= 0.001:
		return
	var flow_direction := _wind_flow_direction()
	if flow_direction.is_zero_approx():
		return
	var move_in := chibi_input.move_vec
	var camera_forward := camera_ctrl.get_forward_xz() if camera_ctrl != null else -global_transform.basis.z
	var camera_right := camera_ctrl.get_right_xz() if camera_ctrl != null else global_transform.basis.x
	var wish := camera_right * move_in.x - camera_forward * move_in.y
	var input_strength := minf(wish.length(), 1.0)
	if input_strength <= 0.01:
		return
	var move_direction := wish.normalized()
	var headwind_alignment := clampf(-move_direction.dot(flow_direction), 0.0, 1.0)
	if headwind_alignment <= 0.001:
		return
	wind_brace_weight = gust_weight * headwind_alignment * input_strength
	var requested_speed := minf(
		lerpf(config.base_run_speed, config.max_flow_speed, flow_level),
		external_walk_speed_cap
	) * input_strength
	var actual_planar := Vector3(get_real_velocity().x, 0.0, get_real_velocity().z)
	var actual_progress := actual_planar.dot(move_direction)
	var progress_loss := clampf(
		(requested_speed - actual_progress) / maxf(requested_speed + WIND_MAX_BACKSTEP_SPEED, 0.01),
		0.0,
		1.0
	)
	wind_recoil_weight = wind_brace_weight * progress_loss


func _wind_tailwind_bonus(max_speed: float, heading_alignment: float, input_strength: float) -> float:
	return max_speed * WIND_TAILWIND_BONUS_RATIO * _wind_gust_weight() \
		* clampf(heading_alignment, 0.0, 1.0) * clampf(input_strength, 0.0, 1.0)


func _wind_adjusted_flow_speed(actual_planar_speed: float, actual_velocity: Vector3, wish: Vector3) -> float:
	var player_velocity := actual_velocity - _scarf_wind_flow_attribution_velocity
	var player_planar_speed := Vector2(player_velocity.x, player_velocity.z).length()
	if not _wind_field_inside or not is_on_floor():
		return player_planar_speed
	var gust_weight := _wind_gust_weight()
	if gust_weight <= 0.001:
		return player_planar_speed
	var flow_direction := _wind_flow_direction()
	if flow_direction.is_zero_approx():
		return player_planar_speed
	var planar_velocity := Vector3(player_velocity.x, 0.0, player_velocity.z)
	var input_strength := minf(wish.length(), 1.0)
	var assistance_speed := 0.0
	if input_strength <= 0.01:
		assistance_speed = minf(
			WIND_IDLE_CARRY_SPEED * gust_weight,
			maxf(planar_velocity.dot(flow_direction), 0.0)
		)
	else:
		var alignment := wish.normalized().dot(flow_direction)
		var max_speed := minf(
			lerpf(config.base_run_speed, config.max_flow_speed, flow_level),
			external_walk_speed_cap
		)
		if alignment > 0.0:
			assistance_speed = _wind_tailwind_bonus(max_speed, alignment, input_strength)
		elif alignment < 0.0:
			var headwind_push := (max_speed + WIND_MAX_BACKSTEP_SPEED) * gust_weight \
				* -alignment * input_strength
			assistance_speed = minf(maxf(planar_velocity.dot(flow_direction), 0.0), headwind_push)
	return maxf(0.0, player_planar_speed - assistance_speed)


func _handle_global_actions() -> void:
	if chibi_input == null:
		return
	if chibi_input.pickup_just_pressed:
		var pickup := _nearest_pickup()
		if pickup != null:
			pickup.take(self)
	if chibi_input.jump_just_pressed:
		request_jump()
	if chibi_input.slide_just_pressed:
		request_slide_or_roll()
	if chibi_input.slide_just_released and current_state == "Slide" and not _wind_field_slide_latched:
		_try_end_slide()


func _nearest_pickup() -> PickupItem:
	var origin := get_capsule_center()
	var nearest: PickupItem = null
	var nearest_distance := INF
	for node in get_tree().get_nodes_in_group(PickupItem.GROUP):
		var item := node as PickupItem
		if item == null:
			continue
		var distance := origin.distance_squared_to(item.global_position)
		if distance < nearest_distance and item.is_reachable(self, origin):
			nearest_distance = distance
			nearest = item
	return nearest


func request_jump() -> void:
	# Super-bounce grace window right after trampoline hit
	if super_bounce_grace_timer > 0.0 and not super_bounce_active:
		super_bounce_active = true
		super_bounce_grace_timer = 0.0
		velocity.y = last_trampoline_velocity * last_trampoline_super_mult
		bounce_anim_timer = 0.75
		add_flow_boost(0.18)
		if juice:
			juice.trigger_squash(0.84, 1.24)
			juice.play_sfx("Whee")
			juice.spawn_super_bounce_wind(global_position)
		return
	if _consume_scarf_glide_cancel_action():
		return

	match current_state:
		"Locomotion":
			if is_on_floor() or coyote_timer > 0.0:
				_execute_ground_jump()
			elif can_deploy_scarf():
				_start_scarf_deploy()
			else:
				jump_buffer_timer = config.jump_buffer_duration
		"Slide":
			if _has_headroom():
				transition_to("Locomotion")
				_execute_ground_jump()
		"WallRun":
			_start_wall_kick()
		"LedgeHang":
			start_ledge_mantle()
		"PolePerch":
			_jump_or_hop_off_pole()
		"BalanceBeam":
			_jump_off_beam()
		"RopeLine":
			_jump_off_rope_line()
		"ZipLine":
			_jump_off_zip_line()
		"RopeSwing":
			_jump_off_rope_swing()
		"Climbing":
			if is_wall_climbing():
				_request_wall_climb_jump()


func request_slide_or_roll() -> void:
	if _consume_scarf_glide_cancel_action():
		return
	match current_state:
		"Locomotion":
			if is_on_floor():
				var planar := Vector2(velocity.x, velocity.z).length()
				if planar >= config.slide_min_speed:
					_start_slide()
			else:
				roll_buffer_timer = config.roll_buffer_window
		"LedgeHang", "LedgeShimmy", "LedgeCorner":
			var outward := global_basis.z.normalized() if current_state == "LedgeCorner" else ledge_wall_normal
			var carry := _ledge_travel_velocity.slide(outward)
			_ledge_drop_coast_axis = carry.normalized()
			_ledge_drop_coast_time = LEDGE_DROP_COAST_DURATION if not carry.is_zero_approx() else 0.0
			_drop_ledge_traversal(carry + outward * 1.4 + Vector3.DOWN * 1.2)
		"RopeLine", "ZipLine":
			_drop_from_parkour_line()
		"Climbing":
			if is_wall_climbing():
				_drop_from_wall(_wall_climb.frame.z * 1.05 + Vector3.DOWN * 0.5)


func _execute_ground_jump() -> void:
	_air_wall_approach = -global_basis.z
	_wall_run_entry_armed = Vector2(velocity.x, velocity.z).length() >= config.wall_run_entry_min_speed
	jump_buffer_timer = 0.0
	coyote_timer = 0.0
	if anim_ctrl != null:
		anim_ctrl.end_running_landing()
	velocity.y = config.jump_velocity
	_clear_ground_pivot()
	add_flow_boost(0.05)
	if juice:
		juice.trigger_squash(0.91, 1.13)
		juice.play_sfx("Jump")
		juice.spawn_dust(global_position)
	var rise_duration := clampf(config.jump_velocity / maxf(config.gravity, 0.001), 0.12, 0.45)
	_start_air_animation("JumpStart", rise_duration, 0.62)


## Read-only eligibility check shared by Jump input and the touch HUD.
func can_deploy_scarf() -> bool:
	if not is_inside_tree() or config == null or current_state != "Locomotion":
		return false
	if is_on_floor() or coyote_timer > 0.0 or _scarf_glide_used_this_airtime:
		return false
	if scarf_glide_phase != &"stowed" or velocity.y >= 0.0:
		return false
	if _swim_recovery_time > 0.0:
		return false
	if pose_mod != null and is_instance_valid(pose_mod.dive_gear) and pose_mod.dive_gear.gesture_weight > 0.001:
		return false
	var space := get_world_3d().direct_space_state
	var floor_clearance := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.04,
		global_position - Vector3.UP * config.scarf_glide_floor_buffer,
		WORLD_MASK,
		[get_rid()]
	)
	if not space.intersect_ray(floor_clearance).is_empty():
		return false
	var capsule_height := _current_half_height() * 2.0
	# Allow the cloth to pass over both hands and inflate above the capsule.
	var clearance_size := Vector3(1.9, maxf(config.scarf_glide_headroom, 0.01), 1.30)
	if _scarf_glide_clearance.size != clearance_size:
		_scarf_glide_clearance.size = clearance_size
	var overhead_clearance := PhysicsShapeQueryParameters3D.new()
	overhead_clearance.shape = _scarf_glide_clearance
	overhead_clearance.transform = Transform3D(
		global_basis.orthonormalized(), global_position + Vector3.UP * (capsule_height + clearance_size.y * 0.5)
	)
	overhead_clearance.collision_mask = WORLD_MASK
	overhead_clearance.exclude = [get_rid()]
	return space.intersect_shape(overhead_clearance, 1).is_empty()


func _start_scarf_deploy() -> void:
	_wall_run_entry_armed = false
	_scarf_glide_used_this_airtime = true
	scarf_glide_phase = &"deploy"
	scarf_glide_progress = 0.0
	scarf_glide_stow_open = 0.0


func _consume_scarf_glide_cancel_action() -> bool:
	var physics_frame := Engine.get_physics_frames()
	if _scarf_glide_cancel_action_frame == physics_frame:
		return true
	if current_state != "Locomotion" or is_on_floor():
		return false
	if scarf_glide_phase not in [&"deploy", &"glide"]:
		return false

	if scarf_glide_phase == &"deploy":
		scarf_glide_stow_open = clampf(scarf_glide_progress, 0.0, 1.0)
	else:
		scarf_glide_stow_open = 1.0
	scarf_glide_phase = &"cancel"
	scarf_glide_progress = 0.0
	_scarf_glide_cancel_action_frame = physics_frame
	return true


func _stow_scarf_glide() -> void:
	if scarf_glide_phase == &"deploy":
		scarf_glide_stow_open = clampf(scarf_glide_progress, 0.0, 1.0)
	elif scarf_glide_phase == &"glide":
		scarf_glide_stow_open = 1.0
	else:
		return
	scarf_glide_phase = &"stow"
	scarf_glide_progress = 0.0


func _clear_scarf_glide_phase(preserve_stow_open: bool = false, reset_used: bool = false) -> void:
	if preserve_stow_open and scarf_glide_phase == &"deploy":
		scarf_glide_stow_open = clampf(scarf_glide_progress, 0.0, 1.0)
	elif preserve_stow_open and scarf_glide_phase == &"glide":
		scarf_glide_stow_open = 1.0
	elif preserve_stow_open and scarf_glide_phase == &"cancel":
		scarf_glide_stow_open = 0.0
	elif not preserve_stow_open:
		scarf_glide_stow_open = 0.0
	scarf_glide_phase = &"stowed"
	scarf_glide_progress = 0.0
	scarf_glide_bank = 0.0
	scarf_glide_touchdown = false
	if reset_used:
		_scarf_glide_used_this_airtime = false


func _advance_scarf_glide(delta: float) -> void:
	if current_state != "Locomotion" and scarf_glide_phase in [&"deploy", &"glide"]:
		_stow_scarf_glide()
	match scarf_glide_phase:
		&"deploy":
			scarf_glide_progress = minf(
				scarf_glide_progress + delta / maxf(config.scarf_glide_deploy_duration, 0.001), 1.0
			)
			if scarf_glide_progress >= 1.0:
				scarf_glide_phase = &"glide"
				scarf_glide_progress = 1.0
		&"glide":
			scarf_glide_progress = 1.0
		&"stow":
			scarf_glide_progress = minf(
				scarf_glide_progress + delta / maxf(config.scarf_glide_stow_duration, 0.001), 1.0
			)
			if scarf_glide_progress >= 1.0:
				scarf_glide_phase = &"stowed"
				scarf_glide_progress = 0.0
				scarf_glide_touchdown = false
		&"cancel":
			scarf_glide_progress = minf(
				scarf_glide_progress + delta / maxf(config.scarf_glide_cancel_duration, 0.001), 1.0
			)
			if scarf_glide_progress >= 1.0:
				scarf_glide_phase = &"stowed"
				scarf_glide_progress = 0.0
				scarf_glide_stow_open = 0.0
	if current_state != "Locomotion" or scarf_glide_phase in [&"stowed", &"stow", &"cancel"]:
		_update_scarf_bank(0.0, delta, 0.0)


func _scarf_glide_open_amount() -> float:
	if scarf_glide_phase == &"glide":
		return 1.0
	if scarf_glide_phase == &"deploy":
		return clampf(scarf_glide_progress, 0.0, 1.0)
	return 0.0


func _update_scarf_bank(lateral_input: float, delta: float, glide_open: float) -> void:
	var target := clampf(lateral_input, -1.0, 1.0) * clampf(glide_open, 0.0, 1.0)
	var response := maxf(config.scarf_glide_bank_response, 0.0)
	scarf_glide_bank = clampf(
		lerpf(scarf_glide_bank, target, 1.0 - exp(-response * delta)), -1.0, 1.0
	)


# ---------------------------------------------------------------------------
# LOCOMOTION
# ---------------------------------------------------------------------------
func _update_locomotion(delta: float) -> void:
	var on_floor := is_on_floor()
	var move_in := chibi_input.move_vec if chibi_input else Vector2.ZERO
	var cam_fwd := camera_ctrl.get_forward_xz() if camera_ctrl else -global_transform.basis.z
	var cam_right := camera_ctrl.get_right_xz() if camera_ctrl else global_transform.basis.x
	var wish := cam_right * move_in.x - cam_fwd * move_in.y
	var has_move_input := wish.length_squared() > 1e-4

	var max_speed := minf(lerpf(config.base_run_speed, config.max_flow_speed, flow_level), external_walk_speed_cap)
	var prior_horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var horiz := prior_horizontal
	var scarf_glide_control_velocity := Vector3.ZERO
	var scarf_wind_carry_requested := Vector3.ZERO
	var scarf_wind_carry_direction := Vector3.ZERO
	var glide_open := _scarf_glide_open_amount()
	if on_floor:
		_scarf_wind_carry_velocity = Vector3.ZERO
		if _wind_field_inside and _wind_gust_weight() > 0.001:
			horiz = _steer_ground_with_wind(horiz, wish, max_speed, delta)
		else:
			horiz = _steer_ground(horiz, wish, max_speed, delta)
		if glide_open > 0.0:
			_update_scarf_bank(0.0, delta, 0.0)
	else:
		if glide_open > 0.0:
			var inside_wind_field := _wind_field_inside
			if inside_wind_field:
				# Separate the previous wind contribution before the normal
				# camera-relative control step, preserving full steer authority.
				horiz -= _scarf_wind_carry_velocity
			var terminal_speed := maxf(config.scarf_glide_terminal_speed, 0.01)
			var fall_ratio := clampf(maxf(-velocity.y, 0.0) / terminal_speed, 0.0, config.scarf_glide_max_drag_ratio)
			velocity.y -= config.gravity * delta
			velocity.y += config.gravity * fall_ratio * glide_open * delta
			if has_move_input:
				var input_strength := minf(wish.length(), 1.0)
				var target_v := wish.normalized() * config.scarf_glide_steer_speed * input_strength
				horiz = horiz.move_toward(target_v, config.scarf_glide_steer_accel * glide_open * delta)
			else:
				horiz = horiz.move_toward(Vector3.ZERO, config.scarf_glide_coast_decel * maxf(glide_open, 0.10) * delta)
			_update_scarf_bank(move_in.x, delta, glide_open)

			if inside_wind_field:
				var wind_target := _wind_flow_direction() * WIND_SCARF_GLIDE_MAX_CARRY_SPEED \
					* _wind_gust_weight() * glide_open
				var carry_accel := WIND_SCARF_GLIDE_CARRY_ACCEL
				if wind_target.length_squared() < _scarf_wind_carry_velocity.length_squared():
					carry_accel = WIND_SCARF_GLIDE_RELEASE_ACCEL
				_scarf_wind_carry_velocity = _scarf_wind_carry_velocity.move_toward(
					wind_target, carry_accel * delta
				).limit_length(WIND_SCARF_GLIDE_MAX_CARRY_SPEED)
				_scarf_wind_flow_attribution_velocity = _scarf_wind_carry_velocity
				scarf_glide_control_velocity = horiz
				scarf_wind_carry_requested = _scarf_wind_carry_velocity
				scarf_wind_carry_direction = _wind_flow_direction()
				horiz += _scarf_wind_carry_velocity
		else:
			# Cancelling/stowing stops assistance at once but leaves the horizontal
			# momentum already imparted to ordinary air movement.
			_scarf_wind_carry_velocity = Vector3.ZERO
			velocity.y -= config.gravity * delta
			if has_move_input:
				var target_v := wish * max_speed
				horiz = horiz.move_toward(target_v, config.ground_accel * config.air_control * delta)
			else:
				var braking := config.air_decel * delta
				var braked := horiz.move_toward(Vector3.ZERO, braking)
				if _ledge_drop_coast_time > 0.0:
					var side_speed := horiz.dot(_ledge_drop_coast_axis)
					var coast_speed := move_toward(side_speed, 0.0, braking * LEDGE_DROP_LATERAL_BRAKE_SCALE)
					braked += _ledge_drop_coast_axis * (coast_speed - braked.dot(_ledge_drop_coast_axis))
				horiz = braked

	velocity.x = horiz.x
	velocity.z = horiz.z

	if not on_floor:
		# Airborne actions retain their input-facing and wall-kick impulse.
		var facing := horiz if current_anim_label == "WallKick" and _air_anim_timer > 0.0 else wish
		if facing.length_squared() > 1e-4:
			var target_yaw := atan2(-facing.x, -facing.z)
			rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-12.0 * delta))

	# Small-curb stair step-up when grounded and moving into a step
	if on_floor and horiz.length() > 0.3:
		_try_step_up(horiz * delta)

	var vertical_speed_before_slide := velocity.y
	move_and_slide()

	var now_falling := not is_on_floor()
	var actual_velocity := get_real_velocity()
	if scarf_wind_carry_requested.length_squared() > 1e-6 \
		and not scarf_wind_carry_direction.is_zero_approx():
		# A wall may cancel some or all of the requested drift. Store only the
		# part present in the resolved movement, so next frame cannot subtract an
		# unrealized carry and create an opposite impulse.
		var actual_planar_velocity := Vector3(actual_velocity.x, 0.0, actual_velocity.z)
		var requested_carry_speed := scarf_wind_carry_requested.dot(scarf_wind_carry_direction)
		var realized_carry_speed := maxf(
			(actual_planar_velocity - scarf_glide_control_velocity).dot(scarf_wind_carry_direction),
			0.0
		)
		realized_carry_speed = minf(realized_carry_speed, requested_carry_speed)
		_scarf_wind_carry_velocity = scarf_wind_carry_direction * realized_carry_speed
		_scarf_wind_flow_attribution_velocity = _scarf_wind_carry_velocity
	if not now_falling:
		_wall_run_entry_armed = false
		_ledge_drop_coast_time = 0.0
		if _try_land_top_station(vertical_speed_before_slide, on_floor):
			return
	var scarf_glide_was_used := _scarf_glide_used_this_airtime
	resolved_planar_speed = Vector2(actual_velocity.x, actual_velocity.z).length()
	var planar_speed := resolved_planar_speed
	var ground_speed := planar_speed
	var ground_motion := Vector3.ZERO
	if not now_falling:
		if on_floor and wish.length_squared() > 0.18 and _try_mount_wall(wish, false, true):
			return
		if not on_floor and _landed_on_climbing_lip():
			var landing_heading := _air_wall_approach if not _air_wall_approach.is_zero_approx() else -global_basis.z
			if _try_mount_wall(landing_heading, false):
				return
		_air_wall_approach = Vector3.ZERO
	if now_falling:
		_clear_ground_pivot()
	else:
		var relative_ground_velocity := actual_velocity - get_platform_velocity()
		ground_motion = Vector3(relative_ground_velocity.x, 0.0, relative_ground_velocity.z)
		ground_speed = ground_motion.length()
		_update_ground_heading(prior_horizontal, ground_motion, wish, delta)

	if now_falling:
		coyote_timer = maxf(0.0, coyote_timer - delta)
		air_time += delta
		peak_fall_speed = minf(peak_fall_speed, velocity.y)
	else:
		coyote_timer = config.coyote_time_duration
		air_time = 0.0
		var dry_scarf_touchdown := false
		if was_falling and scarf_glide_phase in [&"deploy", &"glide"]:
			_stow_scarf_glide()
			dry_scarf_touchdown = get_active_water() == null
			scarf_glide_touchdown = dry_scarf_touchdown
		_scarf_glide_used_this_airtime = false
		_air_anim_timer = 0.0
		bounce_anim_timer = 0.0
		super_bounce_active = false
		super_bounce_grace_timer = 0.0
		if was_falling:
			var landing_fall_speed := peak_fall_speed
			if scarf_glide_was_used:
				landing_fall_speed = minf(vertical_speed_before_slide, 0.0)
			var do_roll := (
				(not suppress_auto_roll and landing_fall_speed < config.auto_roll_fall_speed)
				or (landing_fall_speed < config.roll_min_fall_speed and roll_buffer_timer > 0.0)
			)
			suppress_auto_roll = false
			var scarf_run_landing := dry_scarf_touchdown and ground_speed >= SCARF_RUNNING_LANDING_MIN_SPEED
			var landed_with_impact := landing_fall_speed <= -MIN_SOFT_LAND_IMPACT_SPEED
			if do_roll:
				_start_land_roll()
				peak_fall_speed = 0.0
				was_falling = false
				return
			elif jump_buffer_timer <= 0.0 and (landed_with_impact or scarf_run_landing):
				land_anim_timer = config.soft_land_anim_duration
				var seeded_scarf_strike := false
				if ground_speed < 2.2 and not scarf_run_landing:
					_play_action("LandSoft", land_anim_timer, 0.06)
				elif anim_ctrl != null:
					if scarf_run_landing and pose_mod != null:
						var strike_side := pose_mod.begin_scarf_landing_contact(ground_motion)
						if strike_side >= 0:
							anim_ctrl.align_ground_strike(strike_side)
							seeded_scarf_strike = true
					var landing_duration := ChibiAnimController.SCARF_RUNNING_LANDING_DURATION \
						if scarf_run_landing else ChibiAnimController.RUNNING_LANDING_DURATION
					anim_ctrl.begin_running_landing(-landing_fall_speed, landing_duration)
				if juice and landed_with_impact:
					if ground_speed < 2.2 and not scarf_run_landing:
						juice.trigger_squash(1.15, 0.85)
					juice.spawn_dust(global_position)
					# A scarf strike uses the planted shoe's contact sound.
					if not seeded_scarf_strike:
						juice.play_sfx("Land")
		peak_fall_speed = 0.0

	was_falling = now_falling

	# After checking a vault, give marked surfaces their wall catch before generic ledges.
	if now_falling:
		if planar_speed > 1.2 and air_time < 0.55 and velocity.y > -2.2:
			if _try_start_speed_vault():
				return
		if wish.length_squared() > 0.08:
			_air_wall_approach = wish.normalized()
		var approach := _air_wall_approach if air_time < 0.64 and not _air_wall_approach.is_zero_approx() else horiz
		if velocity.y < 2.6 and approach.length_squared() > 0.25 and _wall_climb_cooldown <= 0.0:
			if _try_mount_wall(approach, false):
				return
		if velocity.y < 2.4:
			if try_grab_ledge():
				return
		if _wall_run_entry_armed and _try_start_wall_run(wish):
			return

	# Buffered jump on touchdown
	if jump_buffer_timer > 0.0:
		if not now_falling:
			_execute_ground_jump()
			return
		else:
			jump_buffer_timer = maxf(0.0, jump_buffer_timer - delta)

	# Flow build / decay
	var flow_scoring_speed := _wind_adjusted_flow_speed(planar_speed, actual_velocity, wish)
	if flow_scoring_speed > 3.0:
		flow_level = clampf(flow_level + config.flow_build_rate * delta, 0.0, 1.0)
	elif flow_scoring_speed < 1.2 and not now_falling:
		flow_level = clampf(flow_level - config.flow_decay_rate * delta, 0.0, 1.0)

	# Drive animations
	if now_falling:
		if _swim_recovery_time > 0.0 and current_anim_label == "Swim" and get_active_water() != null and velocity.y <= 0.0:
			return # Finish the stroke until the nearby bank actually supports her.
		if bounce_anim_timer > 0.0 and velocity.y > -1.8:
			_play_anim("BounceAir")
		elif _air_anim_timer > 0.0:
			return
		elif current_anim_label == "FallFlail" or _should_flail():
			_play_anim("FallFlail")
		else:
			_play_anim("FallLoop")
	elif land_anim_timer <= 0.0 or ground_speed >= 2.2 or current_anim_label != "LandSoft":
		if anim_ctrl != null:
			current_anim_label = anim_ctrl.set_locomotion_gait(ground_speed, config, delta, _swim_controller.get_wade_pose_weight())


func _steer_ground(horizontal: Vector3, wish: Vector3, max_speed: float, delta: float) -> Vector3:
	var input_strength := minf(wish.length(), 1.0)
	if input_strength < 0.01:
		return horizontal.move_toward(Vector3.ZERO, config.ground_decel * delta)
	var direction := wish.normalized()
	var target_speed := max_speed * input_strength
	var speed := horizontal.length()
	if speed > target_speed * 1.01:
		horizontal = horizontal.move_toward(horizontal.normalized() * target_speed, config.ground_decel * delta)
		speed = horizontal.length()

	# Retain some momentum while steering its direction toward the held input.
	var traction := minf(config.ground_directional_friction * delta, 1.0)
	horizontal = horizontal.lerp(direction * speed, traction)
	var speed_limit := maxf(horizontal.length(), target_speed)
	return (horizontal + direction * input_strength * config.ground_accel * delta).limit_length(speed_limit)


func _steer_ground_with_wind(horizontal: Vector3, wish: Vector3, max_speed: float, delta: float) -> Vector3:
	var flow_direction := _wind_flow_direction()
	var gust_weight := _wind_gust_weight()
	if flow_direction.is_zero_approx() or gust_weight <= 0.001:
		return _steer_ground(horizontal, wish, max_speed, delta)
	var input_strength := minf(wish.length(), 1.0)
	if input_strength <= 0.01:
		var carry_target := flow_direction * WIND_IDLE_CARRY_SPEED * gust_weight
		return _steer_ground_toward_velocity(horizontal, carry_target, gust_weight, delta)

	var input_direction := wish.normalized()
	var wind_alignment := input_direction.dot(flow_direction)
	var headwind_alignment := maxf(-wind_alignment, 0.0)
	var tailwind_bonus := _wind_tailwind_bonus(max_speed, wind_alignment, input_strength)
	var desired_velocity := input_direction * max_speed * input_strength
	if tailwind_bonus > 0.0:
		desired_velocity += input_direction * tailwind_bonus
	# At the gust peak, a full upwind push settles just 0.8 m/s downwind. The
	# directional term leaves lateral steering intact and keeps the player's facing on input.
	desired_velocity += flow_direction * (max_speed + WIND_MAX_BACKSTEP_SPEED) \
		* gust_weight * headwind_alignment * input_strength
	return _steer_ground_toward_velocity(horizontal, desired_velocity, input_strength, delta)


func _steer_ground_toward_velocity(
	horizontal: Vector3, target_velocity: Vector3, acceleration_scale: float, delta: float
) -> Vector3:
	var target_speed := target_velocity.length()
	if target_speed <= 0.001:
		return horizontal.move_toward(Vector3.ZERO, config.ground_decel * delta)
	var target_direction := target_velocity / target_speed
	var speed := horizontal.length()
	if speed > target_speed * 1.01:
		horizontal = horizontal.move_toward(horizontal.normalized() * target_speed, config.ground_decel * delta)
		speed = horizontal.length()
	var traction := minf(config.ground_directional_friction * delta, 1.0)
	horizontal = horizontal.lerp(target_direction * speed, traction)
	var speed_limit := maxf(horizontal.length(), target_speed)
	return (horizontal + target_direction * acceleration_scale * config.ground_accel * delta).limit_length(speed_limit)


func _update_ground_heading(previous: Vector3, travel: Vector3, wish: Vector3, delta: float) -> void:
	var direction := wish.normalized() if wish.length_squared() > 1e-4 else Vector3.ZERO
	if direction == Vector3.ZERO:
		_clear_ground_pivot()
	elif _ground_pivot_elapsed >= GROUND_PIVOT_DURATION and previous.length_squared() > 2.2 * 2.2 and previous.normalized().dot(direction) < -0.65:
		_ground_pivot_elapsed = 0.0
		var stride_phase := anim_ctrl.get_ground_phase() if anim_ctrl != null else 0.0
		ground_pivot_side = 0 if stride_phase < 0.25 or stride_phase >= 0.75 else 1

	var speed := travel.length()
	var facing := travel
	if _ground_pivot_elapsed < GROUND_PIVOT_DURATION:
		_ground_pivot_elapsed += delta
		var settle := smoothstep(0.015, 0.055, _ground_pivot_elapsed)
		var release := 1.0 - smoothstep(0.10, GROUND_PIVOT_DURATION, _ground_pivot_elapsed)
		ground_pivot_weight = settle * release * (1.0 - smoothstep(1.4, 4.0, speed))
		facing = direction
	else:
		ground_pivot_weight = 0.0
		if direction != Vector3.ZERO and wind_brace_weight <= 0.001:
			facing = direction if speed < 0.25 else travel + direction * minf(speed * 0.4, 1.6)
		elif direction != Vector3.ZERO:
			facing = direction

	if facing.length_squared() > 0.01:
		var target_yaw := atan2(-facing.x, -facing.z)
		rotation.y = rotate_toward(rotation.y, target_yaw, deg_to_rad(config.ground_turn_rate_deg) * delta)


func _clear_ground_pivot() -> void:
	_ground_pivot_elapsed = GROUND_PIVOT_DURATION
	ground_pivot_weight = 0.0


func _should_flail() -> bool:
	if velocity.y >= 0.0 or (velocity.y >= config.flail_fall_speed_threshold and air_time <= config.flail_air_time_threshold):
		return false
	# Avoid flashing the long-fall pose just before an everyday jump touches down.
	var landing_check := PhysicsRayQueryParameters3D.create(
		global_position, global_position + Vector3.DOWN * 0.30, WORLD_MASK, [get_rid()]
	)
	return get_world_3d().direct_space_state.intersect_ray(landing_check).is_empty()


func _try_step_up(motion: Vector3) -> void:
	var motion_xz := Vector3(motion.x, 0.0, motion.z)
	if motion_xz.length_squared() < 1e-6:
		return
	if not test_move(global_transform, motion_xz):
		return
	var raised := global_transform
	raised.origin.y += config.max_step_height
	if test_move(raised, motion_xz):
		return
	var space := get_world_3d().direct_space_state
	var probe := global_position + motion_xz.normalized() * (config.capsule_radius + 0.08)
	var q := PhysicsRayQueryParameters3D.create(
		probe + Vector3.UP * config.max_step_height,
		probe - Vector3.UP * 0.05,
		WORLD_MASK, [get_rid()]
	)
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and (hit["normal"] as Vector3).y > 0.75:
		var step_h: float = (hit["position"] as Vector3).y - global_position.y
		if step_h > 0.02 and step_h <= config.max_step_height:
			try_move_traversal(global_position + Vector3.UP * step_h)


# ---------------------------------------------------------------------------
# SPEED VAULT
# ---------------------------------------------------------------------------
func _try_start_speed_vault() -> bool:
	var space := get_world_3d().direct_space_state
	var exc: Array[RID] = [get_rid()]
	var center := get_capsule_center()
	var feet_y := global_position.y
	var fwd := Vector3(-global_transform.basis.z.x, 0.0, -global_transform.basis.z.z).normalized()

	var low_origin := center - Vector3(0.0, 0.36, 0.0)
	var hit_front := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		low_origin, low_origin + fwd * config.vault_detect_distance, WORLD_MASK, exc
	))
	if hit_front.is_empty():
		return false
	if _has_dedicated_traversal(hit_front["collider"]):
		return false
	var n: Vector3 = hit_front["normal"]
	if fwd.dot(n) >= -0.45:
		return false

	var vault_dir := Vector3(-n.x, 0.0, -n.z).normalized()
	var pt_front: Vector3 = hit_front["position"]

	# Top surface ray 30 cm into obstacle
	var top_xz := pt_front + vault_dir * 0.30
	var hit_top := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		Vector3(top_xz.x, feet_y + 1.35, top_xz.z),
		Vector3(top_xz.x, feet_y + 0.05, top_xz.z),
		WORLD_MASK, exc
	))
	if hit_top.is_empty():
		return false
	if hit_top["collider"] != hit_front["collider"] or (hit_top["normal"] as Vector3).y < 0.7:
		return false
	var top_pt: Vector3 = hit_top["position"]
	var obs_h := top_pt.y - feet_y
	if obs_h < config.vault_min_height or obs_h > config.vault_max_height:
		return false

	# Far-side clearance ray
	var far_xz := pt_front + vault_dir * config.vault_clearance_depth
	var hit_far := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		Vector3(far_xz.x, top_pt.y + 0.70, far_xz.z),
		Vector3(far_xz.x, top_pt.y - 1.60, far_xz.z),
		WORLD_MASK, exc
	))
	if hit_far.is_empty() or (hit_far["normal"] as Vector3).y < 0.7:
		return false
	var far_pt: Vector3 = hit_far["position"]
	if far_pt.y >= top_pt.y - 0.25:
		return false

	var front := Vector3(pt_front.x, top_pt.y, pt_front.z)
	var back_probe := front - Vector3.UP * 0.08
	var hit_back := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		back_probe + vault_dir * config.vault_clearance_depth, back_probe, WORLD_MASK, exc
	))
	if hit_back.is_empty() or hit_back["collider"] != hit_front["collider"]:
		return false
	var back: Vector3 = hit_back["position"]
	var plant := front - vault_dir * (config.capsule_radius - 0.045)
	plant.y = maxf(global_position.y, top_pt.y - 0.12)
	var lift := Vector3(plant.x, maxf(plant.y, top_pt.y + 0.025), plant.z)
	var clear := back + vault_dir * (config.capsule_radius + 0.03)
	clear.y = lift.y
	var finish := far_pt + Vector3.UP * 0.02
	if (finish - clear).dot(vault_dir) <= 0.0:
		return false
	_vault_points = PackedVector3Array([global_position, plant, lift, clear, finish])
	if not _traversal_path_clear(_vault_position):
		return false

	_vault_alpha = 0.0
	_vault_duration = clampf(lerpf(config.vault_base_duration, config.vault_base_duration * 0.88, flow_level), 0.25, 2.0)
	var entry_speed := Vector2(velocity.x, velocity.z).length()
	var exit_speed := clampf(entry_speed, config.base_run_speed, config.max_flow_speed)
	_vault_exit_velocity = vault_dir * exit_speed
	ledge_edge_point = front
	ledge_wall_normal = -vault_dir

	coyote_timer = 0.0
	jump_buffer_timer = 0.0
	rotation.y = atan2(-vault_dir.x, -vault_dir.z)
	velocity = Vector3.ZERO
	add_flow_boost(config.vault_flow_boost)
	if juice:
		juice.play_sfx("Vault")
	_play_action("SpeedVault", _vault_duration)
	transition_to("SpeedVault")
	return true


func _vault_position(phase: float) -> Vector3:
	for segment in range(VAULT_PHASES.size() - 1):
		if phase <= VAULT_PHASES[segment + 1]:
			var progress := smoothstep(VAULT_PHASES[segment], VAULT_PHASES[segment + 1], phase)
			return _vault_points[segment].lerp(_vault_points[segment + 1], progress)
	return _vault_points[-1]


func _update_speed_vault(delta: float) -> void:
	var phase := minf(1.0, _vault_alpha + delta / _vault_duration)
	if not try_move_traversal(_vault_position(phase)):
		_finish_traversal(Vector3.DOWN)
		return
	_vault_alpha = phase
	if anim_ctrl != null:
		anim_ctrl.set_traversal_phase("SpeedVault", _vault_alpha)
	if _vault_alpha >= 1.0:
		_finish_traversal(_vault_exit_velocity)


# ---------------------------------------------------------------------------
# LEDGE GRAB, HANG, SHIMMY, CORNER TURN & MANTLE
# ---------------------------------------------------------------------------
func try_grab_ledge() -> bool:
	if current_state != "Locomotion" or ledge_grab_cooldown > 0.0:
		return false
	var ledge := _find_ledge()
	if ledge.is_empty() or not _try_move_to_ledge(ledge["edge"], ledge["normal"]):
		return false
	ledge_edge_point = ledge["edge"]
	ledge_wall_normal = ledge["normal"]
	ledge_hang_time = 0.0
	_ledge_travel_velocity = Vector3.ZERO
	shimmy_phase = 0.0
	coyote_timer = 0.0
	jump_buffer_timer = 0.0
	velocity = Vector3.ZERO
	add_flow_boost(0.06)
	if juice:
		juice.play_sfx("LedgeGrab")
	_play_anim("LedgeHang")
	transition_to("LedgeHang")
	return true


func _find_ledge() -> Dictionary:
	var space := get_world_3d().direct_space_state
	var exc: Array[RID] = [get_rid()]
	var center := get_capsule_center()
	var fwd := Vector3(-global_transform.basis.z.x, 0.0, -global_transform.basis.z.z).normalized()

	for offset_y in [0.16, -0.02, -0.20, -0.57]:
		var ray_start := center + Vector3(0.0, offset_y, 0.0)
		var hit_wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			ray_start, ray_start + fwd * config.ledge_detect_distance, WORLD_MASK, exc
		))
		if hit_wall.is_empty():
			continue
		if _has_dedicated_traversal(hit_wall["collider"]):
			continue
		var wn: Vector3 = hit_wall["normal"]
		if absf(wn.y) >= 0.35:
			continue
		var wn_xz := Vector3(wn.x, 0.0, wn.z).normalized()
		if fwd.dot(wn_xz) >= -0.35:
			continue

		var wp: Vector3 = hit_wall["position"]
		var top_xz := wp - wn_xz * 0.10
		var top_hi := minf(center.y + 0.52, wp.y + 0.48)
		var hit_top := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			Vector3(top_xz.x, top_hi, top_xz.z),
			Vector3(top_xz.x, wp.y - 0.04, top_xz.z),
			WORLD_MASK, exc
		))
		if hit_top.is_empty():
			continue
		var tn: Vector3 = hit_top["normal"]
		var tp: Vector3 = hit_top["position"]
		if tn.y <= 0.7:
			continue
		var dy := tp.y - center.y
		var in_band := (dy >= -0.18 and dy <= 0.44) or (dy >= -0.575 and dy < -0.18 and velocity.y <= 1.5)
		if not in_band:
			continue

		var edge := Vector3(wp.x, tp.y, wp.z)
		if traversal_segment_clear(global_position, _ledge_feet(edge, wn_xz)):
			return {"edge": edge, "normal": wn_xz}
	return {}


func _ledge_feet(edge: Vector3, wn: Vector3) -> Vector3:
	return edge + wn * (config.capsule_radius + 0.015) + Vector3.UP * (0.06 - _current_half_height())


func _try_move_to_ledge(edge: Vector3, wn: Vector3) -> bool:
	if not try_move_traversal(_ledge_feet(edge, wn)):
		return false
	var face := (-wn).normalized()
	rotation.y = atan2(-face.x, -face.z)
	return true


func _update_ledge_hang(delta: float) -> void:
	ledge_hang_time += delta
	_ledge_travel_velocity = Vector3.ZERO
	if not _try_move_to_ledge(ledge_edge_point, ledge_wall_normal):
		_drop_ledge_traversal()
		return
	_play_anim("LedgeHang")

	var move_in := chibi_input.move_vec if chibi_input else Vector2.ZERO
	if ledge_hang_time > 0.14 and move_in.y < -0.55:
		start_ledge_mantle()
		return
	if ledge_hang_time > 0.18 and move_in.y > 0.65:
		ledge_grab_cooldown = 0.40
		transition_to("Locomotion")
		velocity = ledge_wall_normal * 1.4
		return
	if absf(move_in.x) > 0.35:
		var sign_x := 1.0 if move_in.x > 0.0 else -1.0
		if not _try_start_shimmy(sign_x) and corner_turn_cooldown <= 0.0:
			_try_start_ledge_corner(sign_x)


func _try_start_shimmy(dir_sign: float) -> bool:
	var space := get_world_3d().direct_space_state
	var exc: Array[RID] = [get_rid()]
	var inward := (-ledge_wall_normal).normalized()
	var right := inward.cross(Vector3.UP).normalized()
	var step_dist := config.ledge_shimmy_speed * config.ledge_shimmy_step_duration # ~0.35 m
	var next_edge := ledge_edge_point + right * (dir_sign * step_dist)

	var wall_probe := next_edge - Vector3.UP * 0.12
	var hit_w := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		wall_probe - inward * 0.35, wall_probe + inward * 0.35, WORLD_MASK, exc
	))
	if hit_w.is_empty():
		return false
	var wn: Vector3 = hit_w["normal"]
	var wn_xz := Vector3(wn.x, 0.0, wn.z).normalized()
	if wn_xz.dot(ledge_wall_normal) < 0.7:
		return false
	var wp: Vector3 = hit_w["position"]
	var top_xz := wp + inward * 0.10
	var hit_t := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		Vector3(top_xz.x, next_edge.y + 0.30, top_xz.z),
		Vector3(top_xz.x, next_edge.y - 0.30, top_xz.z),
		WORLD_MASK, exc
	))
	if hit_t.is_empty() or (hit_t["normal"] as Vector3).y < 0.65:
		return false

	var end_edge := Vector3(wp.x, (hit_t["position"] as Vector3).y, wp.z)
	if not traversal_segment_clear(global_position, _ledge_feet(end_edge, ledge_wall_normal)):
		return false
	shimmy_start_edge = ledge_edge_point
	shimmy_end_edge = end_edge
	shimmy_phase = 0.0
	_ledge_travel_velocity = right * dir_sign * config.ledge_shimmy_speed
	if juice:
		juice.play_sfx("Shimmy")
	_play_anim("ShimmyR" if dir_sign > 0.0 else "ShimmyL")
	transition_to("LedgeShimmy")
	return true


func _update_ledge_shimmy(delta: float) -> void:
	shimmy_phase = minf(1.0, shimmy_phase + delta / config.ledge_shimmy_step_duration)
	var u := clampf(inverse_lerp(0.3, 0.7, shimmy_phase), 0.0, 1.0)
	var s := u * u * (3.0 - 2.0 * u)
	var edge := shimmy_start_edge.lerp(shimmy_end_edge, s)
	var previous := global_position
	if not _try_move_to_ledge(edge, ledge_wall_normal):
		_drop_ledge_traversal()
		return
	_remember_ledge_travel(previous, delta)
	ledge_edge_point = edge
	if shimmy_phase >= 1.0:
		ledge_edge_point = shimmy_end_edge
		transition_to("LedgeHang")


func _try_start_ledge_corner(dir_sign: float) -> bool:
	var space := get_world_3d().direct_space_state
	var exc: Array[RID] = [get_rid()]
	var inward := (-ledge_wall_normal).normalized()
	var side := inward.cross(Vector3.UP).normalized() * dir_sign

	# Outer 90-degree corner probe: step past edge and trace back toward side face
	var around := ledge_edge_point + side * 0.34 + inward * 0.34
	var hit_side := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		around + side * 0.25 - Vector3.UP * 0.14,
		around - side * 0.45 - Vector3.UP * 0.14,
		WORLD_MASK, exc
	))
	if hit_side.is_empty():
		return false
	var new_wn: Vector3 = hit_side["normal"]
	var new_wn_xz := Vector3(new_wn.x, 0.0, new_wn.z).normalized()
	if absf(new_wn_xz.dot(ledge_wall_normal)) > 0.45:
		return false
	var sp: Vector3 = hit_side["position"]
	var top_xz := sp - new_wn_xz * 0.10
	var hit_top := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		Vector3(top_xz.x, ledge_edge_point.y + 0.30, top_xz.z),
		Vector3(top_xz.x, ledge_edge_point.y - 0.30, top_xz.z),
		WORLD_MASK, exc
	))
	if hit_top.is_empty() or (hit_top["normal"] as Vector3).y < 0.65:
		return false

	_corner_new_edge = Vector3(sp.x, (hit_top["position"] as Vector3).y, sp.z)
	_corner_new_normal = new_wn_xz
	_corner_start_pos = global_position
	_corner_end_pos = _ledge_feet(_corner_new_edge, _corner_new_normal)
	var away_from_corner := (ledge_wall_normal + _corner_new_normal).normalized()
	_corner_ctrl_pos = _corner_start_pos.lerp(_corner_end_pos, 0.5) + away_from_corner * (config.capsule_radius * 2.2)
	_corner_start_yaw = rotation.y
	var end_face := (-_corner_new_normal).normalized()
	_corner_end_yaw = atan2(-end_face.x, -end_face.z)
	_corner_alpha = 0.0
	if not _traversal_path_clear(_ledge_corner_position):
		return false

	_ledge_travel_velocity = (_corner_ctrl_pos - _corner_start_pos).normalized() * config.ledge_shimmy_speed
	if juice:
		juice.play_sfx("Shimmy")
	_play_anim("CornerR" if dir_sign > 0.0 else "CornerL")
	transition_to("LedgeCorner")
	return true


func _update_ledge_corner(delta: float) -> void:
	_corner_alpha = minf(1.0, _corner_alpha + delta / config.ledge_corner_duration)
	var s := _corner_alpha * _corner_alpha * (3.0 - 2.0 * _corner_alpha)
	var previous := global_position
	if not try_move_traversal(_ledge_corner_position(_corner_alpha)):
		_drop_ledge_traversal()
		return
	_remember_ledge_travel(previous, delta)
	rotation.y = lerp_angle(_corner_start_yaw, _corner_end_yaw, s)
	if _corner_alpha >= 1.0:
		ledge_edge_point = _corner_new_edge
		ledge_wall_normal = _corner_new_normal
		corner_turn_cooldown = 0.16
		shimmy_phase = 0.0
		transition_to("LedgeHang")


func _ledge_corner_position(phase: float) -> Vector3:
	return _quad_bezier(_corner_start_pos, _corner_ctrl_pos, _corner_end_pos, smoothstep(0.0, 1.0, phase))


func _remember_ledge_travel(previous: Vector3, delta: float) -> void:
	var travel := (global_position - previous).slide(Vector3.UP)
	# Keep the direction through the brief planted poses at each end of a step.
	if not travel.is_zero_approx():
		var speed := maxf(config.ledge_shimmy_speed, travel.length() / delta)
		_ledge_travel_velocity = travel.normalized() * speed


func _drop_ledge_traversal(exit_velocity: Vector3 = Vector3.DOWN) -> void:
	ledge_grab_cooldown = 0.42
	_finish_traversal(exit_velocity)


func start_ledge_mantle() -> bool:
	return _try_ledge_mantle(ledge_edge_point, ledge_wall_normal)


func _try_ledge_mantle(edge: Vector3, normal: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	_mantle_start = global_position
	_mantle_hang = _ledge_feet(edge, normal)
	for inset in [0.44, 0.32, 0.24, 0.16]:
		var landing_probe: Vector3 = edge - normal * inset
		var floor := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			landing_probe + Vector3.UP * 0.40, landing_probe - Vector3.UP * 0.08, WORLD_MASK, [get_rid()]
		))
		if floor.is_empty() or (floor["normal"] as Vector3).y < cos(floor_max_angle):
			continue
		_mantle_end = (floor["position"] as Vector3) + Vector3.UP * 0.025
		_mantle_lift = Vector3(_mantle_hang.x, _mantle_end.y, _mantle_hang.z)
		if not _traversal_path_clear(_mantle_position):
			continue
		ledge_edge_point = edge
		ledge_wall_normal = normal
		var facing := -normal
		rotation.y = atan2(-facing.x, -facing.z)
		_begin_mantle()
		return true
	return false


func _begin_mantle() -> void:
	mantle_alpha = 0.0
	_mantle_duration = clampf(lerpf(config.mantle_base_duration, config.mantle_base_duration * 0.85, flow_level), 0.25, 2.0)
	velocity = Vector3.ZERO
	add_flow_boost(config.ledge_flow_boost)
	if juice:
		juice.play_sfx("Mantle")
	_play_action("MantleUp", _mantle_duration)
	transition_to("MantleUp")


func _mantle_position(phase: float) -> Vector3:
	var lift_start := 0.0
	if not _wall_mantle_active and not _mantle_start.is_equal_approx(_mantle_hang):
		lift_start = 0.16
		if phase < lift_start:
			return _mantle_start.lerp(_mantle_hang, smoothstep(0.0, lift_start, phase))
	var start := _mantle_start if _wall_mantle_active else _mantle_hang
	if phase < 0.58:
		return start.lerp(_mantle_lift, smoothstep(lift_start, 0.58, phase))
	return _mantle_lift.lerp(_mantle_end, smoothstep(0.58, 1.0, phase))


func _update_mantle(delta: float) -> void:
	var phase := minf(1.0, mantle_alpha + delta / _mantle_duration)
	if not try_move_traversal(_mantle_position(phase)):
		_drop_ledge_traversal()
		return
	mantle_alpha = phase
	if anim_ctrl != null:
		anim_ctrl.set_traversal_phase("MantleUp", mantle_alpha)
	if mantle_alpha >= 1.0:
		_finish_traversal(Vector3.ZERO)


func _finish_traversal(exit_velocity: Vector3) -> void:
	velocity = exit_velocity
	air_time = 0.0
	peak_fall_speed = 0.0
	was_falling = false
	transition_to("Locomotion")


# ---------------------------------------------------------------------------
# WALL RUN & WALL KICK
# ---------------------------------------------------------------------------
func _try_start_wall_run(wish: Vector3) -> bool:
	if wall_run_cooldown > 0.0 or air_time <= 0.06 or air_time > config.wall_run_entry_window:
		return false
	if wish.length_squared() < config.wall_run_entry_min_input * config.wall_run_entry_min_input:
		return false
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if horiz.length_squared() < config.wall_run_entry_min_speed * config.wall_run_entry_min_speed or velocity.y < -7.80:
		return false
	var horiz_dir := horiz.normalized()
	var space := get_world_3d().direct_space_state
	var exc: Array[RID] = [get_rid()]
	var center := get_capsule_center()
	var right := global_transform.basis.x.normalized()
	var fwd := (-global_transform.basis.z).normalized()
	var d := config.wall_run_entry_distance

	var probes := [
		[right, d],
		[(right + fwd * 0.6).normalized(), d + 0.08],
		[-right, d],
		[(-right + fwd * 0.6).normalized(), d + 0.08],
	]
	for p in probes:
		var dir: Vector3 = p[0]
		var dist: float = p[1]
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			center, center + dir * dist, WORLD_MASK, exc
		))
		if hit.is_empty():
			continue
		var wn: Vector3 = hit["normal"]
		if absf(wn.y) >= 0.28:
			continue
		var wn_xz := Vector3(wn.x, 0.0, wn.z).normalized()
		var wall_point: Vector3 = hit["position"]
		if (center - wall_point).dot(wn_xz) > d or absf(horiz_dir.dot(wn_xz)) >= 0.78:
			continue
		var tangent := Vector3.UP.cross(wn_xz).normalized()
		var along_speed := horiz.dot(tangent)
		if absf(along_speed) < config.wall_run_entry_min_speed:
			continue
		var run_dir := tangent * signf(along_speed)
		if wish.dot(run_dir) < config.wall_run_entry_min_input:
			continue
		# Confirm wall extends upward (+0.58 m)
		var hi_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			center + Vector3.UP * 0.58, center + Vector3.UP * 0.58 - wn_xz * (d + 0.16), WORLD_MASK, exc
		))
		if hi_hit.is_empty():
			continue

		# Wall is on Chibi's RIGHT if right_of_run.dot(-wn) > 0
		var run_right := run_dir.cross(Vector3.UP).normalized()
		var wall_on_right := 1.0 if run_right.dot(-wn_xz) > 0.0 else -1.0

		_wall_run_normal = wn_xz
		_wall_run_dir = run_dir
		_wall_run_side = wall_on_right
		_wall_run_timer = 0.0
		air_time = 0.0
		peak_fall_speed = 0.0
		coyote_timer = 0.0
		jump_buffer_timer = 0.0
		if camera_ctrl:
			camera_ctrl.target_roll_deg = config.wall_run_camera_roll_deg * wall_on_right
		add_flow_boost(0.10)
		_play_anim("WallRunR" if wall_on_right > 0.0 else "WallRunL")
		transition_to("WallRun")
		return true
	return false


func _update_wall_run(delta: float) -> void:
	_wall_run_timer += delta
	var speed := lerpf(config.wall_run_base_speed, config.wall_run_base_speed * 1.28, flow_level)
	var arc_y := lerpf(0.85, -1.15, clampf(_wall_run_timer / config.wall_run_max_duration, 0.0, 1.0))
	var move_y := chibi_input.move_vec.y if chibi_input else 0.0
	var space := get_world_3d().direct_space_state
	var center := get_capsule_center()
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		center, center - _wall_run_normal * config.wall_run_detect_distance, WORLD_MASK, [get_rid()]
	))
	if hit.is_empty() or _wall_run_timer >= config.wall_run_max_duration or move_y > 0.55:
		wall_run_cooldown = 0.28
		velocity = _wall_run_dir * speed + Vector3(0.0, arc_y, 0.0)
		transition_to("Locomotion")
		return

	var hit_n: Vector3 = hit["normal"]
	if absf(hit_n.y) >= 0.28:
		wall_run_cooldown = 0.28
		velocity = _wall_run_dir * speed + Vector3(0.0, arc_y, 0.0)
		transition_to("Locomotion")
		return

	var wn := Vector3(hit_n.x, 0.0, hit_n.z).normalized()
	var tangent := Vector3.UP.cross(wn).normalized()
	var run_dir := tangent * (1.0 if tangent.dot(_wall_run_dir) >= 0.0 else -1.0)
	_wall_run_normal = wn
	_wall_run_dir = run_dir

	# Keep the capsule clear of the wall and approach over several physics ticks.
	var hit_pt: Vector3 = hit["position"]
	var wall_distance := (global_position - hit_pt).dot(wn)
	var capsule := collision_shape.shape as CapsuleShape3D if collision_shape != null else null
	var clearance := (capsule.radius if capsule != null else config.capsule_radius) + maxf(safe_margin, 0.015)
	var approach := (clearance - wall_distance) * (1.0 - exp(-24.0 * delta)) / delta
	velocity = run_dir * speed + Vector3.UP * arc_y + wn * clampf(approach, -3.0, 3.0)
	move_and_slide()
	rotation.y = lerp_angle(rotation.y, atan2(-run_dir.x, -run_dir.z), 1.0 - exp(-16.0 * delta))
	add_flow_boost(0.24 * delta)
	if is_on_floor():
		wall_run_cooldown = 0.25
		transition_to("Locomotion")


func _start_wall_kick() -> void:
	wall_run_cooldown = 0.16
	air_time = 0.0
	peak_fall_speed = 0.0
	var run_spd := lerpf(config.wall_run_base_speed, config.max_flow_speed, flow_level) * 0.94
	var kick_horiz := _wall_run_normal * config.wall_kick_side_force + _wall_run_dir * run_spd
	velocity = Vector3(kick_horiz.x, config.wall_kick_up_force, kick_horiz.z)
	add_flow_boost(config.wall_run_flow_boost)
	if juice:
		juice.trigger_squash(0.86, 1.18)
		juice.play_sfx("WallKick")
		juice.spawn_dust(get_capsule_center() - _wall_run_normal * 0.28)
		juice.spawn_flow_sparkle(get_capsule_center())
	transition_to("Locomotion")
	_wall_run_entry_armed = true
	_start_air_animation("WallKick", 0.42)


# ---------------------------------------------------------------------------
# SLIDE & LAND ROLL
# ---------------------------------------------------------------------------
func _start_slide() -> void:
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	_slide_dir = horiz.normalized() if horiz.length_squared() > 0.01 else (-global_transform.basis.z).normalized()
	_slide_speed = maxf(horiz.length() + 1.2, config.slide_boost_speed)
	_slide_timer = config.slide_duration
	_wind_field_slide_latched = _wind_field_inside
	_wind_slide_elapsed = 0.0
	_slide_dive_time = 0.0
	_set_capsule_slide(true)
	if pose_mod:
		pose_mod.slide_dive_active = true
		pose_mod.slide_dive_phase = 0.0
	add_flow_boost(config.slide_flow_boost)
	if juice:
		juice.trigger_squash(1.15, 0.85)
		juice.play_sfx("Slide")
		juice.spawn_dust(global_position)
	_play_action("Slide", 0.53)
	transition_to("Slide")


func _has_headroom() -> bool:
	var standing := PhysicsShapeQueryParameters3D.new()
	standing.shape = _standing_clearance
	standing.collision_mask = WORLD_MASK
	standing.exclude = [get_rid()]
	# A slight lift keeps the floor outside the check at a settled slide height.
	var center := global_position + Vector3.UP * (_standing_clearance.height * 0.5 + 0.025)
	standing.transform = Transform3D(Basis.IDENTITY, center)
	return get_world_3d().direct_space_state.intersect_shape(standing, 1).is_empty()


func _try_end_slide() -> void:
	if _has_headroom():
		transition_to("Locomotion")


func _update_slide(delta: float) -> void:
	var wind_field_slide := _wind_field_slide_latched and _wind_field_inside
	var steer_x := chibi_input.move_vec.x if chibi_input else 0.0
	_slide_dir = _slide_dir.rotated(Vector3.UP, deg_to_rad(-steer_x * 65.0 * delta)).normalized()

	var space := get_world_3d().direct_space_state
	var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0.0, 0.25, 0.0),
		global_position - Vector3(0.0, 0.45, 0.0),
		WORLD_MASK, [get_rid()]
	))
	var floor_n := (floor_hit["normal"] as Vector3) if not floor_hit.is_empty() else Vector3.UP
	var slope_dot := _slide_dir.dot(floor_n)
	var downhill := slope_dot > 0.08
	if downhill:
		_slide_speed = clampf(_slide_speed + slope_dot * 5.4 * delta, 2.6, 8.2)
		if not wind_field_slide:
			_slide_timer = maxf(_slide_timer, 0.30)
	else:
		_slide_speed = clampf(_slide_speed - 3.2 * delta, 1.8, 8.2)
		if not wind_field_slide:
			_slide_timer -= delta

	var low_ceiling := not _has_headroom()
	if low_ceiling:
		_slide_speed = maxf(_slide_speed, 2.8)
	if wind_field_slide:
		_slide_speed = maxf(_slide_speed, WIND_SLIDE_MIN_SPEED)

	var slide_velocity := _slide_dir * _slide_speed
	if wind_field_slide:
		var flow_direction := _wind_flow_direction()
		if not flow_direction.is_zero_approx():
			var side_direction := flow_direction.cross(Vector3.UP).normalized()
			var target_speed := WIND_SLIDE_MIN_SPEED + WIND_SLIDE_CARRY_SPEED * _wind_gust_weight()
			var target_side_speed := _slide_dir.dot(side_direction) * target_speed * 0.65
			var downwind_target := flow_direction * target_speed + side_direction * target_side_speed
			var turn_weight := smoothstep(0.0, WIND_SLIDE_TURN_DURATION, _wind_slide_elapsed)
			slide_velocity = slide_velocity.lerp(downwind_target, turn_weight)
			_wind_slide_elapsed += delta
		slide_velocity = slide_velocity.limit_length(WIND_SLIDE_SPEED_LIMIT)
	velocity.x = slide_velocity.x
	velocity.z = slide_velocity.z
	velocity.y -= config.gravity * delta
	move_and_slide()

	var facing_direction := _slide_dir
	if wind_field_slide and slide_velocity.length_squared() > 0.25 * 0.25:
		facing_direction = slide_velocity.normalized()
	var target_yaw := atan2(-facing_direction.x, -facing_direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-12.0 * delta))

	# Dive arc progress (0.38s matching ChibiLedgeAnimInstance)
	_slide_dive_time += delta
	if pose_mod:
		pose_mod.slide_dive_phase = clampf(_slide_dive_time / 0.38, 0.0, 1.0)
		if _slide_dive_time >= 0.38:
			pose_mod.slide_dive_active = false

	if juice and juice.slide_dust_cooldown <= 0.0:
		juice.slide_dust_cooldown = 0.11
		juice.spawn_dust(global_position)

	if not is_on_floor():
		transition_to("Locomotion")
	elif not wind_field_slide and not low_ceiling and (_slide_timer <= 0.0 or _slide_speed <= 2.1):
		transition_to("Locomotion")


func _start_land_roll() -> void:
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	_roll_dir = horiz.normalized() if horiz.length_squared() > 0.05 else (-global_transform.basis.z).normalized()
	_roll_timer = config.roll_duration
	roll_buffer_timer = 0.0
	add_flow_boost(config.roll_flow_boost)
	if juice:
		juice.trigger_squash(1.20, 0.78)
		juice.play_sfx("Roll")
		juice.spawn_dust(global_position)
	_play_action("LandRoll", config.roll_duration, 0.05)
	transition_to("LandRoll")


func _update_land_roll(delta: float) -> void:
	_roll_timer -= delta
	velocity.x = _roll_dir.x * config.roll_speed
	velocity.z = _roll_dir.z * config.roll_speed
	velocity.y -= config.gravity * delta
	move_and_slide()
	if _roll_timer <= 0.0:
		transition_to("Locomotion")


# ---------------------------------------------------------------------------
# INTERACTIVE STATIONS: TRAMPOLINE, POLE, BEAM, LINES, ROPE SWING
# ---------------------------------------------------------------------------
func _try_land_top_station(impact_velocity: float, was_on_floor: bool) -> bool:
	for index in get_slide_collision_count():
		var collision := get_slide_collision(index)
		for contact in collision.get_collision_count():
			if collision.get_normal(contact).dot(Vector3.UP) < cos(floor_max_angle):
				continue
			var support := collision.get_collider(contact)
			if not is_instance_valid(support):
				continue
			var station: Node = support.get_meta(TOP_STATION_META) if support.has_meta(TOP_STATION_META) else null
			if is_instance_valid(station) and station.call("land_on_top", self, impact_velocity, was_on_floor):
				return true
	return false


func trigger_trampoline_bounce(base_vel: float, super_mult: float) -> bool:
	if trampoline_cooldown > 0.0 or current_state != "Locomotion":
		return false
	_wall_run_entry_armed = false
	_clear_scarf_glide_phase(true, true)
	trampoline_cooldown = 0.25
	coyote_timer = 0.0
	last_trampoline_velocity = base_vel
	last_trampoline_super_mult = super_mult
	var is_super := jump_buffer_timer > 0.0 or (chibi_input != null and chibi_input.jump_held)
	jump_buffer_timer = 0.0
	super_bounce_active = is_super
	super_bounce_grace_timer = 0.0 if is_super else 0.18
	velocity.y = base_vel * (super_mult if is_super else 1.0)
	bounce_anim_timer = 0.72
	suppress_auto_roll = true
	add_flow_boost(0.18 if is_super else 0.10)
	if juice:
		juice.trigger_squash(0.84, 1.22)
		juice.play_sfx("Whee" if is_super else "Jump")
		if is_super:
			juice.spawn_super_bounce_wind(global_position)
		else:
			juice.spawn_dust(global_position)
	_play_anim("BounceAir")
	return true


func try_enter_pole_perch(pole_top_world: Vector3) -> bool:
	if pole_cooldown > 0.0 or current_state != "Locomotion":
		return false
	if velocity.y > 1.8:
		return false
	if not try_move_traversal(pole_top_world):
		return false
	_pole_top_pos = pole_top_world
	_pole_hold_time = 0.0
	velocity = Vector3.ZERO
	add_flow_boost(0.08)
	if juice:
		juice.trigger_squash(1.12, 0.88)
		juice.play_sfx("Land")
	_play_anim("PolePerch")
	transition_to("PolePerch")
	return true


func _update_pole_perch(delta: float) -> void:
	_pole_hold_time += delta
	velocity = Vector3.ZERO
	var move_in := chibi_input.move_vec if chibi_input else Vector2.ZERO
	if move_in.length() > 0.25 and camera_ctrl != null:
		var aim := (camera_ctrl.get_right_xz() * move_in.x - camera_ctrl.get_forward_xz() * move_in.y).normalized()
		rotation.y = lerp_angle(rotation.y, atan2(-aim.x, -aim.z), 1.0 - exp(-10.0 * delta))


func _jump_or_hop_off_pole() -> void:
	var aim_dir := (-global_transform.basis.z).normalized()
	if chibi_input != null and chibi_input.move_vec.length() > 0.2 and camera_ctrl != null:
		aim_dir = (camera_ctrl.get_right_xz() * chibi_input.move_vec.x - camera_ctrl.get_forward_xz() * chibi_input.move_vec.y).normalized()

	var best_pole := _find_best_pole_target(aim_dir)
	if best_pole != null:
		_pole_hop_start = global_position
		_pole_hop_end = best_pole.call("get_top_world_position")
		_pole_hop_alpha = 0.0
		var dist := _pole_hop_start.distance_to(_pole_hop_end)
		_pole_hop_duration = clampf(dist / 7.2, 0.28, 0.65)
		_pole_hop_arc = clampf(dist * 0.22, 0.45, 1.10)
		var dir := (_pole_hop_end - _pole_hop_start)
		dir.y = 0.0
		if dir.length_squared() > 0.01:
			rotation.y = atan2(-dir.x, -dir.z)
		add_flow_boost(0.12)
		if juice:
			juice.trigger_squash(0.90, 1.15)
			juice.play_sfx("Jump")
		_play_action("JumpStart", _pole_hop_duration, 0.055)
		transition_to("PoleHop")
	else:
		pole_cooldown = 0.35
		velocity = aim_dir * maxf(config.base_run_speed, 5.2) + Vector3(0.0, config.jump_velocity * 1.05, 0.0)
		if juice:
			juice.play_sfx("Jump")
		transition_to("Locomotion")
		_start_air_animation("JumpStart", JUMP_POSE_DURATION, 0.62)


func _find_best_pole_target(aim_dir: Vector3) -> Node3D:
	var best: Node3D = null
	var best_score := -INF
	for node in get_tree().get_nodes_in_group("parkour_poles"):
		if not (node is Node3D) or not node.has_method("get_top_world_position"):
			continue
		var top: Vector3 = node.call("get_top_world_position")
		var diff := top - _pole_top_pos
		var dist := diff.length()
		if dist < 0.8 or dist > 6.5:
			continue
		var horiz := Vector3(diff.x, 0.0, diff.z).normalized()
		var align := aim_dir.dot(horiz)
		if align < 0.45:
			continue
		var score := align * 3.0 - dist * 0.25
		if score > best_score:
			var arc := clampf(global_position.distance_to(top) * 0.22, 0.45, 1.10)
			if not _traversal_path_clear(_pole_hop_position.bind(global_position, top, arc)):
				continue
			best_score = score
			best = node
	return best


func _pole_hop_position(phase: float, start: Vector3, finish: Vector3, arc: float) -> Vector3:
	return start.lerp(finish, phase) + Vector3.UP * (sin(PI * phase) * arc)


func _update_pole_hop(delta: float) -> void:
	_pole_hop_alpha = minf(1.0, _pole_hop_alpha + delta / maxf(0.15, _pole_hop_duration))
	if not try_move_traversal(_pole_hop_position(_pole_hop_alpha, _pole_hop_start, _pole_hop_end, _pole_hop_arc)):
		pole_cooldown = 0.35
		_finish_traversal(Vector3.DOWN)
		return
	if _pole_hop_alpha >= 1.0:
		_pole_top_pos = _pole_hop_end
		_pole_hold_time = 0.0
		if juice:
			juice.trigger_squash(1.12, 0.88)
			juice.play_sfx("Land")
		_play_anim("PolePerch")
		transition_to("PolePerch")


func try_enter_balance_beam(beam: ParkourBalanceBeam) -> bool:
	if beam_cooldown > 0.0 or current_state != "Locomotion":
		return false
	if velocity.y > 1.5:
		return false
	var margin := minf(0.15, beam.beam_length * 0.25)
	var progress := clampf(-beam.to_local(global_position).z, margin, beam.beam_length - margin)
	if not try_move_traversal(beam.to_global(Vector3(0.0, beam.beam_radius, -progress))):
		return false
	_beam = beam
	_beam_progress = progress
	_beam_direction = 1.0 if global_basis.z.dot(beam.global_basis.z) >= 0.0 else -1.0
	_beam_footing.reset(_beam_progress, _beam_direction, beam.beam_length)
	velocity = Vector3.ZERO
	_play_anim("BeamIdle")
	transition_to("BalanceBeam")
	return true


func has_balance_footing() -> bool:
	return current_state == "BalanceBeam" and is_instance_valid(_beam)


func get_balance_foot_target(side: int) -> Transform3D:
	return _beam.foot_surface(_beam_footing.foot_at(side, Engine.get_physics_interpolation_fraction()))


func _update_balance_beam(delta: float) -> void:
	if not is_instance_valid(_beam):
		transition_to("Locomotion")
		return
	var axis := -_beam.global_basis.z.normalized()
	var move_in := chibi_input.move_vec if chibi_input else Vector2.ZERO
	var wish := Vector3.ZERO
	if move_in.length() > 0.1 and camera_ctrl != null:
		wish = camera_ctrl.get_right_xz() * move_in.x - camera_ctrl.get_forward_xz() * move_in.y
	var along := clampf(wish.dot(axis), -1.0, 1.0)
	var speed := 0.0
	if absf(along) > 0.12:
		_beam_direction = signf(along)
		speed = along * BALANCE_WALK_SPEED
	var face := axis * _beam_direction
	var yaw := atan2(-face.x, -face.z)
	var turn_angle := absf(angle_difference(rotation.y, yaw))
	if turn_angle > 0.01:
		# Give the swing foot time to settle, then turn over two fixed contacts.
		var ready := _beam_footing.prepare_turn(_beam_progress) if turn_angle > 0.65 else _beam_footing.is_settled()
		if ready:
			rotation.y = rotate_toward(rotation.y, yaw, BALANCE_TURN_SPEED * delta)
		speed = 0.0
	elif _beam_footing.is_settling():
		speed = 0.0

	var previous_progress := _beam_progress
	var next_progress := clampf(_beam_progress + speed * delta, 0.0, _beam.beam_length)
	if not try_move_traversal(_beam.to_global(Vector3(0.0, _beam.beam_radius, -next_progress))):
		speed = 0.0
	else:
		_beam_progress = next_progress
	_beam_footing.advance(previous_progress, _beam_progress, delta)

	if not is_zero_approx(speed):
		if anim_ctrl != null:
			anim_ctrl.set_balance_walk_phase(_beam_footing.walk_phase(), current_anim_label != "BeamWalk")
		_play_anim("BeamWalk")
	else:
		_play_anim("BeamIdle")

	if not is_zero_approx(speed) and (_beam_progress <= 0.05 or _beam_progress >= _beam.beam_length - 0.05):
		beam_cooldown = 0.35
		velocity = axis * speed
		transition_to("Locomotion")


func _jump_off_beam() -> void:
	beam_cooldown = 0.35
	var fwd := (-global_transform.basis.z).normalized()
	velocity = fwd * 3.8 + Vector3(0.0, config.jump_velocity, 0.0)
	if juice:
		juice.play_sfx("Jump")
	transition_to("Locomotion")
	_start_air_animation("JumpStart", JUMP_POSE_DURATION, 0.62)


func try_enter_parkour_line(line_node: Node3D, is_zip: bool, start_t: float, length: float, zip_min: float, zip_max: float) -> bool:
	if line_cooldown > 0.0 or current_state != "Locomotion":
		return false
	var line_length := maxf(0.5, length)
	var distance := clampf(start_t * line_length, 0.28, maxf(0.28, line_length - 0.28))
	var target := _line_feet_at(line_node, distance / line_length, is_zip)
	if global_position.distance_to(target) > 0.65 or not traversal_segment_clear(global_position, target):
		return false
	_active_line = line_node
	_line_is_zip = is_zip
	_line_length = line_length
	_line_distance = distance
	_line_time = 0.0
	_rope_climb_sfx_timer = 0.0
	var line_dir: Vector3 = _active_line.call("get_line_direction")
	var fwd := Vector3(-global_transform.basis.z.x, 0.0, -global_transform.basis.z.z).normalized()
	var line_xz := Vector3(line_dir.x, 0.0, line_dir.z).normalized()
	_line_facing_sign = 1.0 if fwd.dot(line_xz) >= 0.0 else -1.0
	_zip_min = zip_min
	_zip_max = zip_max
	_zip_speed = clampf(Vector2(velocity.x, velocity.z).length(), zip_min, zip_max)
	coyote_timer = 0.0
	jump_buffer_timer = 0.0
	velocity = Vector3.ZERO
	if _active_line.has_method("notify_rider_attach"):
		_active_line.call("notify_rider_attach", clampf(_line_distance / _line_length, 0.0, 1.0))
	add_flow_boost(0.08)
	if juice:
		juice.trigger_squash(0.92, 1.10)
		juice.play_sfx("LedgeGrab")
	if is_zip:
		_play_anim("ZipGlide")
		transition_to("ZipLine")
	else:
		_play_anim("RopeHang")
		transition_to("RopeLine")
	return true


func _line_feet_at(line: Node3D, progress: float, is_zip: bool) -> Vector3:
	var rope_pos: Vector3 = line.call("get_rope_world_pos_at_t", progress)
	if not is_zip:
		# SlothCrawl wraps hands and shoes 0.616 m above the actor origin.
		return rope_pos - Vector3.UP * 0.616
	var direction: Vector3 = line.call("get_line_direction")
	var forward := Vector3(direction.x, 0.0, direction.z).normalized()
	# ZipGlide reaches forward to the handle suspended 0.76 m below the cable.
	return rope_pos - forward * 0.29 - Vector3.UP * 1.325


func _move_line_rider(progress: float, is_zip: bool, delta: float) -> bool:
	var target := _line_feet_at(_active_line, progress, is_zip)
	var settle_time := 0.08 if is_zip else 0.10
	if _line_time < settle_time:
		var settle_rate := 30.0 if is_zip else 24.0
		target = global_position.lerp(target, 1.0 - exp(-settle_rate * delta))
	if not try_move_traversal(target):
		_drop_from_parkour_line()
		velocity = Vector3.DOWN
		return false
	_active_line.call("set_rider_progress", progress)
	return true


func _update_rope_line(delta: float) -> void:
	if not is_instance_valid(_active_line):
		transition_to("Locomotion")
		return
	var line_dir: Vector3 = _active_line.call("get_line_direction")
	var line_xz := Vector3(line_dir.x, 0.0, line_dir.z).normalized()
	var move_in := chibi_input.move_vec if chibi_input else Vector2.ZERO
	var wish := Vector3.ZERO
	if move_in.length() > 0.1 and camera_ctrl != null:
		wish = camera_ctrl.get_right_xz() * move_in.x - camera_ctrl.get_forward_xz() * move_in.y
	var along := clampf(wish.dot(line_xz), -1.0, 1.0)
	var step_dir := 1.0 if along > 0.22 else (-1.0 if along < -0.22 else 0.0)

	_line_time += delta
	_rope_climb_sfx_timer -= delta
	if step_dir != 0.0:
		_line_facing_sign = step_dir

	_line_distance = clampf(_line_distance + step_dir * 0.92 * delta, 0.0, _line_length)

	# End-of-line dismount launch (matches Unreal UpdateRopeLine at 0.24 m from ends)
	if _line_distance <= 0.24 or _line_distance >= _line_length - 0.24:
		var exit_sign := 1.0 if _line_distance >= _line_length - 0.24 else -1.0
		_release_parkour_line()
		suppress_auto_roll = true
		line_cooldown = 0.50
		velocity = line_xz * (exit_sign * 2.10) + Vector3(0.0, 2.30, 0.0)
		add_flow_boost(0.08)
		if juice:
			juice.play_sfx("Jump")
		transition_to("Locomotion")
		_start_air_animation("RopeDrop", 0.28)
		return

	var t := clampf(_line_distance / _line_length, 0.0, 1.0)
	if not _move_line_rider(t, false, delta):
		return

	if absf(step_dir) > 0.5:
		_play_anim("RopeClimb")
		if _rope_climb_sfx_timer <= 0.0:
			_rope_climb_sfx_timer = 0.25
			if juice:
				juice.play_sfx("Shimmy")
	else:
		_play_anim("RopeHang")

	var face := line_xz * _line_facing_sign
	rotation.y = lerp_angle(rotation.y, atan2(-face.x, -face.z), 1.0 - exp(-18.0 * delta))


func _release_parkour_line() -> void:
	if is_instance_valid(_active_line) and _active_line.has_method("notify_rider_release"):
		_active_line.call("notify_rider_release")
	_active_line = null


func _drop_from_parkour_line() -> void:
	var was_on_zipline := current_state == "ZipLine"
	var drop_velocity := Vector3.ZERO
	if was_on_zipline and is_instance_valid(_active_line):
		var line_dir: Vector3 = _active_line.call("get_line_direction")
		drop_velocity = Vector3(line_dir.x, 0.0, line_dir.z) * _zip_speed
	_release_parkour_line()
	line_cooldown = 0.50
	suppress_auto_roll = true
	velocity = drop_velocity
	transition_to("Locomotion")
	if was_on_zipline:
		_play_anim("FallLoop")
	else:
		_start_air_animation("RopeDrop", 0.28)


func _jump_off_rope_line() -> void:
	_release_parkour_line()
	line_cooldown = 0.45
	var fwd := (-global_transform.basis.z).normalized()
	velocity = fwd * 3.2 + Vector3(0.0, 2.8, 0.0)
	transition_to("Locomotion")
	_start_air_animation("RopeDrop", 0.28)


func _update_zip_line(delta: float) -> void:
	if not is_instance_valid(_active_line):
		transition_to("Locomotion")
		return
	var line_dir: Vector3 = _active_line.call("get_line_direction")
	var line_xz := Vector3(line_dir.x, 0.0, line_dir.z).normalized()
	_line_time += delta
	_zip_speed = clampf(_zip_speed + 3.6 * delta, _zip_min, _zip_max)
	_line_distance += _zip_speed * delta
	var t := clampf(_line_distance / _line_length, 0.0, 1.0)
	if _line_distance >= _line_length - 0.36:
		_finish_zip_line(false)
		return
	if not _move_line_rider(t, true, delta):
		return
	rotation.y = lerp_angle(rotation.y, atan2(-line_xz.x, -line_xz.z), 1.0 - exp(-22.0 * delta))
	_play_anim("ZipGlide")


func _jump_off_zip_line() -> void:
	_finish_zip_line(true)


func _finish_zip_line(jumped_off: bool) -> void:
	var dir := (-global_transform.basis.z).normalized()
	if is_instance_valid(_active_line):
		var ld: Vector3 = _active_line.call("get_line_direction")
		dir = Vector3(ld.x, 0.0, ld.z).normalized()
	_release_parkour_line()
	line_cooldown = 0.50 if jumped_off else 0.55
	suppress_auto_roll = true
	# Exact Unreal JumpOffZipLine (0.85x + 4.40 m/s up) vs UpdateZipLine end dismount (0.72x + 1.90 m/s up)
	var fwd_mult := 0.85 if jumped_off else 0.72
	var up_vel := 4.40 if jumped_off else 1.90
	velocity = Vector3(dir.x * _zip_speed * fwd_mult, up_vel, dir.z * _zip_speed * fwd_mult)
	add_flow_boost(0.14 if jumped_off else 0.22)
	if juice:
		juice.trigger_squash(0.88 if jumped_off else 0.90, 1.18 if jumped_off else 1.14)
		juice.spawn_dust(global_position)
		juice.spawn_flow_sparkle(get_capsule_center())
		juice.play_sfx("Jump" if jumped_off else "Whee")
	transition_to("Locomotion")
	_start_air_animation("JumpStart", JUMP_POSE_DURATION, 0.62)


func try_enter_rope_swing(
	swing_node: Node3D,
	anchor_world: Vector3,
	rope_len: float,
	max_angle_deg: float,
	pump_accel: float,
	launch_boost_up: float
) -> bool:
	if swing_cooldown > 0.0 or current_state != "Locomotion":
		return false
	_swing_anchor = anchor_world
	_swing_length = maxf(0.8, rope_len)
	_swing_max_angle = deg_to_rad(max_angle_deg)
	_swing_pump_accel = pump_accel
	_swing_launch_boost_up = launch_boost_up
	_swing_time = 0.0

	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	_swing_plane_fwd = horiz.normalized() if horiz.length_squared() > 0.05 else (-global_transform.basis.z).normalized()

	var offset := get_capsule_center() - _swing_anchor
	var fwd_proj := offset.dot(_swing_plane_fwd)
	var down_proj := maxf(0.1, -offset.y)
	_swing_angle = clampf(atan2(fwd_proj, down_proj), -_swing_max_angle, _swing_max_angle)
	var rope_dir := _swing_plane_fwd * sin(_swing_angle) - Vector3.UP * cos(_swing_angle)
	var target := _swing_feet_at(rope_dir, _swing_angle + 0.42)
	if global_position.distance_to(target) > 0.70 or not traversal_segment_clear(global_position, target):
		return false
	_active_swing = swing_node
	var tangent := _swing_plane_fwd * cos(_swing_angle) + Vector3.UP * sin(_swing_angle)
	_swing_ang_vel = velocity.dot(tangent) / _swing_length
	velocity = Vector3.ZERO
	if _active_swing.has_method("set_ridden"):
		_active_swing.call("set_ridden", true)
	add_flow_boost(0.10)
	if juice:
		juice.play_sfx("LedgeGrab")
	_play_anim("RopeSwing")
	transition_to("RopeSwing")
	return true


func _update_rope_swing(delta: float) -> void:
	if not is_instance_valid(_active_swing):
		transition_to("Locomotion")
		return
	var move_in := chibi_input.move_vec if chibi_input else Vector2.ZERO
	var cam_fwd := camera_ctrl.get_forward_xz() if camera_ctrl else _swing_plane_fwd
	var cam_right := camera_ctrl.get_right_xz() if camera_ctrl else _swing_plane_fwd.cross(Vector3.UP).normalized()
	var wish := cam_right * move_in.x - cam_fwd * move_in.y
	var pump_in := clampf(wish.dot(_swing_plane_fwd), -1.0, 1.0)
	var plane_right := _swing_plane_fwd.cross(Vector3.UP).normalized()
	var steer_in := clampf(wish.dot(plane_right), -1.0, 1.0)
	_swing_plane_fwd = _swing_plane_fwd.rotated(Vector3.UP, deg_to_rad(-steer_in * 55.0 * delta)).normalized()

	var res := RopeSwingSolver.advance(
		delta, _swing_angle, _swing_ang_vel, _swing_length, pump_in, _swing_pump_accel, _swing_max_angle
	)
	_swing_angle = res.x
	_swing_ang_vel = res.y
	_swing_time += delta

	var rope_dir := _swing_plane_fwd * sin(_swing_angle) - Vector3.UP * cos(_swing_angle)
	var lean := _swing_angle + 0.42 + (pump_in * (0.14 if pump_in >= 0.0 else 0.07))
	var target_feet := _swing_feet_at(rope_dir, lean)
	if _swing_time < 0.08:
		target_feet = global_position.lerp(target_feet, 1.0 - exp(-32.0 * delta))
	if not try_move_traversal(target_feet):
		_release_rope_swing()
		_finish_traversal(Vector3.DOWN)
		return
	rotation.y = lerp_angle(rotation.y, atan2(-_swing_plane_fwd.x, -_swing_plane_fwd.z), 1.0 - exp(-24.0 * delta))
	if visual_pivot != null:
		visual_pivot.rotation = Vector3(lean, 0.0, 0.0)

	if pump_in > 0.25:
		_play_anim("RopeSwingFwd")
	elif pump_in < -0.25:
		_play_anim("RopeSwingBack")
	else:
		_play_anim("RopeSwing")

	if _active_swing.has_method("set_rope_world_direction"):
		_active_swing.call("set_rope_world_direction", rope_dir, _swing_plane_fwd)


func _swing_feet_at(rope_dir: Vector3, lean: float) -> Vector3:
	var knot := _swing_anchor + rope_dir * _swing_length
	var forward := _swing_plane_fwd * cos(lean) + Vector3.UP * sin(lean)
	var up := -_swing_plane_fwd * sin(lean) + Vector3.UP * cos(lean)
	return knot - forward * 0.41 - up * 0.74


func get_rope_swing_grip_weight() -> float:
	return smoothstep(0.03, 0.13, _swing_time) if current_state == "RopeSwing" else 0.0


func get_rope_swing_hand_target(side: int) -> Vector3:
	if not is_instance_valid(_active_swing) or not _active_swing is ParkourRopeSwing:
		return Vector3.INF
	return (_active_swing as ParkourRopeSwing).get_hand_grip_world(side)


func _release_rope_swing() -> void:
	if is_instance_valid(_active_swing) and _active_swing.has_method("set_ridden"):
		_active_swing.call("set_ridden", false)
	_active_swing = null
	swing_cooldown = 0.45
	suppress_auto_roll = true


func _jump_off_rope_swing() -> void:
	_release_rope_swing()
	var tangent := _swing_plane_fwd * cos(_swing_angle) + Vector3.UP * sin(_swing_angle)
	var lin_vel := tangent * (_swing_ang_vel * _swing_length)
	velocity = lin_vel + Vector3(0.0, _swing_launch_boost_up, 0.0)
	if juice:
		juice.play_sfx("Whee")
	transition_to("Locomotion")
	_start_air_animation("JumpStart", JUMP_POSE_DURATION, 0.62)


# ---------------------------------------------------------------------------
# DYNAMIC WALL CLIMBING
# ---------------------------------------------------------------------------
func is_wall_climbing() -> bool:
	return _wall_climb.phase != WallClimbMotion.Phase.IDLE


func _landed_on_climbing_lip() -> bool:
	for index in get_slide_collision_count():
		var hit := get_slide_collision(index)
		if hit.get_normal().y > 0.65 and WallClimbGeometry.owns_collider(hit.get_collider()):
			return true
	return false


func _try_mount_wall(direction: Vector3, manual: bool, grounded_approach: bool = false) -> bool:
	if _wall_climb_cooldown > 0.0 or pose_mod == null:
		return false
	if not manual and _wall_climb_probe_timer > 0.0:
		return false
	_wall_climb_probe_timer = 0.05
	if _wall_climb_rig != pose_mod:
		var offsets := pose_mod.get_wall_climb_limb_offsets()
		var lengths := pose_mod.get_wall_climb_limb_lengths()
		if offsets.size() != 4 or lengths.size() != 4:
			return false
		_wall_climb.setup(self, collision_shape, offsets, lengths, ChibiPoseModifier.WALL_CLIMB_BODY_INSET)
		_wall_climb_rig = pose_mod
	if not _wall_climb.try_attach(direction, manual, grounded_approach):
		return false
	_set_world_collision(true)
	velocity = Vector3.ZERO
	coyote_timer = 0.0
	jump_buffer_timer = 0.0
	super_bounce_grace_timer = 0.0
	_air_wall_approach = Vector3.ZERO
	if anim_ctrl != null:
		anim_ctrl.set_locomotion_gait(0.0, config, 0.2)
	var normal: Vector3 = _wall_climb.frame.z
	if camera_ctrl != null:
		camera_ctrl.set_climbing_camera(true, normal, 17.0)
	transition_to("Climbing")
	if state_chart != null:
		state_chart.send_event("to_climb_wall")
	return true


func _update_wall_climb(delta: float) -> void:
	var move := chibi_input.move_vec if chibi_input != null else Vector2.ZERO
	if chibi_input != null and chibi_input.jump_just_pressed:
		move = Vector2.ZERO
	var before := _wall_climb.phase
	var climbing_up := move.y < -WallClimbMotion.MIN_DIRECTION
	if before == WallClimbMotion.Phase.HOLD and climbing_up and _try_start_wall_mantle(true):
		return
	var wall_normal_before: Vector3 = _wall_climb.frame.z
	var previous_contacts := _wall_climb.contacts
	var result := _wall_climb.tick(move, delta)
	if result == WallClimbMotion.Result.FALL:
		_drop_from_wall(_wall_climb.outward_velocity)
		return
	if before != WallClimbMotion.Phase.JUMP and _wall_climb.phase == WallClimbMotion.Phase.JUMP:
		_wall_upward_leap = climbing_up
		_play_wall_climb_jump_pose()
	if before != WallClimbMotion.Phase.CORNER and _wall_climb.phase == WallClimbMotion.Phase.CORNER:
		if juice != null and _wall_climb.has_route_profile():
			juice.play_tower_foley("TowerCloth", global_position + Vector3.UP * 0.8, -19.0)
	var normal := _wall_climb.get_presentation_normal()
	var turning_corner := before == WallClimbMotion.Phase.CORNER or _wall_climb.phase == WallClimbMotion.Phase.CORNER
	if camera_ctrl != null and (turning_corner or wall_normal_before.dot(normal) < 0.999):
		camera_ctrl.set_climbing_camera(true, normal, 17.0)
	var facing_yaw := atan2(normal.x, normal.z)
	rotation.y = facing_yaw if turning_corner else lerp_angle(rotation.y, facing_yaw, 1.0 - exp(-20.0 * delta))
	velocity = _wall_climb.outward_velocity
	if pose_mod != null:
		_wall_climb.present(pose_mod)
	if result == WallClimbMotion.Result.CAUGHT:
		if juice != null:
			if _wall_climb.has_route_profile():
				_play_tower_catch_foley(before, previous_contacts)
			else:
				juice.play_sfx("LedgeGrab", 0.03)
		var caught_upward_leap := before == WallClimbMotion.Phase.JUMP and _wall_upward_leap
		_wall_upward_leap = false
		if (climbing_up or caught_upward_leap) and _try_start_wall_mantle(true):
			return
		if _wall_jump_buffer > 0.0:
			_begin_wall_climb_jump(_wall_jump_direction)


func _play_tower_catch_foley(phase: int, previous_contacts: Array[Dictionary]) -> void:
	var light_catch := phase == WallClimbMotion.Phase.REACH or phase == WallClimbMotion.Phase.CORNER
	juice.play_tower_foley("Shimmy" if light_catch else "LedgeGrab", _wall_climb._hand_center(), -7.0)
	# The completed stance can keep an old shoe planted or leave it free.
	for limb in range(2, 4):
		var contact := _wall_climb.contacts[limb]
		if contact.is_empty():
			continue
		var point: Vector3 = contact["point"]
		var previous := previous_contacts[limb]
		if previous.is_empty() or point.distance_squared_to(previous["point"]) > 0.0009:
			juice.play_tower_foley("Step2", point, -13.0)
			break


func _request_wall_climb_jump() -> void:
	var direction := chibi_input.move_vec if chibi_input != null else Vector2.ZERO
	if _wall_climb.phase == WallClimbMotion.Phase.ATTACH or _wall_climb.phase == WallClimbMotion.Phase.REACH or _wall_climb.phase == WallClimbMotion.Phase.CORNER:
		_wall_jump_buffer = 0.20
		_wall_jump_direction = direction
		return
	_begin_wall_climb_jump(direction)


func _begin_wall_climb_jump(direction: Vector2) -> void:
	_wall_jump_buffer = 0.0
	var climbing_up := direction.length() <= 0.27 or direction.y < -0.42
	if climbing_up and _try_start_wall_mantle():
		return
	if _wall_climb.try_jump(direction):
		_wall_upward_leap = climbing_up
		_play_wall_climb_jump_pose()


func _try_start_wall_mantle(summit_only: bool = false) -> bool:
	var lip := _wall_climb.find_mantle_edge(summit_only)
	if lip.is_empty():
		return false
	ledge_edge_point = lip["edge"]
	ledge_wall_normal = _wall_climb.frame.z
	_mantle_start = global_position
	_mantle_lift = lip["lift"]
	_mantle_end = lip["landing"]
	_wall_mantle_active = true
	_begin_mantle()
	return true


func _play_wall_climb_jump_pose() -> void:
	var tower_leap_duration := _wall_climb.get_tower_leap_duration()
	var clip_duration := tower_leap_duration if tower_leap_duration > 0.0 else 0.40
	_play_action("JumpStart", clip_duration, 0.10, 0.72)
	if tower_leap_duration > 0.0 and juice != null:
		juice.play_tower_foley("TowerCloth", global_position + Vector3.UP * 0.8, -17.0)


func _clear_wall_climb(keep_camera: bool) -> void:
	_wall_climb.reset()
	_wall_jump_buffer = 0.0
	_wall_upward_leap = false
	if pose_mod != null:
		pose_mod.clear_wall_climb_pose()
	if not keep_camera and camera_ctrl != null:
		camera_ctrl.set_climbing_camera(false)


func _drop_from_wall(exit_velocity: Vector3) -> void:
	var push := exit_velocity if exit_velocity.length_squared() > 0.01 else _wall_climb.frame.z * 0.55
	transition_to("Locomotion")
	velocity = push
	air_time = 0.0
	coyote_timer = 0.0
	_wall_climb_cooldown = 0.36
	ledge_grab_cooldown = maxf(ledge_grab_cooldown, 0.36)
	wall_run_cooldown = maxf(wall_run_cooldown, 0.26)


# ---------------------------------------------------------------------------
# EXTERNAL STATION HOOKS (POOL)
# ---------------------------------------------------------------------------
func get_active_water() -> WaterBody3D:
	return _active_water_body if is_instance_valid(_active_water_body) else null


func set_active_water_body(water_body: WaterBody3D) -> void:
	_active_water_body = water_body if is_instance_valid(water_body) else null
	_pool_surface_y = _active_water_body.get_surface_height() if _active_water_body != null else 0.0


func enter_pool_swim(water_body: WaterBody3D, surface_y: float) -> void:
	set_active_water_body(water_body)
	_pool_surface_y = surface_y
	_swim_recovery_time = 0.0
	# Preserve the last grounded stride. Swim acceleration takes over from this velocity.
	was_falling = false
	peak_fall_speed = 0.0
	air_time = 0.0
	coyote_timer = 0.0
	transition_to("PoolSwim")


func update_pool_swim_visuals(
	surface_y: float, surface_weight: float, tread_weight: float, swim_pitch_deg: float,
	speed_ratio: float, turn: float, dive: float, rise: float, glide: float
) -> void:
	_pool_surface_y = surface_y
	_pool_underwater_weight = 1.0 - surface_weight
	if anim_ctrl:
		var cadence := 0.46 + 0.70 * clampf(speed_ratio, 0.0, 1.0)
		anim_ctrl.set_swim_blend(surface_weight, tread_weight, cadence, glide)
		current_anim_label = "Swim"
	if pose_mod != null:
		pose_mod.set_swim_pose(turn, dive, rise, glide)
	if visual_pivot != null:
		var pivot := Vector3(0.0, 0.52, 0.0)
		var tilt := Basis(Vector3.RIGHT, deg_to_rad(swim_pitch_deg))
		tilt *= Basis(Vector3.BACK, deg_to_rad(8.0 * turn))
		var origin := pivot + tilt * (_visual_rest_transform.origin - pivot)
		visual_pivot.transform = Transform3D(tilt * _visual_rest_transform.basis, origin)


func exit_pool_swim(clear_active_water: bool = true) -> void:
	if clear_active_water:
		set_active_water_body(null)
	_pool_underwater_weight = 0.0
	if visual_pivot != null:
		_swim_exit_pose = visual_pivot.transform
		_swim_recovery_time = ChibiAnimController.SWIM_GAIT_BLEND_TIME
	transition_to("Locomotion")


func _update_swim_recovery(delta: float) -> void:
	if _swim_recovery_time <= 0.0:
		return
	_swim_recovery_time = maxf(0.0, _swim_recovery_time - delta)
	if current_state != "Locomotion":
		_swim_recovery_time = 0.0
		return
	var weight := 1.0 - _swim_recovery_time / ChibiAnimController.SWIM_GAIT_BLEND_TIME
	visual_pivot.transform = _swim_exit_pose.interpolate_with(_visual_rest_transform, smoothstep(0.0, 1.0, weight))


func try_climb_out_of_pool() -> bool:
	if ledge_grab_cooldown > 0.0:
		return false
	var ledge := _find_ledge()
	if ledge.is_empty() or not _try_ledge_mantle(ledge["edge"], ledge["normal"]):
		return false
	add_flow_boost(0.06)
	set_active_water_body(null)
	_pool_underwater_weight = 0.0
	if visual_pivot != null:
		visual_pivot.transform = _visual_rest_transform
	return true


# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------
func _sync_pose_modifier(delta: float) -> void:
	if pose_mod == null:
		return
	pose_mod.parkour_state = current_state
	pose_mod.ledge_edge_world = ledge_edge_point
	pose_mod.ledge_wall_normal_world = ledge_wall_normal
	pose_mod.mantle_alpha = mantle_alpha
	pose_mod.vault_alpha = _vault_alpha
	pose_mod.shimmy_start_edge = shimmy_start_edge
	pose_mod.shimmy_end_edge = shimmy_end_edge
	pose_mod.shimmy_phase = shimmy_phase
	pose_mod.wade_weight_target = _swim_controller.get_wade_pose_weight() if current_state == "Locomotion" and is_on_floor() else 0.0
	var water := get_active_water()
	if is_instance_valid(water):
		pose_mod.wade_surface_y = water.get_surface_height()
	pose_mod.update_ledge_targets(delta)
	pose_mod.update_ground_targets(delta)


func _play_anim(key: String) -> void:
	current_anim_label = key
	if anim_ctrl != null:
		anim_ctrl.play_state(key)


func _play_action(key: String, duration: float, xfade: float = 0.065, clip_fraction: float = 1.0) -> void:
	current_anim_label = key
	if anim_ctrl != null:
		anim_ctrl.play_action(key, duration, xfade, clip_fraction)


func _start_air_animation(key: String, duration: float, clip_fraction: float = 1.0) -> void:
	_air_anim_timer = duration
	land_anim_timer = 0.0
	_play_action(key, duration, 0.055, clip_fraction)


static func _quad_bezier(a: Vector3, b: Vector3, c: Vector3, t: float) -> Vector3:
	return a.lerp(b, t).lerp(b.lerp(c, t), t)
