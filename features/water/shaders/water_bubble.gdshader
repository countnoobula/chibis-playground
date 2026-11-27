shader_type spatial;
render_mode blend_mix, unshaded, cull_back, depth_draw_never;

uniform vec4 bubble_color : source_color = vec4(0.76, 1.0, 0.99, 0.88);
uniform float bubble_opacity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.3);
	float highlight = pow(max(dot(normalize(NORMAL), normalize(vec3(-0.4, 0.6, 0.7))), 0.0), 12.0);
	ALBEDO = mix(bubble_color.rgb * 0.72, vec3(1.0), highlight * 0.65);
	ALPHA = bubble_color.a * bubble_opacity * (0.12 + 0.75 * rim + 0.25 * highlight);
	EMISSION = bubble_color.rgb * highlight * 0.12;
}
