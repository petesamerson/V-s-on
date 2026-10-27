extends Node

const SAVE_PATH := "user://offline_match.save"
const TEMP_PATH := "user://offline_match.tmp"
const BACKUP_PATH := "user://offline_match.backup"
const SAVE_VERSION := 1

var pending_resume: Dictionary = {}


func write_match(data: Dictionary) -> Error:
	data["save_version"] = SAVE_VERSION

	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	var stored: bool = file.store_var(data, false)
	file.flush()
	var error := file.get_error()
	file.close()

	if not stored:
		return ERR_FILE_CANT_WRITE
	if error != OK:
		return error

	var main_path := ProjectSettings.globalize_path(SAVE_PATH)
	var backup_path := ProjectSettings.globalize_path(BACKUP_PATH)
	var temporary_path := ProjectSettings.globalize_path(TEMP_PATH)

	if FileAccess.file_exists(SAVE_PATH):
		if FileAccess.file_exists(BACKUP_PATH):
			error = DirAccess.remove_absolute(backup_path)
			if error != OK:
				return error

		error = DirAccess.rename_absolute(main_path, backup_path)
		if error != OK:
			return error

	error = DirAccess.rename_absolute(temporary_path, main_path)
	if error != OK and FileAccess.file_exists(BACKUP_PATH):
		DirAccess.rename_absolute(backup_path, main_path)

	return error


func read_match() -> Dictionary:
	for path in [SAVE_PATH, BACKUP_PATH]:
		if not FileAccess.file_exists(path):
			continue

		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue

		var data: Variant = file.get_var(false)
		file.close()

		if not data is Dictionary:
			continue
		if int(data.get("save_version", -1)) != SAVE_VERSION:
			continue

		if (
			not data.get("pieces") is Array
			or not data.get("captures") is Array
			or not data.get("cpu") is Dictionary
			or not data.get("colors") is Array
		):
			continue

		return data

	return {}


func clear_match() -> void:
	pending_resume.clear()

	for path in [SAVE_PATH, BACKUP_PATH, TEMP_PATH]:
		if FileAccess.file_exists(path):
			var error := DirAccess.remove_absolute(
				ProjectSettings.globalize_path(path)
			)
			if error != OK:
				push_error("Could not remove offline save: " + error_string(error))