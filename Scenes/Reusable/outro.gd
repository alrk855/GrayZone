# res://Scripts/Scenes/OutroMinimal.gd
extends Control
# Minimal: load JSON "text" into a Label, wire a Quit button.

# ---- Config (RELATIVE under Data/) ----
# Example file:      res://Data/outro.json
# Localized variant: res://DataMK/outro.json  (resolved by GameState.get_data_path)
@export var json_id: String = "outro.json"

@export var label_path: NodePath = ^"Panel/Label"
@export var quit_button_path: NodePath = ^"Panel/Button"

@onready var _label: Label  = get_node_or_null(label_path) as Label
@onready var _quit:  Button = get_node_or_null(quit_button_path) as Button

func _ready() -> void:
	if _label:
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label.text = _load_text(_dp(json_id))
	else:
		push_warning("Label not found. Assign 'label_path' in the Inspector.")

	if _quit:
		if not _quit.pressed.is_connected(Callable(self, "_on_quit_pressed")):
			_quit.pressed.connect(Callable(self, "_on_quit_pressed"))
	else:
		push_warning("Quit Button not found. Assign 'quit_button_path' in the Inspector.")

func _on_quit_pressed() -> void:
	get_tree().quit()

# ---- Data loader ----
func _load_text(abs_path: String) -> String:
	if abs_path.strip_edges() == "" or not FileAccess.file_exists(abs_path):
		push_warning("Could not open JSON (missing): %s" % abs_path)
		return ""

	var raw: String = FileAccess.get_file_as_string(abs_path)
	var data: Variant = JSON.parse_string(raw)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("JSON did not parse to a Dictionary at: %s" % abs_path)
		return ""

	var dict: Dictionary = data
	if dict.has("text"):
		var t: Variant = dict["text"]
		match typeof(t):
			TYPE_ARRAY:
				var out: PackedStringArray = []
				for item in (t as Array):
					out.append(str(item))
				return "\n".join(out)
			TYPE_STRING:
				return String(t)
		push_warning("'text' field exists but is not String or Array at: %s" % abs_path)
	else:
		push_warning("JSON missing 'text' field at: %s" % abs_path)

	return ""

# ---- Golden path resolver (relative → absolute, locale-aware) ----
func _dp(relative: String) -> String:
	var rel: String = String(relative).strip_edges().trim_prefix("/")
	if GameState.has_method("get_data_path"):
		return String(GameState.get_data_path(rel))
	# Fallback if GameState.get_data_path() is unavailable:
	return "res://Data/" + rel
