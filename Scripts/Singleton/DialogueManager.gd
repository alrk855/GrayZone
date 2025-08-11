extends Node

signal dialogue_started(id: String)
signal dialogue_finished(id: String)

var dialogue_ui: Control = null
var dialogue_data: Array = []
var line_index: int = 0

func start_dialogue(json_path: String, caller: Node = null) -> Control:
	var json_str := FileAccess.get_file_as_string(json_path)
	var parsed: Variant = JSON.parse_string(json_str)

	if typeof(parsed) == TYPE_DICTIONARY and (parsed as Dictionary).has("lines"):
		var dict := parsed as Dictionary
		dialogue_data = dict.get("lines", []) as Array
		line_index = 0

		if is_instance_valid(dialogue_ui):
			dialogue_ui.queue_free()

		var dlg_id: String = str(dict.get("id", _basename(json_path)))

		# Freeze while this dialogue is open
		GameState.push_time_freeze("dialogue:%s" % dlg_id)

		var ui_scene: PackedScene = load("res://Scenes/Reusable/Dialogue.tscn")
		dialogue_ui = ui_scene.instantiate() as Control
		get_tree().current_scene.add_child(dialogue_ui)
		dialogue_ui.call("start", dialogue_data, caller)

		if dialogue_ui.has_signal("dialogue_finished"):
			dialogue_ui.connect("dialogue_finished", Callable(self, "_on_dialogue_ui_finished").bind(dlg_id, dict, null))
		else:
			dialogue_ui.tree_exited.connect(Callable(self, "_on_dialogue_ui_closed").bind(dlg_id, dict))

		emit_signal("dialogue_started", dlg_id)
		return dialogue_ui
	else:
		push_error("Invalid dialogue JSON: " + json_path)
		return null

func _on_dialogue_ui_finished(dlg_id: String, parsed: Dictionary, _payload: Variant = null) -> void:
	# Optional post-cost if you add it at the root of JSON
	if parsed.has("post_time_cost_minutes"):
		var m: int = int(parsed.get("post_time_cost_minutes", 0))
		if m > 0:
			GameState.apply_dialogue_time_cost(m, dlg_id)

	GameState.pop_time_freeze("dialogue:%s" % dlg_id)
	emit_signal("dialogue_finished", dlg_id)

	if is_instance_valid(dialogue_ui):
		dialogue_ui.queue_free()
		dialogue_ui = null

func _on_dialogue_ui_closed(dlg_id: String, parsed: Dictionary) -> void:
	_on_dialogue_ui_finished(dlg_id, parsed, null)

func _basename(path: String) -> String:
	return path.get_file().get_basename()
