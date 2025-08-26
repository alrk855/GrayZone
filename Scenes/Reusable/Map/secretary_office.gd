# res://Scenes/Reusable/Map/secretary_office.gd
extends Control

@onready var secretary: Node = $background/Secretary
@onready var choice_panel_scene: PackedScene = preload("res://Scenes/Reusable/CharacterChoiceButtons.tscn")

const VISIT_SEC_ID := "Visit the Secretary"

# JSONs
const PRINT_MENU_JSON := "res://Data/Dialogue/Secretary/Secretary_Print_Menu.json"
const PRINT_CONFIG_JSON := "res://Data/Dialogue/Secretary/Secretary_Print_Config.json"

var _active_panel: Control = null
var _print_cfg: Dictionary = {}

func _ready() -> void:
	GameState.location = "SecretaryOffice"
	GameState.ensure_task(VISIT_SEC_ID)

	# Auto-trigger first visit
	if GameState.get_task_progress(VISIT_SEC_ID) == 0:
		GameState.update_task_step(VISIT_SEC_ID)
		GameState.set_flag("secretary_met", true)
		DialogueManager.start_dialogue("res://Data/Dialogue/Secretary/Secretary_Initial.json", self)

func _process(_delta: float) -> void:
	# Don’t yank the player out mid-dialogue
	if GameState.time >= 16 * 60 and not GameState.is_time_frozen():
		_close_to_school()

func _close_to_school() -> void:
	get_tree().change_scene_to_file("res://Scenes/Reusable/Map/School.tscn")

func start_interaction() -> void:
	_clear_panel()

	var opts: Array = []
	opts.append({ "text": "Ask about scholarship", "id": "talk" })

	# Only after birth certificate is obtained
	if GameState.has_flag("have_birth_certificate"):
		opts.append({ "text": "Ask about notarization", "id": "notarization" })

	# Print menu only if at least one item is printable
	if _has_any_printables():
		opts.append({ "text": "Print a document", "id": "print" })

	# Submissions from Day 5 onward
	if GameState.day >= 5:
		opts.append({ "text": "Submit documents", "id": "submit" })

	opts.append({ "text": "Back", "id": "back" })

	_active_panel = choice_panel_scene.instantiate()
	add_child(_active_panel)
	_active_panel.call("show_options", opts, Callable(self, "_on_choice_selected"))

func _on_choice_selected(id: String) -> void:
	match id:
		"talk":
			DialogueManager.start_dialogue("res://Data/Dialogue/Secretary/Secretary_Talk.json", self)
		"notarization":
			DialogueManager.start_dialogue("res://Data/Dialogue/Secretary/Secretary_Notarization.json", self)
		"print":
			# Wrapper JSON -> calls sec_show_print_menu
			DialogueManager.start_dialogue(PRINT_MENU_JSON, self)
		"submit":
			if GameState.day < 5:
				DialogueManager.start_dialogue("res://Data/Dialogue/Secretary/Secretary_Submit_PreFriday.json", self)
			else:
				DialogueManager.start_dialogue("res://Data/Dialogue/Secretary/Secretary_Submit.json", self)
		"back":
			_clear_panel()

func on_dialogue_action(line: Dictionary) -> void:
	var act: String = String(line.get("action", ""))
	if act == "sec_show_print_menu":
		_show_print_menu_from_config()
	else:
		GameState.apply_action(line)

# ---------- Printing gating ----------

func _is_print_ready_item(item: Dictionary) -> bool:
	var item_id: String = String(item.get("id", ""))
	var printed_flag: String = String(item.get("flag", ""))

	# Already printed? hide
	if printed_flag != "" and GameState.has_flag(printed_flag):
		return false

	# CV: require task progress >= 2 (visit/draft done → print step)
	if printed_flag == "printed_cv" or item_id == "print_cv":
		return GameState.get_task_progress("cv") >= 2

	# Motivation letter: same logic
	if printed_flag == "printed_motivation" or item_id == "print_letter":
		return GameState.get_task_progress("motivation") >= 2

	# Project: must be written OR bought (janitor)
	if printed_flag == "printed_project" or item_id == "print_project":
		return GameState.has_flag("project_written") or GameState.has_flag("bought_project")

	return false

func _has_any_printables() -> bool:
	var cfg: Dictionary = _load_print_config()
	var items: Array = cfg.get("items", []) as Array
	for v in items:
		var it: Dictionary = v
		if _is_print_ready_item(it):
			return true
	return false

func _show_print_menu_from_config() -> void:
	_clear_panel()

	_print_cfg = _load_print_config()
	var items: Array = _print_cfg.get("items", []) as Array

	var opts: Array = []
	for v in items:
		var it: Dictionary = v
		if _is_print_ready_item(it):
			var text: String = String(it.get("text", ""))
			var price: int = int(it.get("price", 0))
			var id: String = String(it.get("id", ""))
			opts.append({ "text": "%s (%d$)" % [text, price], "id": id })

	if opts.is_empty():
		# Optional: tiny notice instead of silent return
		var nothing: Array = [{ "text": "Nothing to print right now.", "id": "noop" },
			{ "text": "Back", "id": "back" }]
		_active_panel = choice_panel_scene.instantiate()
		add_child(_active_panel)
		_active_panel.call("show_options", nothing, Callable(self, "_on_print_choice"))
		return

	opts.append({ "text": "Back", "id": "back" })

	_active_panel = choice_panel_scene.instantiate()
	add_child(_active_panel)
	_active_panel.call("show_options", opts, Callable(self, "_on_print_choice"))

func _on_print_choice(choice_id: String) -> void:
	if choice_id == "back" or choice_id == "noop":
		_clear_panel()
		return

	var items: Array = _print_cfg.get("items", []) as Array
	for v in items:
		var it: Dictionary = v
		if String(it.get("id", "")) == choice_id:
			var price: int = int(it.get("price", 0))
			var action_json: String = String(it.get("action_json", ""))

			if GameState.money < price:
				# Optional: you can start a "not enough money" JSON here
				print("❌ Not enough money to print.")
				return

			# Let the action JSON handle: add_money:-price, set_flags: printed_*,
			# and update_task_step: cv/motivation/project (print step)
			if action_json != "" and FileAccess.file_exists(action_json):
				DialogueManager.start_dialogue(action_json, self)

			_clear_panel()
			return

func _load_print_config() -> Dictionary:
	if not FileAccess.file_exists(PRINT_CONFIG_JSON):
		return {}
	var txt: String = FileAccess.get_file_as_string(PRINT_CONFIG_JSON)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

func _clear_panel() -> void:
	if _active_panel and is_instance_valid(_active_panel):
		_active_panel.queue_free()
	_active_panel = null
