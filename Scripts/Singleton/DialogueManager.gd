extends Node

signal dialogue_started(id: String)
signal dialogue_finished(id: String)

var dialogue_ui: Control = null
var dialogue_data: Array = []
var line_index: int = 0

var _current_id: String = ""
var _current_json: Dictionary = {}

func start_dialogue(json_path: String, caller: Node = null) -> Control:
	var json_str := FileAccess.get_file_as_string(json_path)
	var parsed: Variant = JSON.parse_string(json_str)
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("lines"):
		push_error("Invalid dialogue JSON: " + json_path)
		return null

	var dict: Dictionary = parsed
	dialogue_data = dict.get("lines", []) as Array
	line_index = 0

	# kill any existing UI first
	if is_instance_valid(dialogue_ui):
		dialogue_ui.queue_free()
	dialogue_ui = null

	var dlg_id: String = str(dict.get("id", _basename(json_path)))
	_current_id = dlg_id
	_current_json = dict

	GameState.push_time_freeze("dialogue:%s" % dlg_id)

	var ui_scene: PackedScene = load("res://Scenes/Reusable/Dialogue.tscn")
	var ui := ui_scene.instantiate() as Control
	dialogue_ui = ui
	get_tree().current_scene.add_child(ui)

	# --- CONNECT SIGNALS BEFORE START() ---
	# finish signals
	if ui.has_signal("dialogue_finished"):
		if not ui.is_connected("dialogue_finished", Callable(self, "_on_dialogue_ui_finished")):
			ui.connect("dialogue_finished", Callable(self, "_on_dialogue_ui_finished").bind(dlg_id, dict, null))
	# always have a safety close
	ui.tree_exited.connect(Callable(self, "_on_dialogue_ui_closed").bind(dlg_id, dict))

	# action bridge to caller (if it has on_dialogue_action)
	if caller and is_instance_valid(caller) and ui.has_signal("dialogue_action") and caller.has_method("on_dialogue_action"):
		ui.connect("dialogue_action", Callable(caller, "on_dialogue_action"))

	# also listen ourselves so "end_dialogue"/"goto __close" work
	if ui.has_signal("dialogue_action"):
		ui.connect("dialogue_action", Callable(self, "_ui_action_bridge"))

	emit_signal("dialogue_started", dlg_id)

	# NOW start the UI, after everything is wired
	ui.call("start", dialogue_data, caller)
	return ui


func _ui_action_bridge(line: Dictionary) -> void:
	var act := String(line.get("action", ""))
	if act == "end_dialogue":
		end_active_dialogue()
	elif act == "goto" and String(line.get("id","")) == "__close":
		end_active_dialogue()

func end_active_dialogue() -> void:
	if _current_id != "":
		_on_dialogue_ui_finished(_current_id, _current_json, null)

func _on_dialogue_ui_finished(dlg_id: String, parsed: Dictionary, _payload: Variant = null) -> void:
	if parsed.has("post_time_cost_minutes"):
		var m: int = int(parsed.get("post_time_cost_minutes", 0))
		if m > 0:
			GameState.apply_dialogue_time_cost(m, dlg_id)
	GameState.pop_time_freeze("dialogue:%s" % dlg_id)
	emit_signal("dialogue_finished", dlg_id)
	if is_instance_valid(dialogue_ui):
		dialogue_ui.queue_free()
	dialogue_ui = null
	_current_id = ""
	_current_json = {}

func _on_dialogue_ui_closed(dlg_id: String, parsed: Dictionary) -> void:
	_on_dialogue_ui_finished(dlg_id, parsed, null)

func _basename(path: String) -> String:
	return path.get_file().get_basename()
