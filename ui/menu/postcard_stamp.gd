extends Control

## Cream paper with a shallow perforation at regular intervals on each edge.
func _draw() -> void:
	var corners := PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	var outline := PackedVector2Array()
	for i in range(4):
		var start := corners[i]
		var edge := corners[(i + 1) % 4] - start
		var tangent := edge.normalized()
		var inward := Vector2(-tangent.y, tangent.x)
		var count := maxi(1, roundi(edge.length() / 11.0))
		var spacing := edge.length() / count
		outline.append(start)
		for notch in range(count):
			var center := start + tangent * ((notch + 0.5) * spacing)
			for step in range(7):
				var angle := PI * step / 6.0
				outline.append(center + 2.8 * (-cos(angle) * tangent + sin(angle) * inward))
	draw_set_transform(Vector2(1.1, 2.7))
	draw_colored_polygon(outline, Color("#79544155"))
	draw_set_transform(Vector2.ZERO)
	draw_colored_polygon(outline, Color("#fff9e9"))
	outline.append(outline[0])
	draw_polyline(outline, Color("#cbb298"), 0.9, true)
	draw_rect(Rect2(Vector2(10, 10), size - Vector2(20, 20)), Color("#ba9b86"), false, 1, true)
