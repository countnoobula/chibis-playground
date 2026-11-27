extends Control

const BERRY_JOURNAL_FONT: Font = preload("res://ui/menu/berry_journal_font.tres")

const BERRY := Color("#cd2454")
const BERRY_DARK := Color("#9b2450")
const RAIL := Color("#f0cbb7")
const CREAM := Color("#fff0db")
const HIGHLIGHT := Color(1.0, 0.97, 0.88, 0.8)
const FOCUS := Color("#d72e63")

var sliders: Dictionary = {}
var invert_button: Button
var invert_enabled: bool = false
var serif_font: Font


func _draw() -> void:
	_draw_slider(Rect2(345.0, 213.0, 238.0, 34.0), _slider(&"master_volume"))
	_draw_slider(Rect2(350.0, 252.0, 230.0, 34.0), _slider(&"music_volume"))
	_draw_slider(Rect2(350.0, 292.0, 230.0, 34.0), _slider(&"sfx_volume"))
	_draw_slider(Rect2(342.0, 432.0, 240.0, 34.0), _slider(&"sensitivity"))
	_draw_quality_slider(Rect2(695.0, 282.0, 346.0, 28.0), _slider(&"quality"))
	_draw_invert_toggle()


func _slider(key: StringName) -> HSlider:
	return sliders.get(key) as HSlider


func _draw_slider(control_rect: Rect2, slider: HSlider) -> void:
	if slider == null:
		return
	if slider.has_focus():
		var focus_rect := Rect2(
			control_rect.position - Vector2(17.0, 1.0),
			control_rect.size + Vector2(34.0, 2.0)
		)
		draw_style_box(_round_style(Color(1.0, 1.0, 1.0, 0.0), FOCUS, 2, 18), focus_rect)
	var fraction := _value_fraction(slider)
	var rail_height := 14.0
	var rail_rect := Rect2(
		control_rect.position.x,
		control_rect.get_center().y - rail_height * 0.5,
		control_rect.size.x,
		rail_height
	)
	var rail_style := _round_style(RAIL, BERRY_DARK, 2, 9)
	draw_style_box(rail_style, rail_rect)
	var fill_width := clampf(rail_rect.size.x * fraction, 0.0, rail_rect.size.x)
	if fill_width > 0.5:
		var fill_rect := Rect2(rail_rect.position, Vector2(fill_width, rail_height))
		draw_style_box(_round_style(BERRY, Color.TRANSPARENT, 0, 8), fill_rect)
	_draw_thumb(Vector2(rail_rect.position.x + rail_rect.size.x * fraction, rail_rect.get_center().y), 13.0)


func _draw_quality_slider(control_rect: Rect2, slider: HSlider) -> void:
	if slider == null:
		return
	if slider.has_focus():
		var focus_rect := Rect2(
			control_rect.position - Vector2(18.0, 4.0),
			control_rect.size + Vector2(36.0, 8.0)
		)
		draw_style_box(_round_style(Color(1.0, 1.0, 1.0, 0.0), FOCUS, 2, 16), focus_rect)
	var rail_rect := Rect2(control_rect.position.x, 288.5, control_rect.size.x, 11.0)
	draw_style_box(_round_style(RAIL, BERRY_DARK, 2, 8), rail_rect)
	var fraction := _value_fraction(slider)
	var fill_width := clampf(rail_rect.size.x * fraction, 0.0, rail_rect.size.x)
	if fill_width > 0.5:
		draw_style_box(_round_style(BERRY, Color.TRANSPARENT, 0, 8), Rect2(rail_rect.position, Vector2(fill_width, rail_rect.size.y)))
	for index in 4:
		var marker_x := control_rect.position.x + control_rect.size.x * float(index) / 3.0
		var marker_center := Vector2(marker_x, rail_rect.get_center().y)
		draw_circle(marker_center, 6.5, CREAM)
		draw_arc(marker_center, 6.5, 0.0, TAU, 32, BERRY_DARK, 2.0, true)
	var selected_center := Vector2(control_rect.position.x + control_rect.size.x * fraction, rail_rect.get_center().y)
	_draw_thumb(selected_center, 13.5)


func _draw_invert_toggle() -> void:
	var toggle_rect := Rect2(365.0, 468.0, 113.0, 42.0)
	var track_rect := Rect2(toggle_rect.position + Vector2(0.0, 4.0), Vector2(toggle_rect.size.x, toggle_rect.size.y - 8.0))
	draw_style_box(_round_style(Color("#e8b5ad"), Color("#aa5369"), 2, 17), track_rect)
	var knob_x := track_rect.position.x + 18.0 if not invert_enabled else track_rect.end.x - 18.0
	_draw_thumb(Vector2(knob_x, track_rect.get_center().y), 15.0)
	var font := serif_font if serif_font != null else BERRY_JOURNAL_FONT
	var text := "On" if invert_enabled else "Off"
	var text_x := track_rect.position.x + 57.0 if not invert_enabled else track_rect.position.x + 24.0
	draw_string(font, Vector2(text_x, track_rect.get_center().y + 7.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color("#642044"))
	if invert_button != null and invert_button.has_focus():
		draw_style_box(_round_style(Color(1.0, 1.0, 1.0, 0.0), FOCUS, 2, 18), toggle_rect.grow(2.0))


func _draw_thumb(center: Vector2, radius: float) -> void:
	draw_circle(center + Vector2(0.0, 2.0), radius + 1.0, Color(0.39, 0.12, 0.25, 0.23))
	draw_circle(center, radius, BERRY_DARK)
	draw_circle(center, radius - 2.0, CREAM)
	draw_circle(center + Vector2(-radius * 0.24, -radius * 0.28), radius * 0.28, HIGHLIGHT)


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
