extends Control

const DESIGN_SIZE := Vector2(1280.0, 720.0)
const SOURCE_SIZE := Vector2(1672.0, 941.0)
const BERRY_BOUNDS := Rect2i(570, 178, 90, 110)
const STROKE_BOUNDS := [
	Rect2i(649, 216, 45, 23),
	Rect2i(645, 239, 47, 25),
	Rect2i(638, 252, 44, 34),
]
const BERRY_PULSE_SCALE := Vector2.ONE * 1.10
const RAY_REVEAL_DURATION := 0.33
const MAX_BERRY_ROTATION := deg_to_rad(10.0)

@onready var berry_button: TextureButton = $BerryButton
@onready var ray_one: Control = $BerryStroke1Reveal
@onready var ray_two: Control = $BerryStroke2Reveal
@onready var ray_three: Control = $BerryStroke3Reveal

var _rays: Array[Control]
var _ray_full_sizes: Array[Vector2]
var _berry_tween: Tween
var _ray_tween: Tween
var _wiggle_schedule_generation := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rays = [ray_one, ray_two, ray_three]
	_layout_art()
	berry_button.pressed.connect(_on_berry_pressed)
	_schedule_wiggle()


func _layout_art() -> void:
	var art_scale := DESIGN_SIZE / SOURCE_SIZE
	_set_art_bounds(berry_button, BERRY_BOUNDS, art_scale)
	berry_button.pivot_offset = berry_button.size * 0.5
	_ray_full_sizes.clear()
	for index in range(_rays.size()):
		var ray := _rays[index]
		_set_art_bounds(ray, STROKE_BOUNDS[index], art_scale)
		_ray_full_sizes.append(ray.size)
		var texture_rect: TextureRect = ray.get_node("Texture")
		texture_rect.position = Vector2.ZERO
		texture_rect.size = ray.size


func _set_art_bounds(control: Control, source_bounds: Rect2i, art_scale: Vector2) -> void:
	control.position = Vector2(source_bounds.position) * art_scale
	control.size = Vector2(source_bounds.size) * art_scale


func _on_berry_pressed() -> void:
	_wiggle_schedule_generation += 1
	if _berry_tween != null and _berry_tween.is_running():
		_berry_tween.kill()
	if _ray_tween != null and _ray_tween.is_running():
		_ray_tween.kill()
	_animate_berry_click()
	_redraw_rays()


func _animate_berry_click() -> void:
	var starting_rotation := berry_button.rotation
	var tween := create_tween()
	_berry_tween = tween
	tween.set_parallel(true)
	tween.tween_property(berry_button, "scale", BERRY_PULSE_SCALE, 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(berry_button, "rotation", clampf(starting_rotation + deg_to_rad(6.0), -MAX_BERRY_ROTATION, MAX_BERRY_ROTATION), 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(berry_button, "rotation", clampf(starting_rotation - deg_to_rad(6.0), -MAX_BERRY_ROTATION, MAX_BERRY_ROTATION), 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.chain().tween_property(berry_button, "rotation", clampf(starting_rotation + deg_to_rad(2.0), -MAX_BERRY_ROTATION, MAX_BERRY_ROTATION), 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.chain().set_parallel(true)
	tween.tween_property(berry_button, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(berry_button, "rotation", 0.0, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.finished.connect(_schedule_wiggle, CONNECT_ONE_SHOT)


func _redraw_rays() -> void:
	var tween := create_tween()
	_ray_tween = tween
	tween.set_parallel(true)
	for index in range(_rays.size()):
		_rays[index].size.x = 0.0
		_rays[index].modulate.a = 0.0
		tween.tween_property(_rays[index], "modulate:a", 1.0, RAY_REVEAL_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(_rays[index], "size:x", _ray_full_sizes[index].x, RAY_REVEAL_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _schedule_wiggle() -> void:
	if not is_inside_tree():
		return
	_wiggle_schedule_generation += 1
	var schedule_generation := _wiggle_schedule_generation
	var timer := get_tree().create_timer(randf_range(3.0, 5.5))
	timer.timeout.connect(_on_wiggle_timer.bind(schedule_generation), CONNECT_ONE_SHOT)


func _on_wiggle_timer(schedule_generation: int) -> void:
	if schedule_generation != _wiggle_schedule_generation or not is_inside_tree():
		return
	var tween := create_tween()
	_berry_tween = tween
	tween.tween_property(berry_button, "rotation", deg_to_rad(4.0), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(berry_button, "rotation", deg_to_rad(-3.0), 0.20).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(berry_button, "rotation", 0.0, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.finished.connect(_schedule_wiggle, CONNECT_ONE_SHOT)
