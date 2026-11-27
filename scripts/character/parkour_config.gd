class_name ParkourConfig
extends Resource

## Meter-converted tuning constants ported 1:1 from Unreal AC_ParkourComponent & ChibiContact.

@export_group("Capsule & Locomotion")
@export var capsule_radius: float = 0.28
@export var capsule_height: float = 1.20
@export var slide_capsule_height: float = 0.60
@export var gravity: float = 16.17 ## Unreal 9.8 * GravityScale 1.65
@export var jump_velocity: float = 4.80
@export var air_control: float = 0.65
@export var ground_accel: float = 22.0 ## Unreal MaxAcceleration 2200 cm/s^2
@export var ground_decel: float = 24.0 ## Unreal BrakingDecelerationWalking 2400 cm/s^2
@export var ground_directional_friction: float = 8.0
@export var ground_turn_rate_deg: float = 720.0
@export var air_decel: float = 15.0 ## Unreal BrakingDecelerationFalling 1500 cm/s^2
@export var max_step_height: float = 0.35
@export var walkable_floor_angle_deg: float = 45.0

@export_group("Flow")
@export var base_run_speed: float = 4.80
@export var max_flow_speed: float = 7.80
@export var flow_build_rate: float = 0.28
@export var flow_decay_rate: float = 0.48
@export var sprint_anim_threshold: float = 5.40
@export var run_anim_threshold: float = 0.35

@export_group("Feel & Buffers")
@export var coyote_time_duration: float = 0.15
@export var jump_buffer_duration: float = 0.22
@export var flail_fall_speed_threshold: float = -4.80
@export var flail_air_time_threshold: float = 0.55
@export var soft_land_anim_duration: float = 0.22

@export_group("Scarf Glide")
@export var scarf_glide_deploy_duration: float = 0.34
@export var scarf_glide_stow_duration: float = 0.30
@export var scarf_glide_cancel_duration: float = 0.20
@export var scarf_glide_terminal_speed: float = 2.40
@export var scarf_glide_steer_speed: float = 4.40
@export var scarf_glide_steer_accel: float = 5.50
@export var scarf_glide_coast_decel: float = 0.55
@export var scarf_glide_max_drag_ratio: float = 1.60
@export var scarf_glide_floor_buffer: float = 0.48
@export var scarf_glide_headroom: float = 0.95
@export var scarf_glide_bank_response: float = 8.0

@export_group("Camera (Phantom Camera)")
## Godot KEEP_HEIGHT uses vertical FOV. Unreal's 90–102 horizontal is 59–70 at 16:9.
@export var base_fov: float = 59.0
@export var max_flow_fov: float = 69.5
@export var base_arm_length: float = 2.30
@export var max_flow_arm_length: float = 2.55
@export var fall_arm_length: float = 2.65
@export var base_shoulder_offset_x: float = 0.24
@export var base_socket_offset_y: float = 0.94 ## 0.60 capsule center + 0.34 Unreal socket Z
@export var camera_pos_lag_speed: float = 12.0
@export var wall_run_camera_roll_deg: float = 3.0

@export_group("Speed Vault")
@export var vault_detect_distance: float = 1.25
@export var vault_min_height: float = 0.10
@export var vault_max_height: float = 1.18
@export var vault_clearance_depth: float = 1.35
@export var vault_base_duration: float = 0.80
@export var vault_flow_boost: float = 0.20

@export_group("Ledge & Mantle")
@export var ledge_detect_distance: float = 0.64
@export var ledge_shimmy_speed: float = 0.58
@export var ledge_shimmy_step_duration: float = 0.60
@export var ledge_corner_duration: float = 0.56
@export var mantle_base_duration: float = 0.88
@export var ledge_flow_boost: float = 0.16

@export_group("Wall Run & Kick")
@export var wall_run_entry_distance: float = 0.52 ## Maximum horizontal gap from capsule center to wall.
@export var wall_run_entry_min_speed: float = 3.20
@export var wall_run_entry_min_input: float = 0.55 ## Movement input projected along the wall.
@export var wall_run_entry_window: float = 0.65
@export var wall_run_detect_distance: float = 0.68
@export var wall_run_base_speed: float = 4.20
@export var wall_run_max_duration: float = 2.20
@export var wall_kick_up_force: float = 5.40
@export var wall_kick_side_force: float = 4.40
@export var wall_run_flow_boost: float = 0.18

@export_group("Slide & Land Roll")
@export var slide_min_speed: float = 2.40
@export var slide_boost_speed: float = 6.80
@export var slide_duration: float = 0.85
@export var slide_flow_boost: float = 0.12
@export var roll_min_fall_speed: float = -4.60
@export var auto_roll_fall_speed: float = -8.60
@export var roll_buffer_window: float = 0.38
@export var roll_duration: float = 0.80
@export var roll_speed: float = 5.20
@export var roll_flow_boost: float = 0.22

@export_group("Juice")
@export var squash_return_speed: float = 14.0
