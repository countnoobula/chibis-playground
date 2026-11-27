extends Button

signal destination_activated(destination_id: StringName)

const BADGE_IDLE := preload("res://ui/menu/art/atlas/pins/badge_idle.png")
const BADGE_ACTIVE := preload("res://ui/menu/art/atlas/pins/badge_active.png")
const PIN_FONT := preload("res://ui/menu/berry_journal_font.tres")
const RIBBON_SOURCE_POSITION := Vector2(85.0, 41.0)
const RIBBON_SOURCE_SIZE := Vector2(277.0, 68.0)
const RIBBON_CENTER_Y := 75.0
const FACE_SOURCE_RECT := Rect2(15.0, 18.0, 80.0, 80.0)
const TIP_SOURCE_POSITION := Vector2(55.0, 143.0)
const RIBBON_FONT_SIZE := 22
const RIBBON_MIN_WIDTH := 70.0
const RIBBON_MAX_WIDTH := 520.0
const RIBBON_TEXT_PADDING := 70.0

@onready var _portrait: TextureRect = $Portrait
@onready var _ribbon: TextureRect = $Ribbon
@onready var _ribbon_label: Label = $Ribbon/TitleLabel

var destination_id: StringName = &""
var display_name := ""
var tip_offset := Vector2.ZERO

var _hit_mask := BitMap.new()
var _selected := false
var _hovered := false
var _scale_factor := 0.75
var _badge_size := Vector2.ZERO
var _ribbon_hit_mask := BitMap.new()


func _ready() -> void:
	pressed.connect(func(): destination_activated.emit(destination_id))
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(set_pointer_hovered.bind(true))
	mouse_exited.connect(set_pointer_hovered.bind(false))


func configure(record: Dictionary) -> void:
	destination_id = StringName(record.get("id", ""))
	display_name = str(record.get("title", ""))
	tooltip_text = display_name
	accessibility_name = display_name
	accessibility_description = "Select %s." % display_name if not display_name.is_empty() else "Select destination."

	var pin: Dictionary = record.get("pin", {})
	_scale_factor = maxf(0.1, float(pin.get("scale", 0.75)))
	_badge_size = BADGE_IDLE.get_size() * _scale_factor
	tip_offset = TIP_SOURCE_POSITION * _scale_factor
	_hit_mask.create_from_image_alpha(BADGE_IDLE.get_image(), 0.12)

	var illustration_path := str(pin.get("image", ""))
	_portrait.texture = load(illustration_path) as Texture2D if not illustration_path.is_empty() else null
	var face_rect := Rect2(FACE_SOURCE_RECT.position * _scale_factor, FACE_SOURCE_RECT.size * _scale_factor)
	_portrait.position = face_rect.position
	_portrait.size = face_rect.size
	_portrait.visible = _portrait.texture != null

	_layout_ribbon(str(pin.get("text", display_name)))
	queue_redraw()


func _layout_ribbon(caption: String) -> void:
	var font_size := maxi(12, roundi(RIBBON_FONT_SIZE * _scale_factor))
	_ribbon_label.add_theme_font_size_override("font_size", font_size)
	_ribbon_label.text = caption
	var text_width := PIN_FONT.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var width := clampf(text_width + RIBBON_TEXT_PADDING * _scale_factor,
		RIBBON_MIN_WIDTH * _scale_factor, RIBBON_MAX_WIDTH * _scale_factor)

	# Leave room for the badge overlap on the left and the tapered tail on the right.
	var left := (_badge_size.x - RIBBON_SOURCE_POSITION.x * _scale_factor) + 8.0 * _scale_factor
	var right := width * 0.065 + 8.0 * _scale_factor
	_ribbon_label.size.x = maxf(1.0, width - left - right)
	var line_count := maxi(1, _ribbon_label.get_line_count())
	var text_height := _ribbon_label.get_line_height() * line_count
	text_height += _ribbon_label.get_theme_constant("line_spacing") * (line_count - 1)
	# The opaque paper occupies about 46 of the texture's 68 source pixels.
	var height := maxf(RIBBON_SOURCE_SIZE.y * _scale_factor,
		(text_height + 10.0 * _scale_factor) * RIBBON_SOURCE_SIZE.y / 46.0)
	var ribbon_y := RIBBON_CENTER_Y * _scale_factor - height * 0.5
	var badge_y := maxf(0.0, -ribbon_y)
	_ribbon.position = Vector2(RIBBON_SOURCE_POSITION.x * _scale_factor, ribbon_y + badge_y)
	_ribbon.size = Vector2(width, height)
	_portrait.position.y = FACE_SOURCE_RECT.position.y * _scale_factor + badge_y
	tip_offset = TIP_SOURCE_POSITION * _scale_factor + Vector2.DOWN * badge_y
	_ribbon_label.position = Vector2(left, 0)
	_ribbon_label.size.y = height
	var curve := _ribbon_label.material as ShaderMaterial
	curve.set_shader_parameter("ribbon_size", _ribbon.size)
	curve.set_shader_parameter("label_left", left)
	# Center the ink of the journal font, including its ascenders and descenders.
	curve.set_shader_parameter("optical_lift", font_size * 0.075)
	_ribbon_hit_mask.create_from_image_alpha(_ribbon.texture.get_image(), 0.12)
	custom_minimum_size = Vector2(
		maxf(_badge_size.x, _ribbon.get_rect().end.x),
		maxf(badge_y + _badge_size.y, _ribbon.get_rect().end.y)
	)
	size = custom_minimum_size

func set_selected(selected: bool) -> void:
	_selected = selected
	accessibility_description = "Selected %s." % display_name if selected else "Select %s." % display_name
	queue_redraw()


func set_pointer_hovered(hovered: bool) -> void:
	_hovered = hovered
	queue_redraw()


func _has_point(point: Vector2) -> bool:
	var badge_origin := tip_offset - TIP_SOURCE_POSITION * _scale_factor
	if Rect2(badge_origin, _badge_size).has_point(point):
		var badge_pixel := Vector2i((point - badge_origin) * BADGE_IDLE.get_size() / _badge_size)
		if _hit_mask.get_bitv(badge_pixel):
			return true
	if not Rect2(_ribbon.position, _ribbon.size).has_point(point):
		return false
	var ribbon_point := point - _ribbon.position
	var ribbon_pixel := Vector2i(ribbon_point * Vector2(_ribbon.texture.get_size()) / _ribbon.size)
	return _ribbon_hit_mask.get_bitv(ribbon_pixel)


func _draw() -> void:
	var badge := BADGE_ACTIVE if _selected or _hovered or has_focus() else BADGE_IDLE
	draw_texture_rect(badge, Rect2(tip_offset - TIP_SOURCE_POSITION * _scale_factor, _badge_size), false)
