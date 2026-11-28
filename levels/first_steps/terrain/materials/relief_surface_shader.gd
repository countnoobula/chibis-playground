extends RefCounted

## Adds a valley-only detail-lighting block to Terrain3D's generated stock shader.
## The paint blend, albedo, PBR outputs, and native displacement remain upstream-owned.

const PATCH_MARKER := "// FIRST_STEPS_RELIEF_SURFACE_PATCH"
const UNIFORM_INSERT_ANCHOR := "group_uniforms;\n\n// Public uniforms"
const ALBEDO_OUTPUT_ANCHOR := "\tALBEDO = mat.albedo_height.rgb * color_map.rgb;"

const RELIEF_UNIFORMS := """

// FIRST_STEPS_RELIEF_SURFACE_PATCH
group_uniforms first_steps_relief_lighting;
uniform float relief_lighting_strength : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float relief_lighting_inner_radius : hint_range(0.0, 6.0, 0.1) = 3.0;
uniform float relief_lighting_outer_radius : hint_range(0.1, 12.0, 0.1) = 6.0;
uniform float relief_lighting_slope_scale : hint_range(0.0, 2.0, 0.05) = 0.55;
uniform float relief_lighting_gradient_limit : hint_range(0.1, 4.0, 0.05) = 1.25;
uniform float relief_lighting_contrast : hint_range(0.0, 3.0, 0.05) = 1.5;
group_uniforms;
"""

const RELIEF_FRAGMENT := """

	// Use the same painted alpha channel that drives native displacement to give
	// its fine slopes readable warm highlights and soft cool shade.
	if (relief_lighting_strength > 0.0) {
		// Derivatives stay outside the radial branch so they remain defined for
		// neighboring fragments at the 3-6 m fade boundary.
		vec2 __relief_world_dx = dFdx(v_vertex.xz);
		vec2 __relief_world_dy = dFdy(v_vertex.xz);
		float __relief_height_dx = dFdx(mat.albedo_height.a);
		float __relief_height_dy = dFdy(mat.albedo_height.a);
		float __relief_det = __relief_world_dx.x * __relief_world_dy.y
			- __relief_world_dx.y * __relief_world_dy.x;
		float __relief_distance = length(v_vertex.xz - _target_pos.xz);
		float __relief_fade = 1.0 - smoothstep(
			relief_lighting_inner_radius,
			relief_lighting_outer_radius,
			__relief_distance
		);
		if (__relief_fade > 0.0 && abs(__relief_det) > 0.000001) {
			vec2 __relief_gradient = vec2(
				(__relief_height_dx * __relief_world_dy.y - __relief_world_dx.y * __relief_height_dy) / __relief_det,
				(__relief_world_dx.x * __relief_height_dy - __relief_height_dx * __relief_world_dy.x) / __relief_det
			);
			// Soft limiting prevents 8-bit height steps from creating razor-sharp facets.
			float __relief_gradient_length = length(__relief_gradient);
			__relief_gradient *= relief_lighting_gradient_limit /
				(relief_lighting_gradient_limit + __relief_gradient_length);
			vec3 __relief_micro_normal = normalize(vec3(
				-__relief_gradient.x * relief_lighting_slope_scale,
				1.0,
				-__relief_gradient.y * relief_lighting_slope_scale
			));
			float __normal_blend = 0.48 * relief_lighting_strength * __relief_fade;
			vec3 __relief_world_normal = normalize(mix(w_normal, __relief_micro_normal, __normal_blend));

			vec3 __relief_light = _light_direction;
			float __relief_light_length = length(__relief_light);
			__relief_light = __relief_light_length > 0.0001
				? __relief_light / __relief_light_length
				: normalize(vec3(0.42, 0.78, 0.46));

			float __relief_light_change = max(dot(__relief_world_normal, __relief_light), 0.0)
				- max(dot(w_normal, __relief_light), 0.0);
			float __relief_tone = clamp(
				__relief_light_change * relief_lighting_contrast,
				-0.28,
				0.28
			);
			float __warm_highlight = max(__relief_tone, 0.0);
			float __cool_shade = max(-__relief_tone, 0.0);
			ALBEDO *= vec3(
				1.0 + __warm_highlight * 0.38 - __cool_shade * 0.30,
				1.0 + __warm_highlight * 0.24 - __cool_shade * 0.22,
				1.0 - __warm_highlight * 0.08 - __cool_shade * 0.14
			);

			// Keep the texture normal map in a basis that follows the relief normal.
			vec3 __relief_tangent = normalize(cross(__relief_world_normal, vec3(0.0, 0.0, 1.0)));
			vec3 __relief_binormal = normalize(cross(__relief_world_normal, __relief_tangent));
			NORMAL = mat3(VIEW_MATRIX) * __relief_world_normal;
			TANGENT = mat3(VIEW_MATRIX) * __relief_tangent;
			BINORMAL = mat3(VIEW_MATRIX) * __relief_binormal;
		}
	}
"""


## Installs a minimal patch over Terrain3D's generated default shader.
## Terrain3D 1.1.0-stable generates this shader from src/shaders/main.glsl and
## src/shaders/pbr_views.glsl at pinned commit 629bbd6.
static func install(terrain_material: Terrain3DMaterial) -> bool:
	if terrain_material == null:
		return false

	terrain_material.shader_override_enabled = true
	var shader := terrain_material.shader_override as Shader
	if shader == null:
		push_error("Terrain3D did not provide a generated surface shader override.")
		return false

	var shader_code := shader.code
	if shader_code.contains(PATCH_MARKER):
		return true
	if not shader_code.contains(UNIFORM_INSERT_ANCHOR) or not shader_code.contains(ALBEDO_OUTPUT_ANCHOR):
		push_error("Terrain3D's generated surface shader no longer matches the First Steps relief patch anchors.")
		return false

	shader_code = shader_code.replace(UNIFORM_INSERT_ANCHOR, "group_uniforms;\n" + RELIEF_UNIFORMS + "\n// Public uniforms")
	shader_code = shader_code.replace(ALBEDO_OUTPUT_ANCHOR, ALBEDO_OUTPUT_ANCHOR + RELIEF_FRAGMENT)
	shader.code = shader_code
	return true
