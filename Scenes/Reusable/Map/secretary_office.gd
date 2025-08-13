extends Control

@onready var secretary: Node = $background/Secretary
@onready var choice_panel_scene: PackedScene = preload("res://Scenes/Reusable/CharacterChoiceButtons.tscn")

const GSR_ID := "Gather Scholarship Requirements"
const VISIT_SEC_ID := "Visit the Secretary"

# Flags used by printing gating
const FLAG_BOUGHT_PROJECT := "bought_project"
const FLAG_PRINTED_CV := "printed_cv"
const FLAG_PRINTED_LETTER := "printed_motivation"
const FLAG_PRINTED_PROJECT := "printed_project"
const FLAG_HAS_BIRTH_CERT := "have_birth_certificate" # NEW: Needed for notarization dialogue

# JSON paths
const PRINT_MENU_JSON := "res://Data/Dialogue/Secretary/Secretary_Print_Menu.json"
const PRINT_CONFIG_JSON := "res://Data/Dialogue/Secretary/Secretary_Print_Config.json"

var _active_panel: Control = null
var _pending_close_to_school: bool = false
var _print_cfg: Dictionary = {}

func _ready() -> void:
	GameState.location = "SecretaryOffice"

	# Auto-trigger first visit intro
	if GameState.tasks.has(VISIT_SEC_ID) and GameState.get_task_progress(VISIT_SEC_ID) == 0:
		GameState.update_task_step(VISIT_SEC_ID)
		DialogueManager.start_dialogue("res://Data/Dialogue/Secretary/Secretary_Initial.json", self)
		return

func _process(_delta: float) -> void:
	if GameState.time >= 16 * 60:
		if GameState.is_time_frozen():
			_pending_close_to_school = true
		else:
			_close_to_school()

func _close_to_school() -> void:
	print("🔒 The secretary has left for the day. Returning to school.")
	get_tree().change_scene_to_file("res://Scenes/Reusable/Map/School.tscn")

func _clear_panel() -> void:
	if _active_panel and is_instance_valid(_active_panel):
		_active_panel.queue_free()
	_active_panel = null

# Entry button in the scene
func start_interaction() -> void:
	if _pending_close_to_school and not GameState.is_time_frozen():
		_pending_close_to_school = false
		_close_to_school()
		return

	_clear_panel()

	var options: Array = []
	options.append({ "text": "Ask about scholarship", "id": "talk" })

	# Only show notarization if we have the birth certificate
	if GameState.has_flag(FLAG_HAS_BIRTH_CERT):
		options.append({ "text": "Ask about notarization", "id": "notarization" })

	if _has_any_printables():
		options.append({ "text": "Print a document", "id": "print" })

	if GameState.day >= 5:
		options.append({ "text": "Submit documents", "id": "submit" })

	options.append({ "text": "Back", "id": "back_dialogue" })

	_active_panel = choice_panel_scene.instantiate() as Control
	add_child(_active_panel)
	_active_panel.call("show_options", options, Callable(self, "_on_choice_selected"))

func _on_choice_selected(choice_id: String) -> void:
	match choice_id:
		"talk":
			DialogueManager.start_dialogue("res://Data/Dialogue/Secretary/Secretary_Talk.json", self)
		"notarization":
			DialogueManager.start_dialogue("res://Data/Dialogue/Secretary/Secretary_Notarization.json", self)
		"print":
			DialogueManager.start_dialogue(PRINT_MENU_JSON, self)
		"submit":
			if GameState.day < 5:
				DialogueManager.start_dialogue("res://Data/Dialogue/Secretary/Secretary_Submit_PreFriday.json", self)
			else:
				DialogueManager.start_dialogue("res://Data/Dialogue/Secretary/Secretary_Submit.json", self)
		"back_dialogue":
			_clear_panel()

func on_dialogue_action(line: Dictionary) -> void:
	var act: String = String(line.get("action", ""))
	match act:
		"sec_show_print_menu":
			_show_print_menu_from_config()
		_:
			GameState.apply_action(line)

# ---------------- JSON-driven printing ----------------

func _has_any_printables() -> bool:
	var cfg := _load_print_config()
	var items: Array = cfg.get("items", []) as Array
	for item_v in items:
		var item: Dictionary = item_v
		var requires_feature: String = String(item.get("requires_feature", ""))
		var requires_flag_any: Array = item.get("requires_flag_any", []) as Array
		var flag_done: String = String(item.get("flag", ""))

		if flag_done != "" and GameState.has_flag(flag_done):
			continue

		if requires_feature != "" and GameState.has_feature(requires_feature):
			return true

		for rf in requires_flag_any:
			if GameState.has_flag(String(rf)):
				return true

	return false

func _show_print_menu_from_config() -> void:
	_clear_panel()

	_print_cfg = _load_print_config()
	if _print_cfg.is_empty():
		print("⚠️ Missing or malformed print config:", PRINT_CONFIG_JSON)
		return

	var items: Array = _print_cfg.get("items", []) as Array
	var opts: Array = []

	for item_v in items:
		var item: Dictionary = item_v
		var id: String = String(item.get("id", ""))
		var text: String = String(item.get("text", ""))
		var price: int = int(item.get("price", 0))
		var flag_done: String = String(item.get("flag", ""))
		var requires_feature: String = String(item.get("requires_feature", ""))
		var requires_flag_any: Array = item.get("requires_flag_any", []) as Array

		if flag_done != "" and GameState.has_flag(flag_done):
			continue

		if requires_feature != "" and not GameState.has_feature(requires_feature):
			var any_ok := false
			for rf in requires_flag_any:
				if GameState.has_flag(String(rf)):
					any_ok = true
					break
			if not any_ok:
				continue

		var label := "%s (%d$)" % [text, price]
		opts.append({ "text": label, "id": id })

	if opts.is_empty():
		print("ℹ️ Nothing to print.")
		return

	opts.append({ "text": "Back", "id": "back" })

	_active_panel = choice_panel_scene.instantiate() as Control
	add_child(_active_panel)
	_active_panel.call("show_options", opts, Callable(self, "_on_print_choice"))

func _on_print_choice(choice_id: String) -> void:
	if choice_id == "back":
		_clear_panel()
		return

	var items: Array = _print_cfg.get("items", []) as Array
	for item_v in items:
		var item: Dictionary = item_v
		if String(item.get("id", "")) != choice_id:
			continue

		var price := int(item.get("price", 0))
		var action_json := String(item.get("action_json", ""))

		if GameState.money < price:
			print("❌ Not enough money to print.")
			return

		if action_json != "" and FileAccess.file_exists(action_json):
			DialogueManager.start_dialogue(action_json, self)
		else:
			print("⚠️ Missing action JSON for", choice_id, "->", action_json)

		_clear_panel()
		return

	print("⚠️ Unknown print choice:", choice_id)

func _load_print_config() -> Dictionary:
	if not FileAccess.file_exists(PRINT_CONFIG_JSON):
		return {}
	var txt := FileAccess.get_file_as_string(PRINT_CONFIG_JSON)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed
