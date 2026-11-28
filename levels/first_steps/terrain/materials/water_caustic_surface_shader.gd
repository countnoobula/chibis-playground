extends RefCounted

## Adds the shared Chibi water caustics to Terrain3D's generated surface shader.
## This patch is independent of player-centered flower relief so it remains active
## on mobile, where Terrain3D displacement is intentionally disabled.

const PATCH_MARKER := "// FIRST_STEPS_WATER_CAUSTIC_PATCH"
const SHADER_TYPE_ANCHOR := "shader_type spatial;"
const ALBEDO_OUTPUT_ANCHOR := "\tALBEDO = mat.albedo_height.rgb * color_map.rgb;"
const CAUSTIC_INCLUDE := "\n#include \"res://features/water/shaders/water_caustics.gdshaderinc\"\n"
const CAUSTIC_FRAGMENT := """

// FIRST_STEPS_WATER_CAUSTIC_PATCH
if (water_caustic_strength > 0.001) {
	float __terrain_caustic_face_weight = mix(
		0.22,
		1.0,
		smoothstep(-0.12, 0.76, normalize(w_normal).y)
	);
	float __terrain_caustic_light = water_caustic_light(v_vertex) * __terrain_caustic_face_weight;
	vec3 __terrain_caustic_color = water_caustic_color.rgb * __terrain_caustic_light * water_caustic_strength;
	ALBEDO += __terrain_caustic_color * 0.34;
	EMISSION += __terrain_caustic_color * 0.16;
}
"""


## Installs the caustic patch over Terrain3D's generated default shader.
## Terrain3D 1.1.0-stable owns the base shader; this changes only its final
## albedo response and leaves texture blending, paint masks, and displacement intact.
static func install(terrain_material: Terrain3DMaterial) -> bool:
	if terrain_material == null:
		return false

	terrain_material.shader_override_enabled = true
	var shader := terrain_material.shader_override as Shader
	if shader == null:
		push_error("Terrain3D did not provide a generated surface shader override for water caustics.")
		return false

	var shader_code := shader.code
	if shader_code.contains(PATCH_MARKER):
		return true
	if not shader_code.contains(SHADER_TYPE_ANCHOR) or not shader_code.contains(ALBEDO_OUTPUT_ANCHOR):
		push_error("Terrain3D's generated surface shader no longer matches the First Steps caustic patch anchors.")
		return false

	shader_code = _insert_shared_include(shader_code)
	shader_code = shader_code.replace(ALBEDO_OUTPUT_ANCHOR, ALBEDO_OUTPUT_ANCHOR + CAUSTIC_FRAGMENT)
	shader.code = shader_code
	return true


static func _insert_shared_include(shader_code: String) -> String:
	var insertion_offset := 0
	for line in shader_code.split("\n", true):
		if line.strip_edges().begins_with("render_mode "):
			return shader_code.insert(insertion_offset + line.length() + 1, CAUSTIC_INCLUDE)
		insertion_offset += line.length() + 1
	var shader_type_offset := shader_code.find(SHADER_TYPE_ANCHOR)
	if shader_type_offset >= 0:
		var line_end := shader_code.find("\n", shader_type_offset)
		if line_end >= 0:
			return shader_code.insert(line_end + 1, CAUSTIC_INCLUDE)
	return shader_code
