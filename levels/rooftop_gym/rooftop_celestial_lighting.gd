extends Node

const PRESETS: Array[Dictionary] = [
	{
		"label": "Dawn", "hour": 5.75, "sun_angles": Vector2(-24.0, 9.0),
		"zenith": Color("#767fba"), "horizon": Color("#efa897"),
		"cloud_tint": Vector3(0.92, 0.61, 0.61),
		"sun_color": Color("#ffb88e"), "sun_energy": 0.93,
		"ambient": Color("#dccee9"), "ambient_energy": 0.54, "fill": 0.22,
	},
	{
		"label": "Day", "hour": 9.0, "sun_angles": Vector2(-18.0, 29.0),
		"zenith": Color("#8ccada"), "horizon": Color("#f5dbbb"),
		"cloud_tint": Vector3(1.0, 0.91, 0.83),
		"sun_color": Color("#ffe6bd"), "sun_energy": 1.18,
		"ambient": Color("#e1eaf7"), "ambient_energy": 0.59, "fill": 0.26,
	},
	{
		"label": "Noon", "hour": 12.0, "sun_angles": Vector2(5.0, 55.0),
		"zenith": Color("#71bddb"), "horizon": Color("#e4f1db"),
		"cloud_tint": Vector3(0.92, 0.97, 1.04),
		"sun_color": Color("#fff5df"), "sun_energy": 1.19,
		"ambient": Color("#e7f1ff"), "ambient_energy": 0.58, "fill": 0.26,
	},
	{
		"label": "Dusk", "hour": 18.5, "sun_angles": Vector2(24.0, 9.0),
		"zenith": Color("#746b9c"), "horizon": Color("#ef9e85"),
		"cloud_tint": Vector3(0.93, 0.55, 0.51),
		"sun_color": Color("#ffa26e"), "sun_energy": 0.88,
		"ambient": Color("#d3bbdf"), "ambient_energy": 0.48, "fill": 0.19,
	},
	{
		"label": "Night", "hour": 22.0, "sun_angles": Vector2(95.0, -32.0),
		"zenith": Color("#202e59"), "horizon": Color("#56628c"),
		"cloud_tint": Vector3(0.065, 0.10, 0.22),
		"sun_color": Color("#ffa26e"), "sun_energy": 0.0,
		"ambient": Color("#aebce8"), "ambient_energy": 0.38, "fill": 0.09,
	},
]
const MOON_COLOR := Color("#b9cfff")
const FULL_MOON_ENERGY := 0.43
const PREVIEW_SHADER := preload("res://levels/rooftop_gym/shaders/rooftop_celestial_sky.gdshader")

var _environment: Environment
var _authored_sky_material: ShaderMaterial
var _preview_sky_material: ShaderMaterial
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _camera: ChibiCameraController
var _authored_environment: Environment
var _authored_sun_basis: Basis
var _authored_sun_color: Color
var _authored_sun_energy: float
var _authored_fill_energy: float


func setup(world: WorldEnvironment, sun: DirectionalLight3D, fill: DirectionalLight3D, camera: ChibiCameraController) -> void:
	_authored_environment = world.environment
	_environment = _authored_environment.duplicate() as Environment
	_environment.sky = _authored_environment.sky.duplicate() as Sky
	_authored_sky_material = _environment.sky.sky_material as ShaderMaterial
	_preview_sky_material = ShaderMaterial.new()
	_preview_sky_material.shader = PREVIEW_SHADER
	for uniform in _authored_sky_material.shader.get_shader_uniform_list():
		var value: Variant = _authored_sky_material.get_shader_parameter(uniform.name)
		if value != null:
			_preview_sky_material.set_shader_parameter(uniform.name, value)
	world.environment = _environment
	_sun = sun
	_fill = fill
	_camera = camera
	_authored_sun_basis = sun.basis
	_authored_sun_color = sun.light_color
	_authored_sun_energy = sun.light_energy
	_authored_fill_energy = fill.light_energy


static func moon_fraction(phase: float) -> float:
	return clampf(0.5 - 0.5 * cos(TAU * phase), 0.0, 1.0)


