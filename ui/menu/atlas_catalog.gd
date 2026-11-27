extends RefCounted

const DEFAULT_PATH := "res://config/roaming_atlas.json"

## Dictionary insertion order follows the designer's tab order in the JSON.
var destinations: Dictionary[StringName, Dictionary] = {}
var default_id: StringName


func read_catalog(path: String = DEFAULT_PATH) -> void:
	destinations.clear()
	default_id = &""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Cannot read atlas catalog %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		push_error("%s:%d: %s" % [path, parser.get_error_line(), parser.get_error_message()])
		return
	var data: Variant = parser.data
	if not data is Dictionary or not data.get("destinations") is Array:
		push_error("%s requires a destinations array." % path)
		return
	for index in data.destinations.size():
		var record: Variant = data.destinations[index]
		var problem := _record_problem(record)
		if not problem.is_empty():
			push_warning("%s destination %d: %s" % [path, index + 1, problem])
			continue
		var id := StringName(record.id)
		if destinations.has(id):
			push_warning("Duplicate atlas destination '%s' in %s." % [id, path])
			continue
		destinations[id] = record
	if destinations.is_empty():
		push_error("%s has no usable destinations." % path)
		return
	var requested: Variant = data.get("default_destination")
	if requested is String and destinations.has(StringName(requested)):
		default_id = StringName(requested)
	else:
		default_id = destinations.keys()[0]
		push_warning("Unknown default destination in %s. Opening %s." % [path, default_id])


static func launch_scene(record: Dictionary) -> String:
	var path: String = record.get("scene", "")
	if record.get("enabled", false) and not path.is_empty() and ResourceLoader.exists(path):
		if path.get_extension().to_lower() in ["tscn", "scn"]:
			return path
		if path.get_extension().to_lower() in ["tres", "res"] and load(path) is PackedScene:
			return path
	return ""


static func _record_problem(record: Variant) -> String:
	if not record is Dictionary:
		return "expected an object"
	for field in ["id", "title", "tagline", "description", "sticker"]:
		if not record.get(field) is String or record[field].strip_edges().is_empty():
			return "missing or empty %s" % field
	if not record.id.is_valid_ascii_identifier() or record.id != record.id.to_snake_case():
		return "id must be a snake_case identifier"
	if not _coordinate(record.get("position")):
		return "position must contain two numbers"
	if not record.get("enabled") is bool or not record.get("scene") is String:
		return "expected an enabled boolean and a scene path (or empty string)"
	var pin: Variant = record.get("pin")
	if not pin is Dictionary or not _positive(pin.get("scale", 0.75)):
		return "pin needs a positive scale"
	if pin.has("text") and (not pin.text is String or pin.text.strip_edges().is_empty()):
		return "pin.text must be a nonempty string"
	var illustration: Variant = pin.get("image")
	for art in [record.sticker, illustration]:
		if not art is String or not ResourceLoader.exists(art, "Texture2D"):
			return "missing texture %s" % str(art)
		var texture := load(art) as Texture2D
		if texture == null:
			return "expected a texture at %s" % art
		if art == illustration and (art.get_extension().to_lower() != "png" or texture.get_size() != Vector2(128, 128)):
			return "pin.image must be a 128 x 128 PNG"
	return ""


static func _coordinate(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1])


static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _positive(value: Variant) -> bool:
	return _number(value) and value > 0
