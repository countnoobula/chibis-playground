extends SceneTree

const SOURCE_ROOT := "res://assets/environment/woodland/textures"
const OUTPUT_ROOT := "res://levels/first_steps/terrain/materials"
const OUTPUT_SIZE := 1024
const HEIGHT_LOW_PERCENTILE := 0.05
const HEIGHT_HIGH_PERCENTILE := 0.95
const HEIGHT_MODE_FLAT := 0
const HEIGHT_MODE_PALE_PETALS := 1
const HEIGHT_MODE_STEPPING_STONES := 2
const PETAL_BLUE_MIN := 90.0 / 255.0
const PETAL_BRIGHTNESS_MIN := 155.0 / 255.0
const PETAL_CHROMA_MAX := 65.0 / 255.0
const PETAL_MIN_COMPONENT_PIXELS := 4
const PETAL_TOP_ALPHA := 0.78
const STONE_GROUT_SOURCE_MAX := 0.16
const STONE_TOP_SOURCE_MIN := 0.50
const STONE_CROWN_SOURCE_START := 0.36
const STONE_CROWN_SOURCE_END := 0.90
const STONE_CROWN_BASE := 0.82
const STONE_CROWN_VARIATION := 0.18
const STONE_GROUT_ALPHA := 0.18
const STONE_TOP_ALPHA := 0.88

var _failed := false


func _initialize() -> void:
	var output_path := ProjectSettings.globalize_path(OUTPUT_ROOT)
	var directory_error := DirAccess.make_dir_recursive_absolute(output_path)
	if directory_error != OK:
		push_error("Could not create terrain material directory: %s" % error_string(directory_error))
		quit(1)
		return

	_pack_set(
		"meadow_grass",
		"valley_ground/T_MossGround01_Color.png",
		"",
		0,
		HEIGHT_MODE_PALE_PETALS,
		"valley_ground/T_MossGround01_Normal.png",
		true,
		"valley_ground/T_MossGround01_ORM.png",
		1,
		0.82
	)
	_pack_set(
		"warm_path",
		"valley_ground/T_WoodlandPath_Color.png",
		"valley_ground/T_WoodlandPath_Surface.png",
		2,
		HEIGHT_MODE_STEPPING_STONES,
		"valley_ground/T_WoodlandPath_Normal.png",
		true,
		"valley_ground/T_WoodlandPath_Surface.png",
		1,
		0.78
	)
	_pack_set(
		"creek_earth",
		"valley_ground/T_ValleyEarth_D.png",
		"",
		0,
		HEIGHT_MODE_FLAT,
		"valley_ground/T_ValleyEarth_N.png",
		true,
		"",
		0,
		0.9
	)
	_pack_set(
		"mossy_stone",
		"valley_cliffs/T_ValleyMoss_BaseColor.png",
		"",
		0,
		HEIGHT_MODE_FLAT,
		"valley_cliffs/T_ValleyMoss_NormalGL.png",
		false,
		"valley_cliffs/T_ValleyMoss_Roughness.png",
		0,
		0.86
	)

	if _failed:
		quit(1)
	else:
		print("Packed four woodland Terrain3D texture sets at %s (%d px each)." % [OUTPUT_ROOT, OUTPUT_SIZE])
		quit(0)


