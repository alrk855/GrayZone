# res://Scenes/Reusable/Map/secretary_office.gd
extends Control

@onready var secretary: Node = $background/Secretary
@onready var choice_panel_scene: PackedScene = preload("res://Scenes/Reusable/CharacterChoiceButtons.tscn")

const VISIT_SEC_ID := "Visit the Secretary"

# ---------- Full-background swap ----------
@export var background_node_path: NodePath = "background" # TextureRect/Sprite2D that renders the scene BG
@onready var _bg_node: Node = get_node_or_null(background_node_path)

@export var bg_here: Texture2D      # present
@export var bg_not_here: Texture2D  # absent

var _bg_current: Texture2D = null

# Hours (change close to 17*60 if needed)
const T_13_00: int = 13 * 60
const T_16_00: int = 16 * 60

# ---------- JSONs ----------
const JSON_SEC_INITIAL   := "res://Data/Dialogue/Secretary/Secretary_Initial.json"
const JSON_SEC_NOT_HERE  := "res://Data/Dialogue/Secretary/Secretary_NotHere.json"
const PRINT_MENU_JSON    := "res://Data/Dialogue/Secretary/Secretary_Print_Menu.json"
const PRINT_CONFIG_JSON  := "res://Data/Dialogue/Secretary/Secretary_Print_Config.json"

var _active_panel: Control = null
var _print_cfg: Dictionary = {}

# Auto-close only if we entered before closing time
var _allow_auto_close := false
var _not_here_fired_on_enter := false

func _ready() -> void:
	GameState.location = "SecretaryOffice"
	GameState.ensure_task(VISIT_SEC_ID)

	_allow_auto_close = GameState.time < T_16_00
	_update_background()

	# ENTER LOGIC:
	if _is_open_now():
		# First-time intro only during working hours
		if GameState.get_task_progress(VISIT_SEC_ID) == 0:
			GameState.update_task_step(VISIT_SEC_ID)
			GameState.set_flag("secretary_met", true)
			DialogueManager.start_dialogue(JSON_SEC_INITIAL, self)
	else:
		# After-hours: ALWAYS show NotHere on enter (deferred so it never gets skipped)
		call_deferred("_start_not_here_on_enter")

func _process(_delta: float) -> void:
	_update_background()

	# Auto-close only if we were here before close and time passes closing
	if _allow_auto_close and GameState.time >= T_16_00 and not GameState.is_time_frozen():
		_close_to_school()

# ----- Presence / Background -----
func _is_open_now() -> bool:
	return GameState.time >= T_13_00 and GameState.time < T_16_00

func _update_background() -> void:
	if _is_open_now() and bg_here:
		_set_bg(bg_here)
	elif not _is_open_now() and bg_not_here:
		_set_bg(bg_not_here)

func _set_bg(tex: Texture2D) -> void:
	if _bg_node == null or tex == null: return
	if _bg_current == tex: return
	_bg_current = tex
	if _bg_node is TextureRect:
		(_bg_node as TextureRect).texture = tex
	elif _bg_node is Sprite2D:
		(_bg_node as Sprite2D).texture = tex
	elif _bg_node.has_method("set_texture"):
		_bg_node.call("set_texture", tex)

# Deferred entry hook so NotHere ALWAYS fires after-hours
func _start_not_here_on_enter() -> void:
	if _not_here_fired_on_enter: return
	_not_here_fired_on_enter = true
	# one extra frame to be extra-safe on slow loads
	await get_tree().process_frame
	_start_not_here_dialogue()

func _start_not_here_dialogue() -> void:
	if FileAccess.file_exists(JSON_SEC_NOT_HERE):
		DialogueManager.start_dialogue(JSON_SEC_NOT_HERE, self)
	else:
		print("Secretary not here (missing JSON): ", JSON_SEC_NOT_HERE)

func _close_to_school() -> void:
	get_tree().change_scene_to_file("res://Scenes/Reusable/Map/School.tscn")

# ----- UI flow -----
func start_interaction() -> void:
	_clear_panel()
	# After-hours -> show NotHere on click too
	if not _is_open_now():
		_start_not_here_dialogue()
		return

	var opts: Array = []
	opts.append({ "text": "Ask about scholarship", "id": "talk" })

	if GameState.has_flag("have_birth_certificate"):
		opts.append({ "text": "Ask about notarization", "id": "notarization" })

	if _has_any_printables():
		opts.append({ "text": "Print a document", "id": "print" })

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
			DialogueManager.start_dialogue(PRINT_MENU_JSON, self) # wrapper -> sec_show_print_menu
		"submit":
			if GameState.day < 5:
				DialogueManager.start_dialogue("res://Data/Dialogue/Secretary/Secretary_Submit_PreFriday.json", self)
			else:
				DialogueManager.start_dialogue("res://Data/Dialogue/Secretary/Secretary_Submit.json", self)
		"back":
			_clear_panel()

func on_dialogue_action(line: Dictionary) -> void:
	var act := String(line.get("action", ""))
	if act == "sec_show_print_menu":
		_show_print_menu_from_config()
	else:
		GameState.apply_action(line)

# ----- Printing gating -----
func _is_print_ready_item(item: Dictionary) -> bool:
	var item_id := String(item.get("id", ""))
	var printed_flag := String(item.get("flag", ""))

	if printed_flag != "" and GameState.has_flag(printed_flag):
		return false
	if printed_flag == "printed_cv" or item_id == "print_cv":
		return GameState.get_task_progress("cv") >= 2
	if printed_flag == "printed_motivation" or item_id == "print_letter":
		return GameState.get_task_progress("motivation") >= 2
	if printed_flag == "printed_project":
		return GameState.has_flag("project_written") or GameState.has_flag("bought_project")
	return false

func _has_any_printables() -> bool:
	var cfg := _load_print_config()
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
			var text := String(it.get("text", ""))
			var price := int(it.get("price", 0))
			var id := String(it.get("id", ""))
			opts.append({ "text": "%s (%d$)" % [text, price], "id": id })

	if opts.is_empty():
		var nothing := [{ "text": "Nothing to print right now.", "id": "noop" }, { "text": "Back", "id": "back" }]
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
			var price := int(it.get("price", 0))
			var action_json := String(it.get("action_json", ""))
			if GameState.money < price:
				print("❌ Not enough money to print.")
				return
			if action_json != "" and FileAccess.file_exists(action_json):
				DialogueManager.start_dialogue(action_json, self)
			_clear_panel()
			return

func _load_print_config() -> Dictionary:
	if not FileAccess.file_exists(PRINT_CONFIG_JSON):
		return {}
	var txt := FileAccess.get_file_as_string(PRINT_CONFIG_JSON)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

func _clear_panel() -> void:
	if _active_panel and is_instance_valid(_active_panel):
		_active_panel.queue_free()
	_active_panel = null
