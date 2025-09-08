extends Node

const TASKS_DIR := "res://Data/Tasks/"
const FONT_PATH := "res://Fonts/MyUIFont.ttf"

var _cache: Dictionary = {}       # id -> parsed task json
var _title_cache: Dictionary = {} # id -> title string

func get_title(task_id: String) -> String:
	if _title_cache.has(task_id):
		return _title_cache[task_id]

	var data: Dictionary = _get_data(task_id)
	var raw_title: String = String(data.get("title", task_id))
	var title: String = _format_placeholders(raw_title)

	# cache only if there are no placeholders
	var has_dyn: bool = raw_title.find("{subject") != -1 or raw_title.find("[Subject") != -1
	if not has_dyn:
		_title_cache[task_id] = title

	return title

func _get_data(task_id: String) -> Dictionary:
	if _cache.has(task_id):
		return _cache[task_id]

	var path := "%s%s.json" % [TASKS_DIR, task_id]
	if not FileAccess.file_exists(path):
		return {}

	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return {}

	var parsed: Variant = JSON.parse_string(f.get_as_text())
	var d: Dictionary = {}
	if typeof(parsed) == TYPE_DICTIONARY:
		d = parsed

	_cache[task_id] = d
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