func _pack_set(
	material_key: String,
	albedo_relative: String,
	height_relative: String,
	height_channel: int,
	height_mode: int,
	normal_relative: String,
	flip_normal_y: bool,
	roughness_relative: String,
	roughness_channel: int,
	roughness_fallback: float
) -> void:
	var albedo := _load_image(albedo_relative)
	var normal := _load_image(normal_relative)
	if albedo == null or normal == null:
		return

	albedo = _resize(albedo)
	normal = _resize(normal)
	var height := _load_image(height_relative) if not height_relative.is_empty() else null
	var roughness := _load_image(roughness_relative) if not roughness_relative.is_empty() else null
	if height != null:
		height = _resize(height)
	if roughness != null:
		roughness = _resize(roughness)
	var height_percentiles: Dictionary = _height_percentiles(height, height_channel) if height != null else {}
	var petal_mask_data: Dictionary = _build_pale_petal_mask(albedo) if height_mode == HEIGHT_MODE_PALE_PETALS else {}
	var petal_mask: Image = petal_mask_data.image if not petal_mask_data.is_empty() else null
	var stone_mask: Image = _build_stepping_stone_mask(height, height_channel) if height_mode == HEIGHT_MODE_STEPPING_STONES else null

	var albedo_height := Image.create(OUTPUT_SIZE, OUTPUT_SIZE, false, Image.FORMAT_RGBA8)
	var normal_roughness := Image.create(OUTPUT_SIZE, OUTPUT_SIZE, false, Image.FORMAT_RGBA8)
	var roughness_total := 0.0
	var height_total := 0.0
	var height_min := 1.0
	var height_max := 0.0
	var shaped_core_count := 0
	var shaped_core_height_total := 0.0
	var flat_background_count := 0
	var flat_background_height_total := 0.0
	var bevel_count := 0
	var albedo_rgb_mismatches := 0
	for y in OUTPUT_SIZE:
		for x in OUTPUT_SIZE:
			var albedo_pixel := albedo.get_pixel(x, y)
			var height_value := 0.5
			var shape_value := 0.0
			match height_mode:
				HEIGHT_MODE_PALE_PETALS:
					shape_value = petal_mask.get_pixel(x, y).r
					height_value = lerpf(0.5, PETAL_TOP_ALPHA, shape_value)
					if shape_value >= 0.95:
						shaped_core_count += 1
						shaped_core_height_total += height_value
					elif shape_value <= 0.05:
						flat_background_count += 1
						flat_background_height_total += height_value
					else:
						bevel_count += 1
				HEIGHT_MODE_STEPPING_STONES:
					shape_value = stone_mask.get_pixel(x, y).r
					height_value = lerpf(STONE_GROUT_ALPHA, STONE_TOP_ALPHA, shape_value)
					if shape_value >= 0.80:
						shaped_core_count += 1
						shaped_core_height_total += height_value
					elif shape_value <= 0.10:
						flat_background_count += 1
						flat_background_height_total += height_value
					else:
						bevel_count += 1
			# Track the value actually representable in the packed 8-bit alpha channel;
			# the native Terrain3D displacement offset is derived from this mean.
			height_value = round(height_value * 255.0) / 255.0
			height_total += height_value
			height_min = minf(height_min, height_value)
			height_max = maxf(height_max, height_value)
			albedo_height.set_pixel(x, y, Color(albedo_pixel.r, albedo_pixel.g, albedo_pixel.b, height_value))
			var packed_albedo_pixel := albedo_height.get_pixel(x, y)
			if not _rgb_bytes_match(albedo_pixel, packed_albedo_pixel):
				albedo_rgb_mismatches += 1

			var normal_pixel := normal.get_pixel(x, y)
			var normal_vector := Vector3(normal_pixel.r * 2.0 - 1.0, normal_pixel.g * 2.0 - 1.0, normal_pixel.b * 2.0 - 1.0)
			if flip_normal_y:
				normal_vector.y = -normal_vector.y
			if normal_vector.length_squared() > 0.000001:
				normal_vector = normal_vector.normalized()
			var roughness_value := _channel(roughness.get_pixel(x, y), roughness_channel) if roughness != null else roughness_fallback
			roughness_total += roughness_value
			normal_roughness.set_pixel(
				x,
				y,
				Color(normal_vector.x * 0.5 + 0.5, normal_vector.y * 0.5 + 0.5, normal_vector.z * 0.5 + 0.5, roughness_value)
			)

	var output_path := ProjectSettings.globalize_path(OUTPUT_ROOT)
	var albedo_error := albedo_height.save_png(output_path.path_join("%s_albedo_height.png" % material_key))
	var normal_error := normal_roughness.save_png(output_path.path_join("%s_normal_roughness.png" % material_key))
	if albedo_error != OK or normal_error != OK:
		push_error("Could not write packed textures for %s." % material_key)
		_failed = true
		return
	if albedo_rgb_mismatches > 0:
		push_error("Packed albedo RGB changed for %s at %d pixels." % [material_key, albedo_rgb_mismatches])
		_failed = true
		return
	var mean_roughness := roughness_total / float(OUTPUT_SIZE * OUTPUT_SIZE)
	var mean_height := height_total / float(OUTPUT_SIZE * OUTPUT_SIZE)
	var displacement_offset := 0.5 - mean_height
	if height_mode == HEIGHT_MODE_PALE_PETALS:
		var petal_coverage := float(petal_mask_data.selected_pixels) / float(OUTPUT_SIZE * OUTPUT_SIZE)
		var core_mean := shaped_core_height_total / float(maxi(shaped_core_count, 1))
		var background_mean := flat_background_height_total / float(maxi(flat_background_count, 1))
		print(
			"Packed %s: cream petal mask B>=%.3f, max RGB>=%.3f, chroma<=%.3f; kept %d components (%d hard pixels, %d feathered pixels, %.2f%%), removed %d tiny marks. Core %.2f%% (mean alpha %.3f), background %.2f%% (mean alpha %.3f), feather %.2f%%; alpha %.3f..%.3f, mean %.6f, offset %.6f; albedo RGB mismatches %d."
			% [material_key, PETAL_BLUE_MIN, PETAL_BRIGHTNESS_MIN, PETAL_CHROMA_MAX, petal_mask_data.kept_components, petal_mask_data.raw_selected_pixels, petal_mask_data.selected_pixels, petal_coverage * 100.0, petal_mask_data.removed_components, float(shaped_core_count) / float(OUTPUT_SIZE * OUTPUT_SIZE) * 100.0, core_mean, float(flat_background_count) / float(OUTPUT_SIZE * OUTPUT_SIZE) * 100.0, background_mean, float(bevel_count) / float(OUTPUT_SIZE * OUTPUT_SIZE) * 100.0, height_min, height_max, mean_height, displacement_offset, albedo_rgb_mismatches]
		)
	elif height_mode == HEIGHT_MODE_STEPPING_STONES:
		var top_mean := shaped_core_height_total / float(maxi(shaped_core_count, 1))
		var grout_mean := flat_background_height_total / float(maxi(flat_background_count, 1))
		print(
			"Packed %s: Surface B P05/median/P95 %.3f/%.3f/%.3f; beveled paver mask B %.3f..%.3f with crown start/end %.3f/%.3f -> alpha %.2f..%.2f; top %.2f%% (mean alpha %.3f), grout %.2f%% (mean alpha %.3f), bevel %.2f%%; output range %.3f..%.3f, mean %.6f, offset %.6f; albedo RGB mismatches %d."
			% [material_key, height_percentiles.low, height_percentiles.median, height_percentiles.high, STONE_GROUT_SOURCE_MAX, STONE_TOP_SOURCE_MIN, STONE_CROWN_SOURCE_START, STONE_CROWN_SOURCE_END, STONE_GROUT_ALPHA, STONE_TOP_ALPHA, float(shaped_core_count) / float(OUTPUT_SIZE * OUTPUT_SIZE) * 100.0, top_mean, float(flat_background_count) / float(OUTPUT_SIZE * OUTPUT_SIZE) * 100.0, grout_mean, float(bevel_count) / float(OUTPUT_SIZE * OUTPUT_SIZE) * 100.0, height_min, height_max, mean_height, displacement_offset, albedo_rgb_mismatches]
		)
	else:
		print("Packed %s: flat height alpha %.3f, mean roughness alpha %.2f, DirectX normal conversion %s." % [material_key, mean_height, mean_roughness, str(flip_normal_y)])


