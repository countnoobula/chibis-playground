shader_type spatial;

render_mode blend_mix, depth_prepass_alpha, cull_back, diffuse_lambert_wrap, specular_disabled;

uniform sampler2D chibi_scarf_print : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D chibi_scarf_weave : source_color, filter_linear, repeat_disable;
uniform vec4 peach_cloth : source_color = vec4(0.94, 0.65, 0.56, 1.0);
uniform vec4 cream_hem : source_color = vec4(0.98, 0.86, 0.75, 1.0);
uniform vec3 scarf_pin_delta[4];
uniform vec3 collapse_center = vec3(0.0, 0.56, -0.09);
uniform float deploy_amount : hint_range(0.0, 1.0) = 0.0;
uniform float canopy_alpha : hint_range(0.0, 1.0) = 0.0;
uniform float bank = 0.0;
uniform float gust = 0.0;
uniform float planar_airflow : hint_range(0.0, 1.0) = 0.0;
uniform float descent_airflow : hint_range(0.0, 1.0) = 0.0;
uniform float airflow_side : hint_range(-1.0, 1.0) = 0.0;
uniform float cloth_tension : hint_range(0.0, 1.0) = 0.0;
uniform float deployment_catch : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	float inflated = clamp(deploy_amount, 0.0, 1.0);
	VERTEX = mix(collapse_center, VERTEX, inflated);

	// Each weight belongs to one actual corner. The four weights are authored
	// in the export mesh, so only the gathered ends follow Chibi's hands.
	float pin_weight = clamp(COLOR.r + COLOR.g + COLOR.b + COLOR.a, 0.0, 1.0);
	float free_cloth = 1.0 - pin_weight;
	VERTEX += scarf_pin_delta[0] * COLOR.r;
	VERTEX += scarf_pin_delta[1] * COLOR.g;
	VERTEX += scarf_pin_delta[2] * COLOR.b;
	VERTEX += scarf_pin_delta[3] * COLOR.a;

	// Keep the center calm under the print while two low-cost waves travel along
	// the cream side hems. Airflow scales the ripples; stow fades their tension.
	float side = UV.x * 2.0 - 1.0;
	float hem_edge = smoothstep(0.60, 0.94, abs(side));
	float planar = clamp(planar_airflow, 0.0, 1.0);
	float descent = clamp(descent_airflow, 0.0, 1.0);
	float tension = clamp(cloth_tension, 0.0, 1.0);
	float phase = gust + airflow_side * UV.y * 1.7;
	float ripple_a = sin(TIME * 3.1 + UV.y * 19.0 + side * 2.2 + phase);
	float ripple_b = sin(TIME * 4.3 - UV.y * 12.5 + side * 4.1 + phase * 0.72);
	float hem_ripples = (ripple_a * 0.64 + ripple_b * 0.36) * hem_edge
		* (0.008 + planar * 0.007 + descent * 0.008) * tension;
	// Lift the free middle of each hem in local Y. Both UV.y ends taper out
	// around the gathered corners, while the outer-x mask stays clear of the print.
	float hem_span = smoothstep(0.08, 0.22, UV.y)
		* (1.0 - smoothstep(0.78, 0.92, UV.y));
	float hem_lift_wave = sin(TIME * 2.8 + UV.y * 13.0 + side * 1.2 + phase) * 0.70
		+ sin(TIME * 4.5 - UV.y * 8.0 + side * 3.1 + phase * 0.65) * 0.30;
	float hem_lift = hem_lift_wave * hem_edge * hem_span
		* (0.010 + planar * 0.008 + descent * 0.018) * tension;
	float body_gate = 0.30 + abs(side) * 0.42;
	float body_wave = sin(TIME * 2.0 + UV.y * 7.2 + UV.x * 1.8 + phase)
		* (0.002 + planar * 0.003 + descent * 0.002) * body_gate * tension;
	float breathing = sin(TIME * 0.82 + UV.y * 2.3 + gust * 0.48)
		* 0.004 * (0.65 + abs(side) * 0.35) * tension;
	float opening_catch = deployment_catch * (0.008 + descent * 0.004)
		* (0.76 + 0.24 * sin(TIME * 8.0 + UV.y * 3.2 + gust));
	VERTEX.z += (hem_ripples + body_wave + breathing + opening_catch) * inflated * free_cloth;

	// A steering turn lifts the hem on its bank side, then relaxes with tension.
	float turn_side = max(clamp(bank, -1.0, 1.0) * side, 0.0);
	float turn_lift = turn_side * hem_edge * (0.003 + planar * 0.004 + descent * 0.003)
		* tension;
	VERTEX.y += (hem_lift + turn_lift) * inflated * free_cloth;
	VERTEX.x += (VERTEX.y - collapse_center.y) * clamp(bank, -1.0, 1.0)
		* 0.13 * inflated * free_cloth * tension;
}

void fragment() {
	float hem = texture(chibi_scarf_weave, vec2(clamp(UV.x, 0.0, 1.0), 0.5)).g;
	vec3 fabric = mix(peach_cloth.rgb, cream_hem.rgb, smoothstep(0.17, 0.43, hem));
	vec2 print_uv = (UV - vec2(0.344, 0.146)) * vec2(3.205128, 1.569859);
	vec4 print_mark = texture(chibi_scarf_print, print_uv);
	float in_print = step(0.0, print_uv.x) * step(print_uv.x, 1.0)
		* step(0.0, print_uv.y) * step(print_uv.y, 1.0);
	ALBEDO = mix(fabric, print_mark.rgb, print_mark.a * in_print * 0.78);
	ROUGHNESS = 0.9;
	EMISSION = ALBEDO * 0.14;
	ALPHA = clamp(canopy_alpha, 0.0, 1.0);
}
