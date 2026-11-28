extends Node3D

## Binds the bounded valley tailwind and finishes only after a grounded arrival.

var _runner: ParkourController
var _finish_area: Area3D
var _finish_shape: CollisionShape3D
var _finish_box: BoxShape3D
var _finish_scene: Node
var _runner_inside_finish := false
var _completion_shown := false


func _ready() -> void:
	var valley := get_parent()
	_runner = valley.get_node_or_null("ChibiRunner") as ParkourController if valley != null else null
	var field := get_node_or_null("WindField") as RunnerWindField3D
	if _runner != null and field != null:
		_runner.wind_field = field
	_finish_area = get_node_or_null("FinishArea") as Area3D
	_finish_shape = get_node_or_null("FinishArea/CollisionShape3D") as CollisionShape3D
	if _finish_shape != null and _finish_shape.shape is BoxShape3D:
		_finish_box = _finish_shape.shape as BoxShape3D
	_finish_scene = get_node_or_null("ValleyFinish")
	if _finish_area != null:
		_finish_area.body_entered.connect(_on_finish_body_entered)
		_finish_area.body_exited.connect(_on_finish_body_exited)


func _physics_process(_delta: float) -> void:
	if _completion_shown or not _runner_inside_finish or _runner == null or not _runner.is_on_floor():
		return
	if not _runner_feet_inside_finish_box():
		return
	_completion_shown = true
	if _finish_scene != null and _finish_scene.has_method("show_completion"):
		_finish_scene.call("show_completion")


func _runner_feet_inside_finish_box() -> bool:
	if _finish_shape == null or _finish_box == null:
		return false
	var feet_local := _finish_shape.to_local(_runner.global_position)
	var half_size := _finish_box.size * 0.5
	return absf(feet_local.x) <= half_size.x \
		and absf(feet_local.y) <= half_size.y \
		and absf(feet_local.z) <= half_size.z


func _on_finish_body_entered(body: Node3D) -> void:
	if body == _runner:
		_runner_inside_finish = true


func _on_finish_body_exited(body: Node3D) -> void:
	if body == _runner:
		_runner_inside_finish = false