func _load_image(relative_path: String) -> Image:
	if relative_path.is_empty():
		return null
	var resource_path := "%s/%s" % [SOURCE_ROOT, relative_path]
	var image := Image.load_from_file(ProjectSettings.globalize_path(resource_path))
	if image == null or image.is_empty():
		push_error("Could not load terrain source texture: %s" % resource_path)
		_failed = true
		return null
	return image


func _resize(source: Image) -> Image:
	if source.get_width() != OUTPUT_SIZE or source.get_height() != OUTPUT_SIZE:
		source.resize(OUTPUT_SIZE, OUTPUT_SIZE, Image.INTERPOLATE_CUBIC)
	return source


func _channel(pixel: Color, channel: int) -> float:
	match channel:
		0:
			return pixel.r
		1:
			return pixel.g
		2:
			return pixel.b
		_:
			return pixel.a


func _rgb_bytes_match(first: Color, second: Color) -> bool:
	return (
		int(round(first.r * 255.0)) == int(round(second.r * 255.0))
		and int(round(first.g * 255.0)) == int(round(second.g * 255.0))
		and int(round(first.b * 255.0)) == int(round(second.b * 255.0))
	)


func _height_percentiles(source: Image, channel: int) -> Dictionary:
	var histogram := PackedInt32Array()
	histogram.resize(256)
	histogram.fill(0)
	var sample_count := 0
	for y in source.get_height():
		for x in source.get_width():
			var value := clampi(roundi(_channel(source.get_pixel(x, y), channel) * 255.0), 0, 255)
			histogram[value] += 1
			sample_count += 1
	return {
		"low": _histogram_percentile(histogram, sample_count, HEIGHT_LOW_PERCENTILE),
		"median": _histogram_percentile(histogram, sample_count, 0.5),
		"high": _histogram_percentile(histogram, sample_count, HEIGHT_HIGH_PERCENTILE),
	}


