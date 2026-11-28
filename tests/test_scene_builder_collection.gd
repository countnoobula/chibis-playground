extends SceneTree

const COLLECTION_NAMES_PATH := "res://Data/scene_builder/collection_names.tres"
const DATABASE_PATH := "res://Data/scene_builder/scene_builder_database.tres"
const BALANCE_BEAM_ITEM_PATH := "res://Data/scene_builder/items/first_steps_balance_beam_item.tscn"
const BALANCE_BEAM_ITEM_UID := "uid://v6q3k2m4n5j0a"
const RUNNER_SCENE_PATH := "res://features/runner/chibi_runner.tscn"
const PLACEMENT_ACTION := preload("res://addons/scene_builder/scene_builder_placement.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var names = load(COLLECTION_NAMES_PATH)
	_assert(names != null, "collection names resource loads")
	_assert(names.palette_name_1 == "First Steps", "collection palette is named First Steps")
	_assert(names.name_01 == "Woodland", "woodland collection is available")
	_assert(names.name_02 == "Gameplay", "gameplay collection is available")

	var database = load(DATABASE_PATH)
	_assert(database != null, "scene builder database loads")
	_assert(database.has_item("Woodland", "Moss Boulder"), "woodland rock is in the collection")
	_assert(database.has_item("Gameplay", "Balance Beam"), "existing balance beam is in the collection")
	_assert(database.get_item("Gameplay", "Balance Beam").uid == BALANCE_BEAM_ITEM_UID, "beam preview UID matches its scene")

	for collection_name in database.get_collection_names():
		for item_name in database.get_item_names(collection_name):
			var item_data: Dictionary = database.get_item(collection_name, item_name)
			var uid_id := ResourceUID.text_to_id(item_data.uid)
			_assert(ResourceUID.has_id(uid_id), "%s/%s has a registered resource UID" % [collection_name, item_name])
			var item_path := ResourceUID.get_id_path(uid_id)
			var packed := load(item_path) as PackedScene
			_assert(packed != null, "%s/%s points to a PackedScene" % [collection_name, item_name])
			if packed:
				var instance := packed.instantiate()
				_assert(instance is Node3D, "%s/%s has a Node3D root" % [collection_name, item_name])
				instance.free()

	await _verify_tuning_survives_reopen(load(BALANCE_BEAM_ITEM_PATH) as PackedScene)
	_verify_placement_undo_redo()
	await _exercise_placed_balance_beam()

	quit(0 if _failure_count == 0 else 1)


var _failure_count := 0


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failure_count += 1
		push_error("FAIL: " + message)


func _exercise_placed_balance_beam() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var item_scene := load(BALANCE_BEAM_ITEM_PATH) as PackedScene
	var placed_item := item_scene.instantiate() as Node3D
	world.add_child(placed_item)
	await process_frame

	var beam := placed_item.get_node_or_null("ParkourBalanceBeam") as ParkourBalanceBeam
	_assert(beam != null, "runtime item instantiates the existing balance-beam gameplay scene")
	if beam == null:
		world.queue_free()
		await process_frame
		return

	var runner_scene := load(RUNNER_SCENE_PATH) as PackedScene
	var runner := runner_scene.instantiate() as ParkourController
	world.add_child(runner)
	runner.reset_for_respawn(beam.to_global(Vector3(0.0, 0.24, -3.2)))
	await _wait_physics_frames(8)
	_assert(runner.has_balance_footing(), "Chibi lands on the beam placed through the First Steps item")

	var starting_z := runner.global_position.z
	runner.chibi_input.set_touch_move(Vector2.UP)
	await _wait_physics_frames(52)
	runner.chibi_input.set_touch_move(Vector2.ZERO)
	_assert(runner.current_state == "BalanceBeam" and runner.global_position.z < starting_z - 0.75,
		"Chibi walks along the placed balance beam")

	for audio_player in runner.find_children("*", "AudioStreamPlayer3D", true, false):
		audio_player.stop()
		audio_player.stream = null
	world.free()
	await process_frame


func _verify_tuning_survives_reopen(item_scene: PackedScene) -> void:
	var save_path := "user://scene_builder_tuning_reopen_check.tscn"
	var temporary_root := Node3D.new()
	var tuned_item := item_scene.instantiate() as Node3D
	tuned_item.name = "BalanceBeamItem"
	tuned_item.set("beam_length", 9.5)
	tuned_item.set("beam_radius", 0.19)
	temporary_root.add_child(tuned_item)
	tuned_item.owner = temporary_root

	var packed := PackedScene.new()
	_assert(packed.pack(temporary_root) == OK, "configured beam item packs for persistence")
	_assert(ResourceSaver.save(packed, save_path) == OK, "configured beam item saves")
	temporary_root.free()

	var reopened_scene := load(save_path) as PackedScene
	var reopened_root := reopened_scene.instantiate() as Node3D
	var reopened_item := reopened_root.get_node("BalanceBeamItem") as Node3D
	_assert(is_equal_approx(float(reopened_item.get("beam_length")), 9.5)
		and is_equal_approx(float(reopened_item.get("beam_radius")), 0.19),
		"beam length and radius survive reopening the saved scene")
	reopened_item.call("_update_editor_preview")
	var preview_mesh := reopened_item.get_node("EditorPreview/BeamMesh") as MeshInstance3D
	var preview_cylinder := preview_mesh.mesh as CylinderMesh
	_assert(is_equal_approx(preview_cylinder.height, 9.5)
		and is_equal_approx(preview_cylinder.top_radius, 0.19),
		"editor beam preview matches saved length and radius")

	root.add_child(reopened_root)
	await process_frame
	var reopened_beam := reopened_item.get_node_or_null("ParkourBalanceBeam") as ParkourBalanceBeam
	_assert(reopened_beam != null and is_equal_approx(reopened_beam.beam_length, 9.5)
		and is_equal_approx(reopened_beam.beam_radius, 0.19),
		"reopened inspector values reach the runtime gameplay beam")
	reopened_root.free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


func _verify_placement_undo_redo() -> void:
	var scene_owner := Node3D.new()
	root.add_child(scene_owner)
	var parent := Node3D.new()
	scene_owner.add_child(parent)
	parent.owner = scene_owner
	var instance := Node3D.new()
	instance.name = "MossBoulder"
	var placed_transform := Transform3D(Basis(Vector3.UP, deg_to_rad(35.0)), Vector3(-4.0, 2.3, -8.0))
	var manager := UndoRedo.new()
	PLACEMENT_ACTION.commit_item_placement(manager, parent, scene_owner, instance, placed_transform)
	_assert(instance.get_parent() == parent and instance.owner == scene_owner
		and instance.global_transform.is_equal_approx(placed_transform),
		"placement records the parent, scene owner, and world transform")

	manager.undo()
	_assert(instance.get_parent() == null and instance.owner == null,
		"undo removes the placed item and clears its scene owner")
	manager.redo()
	_assert(instance.get_parent() == parent and instance.owner == scene_owner
		and instance.global_transform.is_equal_approx(placed_transform),
		"redo restores the placed item and its world transform")
	manager.clear_history()
	scene_owner.free()
	manager.free()


func _wait_physics_frames(count: int) -> void:
	for _frame in count:
		await physics_frame
		await process_frame
