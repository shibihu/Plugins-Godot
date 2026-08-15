@tool
extends EditorPlugin

var dock_instance: Control

func _enter_tree() -> void:
	dock_instance = preload("res://addons/autosave_and_zip/dock.tscn").instantiate()
	if dock_instance.has_method("set_editor_interface"):
		dock_instance.set_editor_interface(get_editor_interface())
	add_control_to_dock(DOCK_SLOT_LEFT_UL, dock_instance)

func _exit_tree() -> void:
	if dock_instance:
		remove_control_from_dock(dock_instance)
		dock_instance.queue_free()