func _histogram_percentile(histogram: PackedInt32Array, sample_count: int, percentile: float) -> float:
	var target_rank := int(floor(float(sample_count - 1) * percentile))
	var cumulative := 0
	for value in histogram.size():
		cumulative += histogram[value]
		if cumulative > target_rank:
			return float(value) / 255.0
	return 1.0


func _build_pale_petal_mask(source: Image) -> Dictionary:
	var pixel_count := OUTPUT_SIZE * OUTPUT_SIZE
	var raw_mask := PackedByteArray()
	raw_mask.resize(pixel_count)
	raw_mask.fill(0)
	var raw_selected_pixels := 0
	for y in OUTPUT_SIZE:
		for x in OUTPUT_SIZE:
			var pixel := source.get_pixel(x, y)
			var brightest := maxf(pixel.r, maxf(pixel.g, pixel.b))
			var darkest := minf(pixel.r, minf(pixel.g, pixel.b))
			var chroma := brightest - darkest
			if pixel.b >= PETAL_BLUE_MIN and brightest >= PETAL_BRIGHTNESS_MIN and chroma <= PETAL_CHROMA_MAX:
				raw_mask[y * OUTPUT_SIZE + x] = 1
				raw_selected_pixels += 1

	var component_result := _remove_small_mask_components(raw_mask, OUTPUT_SIZE, OUTPUT_SIZE, PETAL_MIN_COMPONENT_PIXELS)
	var cleaned_mask: PackedByteArray = component_result.mask
	var mask_image := Image.create(OUTPUT_SIZE, OUTPUT_SIZE, false, Image.FORMAT_RGBA8)
	var kernel := [1, 2, 1]
	var selected_pixels := 0
	for y in OUTPUT_SIZE:
		for x in OUTPUT_SIZE:
			var weighted_mask := 0.0
			for offset_y in range(-1, 2):
				var sample_y := posmod(y + offset_y, OUTPUT_SIZE)
				for offset_x in range(-1, 2):
					var sample_x := posmod(x + offset_x, OUTPUT_SIZE)
					weighted_mask += float(cleaned_mask[sample_y * OUTPUT_SIZE + sample_x] * kernel[offset_y + 1] * kernel[offset_x + 1])
			var value := weighted_mask / 16.0
			if value > 0.0:
				selected_pixels += 1
			mask_image.set_pixel(x, y, Color(value, value, value, 1.0))
	return {
		"image": mask_image,
		"raw_selected_pixels": raw_selected_pixels,
		"selected_pixels": selected_pixels,
		"kept_components": component_result.kept_components,
		"removed_components": component_result.removed_components,
	}


