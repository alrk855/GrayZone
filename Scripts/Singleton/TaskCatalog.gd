extends Node

const TASKS_DIR := "Tasks/"                        # relative; resolved via GameState.get_data_path(...)
const FONT_PATH := "res://Fonts/MyUIFont.ttf"

var _cache: Dictionary = {}        # (task_id|locale) -> parsed task json
var _title_cache: Dictionary = {}  # (task_id|locale) -> title string

func get_title(task_id: String) -> String:
	var key := _title_key(task_id)
	if _title_cache.has(key):
		return _title_cache[key]

	var data: Dictionary = _get_data(task_id)
	var raw_title: String = String(data.get("title", task_id))
	var title: String = _format_placeholders(raw_title)

	# cache only if there are no placeholders
	var has_dyn: bool = raw_title.find("{subject") != -1 or raw_title.find("[Subject") != -1
	if not has_dyn:
		_title_cache[key] = title

	return title

func get_steps_count(task_id: String) -> int:
	var d := _get_data(task_id)
	var arr: Variant = d.get("steps", [])
	if arr is Array:
		return (arr as Array).size()
	return 0

func _get_data(task_id: String) -> Dictionary:
	var key := _data_key(task_id)
	if _cache.has(key):
		return _cache[key]

	var rel_path := "%s%s.json" % [TASKS_DIR, task_id]   # e.g., "Tasks/Visit the Secretary.json"
	var path := GameState.get_data_path(rel_path)        # resolves to Data/… or DataMK/… with fallback

	if not FileAccess.file_exists(path):
		return {}

	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return {}

	var parsed: Variant = JSON.parse_string(f.get_as_text())
	var d: Dictionary = {}
	if typeof(parsed) == TYPE_DICTIONARY:
		d = parsed

	_cache[key] = d
	return d

func _format_placeholders(text: String) -> String:
	var s := text
	if GameState.subject1 != "":
		s = s.replace("{subject1}", GameState.subject1.capitalize())
		s = s.replace("[Subject 1]", GameState.subject1.capitalize())
	if GameState.subject2 != "":
		s = s.replace("{subject2}", GameState.subject2.capitalize())
		s = s.replace("[Subject 2]", GameState.subject2.capitalize())
	return s

func clear_titles() -> void:
	_title_cache.clear()

# ---- locale-aware cache keys ----
# ---- locale-aware cache keys ----
func _locale() -> String:
	var loc := "en"
	# In editor or before autoloads are ready, default to EN
	if Engine.is_editor_hint():
		return loc
	# If the GameState singleton exists, use its locale (fallback to EN if empty)
	if Engine.has_singleton("GameState"):
		loc = String(GameState.current_locale)
		if loc == "":
			loc = "en"
	return loc

func _data_key(task_id: String) -> String:
	return "%s|%s" % [task_id, _locale()]

func _title_key(task_id: String) -> String:
	return "%s|%s" % [task_id, _locale()]
