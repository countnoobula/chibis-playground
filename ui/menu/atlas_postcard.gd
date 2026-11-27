extends Control

signal launch_requested

class StitchOverlay extends Control:
	const STITCH_COLOR := Color("#F7CCB1")

	func _draw() -> void:
		for x in range(24, int(size.x) - 24, 15):
			draw_line(Vector2(x, 7), Vector2(x + 6, 7), STITCH_COLOR, 1.5, true)
			draw_line(Vector2(x, size.y - 7), Vector2(x + 6, size.y - 7), STITCH_COLOR, 1.5, true)
		for y in range(24, int(size.y) - 24, 15):
			draw_line(Vector2(7, y), Vector2(7, y + 6), STITCH_COLOR, 1.5, true)
			draw_line(Vector2(size.x - 7, y), Vector2(size.x - 7, y + 6), STITCH_COLOR, 1.5, true)


const AtlasCatalog := preload("res://ui/menu/atlas_catalog.gd")
const BUTTON_BASE := preload("res://ui/menu/art/buttons/patch_base.png")

@onready var _hero_art: TextureRect = $HeroFrame/HeroArt
@onready var _title_label: Label = $TitleLabel
@onready var _lead_in_label: RichTextLabel = $LeadInLabel
@onready var _description_label: Label = $DescriptionLabel
@onready var _launch_button: TextureButton = $LaunchButton
@onready var _launch_label: Label = $LaunchButton/LaunchLabel
@onready var _focus_ring: Panel = $LaunchButton/FocusRing

var _record: Dictionary = {}
var _current_destination: StringName = &""
var _availability_text := ""
var _lead_in_text := ""
var _launch_is_available := false
var _launch_scene := ""

var current_destination: StringName:
	get:
		return _current_destination

var availability_label: String:
	get:
		return _availability_text

var lead_in_text: String:
	get:
		return _lead_in_text

var launch_available: bool:
	get:
		return _launch_is_available


func _ready() -> void:
	_launch_button.texture_normal = BUTTON_BASE
	_launch_button.texture_hover = BUTTON_BASE
	_launch_button.texture_pressed = BUTTON_BASE
	_launch_button.texture_focused = BUTTON_BASE
	_launch_button.texture_disabled = BUTTON_BASE
	_launch_button.ignore_texture_size = true
	_launch_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_launch_button.pressed.connect(_on_launch_pressed)
	_launch_button.focus_entered.connect(_show_focus_ring)
	_launch_button.focus_exited.connect(_hide_focus_ring)
	_launch_button.mouse_entered.connect(_show_focus_ring)
	_launch_button.mouse_exited.connect(_hide_mouse_focus_ring)
	_add_stitch_overlay()


func present(record: Dictionary) -> void:
	if record.is_empty():
		push_warning("Cannot present an empty atlas destination record.")
		return

	_record = record
	_current_destination = StringName(record.get("id", ""))
	var title := str(record.get("title", ""))
	_title_label.text = title
	_lead_in_text = str(record.get("tagline", ""))
	_lead_in_label.text = "[i]%s[/i]" % _lead_in_text if not _lead_in_text.is_empty() else ""
	_description_label.text = str(record.get("description", ""))
	var sticker_path := str(record.get("sticker", ""))
	_hero_art.texture = load(sticker_path) as Texture2D if not sticker_path.is_empty() else null

	_launch_scene = str(AtlasCatalog.launch_scene(record))
	_launch_is_available = not _launch_scene.is_empty()
	_availability_text = "Available" if _launch_is_available else "Coming soon"
	_launch_button.disabled = not _launch_is_available
	_launch_button.focus_mode = Control.FOCUS_ALL if _launch_is_available else Control.FOCUS_NONE
	_launch_label.text = "Play" if _launch_is_available else "Coming soon"
	_launch_button.accessibility_name = "%s %s" % [_launch_label.text, title]
	_launch_button.accessibility_description = "Launch %s." % title if _launch_is_available else "%s is coming soon." % title
	_launch_button.tooltip_text = _launch_button.accessibility_description
	_launch_button.modulate = Color.WHITE if _launch_is_available else Color("#D9D0C8")
	_launch_label.add_theme_color_override("font_color", Color("#642044") if _launch_is_available else Color("#8D706D"))
	_focus_ring.visible = false


func _add_stitch_overlay() -> void:
	var stitches := StitchOverlay.new()
	stitches.name = "StitchOverlay"
	stitches.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stitches.focus_mode = Control.FOCUS_NONE
	stitches.z_index = 10
	add_child(stitches)
	stitches.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _show_focus_ring() -> void:
	if _launch_is_available:
		_focus_ring.show()


func _hide_focus_ring() -> void:
	_focus_ring.hide()


func _hide_mouse_focus_ring() -> void:
	if not _launch_button.has_focus():
		_focus_ring.hide()


func _on_launch_pressed() -> void:
	if not _launch_is_available or _launch_scene.is_empty():
		return
	launch_requested.emit()
