extends Node

var dialogue_ui: Control
var dialogue_data: Array = []
var line_index := 0

func start_dialogue(json_path: String, caller: Node = null) -> Control:
	var json_str := FileAccess.get_file_as_string(json_path)
	var parsed: Variant = JSON.parse_string(json_str)

	if parsed is Dictionary and parsed.has("lines"):
		dialogue_data = parsed["lines"]
		line_index = 0

		if dialogue_ui:
			dialogue_ui.queue_free()

		var ui_scene = load("res://Scenes/Reusable/Dialogue.tscn")
		dialogue_ui = ui_scene.instantiate()
		get_tree().current_scene.add_child(dialogue_ui)
		dialogue_ui.call("start", dialogue_data, caller)
		return dialogue_ui  # ✅ This was missing — fixes the problem
	else:
		push_error("Invalid dialogue JSON")
		return null
