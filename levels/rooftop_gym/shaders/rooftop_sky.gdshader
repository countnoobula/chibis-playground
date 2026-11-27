shader_type sky;
render_mode use_half_res_pass, disable_fog;

uniform sampler3D cloud_noise : filter_linear, repeat_enable;
uniform vec3 sun_direction = vec3(-0.754, 0.391, -0.528);
uniform vec4 mint_sky : source_color = vec4(0.51, 0.72, 0.74, 1.0);
uniform vec4 peach_horizon : source_color = vec4(0.98, 0.71, 0.59, 1.0);
uniform vec4 distant_haze : source_color = vec4(0.79, 0.65, 0.71, 1.0);
uniform vec4 cloud_shadow : source_color = vec4(0.64, 0.54, 0.69, 1.0);
uniform vec4 cloud_peach : source_color = vec4(0.98, 0.70, 0.56, 1.0);
uniform vec4 cloud_sunlit : source_color = vec4(1.0, 0.92, 0.69, 1.0);

// Fixed sky-space volumes. The front banks leave an opening over the vault lane.
const vec3 BANK_ORIGINS[6] = vec3[](
	vec3(-6.95, 0.85, -8.55), vec3(7.10, 0.80, -8.55),
	vec3(6.90, 0.77, 8.70), vec3(-6.90, 0.82, 9.05),
	vec3(-14.10, 0.34, -29.0), vec3(13.15, 0.33, -25.70)
);
const vec3 BANK_EXTENT = vec3(5.25, 2.19, 2.85);
const vec3 BANK_BOUNDS_OFFSET = vec3(0.0, 1.16, 0.0);
const int VIEW_STEPS = 28;
const float WIND_CYCLE_SECONDS = 300.0;

vec3 atmosphere(vec3 ray) {
	float above_horizon = smoothstep(-0.032, 0.245, ray.y);
	vec3 air = mix(peach_horizon.rgb, mint_sky.rgb, above_horizon);
	air = mix(air, distant_haze.rgb, smoothstep(0.012, 0.29, -ray.y));

	// Broad low-sky glow on the sunward side; the sun sits to the left of spawn.
	float sunward = pow(max(dot(ray.xz, normalize(sun_direction.xz)), 0.0), 3.0);
	float horizon_glow = exp(-abs(ray.y + 0.025) * 9.0) * sunward;
	return mix(air, vec3(1.0, 0.76, 0.36), horizon_glow * 0.48);
}

float cirrus_band(float heading, float height, vec2 center, float bias) {
	float across = heading - center.x;
	float curve = height - center.y - 0.18 * across - 0.38 * across * across;
	float tapered = 1.0 - smoothstep(0.07, 0.38, abs(across));
	float feather = texture(cloud_noise, vec3(across * 0.24, curve * 4.7, bias)).r;
	return tapered * exp(-abs(curve) * 86.0) * smoothstep(0.45, 0.74, feather);
}

vec3 sky_with_cirrus(vec3 ray, vec3 wind_ray, float high_wind) {
	float heading = atan(wind_ray.x, -wind_ray.z) - high_wind;
	float strokes = cirrus_band(heading, ray.y, vec2(-0.36, 0.205), 0.46)
		+ cirrus_band(heading, ray.y, vec2(-0.25, 0.176), 0.51)
		+ cirrus_band(heading, ray.y, vec2(0.46, 0.105), 0.63)
		+ cirrus_band(heading, ray.y, vec2(2.08, 0.180), 0.29);
	return mix(atmosphere(ray), cloud_peach.rgb, min(strokes * 0.56, 0.42));
}

float lobe(vec3 point, vec3 center, vec3 size) {
	return 1.0 - length((point - center) / size);
}

float join_lobes(float a, float b) {
	float overlap = max(0.13 - abs(a - b), 0.0);
	return max(a, b) + overlap * overlap / 0.52;
}

float cloud_density(vec3 local, int bank) {
	vec3 p = local;
	// The towers rise at the outer edges; a low shelf trails toward the opening.
	p.x *= (bank == 0 || bank == 3 || bank == 4) ? -1.0 : 1.0;
	p.z *= (bank == 2 || bank == 3) ? -1.0 : 1.0;
	p.y /= (bank < 2) ? ((bank == 0) ? 1.0 : 0.87) : ((bank < 4) ? 0.69 : 0.31);
	float mass = lobe(p, vec3(-0.43, -0.38, 0.0), vec3(4.05, 0.62, 1.72));
	mass = join_lobes(mass, lobe(p, vec3(-2.08, -0.04, 0.17), vec3(1.70, 0.68, 1.29)));
	mass = join_lobes(mass, lobe(p, vec3(-0.53, 0.24, -0.44), vec3(1.82, 0.97, 1.23)));
	mass = join_lobes(mass, lobe(p, vec3(1.20, 0.71, 0.20), vec3(2.28, 1.22, 1.68)));
	mass = join_lobes(mass, lobe(p, vec3(0.99, 1.62, -0.31), vec3(1.54, 1.26, 1.04)));
	mass = join_lobes(mass, lobe(p, vec3(2.23, 1.80, 0.46), vec3(1.20, 1.12, 1.14)));
	mass = join_lobes(mass, lobe(p, vec3(2.95, 0.56, 0.31), vec3(1.29, 1.02, 1.31)));
	mass = join_lobes(mass, lobe(p, vec3(-0.59, 1.37, 0.35), vec3(0.86, 0.83, 0.92)));
	mass = join_lobes(mass, lobe(p, vec3(1.65, 2.47, 0.08), vec3(0.82, 0.61, 0.67)));
	if (bank < 4) {
		// Near-side puffs form rounded shoulders across the shaded face.
		mass = join_lobes(mass, lobe(p, vec3(-2.11, 0.04, 1.16), vec3(1.17, 0.63, 0.76)));
		mass = join_lobes(mass, lobe(p, vec3(-0.93, 0.53, 1.35), vec3(0.93, 0.81, 0.75)));
		mass = join_lobes(mass, lobe(p, vec3(0.77, 0.26, 1.66), vec3(1.35, 0.77, 0.72)));
		mass = join_lobes(mass, lobe(p, vec3(2.12, 1.18, 1.26), vec3(0.93, 0.92, 0.85)));
	}
	if (mass < -0.29) {
		return 0.0;
	}

	vec3 noise_pos = local + BANK_ORIGINS[bank] * 0.29;
	float billow = texture(cloud_noise, noise_pos * 0.36 + vec3(0.14, 0.55, 0.72)).r;
	float detail = texture(cloud_noise, noise_pos * 0.98 + vec3(0.48, 0.22, 0.26)).r;
	float surface = mass + (billow - 0.52) * 0.65 + (detail - 0.52) * 0.18;
	float base = smoothstep(-0.87, -0.48, p.y + (billow - 0.5) * 0.34);
	return smoothstep(-0.035, 0.22, surface) * base;
}

