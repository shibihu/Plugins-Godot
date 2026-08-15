@tool
extends Control

@onready var auto_save_toggle: CheckButton = $ScrollContainer/MarginContainer/VBoxContainer/AutoSaveSection/ToggleHBox/AutoSaveToggle
@onready var interval_spinbox: SpinBox = $ScrollContainer/MarginContainer/VBoxContainer/AutoSaveSection/IntervalHBox/IntervalSpinBox
@onready var auto_save_status_label: Label = $ScrollContainer/MarginContainer/VBoxContainer/AutoSaveSection/AutoSaveStatusLabel
@onready var auto_save_timer: Timer = $AutoSaveTimer

@onready var folder_line_edit: LineEdit = $ScrollContainer/MarginContainer/VBoxContainer/ZipSection/FolderHBox/FolderLineEdit
@onready var browse_folder_button: Button = $ScrollContainer/MarginContainer/VBoxContainer/ZipSection/FolderHBox/BrowseFolderButton
@onready var zip_path_line_edit: LineEdit = $ScrollContainer/MarginContainer/VBoxContainer/ZipSection/ZipPathHBox/ZipPathLineEdit
@onready var browse_zip_button: Button = $ScrollContainer/MarginContainer/VBoxContainer/ZipSection/ZipPathHBox/BrowseZipButton
@onready var extract_zip_button: Button = $ScrollContainer/MarginContainer/VBoxContainer/ZipSection/ExtractZipButton
@onready var zip_status_label: Label = $ScrollContainer/MarginContainer/VBoxContainer/ZipSection/ZipStatusLabel

@onready var folder_dialog: FileDialog = $FolderDialog
@onready var zip_dialog: FileDialog = $ZipDialog
@onready var confirmation_dialog: AcceptDialog = $ConfirmationDialog

func _ready() -> void:
	if folder_line_edit and folder_line_edit.text.is_empty():
		folder_line_edit.text = "res://"
	_update_default_zip_path()

	if auto_save_toggle:
		auto_save_toggle.toggled.connect(_on_auto_save_toggled)
	if interval_spinbox:
		interval_spinbox.value_changed.connect(_on_interval_value_changed)
	if auto_save_timer:
		auto_save_timer.timeout.connect(_on_auto_save_timer_timeout)

	if browse_folder_button:
		browse_folder_button.pressed.connect(_on_browse_folder_pressed)
	if browse_zip_button:
		browse_zip_button.pressed.connect(_on_browse_zip_pressed)
	if extract_zip_button:
		extract_zip_button.pressed.connect(_on_extract_zip_pressed)
	if folder_line_edit:
		folder_line_edit.text_changed.connect(_on_folder_text_changed)

	if folder_dialog:
		folder_dialog.dir_selected.connect(_on_folder_selected)
	if zip_dialog:
		zip_dialog.file_selected.connect(_on_zip_file_selected)

func _update_default_zip_path() -> void:
	if zip_path_line_edit and (zip_path_line_edit.text.is_empty() or zip_path_line_edit.text.ends_with("_backup.zip")):
		var folder_path := folder_line_edit.text if folder_line_edit else "res://"
		var folder_name := _get_folder_name(folder_path)
		zip_path_line_edit.text = folder_path.path_join(folder_name + "_backup.zip")

func _get_folder_name(path: String) -> String:
	var clean_path := path.rstrip("/")
	if clean_path == "res:" or clean_path.is_empty():
		var proj_name: String = ProjectSettings.get_setting("application/config/name", "project")
		return proj_name.validate_filename()
	return clean_path.get_file()

func _on_folder_text_changed(_new_text: String) -> void:
	_update_default_zip_path()

func _on_auto_save_toggled(toggled_on: bool) -> void:
	if toggled_on:
		auto_save_timer.wait_time = interval_spinbox.value
		auto_save_timer.start()
		auto_save_status_label.text = "Status: Auto-Save ON (Every " + str(int(interval_spinbox.value)) + "s)"
	else:
		auto_save_timer.stop()
		auto_save_status_label.text = "Status: Auto-Save OFF"

