extends Node

## Persisted player settings applied to audio, input, and the active viewport.

signal setting_changed(key: StringName, value: Variant)

const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "game"
const QUALITY_LABELS := ["Low", "Medium", "High", "Ultra"]
const QUALITY_VIEWPORT_SCALE := [0.70, 0.85, 1.0, 1.15]
const QUALITY_MSAA := [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_2X, Viewport.MSAA_4X]
const ULTRA_SHADOW_DISTANCE_MULTIPLIER := 1.5
const DIRECTIONAL_SHADOW_FILTER_SETTING := "rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"
const POSITIONAL_SHADOW_FILTER_SETTING := "rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality"

var master_volume: float = 1.0
var music_volume: float = 1.0
var sfx_volume: float = 1.0
var sensitivity: float = 1.0
var invert_y: bool = false
var quality: int = 2

var _light_shadow_defaults: Dictionary[int, bool] = {}
var _directional_shadow_distance_defaults: Dictionary[int, float] = {}
var _directional_high_filter_quality: int = RenderingServer.SHADOW_QUALITY_SOFT_HIGH
var _positional_high_filter_quality: int = RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM


func _ready() -> void:
	_load_settings()
	_directional_high_filter_quality = _get_project_shadow_filter_quality(DIRECTIONAL_SHADOW_FILTER_SETTING, _directional_high_filter_quality)
	_positional_high_filter_quality = _get_project_shadow_filter_quality(POSITIONAL_SHADOW_FILTER_SETTING, _positional_high_filter_quality)
	_apply_all()
	get_tree().scene_changed.connect(_on_scene_changed)


func set_setting(key: StringName, value: Variant) -> bool:
	var previous: Variant
	match key:
		&"master_volume":
			previous = master_volume
			master_volume = clampf(float(value), 0.0, 1.0)
		&"music_volume":
			previous = music_volume
			music_volume = clampf(float(value), 0.0, 1.0)
		&"sfx_volume":
			previous = sfx_volume
			sfx_volume = clampf(float(value), 0.0, 1.0)
		&"sensitivity":
			previous = sensitivity
			sensitivity = clampf(float(value), 0.5, 2.0)
		&"invert_y":
			previous = invert_y
			invert_y = bool(value)
		&"quality":
			previous = quality
			quality = clampi(int(value), 0, QUALITY_LABELS.size() - 1)
		_:
			return false
	var current: Variant = get(key)
	if _same_setting_value(previous, current):
		return true
	_apply_setting(key)
	_persist_settings()
	setting_changed.emit(key, current)
	return true


func get_quality_label() -> String:
	return QUALITY_LABELS[clampi(quality, 0, QUALITY_LABELS.size() - 1)]


func _same_setting_value(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_FLOAT and typeof(b) == TYPE_FLOAT:
		return is_equal_approx(a, b)
	return a == b


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	master_volume = clampf(float(config.get_value(SETTINGS_SECTION, "master_volume", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(config.get_value(SETTINGS_SECTION, "music_volume", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(config.get_value(SETTINGS_SECTION, "sfx_volume", sfx_volume)), 0.0, 1.0)
	sensitivity = clampf(float(config.get_value(SETTINGS_SECTION, "sensitivity", sensitivity)), 0.5, 2.0)
	invert_y = bool(config.get_value(SETTINGS_SECTION, "invert_y", invert_y))
	quality = clampi(int(config.get_value(SETTINGS_SECTION, "quality", quality)), 0, QUALITY_LABELS.size() - 1)


func _persist_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(SETTINGS_SECTION, "master_volume", master_volume)
	config.set_value(SETTINGS_SECTION, "music_volume", music_volume)
	config.set_value(SETTINGS_SECTION, "sfx_volume", sfx_volume)
	config.set_value(SETTINGS_SECTION, "sensitivity", sensitivity)
	config.set_value(SETTINGS_SECTION, "invert_y", invert_y)
	config.set_value(SETTINGS_SECTION, "quality", quality)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save game settings: %s" % error_string(error))


func _apply_all() -> void:
	_apply_audio()
	_apply_camera_settings()
	_apply_graphics()


func _apply_setting(key: StringName) -> void:
	match key:
		&"master_volume", &"music_volume", &"sfx_volume":
			_apply_audio()
		&"sensitivity", &"invert_y":
			_apply_camera_settings()
		&"quality":
			_apply_graphics()


func _apply_audio() -> void:
	_set_bus_volume(&"Master", master_volume)
	_set_bus_volume(&"Music", music_volume)
	_set_bus_volume(&"SFX", sfx_volume)


func _set_bus_volume(bus_name: StringName, linear_volume: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(linear_volume, 0.0001)))
	AudioServer.set_bus_mute(bus_index, is_zero_approx(linear_volume))


func _apply_camera_settings() -> void:
	for input_node in get_tree().get_nodes_in_group(&"chibi_input"):
		if is_instance_valid(input_node) and input_node.has_method("set_camera_settings"):
			input_node.call("set_camera_settings", sensitivity, invert_y)


func _apply_graphics() -> void:
	quality = clampi(quality, 0, QUALITY_LABELS.size() - 1)
	var viewport := get_viewport()
	if viewport != null:
		viewport.scaling_3d_scale = QUALITY_VIEWPORT_SCALE[quality]
		viewport.msaa_3d = QUALITY_MSAA[quality]
	RenderingServer.directional_soft_shadow_filter_set_quality(_shadow_filter_for_quality(_directional_high_filter_quality))
	RenderingServer.positional_soft_shadow_filter_set_quality(_shadow_filter_for_quality(_positional_high_filter_quality))
	if get_tree().current_scene != null:
		_apply_scene_shadow_quality(get_tree().current_scene)


func _get_project_shadow_filter_quality(setting_name: String, fallback: int) -> int:
	var value: Variant = ProjectSettings.get_setting_with_override(setting_name)
	if value == null:
		return fallback
	return clampi(int(value), RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_MAX - 1)


func _shadow_filter_for_quality(high_quality: int) -> int:
	match quality:
		0:
			return RenderingServer.SHADOW_QUALITY_SOFT_LOW
		1:
			return maxi(RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, high_quality - 1)
		2:
			return high_quality
		_:
			return RenderingServer.SHADOW_QUALITY_SOFT_ULTRA


func _apply_scene_shadow_quality(node: Node) -> void:
	if node is Light3D:
		var light := node as Light3D
		var instance_id := light.get_instance_id()
		if not _light_shadow_defaults.has(instance_id):
			_light_shadow_defaults[instance_id] = light.shadow_enabled
		light.shadow_enabled = bool(_light_shadow_defaults[instance_id]) and quality > 0
		if light is DirectionalLight3D:
			var directional_light := light as DirectionalLight3D
			if not _directional_shadow_distance_defaults.has(instance_id):
				_directional_shadow_distance_defaults[instance_id] = directional_light.directional_shadow_max_distance
			var authored_distance: float = _directional_shadow_distance_defaults[instance_id]
			var multiplier := ULTRA_SHADOW_DISTANCE_MULTIPLIER if quality == 3 else 1.0
			directional_light.directional_shadow_max_distance = authored_distance * multiplier
	for child in node.get_children():
		_apply_scene_shadow_quality(child)


func _on_scene_changed() -> void:
	_light_shadow_defaults.clear()
	_directional_shadow_distance_defaults.clear()
	call_deferred("_apply_graphics")
