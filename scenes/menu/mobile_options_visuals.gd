extends Control

const INK := Color("#4f1939")
const BERRY := Color("#cc2857")
const BERRY_DARK := Color("#98244d")
const RAIL := Color("#f0cbb7")
const CREAM := Color("#fff0db")
const THUMB := preload("res://scenes/menu/art/mobile_options/slider_thumb.png")
const TAB_RECTS := [
	Rect2(159.0, 189.0, 350.0, 129.0),
	Rect2(159.0, 335.0, 346.0, 115.0),
	Rect2(159.0, 473.0, 346.0, 117.0),
]

var sliders: Dictionary = {}
var invert_button: Button
var invert_enabled: bool = false
var serif_font: Font
var selected_section: int = 0
var has_selected_tab_overlay: bool = false


func _draw() -> void:
	if not has_selected_tab_overlay:
		var tab_rect: Rect2 = TAB_RECTS[clampi(selected_section, 0, TAB_RECTS.size() - 1)]
		draw_style_box(_round_style(Color(1.0, 1.0, 1.0, 0.0), BERRY, 3, 30), tab_rect.grow(2.0))
	for key in sliders:
		var slider := _slider(key)
		if not slider.is_visible_in_tree():
			continue
		if key == &"quality":
			_draw_quality_slider(slider.get_rect(), slider)
		else:
			_draw_volume_slider(slider.get_rect(), slider)
	_draw_invert_toggle()


func _slider(key: StringName) -> HSlider:
	return sliders.get(key) as HSlider


func _draw_volume_slider(control_rect: Rect2, slider: HSlider) -> void:
	if slider == null or not slider.is_visible_in_tree():
		return
	if slider.has_focus():
		var focus_rect := Rect2(
			control_rect.position - Vector2(32.0, 4.0),
			control_rect.size + Vector2(64.0, 8.0)
		)
		draw_style_box(_round_style(Color(1.0, 1.0, 1.0, 0.0), BERRY, 3, 30), focus_rect)
	var center_y := control_rect.get_center().y
	var rail_rect := Rect2(control_rect.position.x, center_y - 12.0, control_rect.size.x, 24.0)
	draw_style_box(_round_style(RAIL, BERRY_DARK, 3, 14), rail_rect)
	var fraction := _value_fraction(slider)
	var fill_width := clampf(rail_rect.size.x * fraction, 0.0, rail_rect.size.x)
	if fill_width > 0.5:
		draw_style_box(_round_style(BERRY, Color.TRANSPARENT, 0, 13), Rect2(rail_rect.position, Vector2(fill_width, rail_rect.size.y)))
	_draw_thumb(Vector2(rail_rect.position.x + rail_rect.size.x * fraction, center_y), 28.0)


func _draw_quality_slider(control_rect: Rect2, slider: HSlider) -> void:
	if slider == null or not slider.is_visible_in_tree():
		return
	if slider.has_focus():
		var focus_rect := Rect2(
			control_rect.position - Vector2(34.0, 5.0),
			control_rect.size + Vector2(68.0, 10.0)
		)
		draw_style_box(_round_style(Color(1.0, 1.0, 1.0, 0.0), BERRY, 3, 28), focus_rect)
	var rail_rect := Rect2(control_rect.position.x, 304.0, control_rect.size.x, 22.0)
	draw_style_box(_round_style(RAIL, BERRY_DARK, 3, 13), rail_rect)
	var fraction := _value_fraction(slider)
	var fill_width := clampf(rail_rect.size.x * fraction, 0.0, rail_rect.size.x)
	if fill_width > 0.5:
		draw_style_box(_round_style(BERRY, Color.TRANSPARENT, 0, 12), Rect2(rail_rect.position, Vector2(fill_width, rail_rect.size.y)))
	for index in 4:
		var marker_x := control_rect.position.x + control_rect.size.x * float(index) / 3.0
		var marker_center := Vector2(marker_x, rail_rect.get_center().y)
		draw_circle(marker_center, 9.0, CREAM)
		draw_arc(marker_center, 9.0, 0.0, TAU, 32, BERRY_DARK, 3.0, true)
	var selected_center := Vector2(control_rect.position.x + control_rect.size.x * fraction, rail_rect.get_center().y)
	_draw_thumb(selected_center, 29.0)


func _draw_invert_toggle() -> void:
	if invert_button == null or not invert_button.is_visible_in_tree():
		return
	var track_rect := Rect2(977.0, 342.0, 265.0, 60.0)
	draw_style_box(_round_style(Color("#e8b5ad"), Color("#aa5369"), 3, 30), track_rect)
	var knob_x := track_rect.position.x + 30.0 if not invert_enabled else track_rect.end.x - 30.0
	_draw_thumb(Vector2(knob_x, track_rect.get_center().y), 27.0)
	var font := serif_font if serif_font != null else ThemeDB.fallback_font
	var text := "Off" if not invert_enabled else "On"
	var text_x := track_rect.position.x + 108.0 if not invert_enabled else track_rect.position.x + 46.0
	draw_string(font, Vector2(text_x, track_rect.get_center().y + 10.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 30, INK)
	if invert_button.has_focus():
		draw_style_box(_round_style(Color(1.0, 1.0, 1.0, 0.0), BERRY, 3, 32), track_rect.grow(8.0))


func _draw_thumb(center: Vector2, radius: float) -> void:
	var diameter := (radius * 2.0) * 64.0 / 55.5
	draw_circle(center + Vector2(0, 3), radius, Color(0.34, 0.12, 0.24, 0.18), true, -1, true)
	draw_texture_rect(THUMB, Rect2(center - Vector2.ONE * diameter * 0.5, Vector2.ONE * diameter), false)



func _value_fraction(slider: HSlider) -> float:
	if is_equal_approx(slider.max_value, slider.min_value):
		return 0.0
	return clampf(inverse_lerp(slider.min_value, slider.max_value, slider.value), 0.0, 1.0)


func _round_style(fill: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style
