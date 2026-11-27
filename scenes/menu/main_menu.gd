extends Control

const DESIGN_SIZE := Vector2(1280, 720)

var _touch_index := -1

@onready var artwork_canvas: Control = $ArtworkCanvas


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if OS.get_cmdline_user_args().has("--mobile-menu"):
		get_window().title = "Strawberry Hollow · Mobile preview"
	resized.connect(_fit_canvas)
	_fit_canvas()
	$ArtworkCanvas/TitleControls.options_requested.connect(_open_options)


func _fit_canvas() -> void:
	var fit_scale := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	artwork_canvas.scale = Vector2.ONE * fit_scale
	artwork_canvas.position = (size - DESIGN_SIZE * fit_scale) * 0.5


func _open_options() -> void:
	var mobile: bool = $ArtworkCanvas/TitleControls.mobile_layout
	var scene := preload("res://scenes/menu/mobile_options.tscn") if mobile else preload("res://scenes/menu/options.tscn")
	var options := scene.instantiate()
	var parent: Control = self if mobile else artwork_canvas
	$ArtworkCanvas/TitleArt.hide()
	$ArtworkCanvas/TitleControls.hide()
	options.back_requested.connect(_close_options.bind(options))
	parent.add_child(options)


func _close_options(options: Control) -> void:
	options.hide()
	options.queue_free()
	$ArtworkCanvas/TitleArt.show()
	$ArtworkCanvas/TitleControls.show()
	$ArtworkCanvas/TitleControls/OptionsButton.grab_focus.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_touch_index = -1


# Gameplay handles touch directly, so global mouse-from-touch emulation is disabled.
# Feed the journal, berry, and menu buttons one pointer while this screen is open.
func _input(event: InputEvent) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION or Input.emulate_mouse_from_touch:
		return
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			_touch_index = event.index
		if event.index != _touch_index:
			return
		var pointer := InputEventMouseButton.new()
		pointer.position = event.position
		pointer.global_position = event.position
		pointer.button_index = MOUSE_BUTTON_LEFT
		pointer.pressed = event.pressed
		pointer.button_mask = MOUSE_BUTTON_MASK_LEFT if event.pressed else 0
		pointer.canceled = event.canceled
		if not event.pressed:
			_touch_index = -1
		_send_touch_pointer(pointer)
	elif event is InputEventScreenDrag and event.index == _touch_index:
		var motion := InputEventMouseMotion.new()
		motion.position = event.position
		motion.global_position = event.position
		motion.relative = event.relative
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		_send_touch_pointer(motion)


func _send_touch_pointer(event: InputEventMouse) -> void:
	var viewport := get_viewport()
	viewport.set_input_as_handled()
	event.device = InputEvent.DEVICE_ID_EMULATION
	viewport.push_input(event, true)
