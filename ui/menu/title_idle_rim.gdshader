shader_type canvas_item;

void fragment() {
	// The gingham binding is coral. Preserve the lighter woven center.
	float coral = smoothstep(0.10, 0.38, COLOR.r - COLOR.g);
	float luminance = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	COLOR.rgb = mix(COLOR.rgb, vec3(luminance), 0.60 * coral);
}