vec2 bank_interval(vec3 reciprocal_ray, vec3 origin, int bank) {
	vec3 bounds_scale = vec3(1.0, (bank < 4) ? 1.0 : 0.38, 1.0);
	vec3 center = origin + BANK_BOUNDS_OFFSET * bounds_scale;
	vec3 extent = BANK_EXTENT * bounds_scale;
	vec3 a = (center - extent) * reciprocal_ray;
	vec3 b = (center + extent) * reciprocal_ray;
	vec3 near_hit = min(a, b);
	vec3 far_hit = max(a, b);
	float begin = max(max(near_hit.x, near_hit.y), max(near_hit.z, 0.0));
	float end = min(min(far_hit.x, far_hit.y), far_hit.z);
	return vec2(begin, end);
}

vec3 light_in_cloud(vec3 local, float density, int bank, vec3 sun_in_bank_space) {
	float sun_depth = cloud_density(local + sun_in_bank_space * 0.42, bank) * 0.47
		+ cloud_density(local + sun_in_bank_space * 1.32, bank) * 0.88;
	float direct = exp(-1.45 * sun_depth - density * 0.28);
	// Ambient scattering gives the shaded lobes some of the color of the sunlit air.
	float bounced = 0.04 + smoothstep(-0.6, 2.5, local.y) * 0.16;
	float light_level = direct + bounced;
	float warm = smoothstep(0.17, 0.76, light_level);
	float gold = smoothstep(0.50, 1.02, light_level);
	vec3 shade = mix(cloud_shadow.rgb * 0.91, cloud_shadow.rgb * 1.09, 1.0 - density);
	return mix(mix(shade, cloud_peach.rgb, warm), cloud_sunlit.rgb * 1.12, gold);
}

vec3 rotate_about_up(vec3 direction, float c, float s) {
	return vec3(c * direction.x + s * direction.z, direction.y, c * direction.z - s * direction.x);
}

vec3 render_clouds(vec3 ray, float wind_phase) {
	// A long breeze moves the banks across the roof without losing their framing.
	float drift = 0.22 * sin(wind_phase);
	float c = cos(drift);
	float s = sin(drift);
	vec3 wind_ray = rotate_about_up(ray, c, s);
	vec3 sun_in_bank_space = rotate_about_up(sun_direction, c, s);
	vec3 air = sky_with_cirrus(ray, wind_ray, 0.043 * sin(wind_phase * 2.0));
	if (ray.y < -0.035) {
		return air;
	}

	// Clip each march to its bank and accumulate in-scattered light front to back.
	vec3 axis_sign = mix(vec3(-1.0), vec3(1.0), greaterThanEqual(wind_ray, vec3(0.0)));
	vec3 reciprocal_ray = axis_sign / max(abs(wind_ray), vec3(0.0001));
	vec3 light = vec3(0.0);
	float transmittance = 1.0;
	for (int bank = 0; bank < 6; bank++) {
		vec3 center = BANK_ORIGINS[bank];
		vec2 interval = bank_interval(reciprocal_ray, center, bank);
		if (interval.y <= interval.x) {
			continue;
		}

		float stride = (interval.y - interval.x) / float(VIEW_STEPS);
		for (int step_index = 0; step_index < VIEW_STEPS; step_index++) {
			float distance = interval.x + (float(step_index) + 0.5) * stride;
			vec3 local = wind_ray * distance - center;
			float density = cloud_density(local, bank);
			if (density > 0.005) {
				float opacity = 1.0 - exp(-density * 2.25 * stride);
				vec3 scatter = light_in_cloud(local, density, bank, sun_in_bank_space);
				if (bank >= 4) {
					scatter = mix(scatter, air, 0.28);
				}
				light += transmittance * opacity * scatter;
				transmittance *= 1.0 - opacity;
			}
			if (transmittance < 0.015) {
				break;
			}
		}
		if (transmittance < 0.015) {
			break;
		}
	}

	float cloud_visibility = smoothstep(-0.035, 0.037, ray.y);
	return mix(air, air * transmittance + light, cloud_visibility);
}

void sky() {
	if (AT_CUBEMAP_PASS) {
		COLOR = atmosphere(EYEDIR);
	} else if (AT_HALF_RES_PASS) {
		// Composite RGB here so the visible sky does not rely on subpass alpha.
		// A 300-second cycle returns to the same phase at Godot's TIME rollover.
		COLOR = render_clouds(EYEDIR, TIME * TAU / WIND_CYCLE_SECONDS);
	} else {
		COLOR = HALF_RES_COLOR.rgb;
	}
}
