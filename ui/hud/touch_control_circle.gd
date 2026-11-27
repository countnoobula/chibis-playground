extends Control

## Draws a touch control. TouchControlsHUD owns hit testing and finger state.

const INK := Color("302b3d")
const CREAM := Color("fff8ee")
const SILHOUETTES := preload("res://ui/art/touch_action_icons.png")
const CELL_SIZE := 128
const ICON_CELLS := {
	"jump": Vector2i(0, 0), "slide": Vector2i(1, 0), "pickup": Vector2i(2, 0),
	"ledge": Vector2i(0, 1), "drop": Vector2i(1, 1), "off": Vector2i(2, 1),
	"swim_up": Vector2i(0, 2), "dive": Vector2i(1, 2), "wall_leap": Vector2i(2, 2),
}

var accent := Color("c3b1d9")
var caption := "" # Semantic action name for inspection and tests.
var symbol := ""
var held := false
var inactive := false
var stick_offset := Vector2.ZERO
var hit_padding := 5.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func contains_point(point: Vector2) -> bool:
	return is_visible_in_tree() and get_global_rect().get_center().distance_to(point) <= size.x * 0.5 + hit_padding


func _draw() -> void:
	var center := size * 0.5
	var radius := center.x - 2.0
	if radius <= 0.0:
		return
	var fill := Color(INK, 0.22 if inactive else 0.41)
	if held and not inactive:
		fill = Color(INK.lerp(accent, 0.22), 0.52 if symbol == "stick" else 0.72)
	draw_arc(center + Vector2(0, 1.5), radius + 1.0, 0.0, TAU, 64, Color(INK, 0.28), 2.0, true)
	draw_circle(center, radius, fill, true, -1.0, true)
	draw_arc(center, radius, 0.0, TAU, 64, Color(CREAM, 0.34 if inactive else 0.70), 1.5, true)
	if held and not inactive:
		draw_arc(center, radius - 4.0, 0.0, TAU, 64, Color(accent, 0.92), 2.0, true)
	if symbol == "stick":
		var knob := center + stick_offset
		draw_circle(knob, radius * 0.30, Color(accent, 0.66), true, -1.0, true)
		draw_arc(knob, radius * 0.30, 0.0, TAU, 32, Color(CREAM, 0.84), 1.5, true)
		return

	var icon_color := Color(CREAM, 0.42) if inactive else CREAM
	if ICON_CELLS.has(symbol):
		var cell: Vector2i = ICON_CELLS[symbol]
		var icon_size := Vector2.ONE * size.x * 0.75
		var region := Rect2(Vector2(cell * CELL_SIZE), Vector2.ONE * CELL_SIZE)
		draw_texture_rect_region(SILHOUETTES, Rect2(center - icon_size * 0.5, icon_size), region, icon_color)
	else:
		var extent := size.x * (0.30 if symbol == "gear" else 0.32)
		_draw_symbol(center, extent, icon_color)


func _draw_symbol(center: Vector2, extent: float, icon_color: Color) -> void:
	var stroke := maxf(1.5, extent * 0.14)
	match symbol:
		"parachute":
			var hem_y := extent * 0.13
			var hem_left := center + Vector2(-0.74 * extent, hem_y)
			var hem_right := center + Vector2(0.74 * extent, hem_y)
			var harness := center + Vector2(0.0, extent * 0.72)
			draw_arc(center + Vector2(0.0, hem_y), extent * 0.74, PI, TAU, 32, icon_color, stroke, true)
			draw_line(hem_left, hem_right, icon_color, stroke, true)
			draw_line(hem_left, harness, icon_color, stroke, true)
			draw_line(hem_right, harness, icon_color, stroke, true)
			draw_line(center + Vector2(0.0, -extent * 0.61), center + Vector2(0.0, hem_y), icon_color, stroke * 0.72, true)
			draw_circle(harness, stroke * 0.7, icon_color, true, -1.0, true)
		"gear":
			draw_arc(center, extent * 0.52, 0.0, TAU, 32, icon_color, stroke * 1.5, true)
			for i in 8:
				var direction := Vector2.from_angle(i * TAU / 8.0)
				draw_line(center + direction * extent * 0.53, center + direction * extent * 0.79, icon_color, stroke * 1.6, true)
			draw_circle(center, extent * 0.14, icon_color, true, -1.0, true)