func apply_preview(hour: float, phase: float) -> void:
	hour = fposmod(hour, 24.0)
	var start := PRESETS.back() as Dictionary
	var end := PRESETS.front() as Dictionary
	var start_hour := float(start.hour)
	var end_hour := float(end.hour) + 24.0
	var sample_hour := hour + 24.0 if hour < float(end.hour) else hour
	for index in range(1, PRESETS.size()):
		if hour < float(PRESETS[index - 1].hour) or hour >= float(PRESETS[index].hour):
			continue
		start = PRESETS[index - 1]
		end = PRESETS[index]
		start_hour = float(start.hour)
		end_hour = float(end.hour)
		break

	var weight := smoothstep(start_hour, end_hour, sample_hour)
	var angles: Vector2 = (start.sun_angles as Vector2).lerp(end.sun_angles, weight)
	var sun_direction := _sky_direction(angles)
	var moon_track := (hour - 22.0) * TAU / 24.0
	var moon_altitude := 38.0 * cos(moon_track) - 7.0
	var moon_direction := _sky_direction(Vector2(16.0 + 46.0 * sin(moon_track), moon_altitude))
	var solar_visibility := smoothstep(-3.0, 4.0, angles.y)
	var night := 1.0 - smoothstep(-9.0, -3.0, angles.y)
	var lunar_visibility := smoothstep(-3.0, 8.0, moon_altitude) * night
	var moonlight := FULL_MOON_ENERGY * pow(moon_fraction(phase), 1.25) * lunar_visibility
	var sunlight := lerpf(start.sun_energy, end.sun_energy, weight) * solar_visibility
	# Fade sunlight out before moonlight comes in, and reuse its shadow map.
	var use_moon := angles.y < -3.0
	var key_direction := moon_direction if use_moon else sun_direction
	_sun.basis = Basis.looking_at(-key_direction)
	_sun.light_color = MOON_COLOR if use_moon else (start.sun_color as Color).lerp(end.sun_color, weight)
	_sun.light_energy = moonlight if use_moon else sunlight
	_fill.light_energy = lerpf(start.fill, end.fill, weight)

	_environment.ambient_light_color = (start.ambient as Color).lerp(end.ambient, weight)
	_environment.ambient_light_energy = lerpf(start.ambient_energy, end.ambient_energy, weight)
	var horizon: Color = (start.horizon as Color).lerp(end.horizon, weight)
	var zenith: Color = (start.zenith as Color).lerp(end.zenith, weight)
	_environment.fog_light_color = horizon
	_sync_water_lighting()

	var cloud_tint: Vector3 = (start.cloud_tint as Vector3).lerp(end.cloud_tint, weight)
	cloud_tint *= 1.0 + moonlight * 1.2
	RenderingServer.global_shader_parameter_set(&"rooftop_sky_key", key_direction)
	RenderingServer.global_shader_parameter_set(&"rooftop_sky_sun", Vector4(sun_direction.x, sun_direction.y, sun_direction.z, solar_visibility))
	RenderingServer.global_shader_parameter_set(&"rooftop_sky_moon", Vector4(moon_direction.x, moon_direction.y, moon_direction.z, phase))
	RenderingServer.global_shader_parameter_set(&"rooftop_sky_cloud", Vector4(cloud_tint.x, cloud_tint.y, cloud_tint.z, lunar_visibility))
	RenderingServer.global_shader_parameter_set(&"rooftop_sky_zenith", _linear_color(zenith))
	RenderingServer.global_shader_parameter_set(&"rooftop_sky_horizon", _linear_color(horizon))
	if _environment.sky.sky_material != _preview_sky_material:
		_environment.sky.sky_material = _preview_sky_material


func restore_authored() -> void:
	_environment.sky.sky_material = _authored_sky_material
	_sun.basis = _authored_sun_basis
	_sun.light_color = _authored_sun_color
	_sun.light_energy = _authored_sun_energy
	_fill.light_energy = _authored_fill_energy
	_environment.ambient_light_color = _authored_environment.ambient_light_color
	_environment.ambient_light_energy = _authored_environment.ambient_light_energy
	_environment.fog_light_color = _authored_environment.fog_light_color
	_sync_water_lighting()


func _sync_water_lighting() -> void:
	if is_instance_valid(_camera):
		_camera.sync_water_ambient_lighting()


static func _sky_direction(angles: Vector2) -> Vector3:
	var yaw := deg_to_rad(angles.x)
	var elevation := deg_to_rad(angles.y)
	return Vector3(sin(yaw) * cos(elevation), sin(elevation), -cos(yaw) * cos(elevation))


static func _linear_color(color: Color) -> Vector4:
	var linear := color.srgb_to_linear()
	return Vector4(linear.r, linear.g, linear.b, 0.0)
