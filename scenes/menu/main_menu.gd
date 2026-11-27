extends Control

const DESIGN_SIZE := Vector2(1280, 720)
const MOBILE_CROP_TOP_FRACTION := 0.10

var _pointer := preload("res://scripts/ui/menu_touch_pointer.gd").new()

@onready var artwork_canvas: Control = $ArtworkCanvas


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if OS.get_cmdline_user_args().has("--mobile-menu"):
		get_window().title = "Strawberry Hollow · Mobile preview"
	resized.connect(_fit_canvas)
	_fit_canvas()
	$ArtworkCanvas/TitleControls.options_requested.connect(_open_options)


func _fit_canvas() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var is_mobile_layout := OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--mobile-menu")
	var is_wide_landscape := size.x / size.y > DESIGN_SIZE.x / DESIGN_SIZE.y
	var fit_scale: float
	if is_mobile_layout and is_wide_landscape:
		fit_scale = maxf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
		var vertical_crop := maxf(0.0, DESIGN_SIZE.y * fit_scale - size.y)
		artwork_canvas.position = Vector2(
			(size.x - DESIGN_SIZE.x * fit_scale) * 0.5,
			-vertical_crop * MOBILE_CROP_TOP_FRACTION
		)
	else:
		fit_scale = minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
		artwork_canvas.position = (size - DESIGN_SIZE * fit_scale) * 0.5
	artwork_canvas.scale = Vector2.ONE * fit_scale
	$ArtworkCanvas/TitleControls.call("fit_to_visible_area")


func _open_options() -> void:
	var mobile: bool = $ArtworkCanvas/TitleControls.mobile_layout
	var scene: PackedScene = preload("res://scenes/menu/mobile_options.tscn") if mobile else preload("res://scenes/menu/options.tscn")
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
		_pointer.reset(get_viewport())


func _input(event: InputEvent) -> void:
	_pointer.forward(get_viewport(), event)
