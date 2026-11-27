@tool
extends EditorScenePostImport

const WOODLAND_ROOT := "res://assets/environment/woodland/"
const FOLIAGE_SHADER := preload("res://assets/environment/woodland/foliage.gdshader")


func _post_import(scene: Node) -> Object:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(WOODLAND_ROOT + "manifest.json"))
	var key := get_source_file().trim_prefix(WOODLAND_ROOT)
	if not manifest is Dictionary or not manifest.get("models", {}).has(key):
		push_error("Woodland import has no manifest entry for %s." % key)
		return scene
	var entry: Dictionary = manifest.models[key]
	var replacements := {}
	for slot: String in entry.materials:
		var recipe: Dictionary = entry.materials[slot]
		replacements[slot] = _material(recipe, manifest.textures, float(entry.bounds_max[1]))
	_apply_materials(scene, replacements)
	return scene


func _apply_materials(node: Node, replacements: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh is ArrayMesh:
		var mesh := node.mesh as ArrayMesh
		for index in mesh.get_surface_count():
			var material := mesh.surface_get_material(index)
			if material and replacements.has(material.resource_name):
				mesh.surface_set_material(index, replacements[material.resource_name])
	for child in node.get_children():
		_apply_materials(child, replacements)


func _texture(recipe: Dictionary, textures: Dictionary, field: String) -> Texture2D:
	var key: String = recipe.get(field, "")
	if key.is_empty():
		return null
	var path := WOODLAND_ROOT + str(textures[key].path)
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	# On a clean import the GLB can precede its PNGs. Serialize a reference
	# to the shared path so the imported texture is used when the scene loads.
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		push_error("Missing woodland texture %s" % path)
		return null
	image.generate_mipmaps(field == "normal")
	var texture := ImageTexture.create_from_image(image)
	texture.resource_path = path
	return texture


func _material(recipe: Dictionary, textures: Dictionary, height: float) -> Material:
	var color := Color.html(recipe.color)
	if float(recipe.get("wind", 0.0)) > 0.0 or recipe.has("detail"):
		var foliage := ShaderMaterial.new()
		foliage.resource_name = recipe.source_slot
		foliage.shader = FOLIAGE_SHADER
		foliage.set_shader_parameter("base_color", color)
		foliage.set_shader_parameter("roughness", recipe.roughness)
		foliage.set_shader_parameter("shininess", recipe.get("specular", 0.4))
		foliage.set_shader_parameter("plant_height", maxf(height, 0.07))
		foliage.set_shader_parameter("wind_amplitude", recipe.get("wind", 0.0))
		foliage.set_shader_parameter("vertex_tint", recipe.get("vertex_tint", 0.0))
		foliage.set_shader_parameter("detail_cutout", recipe.get("cutout", 0.0))
		foliage.set_shader_parameter("transmission", 0.12 if recipe.has("wind") else 0.0)
		if recipe.has("backlight"):
			foliage.set_shader_parameter("backlight_color", Color.html(recipe.backlight))
		_set_map(foliage, "color_map", _texture(recipe, textures, "albedo"))
		_set_map(foliage, "detail_map", _texture(recipe, textures, "detail"))
		_set_map(foliage, "roughness_map", _texture(recipe, textures, "roughness_map"))
		var normals := _texture(recipe, textures, "normal")
		if normals:
			foliage.set_shader_parameter("normal_map", normals)
			foliage.set_shader_parameter("normal_strength", recipe.normal_strength)
		var surface := _texture(recipe, textures, "surface")
		_set_map(foliage, "surface_map", surface)
		return foliage

	var material := StandardMaterial3D.new()
	material.resource_name = recipe.source_slot
	material.albedo_color = color
	material.roughness = recipe.roughness
	material.albedo_texture = _texture(recipe, textures, "albedo")
	if recipe.get("triplanar", false):
		material.uv1_triplanar = true
		material.uv1_scale = Vector3.ONE * 0.66
	material.vertex_color_use_as_albedo = float(recipe.get("vertex_tint", 0.0)) > 0.0
	if recipe.get("two_sided", false):
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.backlight_enabled = true
		material.backlight = Color(0.10, 0.14, 0.05)
	if recipe.get("transparent", false):
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = 0.45
		material.metallic_specular = 0.85
	var normal := _texture(recipe, textures, "normal")
	if normal:
		material.normal_enabled = true
		material.normal_texture = normal
		material.normal_scale = recipe.normal_strength
	var surface := _texture(recipe, textures, "surface")
	if surface:
		material.ao_enabled = true
		material.ao_texture = surface
		material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		material.roughness_texture = surface
		material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	else:
		material.roughness_texture = _texture(recipe, textures, "roughness_map")
		material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	var height_map := _texture(recipe, textures, "height_map")
	if height_map:
		material.heightmap_enabled = true
		material.heightmap_texture = height_map
		material.heightmap_scale = recipe.height_scale
	return material


func _set_map(material: ShaderMaterial, parameter: String, texture: Texture2D) -> void:
	if texture:
		material.set_shader_parameter(parameter, texture)
		material.set_shader_parameter("use_" + parameter, true)
