shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform vec4 base_color : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.7;
uniform float shininess : hint_range(0.0, 1.0) = 0.4;
uniform float plant_height = 0.5;
uniform float wind_amplitude = 0.0;
uniform float vertex_tint : hint_range(0.0, 1.0) = 0.0;
uniform float transmission : hint_range(0.0, 1.0) = 0.12;
uniform vec4 backlight_color : source_color = vec4(0.84, 0.87, 0.56, 1.0);
uniform float detail_cutout : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D color_map : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_map : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D surface_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_strength = 0.0;
uniform bool use_color_map = false;
uniform bool use_detail_map = false;
uniform bool use_roughness_map = false;
uniform bool use_surface_map = false;

void vertex() {
	float anchor = clamp(VERTEX.y / plant_height, 0.0, 1.0);
	vec2 base_world = MODEL_MATRIX[3].xz;
	float phase = TIME * 1.122 + dot(base_world, vec2(1.2, 0.74));
	vec3 wind = vec3(sin(phase), 0.0, 0.62 * sin(phase + 1.1));
	VERTEX += wind * wind_amplitude * anchor * anchor;
}

void fragment() {
	vec3 color = base_color.rgb;
	if (use_color_map) {
		color *= texture(color_map, UV).rgb;
	}
	if (use_detail_map) {
		float detail = texture(detail_map, UV).r;
		if (detail < detail_cutout) {
			discard;
		}
		color *= 1.0 + 0.12 * detail;
	}
	ALBEDO = color * mix(vec3(1.0), COLOR.rgb, vertex_tint);
	ROUGHNESS = roughness;
	if (use_roughness_map) {
		ROUGHNESS = texture(roughness_map, UV).r;
	}
	if (use_surface_map) {
		vec3 surface = texture(surface_map, UV).rgb;
		AO = surface.r;
		ROUGHNESS = surface.g;
	}
	SPECULAR = shininess;
	if (normal_strength > 0.0) {
		NORMAL_MAP = texture(normal_map, UV).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}
	vec3 backlight = mix(ALBEDO, backlight_color.rgb, 0.25);
	BACKLIGHT = backlight * transmission;
}
