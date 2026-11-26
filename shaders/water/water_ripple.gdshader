shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never;

uniform vec4 ripple_color : source_color = vec4(0.77, 1.0, 0.94, 0.74);
uniform float ring_alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	ALBEDO = ripple_color.rgb;
	ALPHA = ripple_color.a * ring_alpha;
}
