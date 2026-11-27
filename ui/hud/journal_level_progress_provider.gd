class_name JournalLevelProgressProvider
extends RefCounted

## Level-owned data exposed to the journal through an explicit HUD binding.

signal progress_changed

const EMPTY_AREA_NAME := "Area unavailable"

var _area_name := EMPTY_AREA_NAME
var _strawberries_collected := 0
var _strawberries_total := 0


func _init(area_name: String = EMPTY_AREA_NAME) -> void:
	_area_name = _normalized_area_name(area_name)


func get_area_name() -> String:
	return _area_name


func get_berry_progress() -> Vector2i:
	return Vector2i(_strawberries_collected, _strawberries_total)


func register_strawberry() -> void:
	_strawberries_total += 1
	progress_changed.emit()


func collect_strawberry() -> void:
	if _strawberries_collected >= _strawberries_total:
		return
	_strawberries_collected += 1
	progress_changed.emit()


func set_area_name(area_name: String) -> void:
	var normalized := _normalized_area_name(area_name)
	if _area_name == normalized:
		return
	_area_name = normalized
	progress_changed.emit()


func _normalized_area_name(area_name: String) -> String:
	var normalized := area_name.strip_edges()
	return EMPTY_AREA_NAME if normalized.is_empty() else normalized