func _on_interval_value_changed(value: float) -> void:
	if auto_save_timer and not auto_save_timer.is_stopped():
		auto_save_timer.wait_time = value
		auto_save_status_label.text = "Status: Auto-Save ON (Every " + str(int(value)) + "s)"

func _on_auto_save_timer_timeout() -> void:
	if Engine.is_editor_hint():
		if EditorInterface.has_method("save_scene"):
			EditorInterface.save_scene()
		if EditorInterface.has_method("save_all_scenes"):
			EditorInterface.save_all_scenes()
		if EditorInterface.has_method("save_project_data"):
			EditorInterface.save_project_data()

		var current_time := Time.get_time_string_from_system()
		auto_save_status_label.text = "Status: Auto-saved at " + current_time

func _on_browse_folder_pressed() -> void:
	folder_dialog.popup_centered_ratio(0.6)

func _on_folder_selected(dir_path: String) -> void:
	folder_line_edit.text = dir_path
	_update_default_zip_path()

func _on_browse_zip_pressed() -> void:
	zip_dialog.popup_centered_ratio(0.6)

func _on_zip_file_selected(file_path: String) -> void:
	zip_path_line_edit.text = file_path

func _on_extract_zip_pressed() -> void:
	var target_folder := folder_line_edit.text.strip_edges()
	var zip_output_path := zip_path_line_edit.text.strip_edges()

	if target_folder.is_empty():
		zip_status_label.text = "Error: Please specify a target project folder."
		return

	if zip_output_path.is_empty():
		zip_status_label.text = "Error: Please specify a ZIP output path."
		return

	var global_target_dir := ProjectSettings.globalize_path(target_folder)
	var global_zip_path := ProjectSettings.globalize_path(zip_output_path)

	if not DirAccess.dir_exists_absolute(global_target_dir):
		zip_status_label.text = "Error: Target folder does not exist."
		return

	var parent_zip_dir := global_zip_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(parent_zip_dir):
		DirAccess.make_dir_recursive_absolute(parent_zip_dir)

	zip_status_label.text = "Creating ZIP archive..."

	var packer := ZIPPacker.new()
	var err := packer.open(global_zip_path, ZIPPacker.APPEND_CREATE)
	if err != OK:
		zip_status_label.text = "Failed to create ZIP file. Error code: " + str(err)
		return

	var file_count := _add_folder_to_zip(packer, global_target_dir, global_target_dir, global_zip_path)
	packer.close()

	zip_status_label.text = "Success! Created ZIP with " + str(file_count) + " files."
	confirmation_dialog.dialog_text = "Project successfully backed up to ZIP!\nPath: " + zip_output_path + "\nFiles compressed: " + str(file_count)
	confirmation_dialog.popup_centered()

func _add_folder_to_zip(packer: ZIPPacker, base_dir: String, current_dir: String, global_zip_path: String) -> int:
	var dir := DirAccess.open(current_dir)
	if not dir:
		return 0

	var count := 0
	var normalized_base := base_dir
	if not normalized_base.ends_with("/") and not normalized_base.ends_with("\\"):
		normalized_base += "/"

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if file_name == "." or file_name == "..":
			file_name = dir.get_next()
			continue

		# Skip .godot imported cache directory
		if file_name == ".godot":
			file_name = dir.get_next()
			continue

		var full_path := current_dir.path_join(file_name)
		var global_full_path := ProjectSettings.globalize_path(full_path)

		if global_full_path == global_zip_path:
			file_name = dir.get_next()
			continue

		if dir.current_is_dir():
			count += _add_folder_to_zip(packer, base_dir, full_path, global_zip_path)
		else:
			var rel_path := global_full_path.substr(normalized_base.length())
			rel_path = rel_path.replace("\\", "/")

			var open_err := packer.start_file(rel_path)
			if open_err == OK:
				var file := FileAccess.open(full_path, FileAccess.READ)
				if file:
					packer.write_file(file.get_buffer(file.get_length()))
					file.close()
					count += 1
				packer.close_file()

		file_name = dir.get_next()
	dir.list_dir_end()
	return count
