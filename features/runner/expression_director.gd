extends Node
## Runner-local expression arbitration. A manual request with zero duration holds until release.
signal requests_cleared

const FALL_PRIORITY := 50
const IDS = [&"neutral", &"gentle_neutral", &"open_smile", &"bright_smile", &"delighted",
	&"playful_wink", &"soft_determination", &"focused_determination", &"tiny_pout", &"brave_little_smile",
	&"surprised", &"little_gasp", &"wide_eyed_gasp", &"startled_squeal", &"free_fall_squeal",
	&"sleepy", &"scared", &"angry", &"sad", &"crying"]
const NAMES = ["Neutral", "Gentle neutral", "Open smile", "Bright smile", "Delighted",
	"Playful wink", "Soft determination", "Focused determination", "Tiny pout", "Brave little smile",
	"Surprised", "Little gasp", "Wide-eyed gasp", "Startled squeal", "Free-fall squeal",
	"Sleepy", "Scared", "Angry", "Sad", "Crying"]

var _requests: Dictionary = {}
var _automatic_face := -1
var _next_handle := 1
var _face_manual := false
var _face_index := -1
var _cloud_index := -1
var _face = null
var _cloud = null


func _ready() -> void:
	set_process(false)


func request_expression(id: StringName, duration: float = 0.0, priority: int = 0, output: StringName = &"both") -> int:
	var index := IDS.find(id)
	if index < 0 or output not in [&"face", &"cloud", &"both"] or duration < 0.0 or not is_finite(duration):
		return -1
	var handle := _next_handle
	_next_handle += 1
	_requests[handle] = {"index": index, "remaining": duration, "timed": duration > 0.0, "priority": priority, "output": output}
	_refresh()
	return handle


func has_request(handle: int) -> bool:
	return _requests.has(handle)


func release_expression(handle: int) -> void:
	if _requests.erase(handle):
		_refresh()


func prepare_rooftop() -> void:
	_ensure_face()
	_face.warm_up_fall()


func _ensure_face() -> void:
	if _face == null:
		_face = preload("res://features/runner/expression_face.gd").new()
		_face.name = "ExpressionFace"
		add_child(_face)
		_face.setup(get_parent())


func set_automatic(face_index: int) -> void:
	if face_index == _automatic_face:
		return
	_automatic_face = face_index
	_refresh()


func clear_requests() -> void:
	_requests.clear()
	_face_manual = false
	_automatic_face = -1
	_face_index = -1
	_cloud_index = -1
	if _face != null:
		_face.clear_pose()
	if _cloud != null:
		_cloud.clear_pose()
	set_process(false)
	requests_cleared.emit()


func _process(delta: float) -> void:
	var expired := false
	for handle in _requests.keys():
		var entry: Dictionary = _requests[handle]
		if entry.timed:
			entry.remaining -= delta
			if entry.remaining <= 0.0:
				_requests.erase(handle)
				expired = true
	if expired:
		_refresh()


func _winner(channel: StringName) -> int:
	var best := -1
	for handle: int in _requests:
		var entry: Dictionary = _requests[handle]
		if entry.output != channel and entry.output != &"both":
			continue
		if best < 0 or entry.priority > _requests[best].priority or (entry.priority == _requests[best].priority and handle > best):
			best = handle
	# A held picker override has priority 100. Ordinary authored cues yield to a flail.
	if channel == &"face" and best >= 0 and _automatic_face in [11, 14] and _requests[best].priority < FALL_PRIORITY:
		return -1
	return best


func _refresh() -> void:
	var timed := false
	for entry: Dictionary in _requests.values():
		if entry.timed:
			timed = true
			break
	set_process(timed)
	var face_handle := _winner(&"face")
	var face_index := _automatic_face if face_handle < 0 else int(_requests[face_handle].index)
	if face_index != _face_index or (face_handle >= 0 and not _face_manual):
		_ensure_face()
		if face_handle >= 0:
			_face.show_pose(face_index)
		else:
			var duration := 0.22
			if face_index in [11, 14]:
				duration = 0.11
			elif face_index in [0, 1, 9, -1]:
				duration = 0.32
			_face.blend_to_pose(face_index, duration)
		_face_index = face_index
	_face_manual = face_handle >= 0
	var cloud_handle := _winner(&"cloud")
	var cloud_index := -1 if cloud_handle < 0 else int(_requests[cloud_handle].index)
	if cloud_index != _cloud_index:
		if _cloud == null:
			_cloud = preload("res://features/runner/expression_cloud.gd").new()
			_cloud.name = "ExpressionCloud"
			get_parent().add_child(_cloud)
		if cloud_handle >= 0:
			_cloud.show_pose(cloud_index)
		else:
			_cloud.clear_pose()
		_cloud_index = cloud_index
