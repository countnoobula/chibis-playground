shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Mobile-safe port of Unreal M_RopeNetDeform:
// 6x18 Verlet particle offsets passed as uniform vec3[108] (zero 32-bit float vertex-texture quirks!).

uniform vec4 albedo_color : source_color = vec4(0.82, 0.59, 0.31, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.78;
uniform float live_net : hint_range(0.0, 1.0) = 1.0;
uniform vec3 net_offsets[108];

vec3 sample_net_offset(vec3 p) {
	// Only displace vertices in front of backing panel (Godot +Z > +0.10 m; Unreal X < -10 cm)
	if (p.z < 0.10) {
		return vec3(0.0);
	}
	float y = clamp(p.y, 0.07, 2.65);
	float ry = y < 0.16 ? (y - 0.07) / 0.09 : (y > 2.56 ? 16.0 + (y - 2.56) / 0.09 : 1.0 + (y - 0.16) / 0.16);
	float rx = clamp((p.x + 0.50) / 0.20, 0.0, 5.0);

	int x0 = min(int(floor(rx)), 4);
	int y0 = min(int(floor(ry)), 16);
	float fx = rx - float(x0);
	float fy = ry - float(y0);

	int idx = y0 * 6 + x0;
	vec3 o00 = net_offsets[idx];
	vec3 o10 = net_offsets[idx + 1];
	vec3 o01 = net_offsets[idx + 6];
	vec3 o11 = net_offsets[idx + 7];
	vec3 sim_off = mix(mix(o00, o10, fx), mix(o01, o11, fx), fy);

	// Analytic idle parabolic sag fallback
	vec2 q = clamp(vec2(p.x / 0.50, (p.y - 1.36) / 1.29), vec2(-1.0), vec2(1.0));
	vec2 sag = vec2(1.0) - q * q;
	vec3 idle_off = vec3(0.0, -0.05 * sag.x - 0.02 * sag.y, 0.03 * sag.x + 0.02 * sag.y);

	return mix(idle_off, sim_off, live_net);
}

void vertex() {
	VERTEX += sample_net_offset(VERTEX);
}

void fragment() {
	ALBEDO = albedo_color.rgb;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
}
