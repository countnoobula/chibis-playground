shader_type sky;
render_mode use_quarter_res_pass, disable_fog;

#include "res://levels/rooftop_gym/shaders/rooftop_clouds.gdshaderinc"

void sky() {
	if (AT_CUBEMAP_PASS) {
		COLOR = atmosphere(EYEDIR);
	} else if (AT_QUARTER_RES_PASS) {
		// Composite RGB here so the visible sky does not rely on subpass alpha.
		COLOR = render_clouds(EYEDIR, rooftop_cloud_phase);
	} else {
		COLOR = QUARTER_RES_COLOR.rgb;
	}
}
