shader_type canvas_item;
render_mode unshaded;

uniform vec2 ribbon_size = vec2(277.0, 68.0);
uniform float label_left = 0.0;
uniform float optical_lift = 1.0;

void vertex() {
	// In the 277 x 68 source art the top/bottom midpoint rises from y=32
	// to y=30 near x=100, then falls to y=37 just before the notched end.
	float x = clamp((VERTEX.x + label_left) / ribbon_size.x, 0.0, 0.92);
	float from_crest = x - 0.36;
	float center_y = 30.25 + (from_crest < 0.0 ? 13.5 : 24.0) * from_crest * from_crest;
	VERTEX.y += (center_y / 68.0 - 0.5) * ribbon_size.y - optical_lift;
}
