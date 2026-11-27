extends Control

## Hit regions sit directly over the three illustrated index patches.
signal section_selected(section: int)

const NAMES := ["Audio", "Camera", "Graphics"]
const PATCHES: Array[Rect2] = [
	Rect2(126, 32, 168, 64),
	Rect2(125, 110, 169, 62),
	Rect2(125, 187, 169, 62),
]
const INACTIVE_AUDIO := preload("res://scenes/menu/art/mobile_options/tab_audio_inactive.png")
var _selected := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var empty := StyleBoxEmpty.new()
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color("#8a3972")
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(12)
	for index in NAMES.size():
		var button := Button.new()
		button.name = NAMES[index] + "SectionButton"
		button.accessibility_name = NAMES[index]
		button.position = PATCHES[index].position
		button.size = PATCHES[index].size
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for style in ["normal", "hover", "pressed", "hover_pressed"]:
			button.add_theme_stylebox_override(style, empty)
		button.add_theme_stylebox_override("focus", focus)
		button.pressed.connect(_select.bind(index))
		add_child(button)


func _select(index: int) -> void:
	_selected = index
	section_selected.emit(index)
	queue_redraw()


func set_selected(section: int) -> void:
	_selected = clampi(section, 0, NAMES.size() - 1)
	queue_redraw()


func _draw() -> void:
	if _selected != 0:
		draw_texture_rect(INACTIVE_AUDIO, PATCHES[0], false)
	var selected_style := StyleBoxFlat.new()
	selected_style.bg_color = Color("#d8c9ec", 0.18)
	selected_style.border_color = Color("#795c9f")
	selected_style.set_border_width_all(4)
	selected_style.set_corner_radius_all(16)
	selected_style.anti_aliasing = true
	draw_style_box(selected_style, PATCHES[_selected].grow(-2.0))
