shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://features/water/shaders/water_caustics.gdshaderinc"

// 50 cm ceramic tiles with grout and 2.5 m lane stripes.
uniform vec4 tile_color : source_color;
uniform vec4 lane_color : source_color;
uniform vec4 grout_color : source_color;

varying vec3 local_p;
varying vec3 world_p;

void vertex() {
	local_p = VERTEX;
	world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 p = world_p;
	vec3 q = abs(fract(p / 0.50 + 0.5) - 0.5) * 0.50;
	float seam = min(min(max(q.x, q.y), q.z), q.x);
	float footprint = max(fwidth(p.x), max(fwidth(p.y), fwidth(p.z)));
	float edge = min(footprint * 0.5, 0.014);
	float grout = smoothstep(0.0045 - edge, 0.014 + edge, seam);
	grout = mix(grout, 1.0, smoothstep(0.02, 0.10, footprint));
	float lane_axis = p.z / 2.50;
	float lane_distance = abs(fract(lane_axis - 0.47) - 0.5);
	float lane_edge = clamp(fwidth(lane_axis), 0.001, 0.03);
	float band = 1.0 - smoothstep(0.03 - lane_edge, 0.03 + lane_edge, lane_distance);
	vec3 tile_col = mix(tile_color.rgb, lane_color.rgb, band);
	vec3 base_color = mix(grout_color.rgb, tile_col, grout);
	float caustic = water_caustic_light(p);
	vec3 glimmer = water_caustic_color.rgb * caustic * water_caustic_strength;
	ALBEDO = base_color + glimmer * 0.34;
	EMISSION = glimmer * 0.16;
	ROUGHNESS = mix(0.82, 0.53, grout);
	METALLIC = 0.0;
}

