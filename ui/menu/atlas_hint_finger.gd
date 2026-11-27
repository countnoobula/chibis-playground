extends TextureRect

var elapsed := 0.0


func _ready() -> void:
	pivot_offset = Vector2(46, 48)


func _process(delta: float) -> void:
	elapsed = fmod(elapsed + delta, 3.4)
	# Pause at center, then sweep the fingertip in a shallow arc.
	var progress := clampf((elapsed - 0.55) / 2.45, 0.0, 1.0)
	var sweep := sin(TAU * smoothstep(0.0, 1.0, progress))
	position = Vector2(7.0 * sweep, -2.5 * sweep * sweep)
	rotation = deg_to_rad(5.0 * sweep)
