extends Control

signal back_requested

const DESIGN_SIZE := Vector2(1280.0, 720.0)
const BACK_POSITION := Vector2.ZERO
const BACK_SIZE := Vector2(170.0, 76.0)
const BACK_RING_INSET := Vector2(8.0, 7.0)
const POSTCARD_POSITION := Vector2(988.0, 542.0)
const POSTCARD_SIZE := Vector2(268.0, 90.0)
const PLAY_LABEL_RECT := Rect2(8.0, 5.0, 252.0, 49.0)
const STATUS_LABEL_RECT := Rect2(8.0, 56.0, 252.0, 27.0)
const STATIC_HINT_RECT := Rect2(0.0, 656.0, 294.0, 64.0)

@onready var design_canvas: Control = $DesignCanvas
@onready var back_button: Button = $DesignCanvas/BackButton
@onready var back_focus_ring: Panel = $DesignCanvas/BackButton/FocusRing
@onready var postcard: Control = $DesignCanvas/Postcard
@onready var launch_button: Button = $DesignCanvas/Postcard/LaunchButton
@onready var status_label: Label = $DesignCanvas/Postcard/StatusLabel
@onready var static_hint_cover: PanelContainer = $DesignCanvas/StaticHintCover


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	back_button.accessibility_name = "Back"
	back_button.accessibility_description = "Return to the title screen."
	back_button.tooltip_text = "Back to title"
	back_button.pressed.connect(_on_back_pressed)
	back_button.focus_neighbor_left = back_button.get_path_to(back_button)
	back_button.focus_neighbor_right = back_button.get_path_to(back_button)
	back_button.focus_neighbor_top = back_button.get_path_to(back_button)
	back_button.focus_neighbor_bottom = back_button.get_path_to(back_button)
	back_button.focus_entered.connect(_show_back_focus_ring)
	back_button.focus_exited.connect(_hide_back_focus_ring)
	launch_button.accessibility_name = "Play First Steps Valley"
	launch_button.accessibility_description = "Coming soon. First Steps Valley is still in progress."
	launch_button.disabled = true
	status_label.text = "Coming soon"
	get_viewport().size_changed.connect(fit_to_visible_area)
	resized.connect(fit_to_visible_area)
	fit_to_visible_area()


func fit_to_visible_area() -> void:
	if not is_node_ready() or size.x <= 0.0 or size.y <= 0.0:
		return
	var fit_scale := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	design_canvas.size = DESIGN_SIZE
	design_canvas.scale = Vector2.ONE * fit_scale
	design_canvas.position = (size - DESIGN_SIZE * fit_scale) * 0.5
	back_button.position = BACK_POSITION
	back_button.size = BACK_SIZE
	back_focus_ring.position = BACK_RING_INSET
	back_focus_ring.size = BACK_SIZE - BACK_RING_INSET * 2.0
	postcard.position = POSTCARD_POSITION
	postcard.size = POSTCARD_SIZE
	launch_button.position = Vector2.ZERO
	launch_button.size = POSTCARD_SIZE
	status_label.position = STATUS_LABEL_RECT.position
	status_label.size = STATUS_LABEL_RECT.size
	static_hint_cover.position = STATIC_HINT_RECT.position
	static_hint_cover.size = STATIC_HINT_RECT.size


func focus_back() -> void:
	back_button.grab_focus()


func _show_back_focus_ring() -> void:
	back_focus_ring.show()


func _hide_back_focus_ring() -> void:
	back_focus_ring.hide()


func _on_back_pressed() -> void:
	back_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not (event is InputEventKey and event.echo):
		get_viewport().set_input_as_handled()
		back_requested.emit()
