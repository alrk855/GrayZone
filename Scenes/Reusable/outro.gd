extends Control
# Minimal: load JSON "text" into a Label, wire a Quit button.

@export_file("*.json") var json_path: String = "res://Data/outro.json"
@export var label_path: NodePath = "Panel/Label"
@export var quit_button_path: NodePath = "Panel/Button"

@onready var _label: Label = get_node_or_null(label_path)
@onready var _quit: Button = get_node_or_null(quit_button_path)

func _ready() -> void:
	if _label:
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label.text = _load_text(json_path)
	else:
		push_warning("Label not found. Assign 'label_path' in the Inspector.")

	if _quit:
		if not _quit.pressed.is_connected(_on_quit_pressed):
			_quit.pressed.connect(_on_quit_pressed)
	else:
		push_warning("Quit Button not found. Assign 'quit_button_path' in the Inspector.")

func _on_quit_pressed() -> void:
	get_tree().quit()

func _load_text(path: String) -> String:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		push_warning("Could not open JSON: %s" % path)
		return ""

	var raw := fa.get_as_text()
	fa.close()

	var data = JSON.parse_string(raw)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("JSON did not parse to a Dictionary.")
		return ""

	if data.has("text"):
		var t = data["text"]
		if typeof(t) == TYPE_ARRAY:
			var lines: PackedStringArray = []
			for item in t:
				lines.append(str(item))
			return "\n".join(lines)
		elif typeof(t) == TYPE_STRING:
			return t

	push_warning("JSON missing 'text' field or wrong type.")
	return ""