func _remove_small_mask_components(mask: PackedByteArray, width: int, height: int, minimum_size: int) -> Dictionary:
	var visited := PackedByteArray()
	visited.resize(mask.size())
	visited.fill(0)
	var filtered := PackedByteArray()
	filtered.resize(mask.size())
	filtered.fill(0)
	var queue := PackedInt32Array()
	queue.resize(mask.size())
	var kept_components := 0
	var removed_components := 0
	var kept_pixels := 0
	for start in mask.size():
		if mask[start] == 0 or visited[start] != 0:
			continue
		var head := 0
		var tail := 0
		queue[tail] = start
		tail += 1
		visited[start] = 1
		while head < tail:
			var index := queue[head]
			head += 1
			var y := int(index / width)
			var x := index - y * width
			for offset_y in range(-1, 2):
				var next_y := posmod(y + offset_y, height)
				for offset_x in range(-1, 2):
					if offset_x == 0 and offset_y == 0:
						continue
					var next_x := posmod(x + offset_x, width)
					var next_index := next_y * width + next_x
					if mask[next_index] == 0 or visited[next_index] != 0:
						continue
					visited[next_index] = 1
					queue[tail] = next_index
					tail += 1
		if tail >= minimum_size:
			kept_components += 1
			kept_pixels += tail
			for queue_index in tail:
				filtered[queue[queue_index]] = 1
		else:
			removed_components += 1
	return {
		"mask": filtered,
		"kept_components": kept_components,
		"removed_components": removed_components,
		"kept_pixels": kept_pixels,
	}


func _build_stepping_stone_mask(source: Image, channel: int) -> Image:
	var mask := Image.create(OUTPUT_SIZE, OUTPUT_SIZE, false, Image.FORMAT_RGBA8)
	var kernel := [1, 2, 1]
	for y in OUTPUT_SIZE:
		for x in OUTPUT_SIZE:
			var weighted_source := 0.0
			for offset_y in range(-1, 2):
				var sample_y := posmod(y + offset_y, OUTPUT_SIZE)
				for offset_x in range(-1, 2):
					var sample_x := posmod(x + offset_x, OUTPUT_SIZE)
					var sample := _channel(source.get_pixel(sample_x, sample_y), channel)
					weighted_source += sample * float(kernel[offset_y + 1] * kernel[offset_x + 1])
			var smoothed_source := weighted_source / 16.0
			var bevel := _smoothstep(STONE_GROUT_SOURCE_MAX, STONE_TOP_SOURCE_MIN, smoothed_source)
			var crown := clampf((smoothed_source - STONE_CROWN_SOURCE_START) / (STONE_CROWN_SOURCE_END - STONE_CROWN_SOURCE_START), 0.0, 1.0)
			var profile := bevel * (STONE_CROWN_BASE + STONE_CROWN_VARIATION * crown)
			mask.set_pixel(x, y, Color(profile, profile, profile, 1.0))
	return mask


func _smoothstep(edge_low: float, edge_high: float, value: float) -> float:
	var amount := clampf((value - edge_low) / (edge_high - edge_low), 0.0, 1.0)
	return amount * amount * (3.0 - 2.0 * amount)
