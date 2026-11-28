shader_type sky;
render_mode use_quarter_res_pass, disable_fog;

#define ROOFTOP_CELESTIAL_PREVIEW
#include "res://levels/rooftop_gym/shaders/rooftop_clouds.gdshaderinc"

void sky() {
	if (AT_CUBEMAP_PASS) {
		COLOR = atmosphere(EYEDIR);
	} else if (AT_QUARTER_RES_PASS) {
		vec4 clouds = render_clouds(EYEDIR, rooftop_cloud_phase);
		COLOR = clouds.rgb;
		ALPHA = clouds.a;
	} else {
		COLOR = QUARTER_RES_COLOR.rgb;
		if (EYEDIR.y >= -0.035) {
			// Mobile's sky sampling divides the packed alpha by its 0.5 luminance multiplier.
			float clear_sky = clamp(QUARTER_RES_COLOR.a * 0.5, 0.0, 1.0);
			COLOR += celestial_discs(EYEDIR) * clear_sky;
		}
	}
}
