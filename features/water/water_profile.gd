extends Resource
class_name WaterProfile

## Shared appearance and lightweight behavior settings for a WaterBody3D.

@export_group("Underwater camera tint")
@export var underwater_color: Color = Color(0.06, 0.42, 0.48, 1.0)
@export_range(0.5, 40.0, 0.1, "or_greater") var visibility_distance: float = 10.0

@export_group("Surface")
@export var shallow_color: Color = Color(0.42, 0.94, 0.88, 1.0)
@export var deep_color: Color = Color(0.04, 0.52, 0.64, 1.0)
@export var foam_color: Color = Color(0.92, 1.0, 0.94, 1.0)
@export_range(0.0, 1.0, 0.01) var surface_opacity: float = 0.34
@export_range(0.0, 0.04, 0.001) var wave_height: float = 0.008
@export_range(0.0, 0.03, 0.001) var refraction_strength: float = 0.005
@export_range(0.05, 2.0, 0.01) var shoreline_width: float = 0.32

@export_group("Warm caustics")
@export var caustic_color: Color = Color(1.0, 0.78, 0.39, 1.0)
@export_range(0.0, 2.0, 0.01) var caustic_strength: float = 0.62
@export_range(0.1, 8.0, 0.05) var caustic_scale: float = 1.8
@export_range(0.0, 2.0, 0.01) var caustic_speed: float = 0.22
@export_range(0.05, 1.0, 0.01) var caustic_shore_fade: float = 0.7

@export_group("Small water effects")
@export var ripple_color: Color = Color(0.77, 1.0, 0.94, 0.74)
@export var bubble_color: Color = Color(0.76, 1.0, 0.99, 0.88)
@export_range(0.2, 4.0, 0.05) var bubble_rise_speed: float = 1.25
