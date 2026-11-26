shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/water/water_caustics.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.69, 0.62, 0.48, 1.0);
uniform sampler2D base_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_base_texture = false;
uniform bool use_vertex_color = true;
uniform float roughness : hint_range(0.0, 1.0) = 0.82;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 base = base_color.rgb;
	if (has_base_texture) {
		base *= texture(base_texture, UV).rgb;
	}
	if (use_vertex_color) {
		base *= COLOR.rgb;
	}
	float face_weight = mix(0.22, 1.0, smoothstep(-0.12, 0.76, normalize(world_normal).y));
	float light_pattern = water_caustic_light(world_position) * face_weight;
	vec3 caustics = water_caustic_color.rgb * light_pattern * water_caustic_strength;
	ALBEDO = base + caustics * 0.34;
	EMISSION = caustics * 0.16;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}



