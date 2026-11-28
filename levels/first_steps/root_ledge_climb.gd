extends Node3D

## Climb data for the valley's single-face exposed-root ledge route.

const WallClimbCapability := preload("res://features/runner/climbing/wall_climb_capability.gd")

var _capability: WallClimbCapability


func _ready() -> void:
	add_to_group("climbable_wall")


func get_climb_capability() -> WallClimbCapability:
	if _capability == null:
		_capability = WallClimbCapability.new()
		_capability.summit_marker = get_node_or_null("../ShelfLanding") as Marker3D
		_capability.summit_group = &"root_ledge_summit"
		_capability.summit_height_tolerance = 0.42
		_capability.roof_reach = 0.34
		var short_leap := WallClimbCapability.LeapProfile.new()
		short_leap.stride = 0.48
		short_leap.search_radius = 0.54
		short_leap.min_forward_up = 0.24
		short_leap.min_forward_down = 0.24
		short_leap.max_forward = 0.86
		short_leap.max_side_lateral = 0.24
		short_leap.max_side_cardinal = 0.24
		short_leap.short_side_hop = true
		_capability.short_side_leap = short_leap
		_capability.leap_profiles = [
			_make_leap_profile(0.66, 0.92),
			_make_leap_profile(0.88, 1.24),
			_make_leap_profile(1.20, 1.60),
		]
	return _capability


func _make_leap_profile(stride: float, max_forward: float) -> WallClimbCapability.LeapProfile:
	var profile := WallClimbCapability.LeapProfile.new()
	profile.stride = stride
	profile.search_radius = 0.72
	profile.min_forward_up = 0.37
	profile.min_forward_down = 0.22
	profile.max_forward = max_forward
	profile.max_side_lateral = 0.24
	profile.max_side_cardinal = 0.70
	return profile
