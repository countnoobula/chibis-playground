extends SceneTree

const ATLAS_CATALOG = preload("res://ui/menu/atlas_catalog.gd")
const ATLAS_SCENE = preload("res://ui/menu/atlas_preview.tscn")
const PIN_SCENE = preload("res://ui/menu/atlas_map_pin.tscn")

const CUSTOM_ID: StringName = &"synthetic_marker"
const CUSTOM_SCENE := "res://ui/menu/options.tscn"
const CUSTOM_IMAGE := "res://ui/menu/art/atlas/pins/intro.png"

var _fixture_path := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var config_text := FileAccess.get_file_as_string(ATLAS_CATALOG.DEFAULT_PATH)
	if not _check(not config_text.is_empty(), "The default atlas catalog should be readable."):
		return
	var parser := JSON.new()
	if not _check(parser.parse(config_text) == OK and parser.data is Dictionary, "The default atlas catalog should contain valid JSON."):
		return
	var fixture_data: Dictionary = parser.data.duplicate(true)
	var fixture_destinations: Array = fixture_data.get("destinations", [])
	if not _check(not fixture_destinations.is_empty(), "The production catalog should contain destinations before the synthetic marker."):
		return

	var expected_order: Array[StringName] = []
	for destination: Dictionary in fixture_destinations:
		expected_order.append(StringName(destination.get("id", "")))

	var synthetic := {
		"id": String(CUSTOM_ID),
		"position": [321, 234],
		"pin": {"image": CUSTOM_IMAGE, "scale": 0.75, "text": "Hidden Cove"},
		"sticker": "res://ui/menu/art/atlas/postcards/lake.png",
		"title": "Cloudberry Hollow",
		"tagline": "A fifth place on the map.",
		"description": "A synthetic destination used to exercise data-driven atlas records.",
		"enabled": true,
		"scene": CUSTOM_SCENE,
	}
	fixture_destinations.append(synthetic)
	fixture_data["default_destination"] = String(CUSTOM_ID)
	expected_order.append(CUSTOM_ID)
	_fixture_path = OS.get_user_data_dir().path_join("chibi_synthetic_atlas_catalog_%d.json" % OS.get_process_id())
	var fixture := FileAccess.open(_fixture_path, FileAccess.WRITE)
	if not _check(fixture != null, "The synthetic atlas catalog fixture should be writable."):
		return
	fixture.store_string(JSON.stringify(fixture_data, "\t"))
	fixture.close()

	var catalog = ATLAS_CATALOG.new()
	catalog.read_catalog(_fixture_path)
	if not _check(catalog.default_id == CUSTOM_ID, "The catalog should retain a custom default destination."):
		return
	if not _check(catalog.destinations.keys() == expected_order, "Destination dictionary order should match JSON focus order, including the fifth marker."):
		return
	var synthetic_record: Dictionary = catalog.destinations[CUSTOM_ID]
	var synthetic_position: Array = synthetic_record.get("position", [])
	if not _check(
		synthetic_record.get("title") == "Cloudberry Hollow"
		and synthetic_record.get("pin", {}).get("image") == CUSTOM_IMAGE
		and synthetic_position.size() == 2
		and is_equal_approx(float(synthetic_position[0]), 321.0)
		and is_equal_approx(float(synthetic_position[1]), 234.0),
		"The catalog should preserve a marker's custom title, illustration, and map position."
	):
		return
	if not _check(ATLAS_CATALOG.launch_scene(synthetic_record) == CUSTOM_SCENE, "Any enabled destination should resolve its configured scene, independent of its id."):
		return

	if not _check_scene_gates(synthetic_record):
		return
	if not await _check_ribbon_sizing(synthetic_record):
		return
	if not await _check_runtime_atlas(synthetic_record, expected_order):
		return

	_cleanup_fixture()
	print("PASS: Atlas catalog defaults, JSON focus order, synthetic marker data, generic launches, scene gates, and dynamic ribbon sizing")
	quit(0)


func _check_scene_gates(record: Dictionary) -> bool:
	var disabled := record.duplicate(true)
	disabled["enabled"] = false
	if not _check(ATLAS_CATALOG.launch_scene(disabled).is_empty(), "A destination disabled in the catalog should not resolve a launch scene."):
		return false
	var missing := record.duplicate(true)
	missing["scene"] = "res://levels/missing_atlas_destination.tscn"
	if not _check(ATLAS_CATALOG.launch_scene(missing).is_empty(), "A missing destination scene should not resolve a launch scene."):
		return false
	var invalid := record.duplicate(true)
	invalid["scene"] = CUSTOM_IMAGE
	if not _check(ATLAS_CATALOG.launch_scene(invalid).is_empty(), "An existing non-scene resource should not resolve as a launch scene."):
		return false
	var absent := record.duplicate(true)
	absent.erase("scene")
	return _check(ATLAS_CATALOG.launch_scene(absent).is_empty(), "A destination with no scene field should remain unavailable.")


