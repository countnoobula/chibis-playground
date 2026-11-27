class_name ChibiInput
extends Node

## Aggregates keyboard, mouse, gamepad, and Touch HUD inputs
## into a single clean per-frame interface.

@export var mouse_sensitivity: float = 0.0028
@export var gamepad_look_sensitivity: float = 2.4
@export var touch_look_sensitivity: float = 0.0055

var move_vec: Vector2 = Vector2.ZERO
var look_delta: Vector2 = Vector2.ZERO

var jump_just_pressed: bool = false
var jump_held: bool = false
var slide_just_pressed: bool = false
var slide_held: bool = false
var slide_just_released: bool = false
var pickup_just_pressed: bool = false
var rise_held: bool = false
var dive_held: bool = false

var _mouse_accum: Vector2 = Vector2.ZERO
var _touch_move: Vector2 = Vector2.ZERO
var _touch_look_accum: Vector2 = Vector2.ZERO
var _touch_jump_held: bool = false
var _touch_jump_queued: bool = false
var _touch_slide_held: bool = false
var _touch_slide_queued: bool = false
var _touch_slide_released_queued: bool = false
var _touch_pickup_queued: bool = false
var _touch_active: bool = false
var _menu_open: bool = false
var _held_at_resume: Array[StringName] = []
var _camera_sensitivity: float = 1.0
var _invert_y: bool = false


func _ready() -> void:
	add_to_group(&"chibi_input")
	_update_mouse_mode()
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null:
		set_camera_settings(float(settings.get("sensitivity")), bool(settings.get("invert_y")))


func set_camera_settings(sensitivity: float, invert_y: bool) -> void:
	_camera_sensitivity = clampf(sensitivity, 0.5, 2.0)
	_invert_y = invert_y


func set_touch_mode(enabled: bool) -> void:
	_touch_active = enabled
	_update_mouse_mode()


func set_menu_open(open: bool) -> void:
	if _menu_open and not open:
		# A keyboard or gamepad button that closed the menu belongs to that menu.
		_held_at_resume.clear()
		for action in [&"jump", &"slide_roll", &"pick_up"]:
			if Input.is_action_pressed(action):
				_held_at_resume.append(action)
	_menu_open = open
	_mouse_accum = Vector2.ZERO
	_update_mouse_mode()


func _update_mouse_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _menu_open or _touch_active or OS.has_feature("mobile") else Input.MOUSE_MODE_CAPTURED


func clear_touch_input() -> void:
	_touch_move = Vector2.ZERO
	_touch_look_accum = Vector2.ZERO
	_touch_jump_held = false
	_touch_jump_queued = false
	_touch_slide_held = false
	_touch_slide_queued = false
	_touch_slide_released_queued = false
	_touch_pickup_queued = false
	move_vec = Vector2.ZERO
	look_delta = Vector2.ZERO
	jump_just_pressed = false
	jump_held = false
	slide_just_pressed = false
	slide_held = false
	slide_just_released = false
	pickup_just_pressed = false
	rise_held = false
	dive_held = false


func set_touch_move(vec: Vector2) -> void:
	_touch_move = vec


func add_touch_look(delta_px: Vector2) -> void:
	_touch_look_accum += delta_px * touch_look_sensitivity


func set_touch_jump(pressed: bool, canceled: bool = false) -> void:
	if canceled:
		_touch_jump_queued = false
	elif pressed and not _touch_jump_held:
		_touch_jump_queued = true
	_touch_jump_held = pressed


func set_touch_slide(pressed: bool, canceled: bool = false) -> void:
	if canceled:
		_touch_slide_queued = false
	if pressed and not _touch_slide_held:
		_touch_slide_queued = true
	elif not pressed and _touch_slide_held:
		_touch_slide_released_queued = true
	_touch_slide_held = pressed


func trigger_touch_pickup() -> void:
	_touch_pickup_queued = true


func cancel_touch_pickup() -> void:
	_touch_pickup_queued = false


func _input(event: InputEvent) -> void:
	if not _menu_open and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_accum += event.relative * mouse_sensitivity


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _menu_open and not _touch_active and not OS.has_feature("mobile"):
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func poll(delta: float) -> void:
	var kb_move := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Both movement sources use +X right and +Y down.
	var combined := kb_move + _touch_move
	if combined.length() > 1.0:
		combined = combined.normalized()
	move_vec = combined

	var gp_look := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	)
	if gp_look.length() < 0.16:
		gp_look = Vector2.ZERO
	look_delta = (_mouse_accum + _touch_look_accum + gp_look * gamepad_look_sensitivity * delta) * _camera_sensitivity
	if _invert_y:
		look_delta.y = -look_delta.y
	_mouse_accum = Vector2.ZERO
	_touch_look_accum = Vector2.ZERO

	var device_jump := &"jump" not in _held_at_resume
	var device_slide := &"slide_roll" not in _held_at_resume
	var device_pickup := &"pick_up" not in _held_at_resume
	jump_just_pressed = (device_jump and Input.is_action_just_pressed("jump")) or _touch_jump_queued
	jump_held = (device_jump and Input.is_action_pressed("jump")) or _touch_jump_held
	slide_just_pressed = (device_slide and Input.is_action_just_pressed("slide_roll")) or _touch_slide_queued
	slide_held = (device_slide and Input.is_action_pressed("slide_roll")) or _touch_slide_held
	slide_just_released = (device_slide and Input.is_action_just_released("slide_roll")) or _touch_slide_released_queued
	pickup_just_pressed = (device_pickup and Input.is_action_just_pressed("pick_up")) or _touch_pickup_queued
	if not _held_at_resume.is_empty():
		_held_at_resume = _held_at_resume.filter(Input.is_action_pressed)

	rise_held = jump_held
	dive_held = slide_held

	_touch_jump_queued = false
	_touch_slide_queued = false
	_touch_slide_released_queued = false
	_touch_pickup_queued = false
