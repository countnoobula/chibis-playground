@tool
extends RefCounted

## Shared placement action so editor placement and headless verification use the same undo/redo path.
static func commit_item_placement(
	manager,
	parent: Node,
	scene_owner: Node,
	instance: Node3D,
	global_transform: Transform3D
) -> void:
	manager.create_action("Instantiate selected item")
	if manager is UndoRedo:
		manager.add_do_method(Callable(parent, "add_child").bind(instance))
		manager.add_do_method(Callable(instance, "set_owner").bind(scene_owner))
		manager.add_do_method(Callable(instance, "set_global_transform").bind(global_transform))
		manager.add_undo_method(Callable(instance, "set_owner").bind(null))
		manager.add_undo_method(Callable(parent, "remove_child").bind(instance))
	else:
		# EditorUndoRedoManager uses the object/method/arguments form.
		manager.add_do_method(parent, "add_child", instance)
		manager.add_do_method(instance, "set_owner", scene_owner)
		manager.add_do_method(instance, "set_global_transform", global_transform)
		manager.add_undo_method(instance, "set_owner", null)
		manager.add_undo_method(parent, "remove_child", instance)
	manager.add_do_reference(instance)
	manager.commit_action()
