// Shared warm, moving caustic network and water-volume clip helpers.
uniform vec4 water_caustic_color : source_color = vec4(1.0, 0.78, 0.39, 1.0);
uniform float water_caustic_strength : hint_range(0.0, 2.0) = 0.62;
uniform float water_caustic_scale : hint_range(0.1, 8.0) = 1.8;
uniform float water_caustic_speed : hint_range(0.0, 2.0) = 0.22;
uniform float water_caustic_shore_fade : hint_range(0.05, 1.0) = 0.7;
uniform float water_plane_y = 0.0;
uniform float water_depth = 2.0;
uniform vec2 water_outline_points[32];
uniform int water_outline_count = 0;

float water_hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float water_voronoi_caustic(vec2 p, float phase) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	float nearest_distance = 10.0;
	float second_distance = 10.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offset = vec2(float(x), float(y));
			vec2 id = cell + offset;
			float h0 = water_hash21(id);
			float h1 = water_hash21(id + vec2(17.17, 31.73));
			vec2 drift = 0.5 + 0.36 * sin(phase + vec2(h0, h1) * 6.2831853);
			vec2 delta = offset + drift - local;
			float d = length(delta);
			if (d < nearest_distance) {
				second_distance = nearest_distance;
				nearest_distance = d;
			} else if (d < second_distance) {
				second_distance = d;
			}
		}
	}
	float edge = second_distance - nearest_distance;
	return pow(1.0 - smoothstep(0.018, 0.105, edge), 1.65);
}

// Returns x=inside (0/1) and y=distance to the closest outline edge.
vec2 water_outline_info(vec2 point_xz) {
	if (water_outline_count < 3) {
		return vec2(0.0, 100000.0);
	}
	float nearest_distance = 100000.0;
	bool inside = false;
	int previous_i = water_outline_count - 1;
	for (int i = 0; i < 32; i++) {
		if (i >= water_outline_count) {
			break;
		}
		vec2 a = water_outline_points[i];
		vec2 b = water_outline_points[previous_i];
		vec2 edge = a - b;
		float denominator = max(dot(edge, edge), 0.00001);
		float t = clamp(dot(point_xz - b, edge) / denominator, 0.0, 1.0);
		nearest_distance = min(nearest_distance, length(point_xz - (b + t * edge)));
		bool crosses = ((a.y > point_xz.y) != (b.y > point_xz.y)) &&
			(point_xz.x < (b.x - a.x) * (point_xz.y - a.y) / (b.y - a.y + 0.000001) + a.x);
		if (crosses) {
			inside = !inside;
		}
		previous_i = i;
	}
	return vec2(inside ? 1.0 : 0.0, nearest_distance);
}

float water_outline_distance(vec2 point_xz) {
	return water_outline_info(point_xz).y;
}

float water_caustic_clip(vec3 world_position) {
	float depth_below_surface = water_plane_y - world_position.y;
	if (depth_below_surface <= 0.015 || depth_below_surface >= water_depth + 0.18) {
		return 0.0;
	}
	vec2 outline = water_outline_info(world_position.xz);
	float shore = smoothstep(0.0, max(water_caustic_shore_fade, 0.001), outline.y);
	float submerged = smoothstep(0.015, 0.20, depth_below_surface);
	// Keep optical attenuation gradual through the basin, including its floor, then
	// clip only geometry just below the authored volume depth.
	float optical_attenuation = exp(-max(depth_below_surface, 0.0) * 0.19);
	float below_bottom = 1.0 - smoothstep(water_depth + 0.08, water_depth + 0.18, depth_below_surface);
	return outline.x * shore * submerged * optical_attenuation * below_bottom;
}

vec2 water_wave_warp(vec2 p, float phase) {
	return vec2(
		sin(p.y * 1.68 + p.x * 0.55 + phase * 1.32) + 0.48 * sin(p.x * 3.7 + p.y * 1.35 - phase * 0.98),
		sin(p.x * 1.75 - p.y * 0.71 - phase * 1.21) + 0.43 * sin(p.y * 3.5 - p.x * 0.85 + phase * 0.84)
	) * 0.23;
}

float water_caustic_light(vec3 world_position) {
	float clip = water_caustic_clip(world_position);
	if (clip <= 0.001) {
		return 0.0;
	}
	float time_value = TIME * water_caustic_speed;
	vec2 p = world_position.xz * water_caustic_scale;
	vec2 warp = water_wave_warp(p, time_value);
	float network = water_voronoi_caustic(p + warp + vec2(time_value * 0.34, -time_value * 0.23), time_value * 1.25);
	float glint = network * (0.77 + 0.23 * sin(time_value * 2.0 + p.x * 0.39 + p.y * 0.33));
	return glint * clip;
}

float water_shore_alpha(vec2 world_xz, float shoreline_width) {
	float distance_to_edge = water_outline_distance(world_xz);
	return smoothstep(0.0, max(shoreline_width, 0.001), distance_to_edge);
}

