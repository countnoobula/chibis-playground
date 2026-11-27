extends RefCounted

## Gameplay uses raw touch input. Menus forward one finger to their native GUI controls.
var _touch_index := -1


func reset(viewport: Viewport) -> void:
	if _touch_index == -1:
		return
	_touch_index = -1
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.canceled = true
	release.device = InputEvent.DEVICE_ID_EMULATION
	viewport.push_input(release, true)


func forward(viewport: Viewport, event: InputEvent) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION or Input.emulate_mouse_from_touch:
		return
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled and _touch_index == -1:
			_touch_index = event.index
		if event.index != _touch_index:
			return
		var pointer := InputEventMouseButton.new()
		pointer.position = event.position
		pointer.global_position = event.position
		pointer.button_index = MOUSE_BUTTON_LEFT
		pointer.pressed = event.pressed and not event.canceled
		pointer.button_mask = MOUSE_BUTTON_MASK_LEFT if pointer.pressed else 0
		pointer.canceled = event.canceled
		if not pointer.pressed:
			_touch_index = -1
		_send_touch_pointer(viewport, pointer)
	elif event is InputEventScreenDrag and event.index == _touch_index:
		var motion := InputEventMouseMotion.new()
		motion.position = event.position
		motion.global_position = event.position
		motion.relative = event.relative
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		_send_touch_pointer(viewport, motion)


func _send_touch_pointer(viewport: Viewport, event: InputEventMouse) -> void:
	viewport.set_input_as_handled()
	event.device = InputEvent.DEVICE_ID_EMULATION
	viewport.push_input(event, true)
