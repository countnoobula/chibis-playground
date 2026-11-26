shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/water/water_caustics.gdshaderinc"

uniform vec4 shallow_color : source_color = vec4(0.42, 0.94, 0.88, 1.0);
uniform vec4 deep_color : source_color = vec4(0.04, 0.52, 0.64, 1.0);
uniform vec4 foam_color : source_color = vec4(0.92, 1.0, 0.94, 1.0);
uniform float surface_opacity : hint_range(0.0, 1.0) = 0.34;
uniform float wave_height : hint_range(0.0, 0.04) = 0.008;
uniform float refraction_strength : hint_range(0.0, 0.03) = 0.005;
uniform float shoreline_width : hint_range(0.05, 2.0) = 0.32;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

varying vec3 local_position;
varying vec3 world_position;

void vertex() {
	local_position = VERTEX;
	float wave_a = sin(VERTEX.x * 1.35 + VERTEX.z * 0.81 + TIME * 0.75);
	float wave_b = sin(VERTEX.z * 2.15 - VERTEX.x * 0.57 - TIME * 0.92);
	VERTEX.y += (wave_a * 0.58 + wave_b * 0.42) * wave_height;
	NORMAL = normalize(vec3(-cos(VERTEX.x * 1.35 + TIME * 0.75) * wave_height * 0.7, 1.0, -cos(VERTEX.z * 2.15 - TIME * 0.92) * wave_height * 0.7));
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float linear_view_depth(float raw_depth, vec2 uv, mat4 inverse_projection) {
	vec4 view_position = inverse_projection * vec4(uv * 2.0 - 1.0, raw_depth, 1.0);
	view_position.xyz /= max(view_position.w, 0.00001);
	return -view_position.z;
}

void fragment() {
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	// The Mobile renderer uses reverse-Z: a cleared sky depth is close to zero.
	float center_raw_depth = texture(depth_texture, SCREEN_UV).r;
	float water_view_depth = -VERTEX.z;
	float thickness = water_depth;
	if (center_raw_depth > 0.00001) {
		thickness = max(linear_view_depth(center_raw_depth, SCREEN_UV, INV_PROJECTION_MATRIX) - water_view_depth, 0.0);
	}
	float depth_weight = smoothstep(0.06, max(water_depth, 0.07), thickness);
	float shore_by_geometry = water_shore_alpha(world_position.xz, shoreline_width);
	float shore_by_depth = smoothstep(0.015, 0.24, thickness);
	float shore_weight = min(shore_by_geometry, shore_by_depth);
	float wave = sin(local_position.x * 2.4 + local_position.z * 1.8 + TIME * 0.8) +
		sin(local_position.z * 3.2 - local_position.x * 0.7 - TIME * 0.95);
	float crest = pow(clamp(wave * 0.5, 0.0, 1.0), 7.0);
	vec2 ripple = water_wave_warp(local_position.xz * 2.35, TIME * water_caustic_speed);
	vec3 water_color = mix(shallow_color.rgb, deep_color.rgb, depth_weight * 0.84);
	vec3 screen_center = texture(screen_texture, SCREEN_UV).rgb;
	vec2 offset = ripple + NORMAL.xy * 0.18;
	vec2 refracted_uv = clamp(SCREEN_UV + offset * refraction_strength * shore_weight, vec2(0.001), vec2(0.999));
	float refracted_raw_depth = texture(depth_texture, refracted_uv).r;
	bool refracted_behind_water = refracted_raw_depth <= 0.00001;
	if (!refracted_behind_water) {
		float refracted_view_depth = linear_view_depth(refracted_raw_depth, refracted_uv, INV_PROJECTION_MATRIX);
		refracted_behind_water = refracted_view_depth > water_view_depth + 0.025;
	}
	vec3 refracted_color = screen_center;
	if (refracted_behind_water) {
		refracted_color = texture(screen_texture, refracted_uv).rgb;
	}
	vec3 color = mix(water_color, refracted_color * vec3(0.79, 1.02, 1.04), 0.25 * shore_weight);
	color = mix(color, foam_color.rgb, crest * (0.18 + 0.20 * shore_weight));
	float output_alpha = surface_opacity * mix(0.20, 1.0, shore_weight);
	float output_roughness = 0.38;
	float output_specular = 0.16;
	vec3 emission = foam_color.rgb * crest * (0.025 + 0.04 * (1.0 - shore_weight));
	if (!FRONT_FACING) {
		float underside_wave = 0.5 + 0.5 * sin(local_position.x * 1.2 + local_position.z * 1.9 + TIME * 0.65);
		float underside_net = water_voronoi_caustic(
			local_position.xz * 2.35 + ripple * 1.55 + vec2(TIME * 0.12, -TIME * 0.09), TIME * 0.42
		);
		float glint = underside_net * (0.64 + 0.36 * underside_wave);
		vec3 warm_glint = water_caustic_color.rgb * (0.035 + 0.28 * glint);
		color = mix(color, deep_color.rgb + foam_color.rgb * (0.035 + 0.13 * underside_wave), 0.32);
		color += warm_glint;
		output_alpha = max(output_alpha, 0.43 * shore_by_geometry);
		output_roughness = 0.78;
		output_specular = 0.035;
		emission += water_caustic_color.rgb * glint * 0.13;
	}
	ALBEDO = color;
	ALPHA = output_alpha;
	ROUGHNESS = output_roughness;
	SPECULAR = output_specular;
	EMISSION = emission;
}