func _check_ribbon_sizing(record: Dictionary) -> bool:
	var short_record := record.duplicate(true)
	short_record["title"] = "Short title"
	short_record["pin"]["text"] = "Go"
	var long_record := record.duplicate(true)
	long_record["pin"]["text"] = "A remarkably long marker label"

	var short_pin := PIN_SCENE.instantiate() as Button
	var long_pin := PIN_SCENE.instantiate() as Button
	root.add_child(short_pin)
	root.add_child(long_pin)
	short_pin.call("configure", short_record)
	long_pin.call("configure", long_record)
	await process_frame
	var short_width := short_pin.size.x
	var long_width := long_pin.size.x
	var short_label := short_pin.get_node_or_null("Ribbon/TitleLabel") as Label
	var long_label := long_pin.get_node_or_null("Ribbon/TitleLabel") as Label
	var fallback_record := record.duplicate(true)
	fallback_record["pin"].erase("text")
	var fallback_pin := PIN_SCENE.instantiate() as Button
	root.add_child(fallback_pin)
	fallback_pin.call("configure", fallback_record)
	await process_frame
	var fallback_label := fallback_pin.get_node_or_null("Ribbon/TitleLabel") as Label
	var fallback_matches_title := fallback_label != null and fallback_label.text == str(record.get("title", ""))
	var sizing_passed := short_label != null and long_label != null and long_width > short_width and fallback_matches_title
	if not _check(
		sizing_passed,
		"Marker button width should grow with a long ribbon label, and omitted pin.text should use the destination title."
	):
		return false
	short_pin.queue_free()
	long_pin.queue_free()
	fallback_pin.queue_free()
	await process_frame
	return true


func _check_runtime_atlas(record: Dictionary, expected_order: Array[StringName]) -> bool:
	var atlas := ATLAS_SCENE.instantiate() as Control
	atlas.set("catalog_path", _fixture_path)
	root.add_child(atlas)
	await process_frame
	await process_frame
	var runtime_catalog: Object = atlas.get("catalog")
	var actual_order: Array = atlas.get("destination_order")
	if not _check(runtime_catalog.get("default_id") == CUSTOM_ID, "AtlasPreview should use the injected catalog's default destination."):
		return false
	if not _check(actual_order == expected_order and atlas.get("selected_destination_id") == CUSTOM_ID, "AtlasPreview should create pins in catalog order and select the configured default."):
		return false
	var world_map := atlas.get_node_or_null("DesignCanvas/MapViewport/WorldMap") as Control
	var pin := world_map.get_node_or_null("SyntheticMarkerPin") as Button if world_map != null else null
	var postcard := atlas.get_node_or_null("DesignCanvas/Postcard") as Control
	var launch_button := postcard.get_node_or_null("LaunchButton") as BaseButton if postcard != null else null
	if not _check(pin != null and postcard != null and launch_button != null, "The synthetic record should create a marker and postcard action."):
		return false
	var portrait := pin.get_node_or_null("Portrait") as TextureRect
	var ribbon_label := pin.get_node_or_null("Ribbon/TitleLabel") as Label
	if not _check(
		pin.accessibility_name == "Cloudberry Hollow"
		and ribbon_label != null and ribbon_label.text == "Hidden Cove"
		and portrait != null and portrait.texture != null and portrait.texture.resource_path == CUSTOM_IMAGE,
		"The runtime marker should use its custom title, text override, and changed illustration."
	):
		return false
	var tip: Vector2 = atlas.call("get_pin_tip_screen", CUSTOM_ID)
	var expected_tip: Vector2 = atlas.call("map_to_screen", Vector2(321, 234))
	if not _check(tip.distance_to(expected_tip) < 0.1, "The synthetic pin should stay anchored at its configured world position."):
		return false
	var back_button := atlas.get_node_or_null("DesignCanvas/BackButton") as Control
	if not _check(back_button != null and back_button.get_node_or_null(back_button.focus_next) == pin, "Back focus should enter the configured default pin."):
		return false
	for index in expected_order.size():
		var destination_id: StringName = expected_order[index]
		var current_pin := world_map.get_node_or_null(String(destination_id).to_pascal_case() + "Pin") as Control
		var expected_next: Control = launch_button if destination_id == CUSTOM_ID else world_map.get_node_or_null(String(expected_order[(index + 1) % expected_order.size()]).to_pascal_case() + "Pin") as Control
		if not _check(current_pin != null and current_pin.get_node_or_null(current_pin.focus_next) == expected_next, "Pin focus order should follow catalog order and reach Play from the selected default."):
			return false
	var launch_events: Array[String] = []
	atlas.connect("launch_requested", func(scene_path: String) -> void: launch_events.append(scene_path))
	launch_button.emit_signal("pressed")
	await process_frame
	if not _check(launch_events == [CUSTOM_SCENE], "The postcard action should emit the configured generic scene path."):
		return false

	var missing := record.duplicate(true)
	missing["id"] = "missing_scene"
	missing["scene"] = "res://levels/missing_atlas_destination.tscn"
	postcard.call("present", missing)
	if not _check(launch_button.disabled and not bool(postcard.get("launch_available")), "The postcard should gate a destination whose scene is missing."):
		return false
	var invalid := record.duplicate(true)
	invalid["id"] = "invalid_scene"
	invalid["scene"] = CUSTOM_IMAGE
	postcard.call("present", invalid)
	if not _check(launch_button.disabled and not bool(postcard.get("launch_available")), "The postcard should gate an existing resource that is not a scene."):
		return false
	launch_button.emit_signal("pressed")
	await process_frame
	if not _check(launch_events == [CUSTOM_SCENE], "A pending or invalid postcard action should not emit a scene launch."):
		return false
	var disabled := record.duplicate(true)
	disabled["enabled"] = false
	postcard.call("present", disabled)
	if not _check(launch_button.disabled and not bool(postcard.get("launch_available")), "An explicitly disabled destination should keep the postcard action unavailable."):
		return false
	launch_button.emit_signal("pressed")
	await process_frame
	if not _check(launch_events == [CUSTOM_SCENE], "An explicitly disabled postcard action should not emit a scene launch."):
		return false

	atlas.queue_free()
	await process_frame
	return true


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	printerr("FAIL: ", message)
	_cleanup_fixture()
	quit(1)
	return false


func _cleanup_fixture() -> void:
	if not _fixture_path.is_empty() and FileAccess.file_exists(_fixture_path):
		DirAccess.remove_absolute(_fixture_path)
