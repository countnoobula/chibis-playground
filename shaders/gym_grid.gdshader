shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

// Low-contrast deck seams fade as their spacing becomes smaller on screen.

uniform vec4 base_color : source_color = vec4(0.90, 0.87, 0.84, 1.0);
uniform vec4 line_color : source_color = vec4(0.81, 0.77, 0.76, 1.0);
uniform float grid_scale : hint_range(0.25, 4.0) = 2.0;
uniform float line_width : hint_range(0.005, 0.08) = 0.018;
uniform float roughness_val : hint_range(0.1, 1.0) = 0.85;

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 deck_pos = world_pos.xz;
	vec2 texel = max(fwidth(deck_pos), vec2(0.0001));
	vec2 edge = abs(fract(deck_pos / grid_scale + 0.5) - 0.5) * grid_scale;
	vec2 seam = 1.0 - smoothstep(max(vec2(0.0), line_width - texel), line_width + texel, edge);
	seam *= 1.0 - smoothstep(vec2(0.025), vec2(0.17), texel);
	float top = smoothstep(0.7, 1.0, world_nrm.y);
	ALBEDO = mix(base_color.rgb, line_color.rgb, max(seam.x, seam.y) * top * 0.48);
	ROUGHNESS = roughness_val;
	METALLIC = 0.0;
}
