extends Control

const DESIGN_SIZE := Vector2(1280, 720)
const MOBILE_CROP_TOP_FRACTION := 0.10
const TRANSITION_DURATION := 0.30
const ATLAS_PREVIEW_SCENE := preload("res://ui/menu/atlas_preview.tscn")

var _pointer := preload("res://ui/hud/menu_touch_pointer.gd").new()
var _atlas_preview: Control
var _transitioning := false

@onready var artwork_canvas: Control = $ArtworkCanvas
@onready var title_art: Control = $ArtworkCanvas/TitleArt
@onready var title_controls: Control = $ArtworkCanvas/TitleControls


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if OS.get_cmdline_user_args().has("--mobile-menu"):
		get_window().title = "Strawberry Hollow · Mobile preview"
	resized.connect(_fit_canvas)
	_fit_canvas()
	title_controls.connect("play_requested", _open_atlas)
	title_controls.connect("options_requested", _open_options)


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
	title_controls.call("fit_to_visible_area")
	if is_instance_valid(_atlas_preview):
		_atlas_preview.call("fit_to_visible_area")


func _open_options() -> void:
	if _transitioning or is_instance_valid(_atlas_preview):
		return
	var mobile := bool(title_controls.get("mobile_layout"))
	var scene: PackedScene = preload("res://ui/menu/mobile_options.tscn") if mobile else preload("res://ui/menu/options.tscn")
	var options := scene.instantiate()
	var parent: Control = self if mobile else artwork_canvas
	title_art.hide()
	title_controls.hide()
	options.back_requested.connect(_close_options.bind(options))
	parent.add_child(options)


func _close_options(options: Control) -> void:
	options.hide()
	options.queue_free()
	title_art.show()
	title_controls.show()
	title_controls.get_node("OptionsButton").grab_focus.call_deferred()


func _open_atlas() -> void:
	if _transitioning or is_instance_valid(_atlas_preview):
		return
	_transitioning = true
	_atlas_preview = ATLAS_PREVIEW_SCENE.instantiate() as Control
	_atlas_preview.modulate.a = 0.0
	_atlas_preview.connect("back_requested", _return_to_title)
	_atlas_preview.connect("launch_requested", _launch_scene)
	add_child(_atlas_preview)
	_atlas_preview.call("set_interaction_enabled", false)
	_atlas_preview.call("fit_to_visible_area")
	var tween := create_tween().set_parallel(true)
	tween.tween_property(title_art, "modulate:a", 0.0, TRANSITION_DURATION)
	tween.tween_property(title_controls, "modulate:a", 0.0, TRANSITION_DURATION)
	tween.tween_property(_atlas_preview, "modulate:a", 1.0, TRANSITION_DURATION)
	await tween.finished
	if not is_instance_valid(_atlas_preview):
		return
	title_art.hide()
	title_controls.hide()
	title_art.modulate.a = 1.0
	title_controls.modulate.a = 1.0
	_atlas_preview.modulate.a = 1.0
	_transitioning = false
	_atlas_preview.call("set_interaction_enabled", true)
	_atlas_preview.call("focus_back")


func _return_to_title() -> void:
	if _transitioning or not is_instance_valid(_atlas_preview):
		return
	_transitioning = true
	_atlas_preview.call("set_interaction_enabled", false)
	title_art.show()
	title_controls.show()
	title_art.modulate.a = 0.0
	title_controls.modulate.a = 0.0
	var preview := _atlas_preview
	var tween := create_tween().set_parallel(true)
	tween.tween_property(title_art, "modulate:a", 1.0, TRANSITION_DURATION)
	tween.tween_property(title_controls, "modulate:a", 1.0, TRANSITION_DURATION)
	tween.tween_property(preview, "modulate:a", 0.0, TRANSITION_DURATION)
	await tween.finished
	if is_instance_valid(preview):
		preview.hide()
		preview.queue_free()
	_atlas_preview = null
	_transitioning = false
	title_controls.get_node("PlayButton").grab_focus.call_deferred()


func _launch_scene(scene_path: String) -> void:
	if _transitioning or not is_instance_valid(_atlas_preview):
		return
	if scene_path.is_empty():
		push_warning("Atlas launch was requested without a scene path.")
		return
	var target_scene := ResourceLoader.load(scene_path) as PackedScene
	if target_scene == null:
		push_error("Atlas destination scene could not be loaded: %s" % scene_path)
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	var restore_focus_path := NodePath()
	if focus_owner != null and _atlas_preview.is_ancestor_of(focus_owner):
		restore_focus_path = _atlas_preview.get_path_to(focus_owner)
	_transitioning = true
	var preview := _atlas_preview
	preview.call("set_interaction_enabled", false)
	var tween := create_tween()
	tween.tween_property(preview, "modulate:a", 0.0, TRANSITION_DURATION)
	await tween.finished
	if not is_instance_valid(preview):
		return
	var change_result: Error = get_tree().change_scene_to_packed(target_scene)
	if change_result != OK:
		await _restore_atlas_after_launch_failure(preview, restore_focus_path, scene_path, change_result)


func _restore_atlas_after_launch_failure(
	preview: Control, focus_path: NodePath, scene_path: String, change_result: Error
) -> void:
	push_error("Could not launch atlas destination %s: %s" % [scene_path, error_string(change_result)])
	if not is_instance_valid(preview):
		_atlas_preview = null
		title_art.show()
		title_controls.show()
		title_art.modulate.a = 1.0
		title_controls.modulate.a = 1.0
		_transitioning = false
		title_controls.get_node("PlayButton").grab_focus.call_deferred()
		return
	preview.show()
	preview.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(preview, "modulate:a", 1.0, TRANSITION_DURATION)
	await tween.finished
	if not is_instance_valid(preview):
		return
	preview.modulate.a = 1.0
	preview.call("set_interaction_enabled", true)
	_transitioning = false
	var restore_focus := preview.get_node_or_null(focus_path) as Control if not focus_path.is_empty() else null
	if restore_focus != null and restore_focus.is_visible_in_tree() and restore_focus.focus_mode != Control.FOCUS_NONE:
		restore_focus.grab_focus.call_deferred()
	else:
		preview.call("focus_back")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_pointer.reset(get_viewport())


func _input(event: InputEvent) -> void:
	_pointer.forward(get_viewport(), event)
	if _transitioning or (event.is_echo() and event.is_action(&"ui_accept")):
		get_viewport().set_input_as_handled()
		return
	# Keep the title's confirm/back bindings local. In gameplay B is slide/roll.
	if event is InputEventJoypadButton and event.button_index in [JOY_BUTTON_A, JOY_BUTTON_B]:
		var action := &"ui_accept" if event.button_index == JOY_BUTTON_A else &"ui_cancel"
		if not event.is_action(action):
			var menu_event := InputEventAction.new()
			menu_event.action = action
			menu_event.pressed = event.pressed
			get_viewport().set_input_as_handled()
			get_viewport().push_input(menu_event, true)
