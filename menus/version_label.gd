
extends Label

const LATEST_RELEASE_URL := \
	"https://api.github.com/repos/petesamerson/V-s-on/releases/latest"

var _installed_version: String


func _ready() -> void:
	_installed_version = str(ProjectSettings.get_setting("application/config/version", ""))
	text = "v" + _installed_version if not _installed_version.is_empty() else "Development build"

	var request := HTTPRequest.new()
	add_child(request)
	request.timeout = 5.0
	request.request_completed.connect(_on_release_checked)
	request.request(LATEST_RELEASE_URL, PackedStringArray(["Accept: application/vnd.github+json"]))


func _on_release_checked(
	result: int, status: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or status != 200:
		return

	var release = JSON.parse_string(body.get_string_from_utf8())
	if not release is Dictionary:
		return

	var latest := str(release.get("tag_name", "")).trim_prefix("v")
	var installed := _installed_version.trim_prefix("v")
	if _is_newer(latest, installed):
		text = "v%s · Update available (v%s)" % [installed, latest]


func _is_newer(latest: String, installed: String) -> bool:
	var latest_parts := latest.split(".")
	var installed_parts := installed.split(".")
	if latest_parts.size() != 3 or installed_parts.size() != 3:
		return false

	for index in range(3):
		if not latest_parts[index].is_valid_int() or not installed_parts[index].is_valid_int():
			return false

	for index in range(3):
		var latest_number := latest_parts[index].to_int()
		var installed_number := installed_parts[index].to_int()
		if latest_number != installed_number:
			return latest_number > installed_number

	return false