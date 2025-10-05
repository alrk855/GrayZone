# res://Scenes/Reusable/Map/secretary_office.gd
extends Control

@onready var secretary: Node = $background/Secretary
@onready var choice_panel_scene: PackedScene = preload("res://Scenes/Reusable/CharacterChoiceButtons.tscn")

const VISIT_SEC_ID := "Visit the Secretary"
const TASK_REQ := "Gather Scholarship Requirements"

# ---------- Full-background swap ----------
@export var background_node_path: NodePath = "background" # TextureRect/Sprite2D that renders the scene BG
@onready var _bg_node: Node = get_node_or_null(background_node_path)

@export var bg_here: Texture2D      # present
@export var bg_not_here: Texture2D  # absent

var _bg_current: Texture2D = null

# Hours
const T_13_00: int = 12 * 60
const T_16_00: int = 16 * 60

# ---------- JSONs (RELATIVE IDs; resolved via GameState.get_data_path) ----------
const JSON_SEC_INITIAL   := "Dialogue/Secretary/Secretary_Initial.json"
const JSON_SEC_NOT_HERE  := "Dialogue/Secretary/Secretary_NotHere.json"
const PRINT_MENU_JSON    := "Dialogue/Secretary/Secretary_Print_Menu.json"
const PRINT_CONFIG_JSON  := "Dialogue/Secretary/Secretary_Print_Config.json"
const JSON_TALK          := "Dialogue/Secretary/Secretary_Talk.json"

# Submit-specific JSONs
const JSON_SUBMIT_COMPLETE                := "Dialogue/Secretary/Secretary_Submit_Complete.json"
const JSON_SUBMIT_INCOMPLETE_PROMPT       := "Dialogue/Secretary/Secretary_Submit_Incomplete.json"
const JSON_SUBMIT_INCOMPLETE_ACCEPTED     := "Dialogue/Secretary/Secretary_Submit_Incomplete_Accepted.json"
const JSON_SUBMIT_INCOMPLETE_DECLINED     := "Dialogue/Secretary/Secretary_Submit_Incomplete_Declined.json"

# Endings scene
const ENDINGS_SCENE_PATH := "res://Scenes/ENDINGS.tscn"

var _active_panel: Control = null
var _print_cfg: Dictionary = {}

# Auto-close only if we entered before closing time
var _allow_auto_close := false
var _not_here_fired_on_enter := false

# Fade overlay
var _fade_layer: CanvasLayer = null
var _fade_rect: ColorRect = null

func _ready() -> void:
	GameState.location = "SecretaryOffice"
	GameState.ensure_task(VISIT_SEC_ID)

	_allow_auto_close = GameState.time < T_16_00
	_update_background()

	# ========== A) First-visit bump preserved ==========
	if _is_open_now():
		if GameState.get_task_progress(VISIT_SEC_ID) == 0:
			GameState.update_task_step(VISIT_SEC_ID)
			GameState.set_flag("secretary_met", true)
			var p := _jp(JSON_SEC_INITIAL)
			if p != "" and FileAccess.file_exists(p):
				DialogueManager.start_dialogue(p, self)
	else:
		call_deferred("_start_not_here_on_enter")
	# ===================================================

func _process(_delta: float) -> void:
	_update_background()
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
	if _bg_node == null or tex == null:
		return
	if _bg_current == tex:
		return
	_bg_current = tex
	if _bg_node is TextureRect:
		(_bg_node as TextureRect).texture = tex
	elif _bg_node is Sprite2D:
		(_bg_node as Sprite2D).texture = tex
	elif _bg_node.has_method("set_texture"):
		_bg_node.call("set_texture", tex)

# Deferred entry hook so NotHere ALWAYS fires after-hours
func _start_not_here_on_enter() -> void:
	if _not_here_fired_on_enter:
		return
	_not_here_fired_on_enter = true
	await get_tree().process_frame
	_start_not_here_dialogue()

func _start_not_here_dialogue() -> void:
	var p := _jp(JSON_SEC_NOT_HERE)
	if p != "" and FileAccess.file_exists(p):
		DialogueManager.start_dialogue(p, self)
	else:
		print(tr("Secretary not here (missing JSON): ") + p)

func _close_to_school() -> void:
	_fade_and_change_scene("res://Scenes/Reusable/Map/School.tscn")

# ----- UI flow -----
func start_interaction() -> void:
	_clear_panel()
	if not _is_open_now():
		_start_not_here_dialogue()
		return

	var opts: Array = []
	opts.append({ "text": tr("Ask about scholarship"), "id": "talk" })

	if _has_any_printables():
		opts.append({ "text": tr("Print a document"), "id": "print" })

	if GameState.day >= 5:
		opts.append({ "text": tr("Submit documents"), "id": "submit" })

	opts.append({ "text": tr("Back"), "id": "back" })

	_active_panel = choice_panel_scene.instantiate()
	add_child(_active_panel)
	_active_panel.call("show_options", opts, Callable(self, "_on_choice_selected"))

func _on_choice_selected(id: String) -> void:
	match id:
		"talk":
			var p_talk := _jp(JSON_TALK)
			if p_talk != "" and FileAccess.file_exists(p_talk):
				DialogueManager.start_dialogue(p_talk, self)
		"print":
			var p_menu := _jp(PRINT_MENU_JSON)
			if p_menu != "" and FileAccess.file_exists(p_menu):
				DialogueManager.start_dialogue(p_menu, self)
		"submit":
			await _start_submit_flow()
		"back":
			_clear_panel()

# ----- Submit flow (strictly checks the task progress vs steps) -----
func _start_submit_flow() -> void:
	_clear_panel()
	if _is_requirements_task_complete():
		# Complete route
		var p := _jp(JSON_SUBMIT_COMPLETE)
		if p != "" and FileAccess.file_exists(p):
			var ui := DialogueManager.start_dialogue(p, self)
			if ui and ui.has_signal("dialogue_finished"):
				await ui.dialogue_finished
		_finalize_submission_complete()
		await _goto_endings()
	else:
		# Incomplete prompt
		var p2 := _jp(JSON_SUBMIT_INCOMPLETE_PROMPT)
		if p2 != "" and FileAccess.file_exists(p2):
			var ui2 := DialogueManager.start_dialogue(p2, self)
			if ui2 and ui2.has_signal("dialogue_finished"):
				await ui2.dialogue_finished
		# If your JSON uses action to show choices, great; we also show a menu fallback:
		_show_submit_incomplete_choices()

func _show_submit_incomplete_choices() -> void:
	_clear_panel()
	var opts := [
		{ "text": tr("Submit anyway"), "id": "submit_anyway" },
		{ "text": tr("Cancel"),        "id": "cancel" }
	]
	_active_panel = choice_panel_scene.instantiate()
	add_child(_active_panel)
	_active_panel.call("show_options", opts, Callable(self, "_on_submit_incomplete_choice"))

func _on_submit_incomplete_choice(choice_id: String) -> void:
	match choice_id:
		"submit_anyway":
			_clear_panel()
			var p := _jp(JSON_SUBMIT_INCOMPLETE_ACCEPTED)
			if p != "" and FileAccess.file_exists(p):
				var ui := DialogueManager.start_dialogue(p, self)
				if ui and ui.has_signal("dialogue_finished"):
					ui.connect("dialogue_finished", func():
						_finalize_submission_incomplete()
						_goto_endings()
					, CONNECT_ONE_SHOT)
					return
			_finalize_submission_incomplete()
			await _goto_endings()
		"cancel":
			_clear_panel()
			var p2 := _jp(JSON_SUBMIT_INCOMPLETE_DECLINED)
			if p2 != "" and FileAccess.file_exists(p2):
				DialogueManager.start_dialogue(p2, self)

func _finalize_submission_complete() -> void:
	# Mark a generic "submitted" flag if you want; task logic remains your own
	GameState.set_flag("submitted_docs_complete", true)

func _finalize_submission_incomplete() -> void:
	GameState.set_flag("submitted_incomplete_docs", true)

func _is_requirements_task_complete() -> bool:
	var total := _get_task_steps_count(TASK_REQ)
	if total <= 0:
		return false
	return GameState.get_task_progress(TASK_REQ) >= total

func _get_task_steps_count(task_id: String) -> int:
	var path := GameState.get_data_path("Tasks/%s.json" % task_id)
	if not FileAccess.file_exists(path):
		return 0
	var txt := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return 0
	var steps = (parsed as Dictionary).get("steps", [])
	return (steps as Array).size() if steps is Array else 0

# ----- Dialogue Manager action hooks -----
func on_dialogue_action(line: Dictionary) -> void:
	var act := String(line.get("action", ""))

	match act:
		"sec_show_print_menu":
			_show_print_menu_from_config()
		"sec_show_submit_incomplete_choices":
			_show_submit_incomplete_choices()
		"sec_submit_anyway":
			_finalize_submission_incomplete()
		"sec_submit_complete":
			_finalize_submission_complete()
		"sec_submit_cancel":
			# nothing; player will come back later
			pass
		"ending":
			await _goto_endings()
		_:
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
			opts.append({ "text": "%s (%dMKD)" % [text, price], "id": id })

	if opts.is_empty():
		var nothing := [
			{ "text": tr("Nothing to print right now."), "id": "noop" },
			{ "text": tr("Back"), "id": "back" }
		]
		_active_panel = choice_panel_scene.instantiate()
		add_child(_active_panel)
		_active_panel.call("show_options", nothing, Callable(self, "_on_print_choice"))
		return

	opts.append({ "text": tr("Back"), "id": "back" })
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
			var action_rel := String(it.get("action_json", ""))

			if GameState.money < price:
				print(tr("❌ Not enough money to print."))
				return

			if action_rel != "":
				var p := _jp(action_rel)
				if p != "" and FileAccess.file_exists(p):
					DialogueManager.start_dialogue(p, self)
			_clear_panel()
			return

func _load_print_config() -> Dictionary:
	var p := _jp(PRINT_CONFIG_JSON)
	if p == "" or not FileAccess.file_exists(p):
		return {}
	var txt := FileAccess.get_file_as_string(p)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

func _clear_panel() -> void:
	if _active_panel and is_instance_valid(_active_panel):
		_active_panel.queue_free()
	_active_panel = null

# -------- Locale-aware resolver for RELATIVE IDs (R1: no fallback) --------
func _jp(rel: String) -> String:
	var base := String(rel).strip_edges().trim_prefix("/")
	if not GameState.has_method("get_data_path"):
		push_error("GameState.get_data_path is required for JSON path resolution. Missing for: " + base)
		return ""
	return String(GameState.get_data_path(base))

# ============ Fade helpers ============
func _ensure_fader() -> void:
	if _fade_layer == null or not is_instance_valid(_fade_layer):
		_fade_layer = CanvasLayer.new()
		_fade_layer.layer = 100
		add_child(_fade_layer)
	if _fade_rect == null or not is_instance_valid(_fade_rect):
		_fade_rect = ColorRect.new()
		_fade_rect.color = Color(0, 0, 0, 1)
		_fade_rect.modulate = Color(1, 1, 1, 0)
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fade_layer.add_child(_fade_rect)

func _fade_to(alpha: float, duration: float) -> void:
	_ensure_fader()
	var tw := create_tween()
	tw.tween_property(_fade_rect, "modulate:a", alpha, duration)
	await tw.finished

func _fade_and_change_scene(path: String) -> void:
	if path == "":
		return
	await _fade_to(1.0, 0.4)
	if ResourceLoader.exists(path):
		get_tree().change_scene_to_file(path)
	await _fade_to(0.0, 0.4)

func _goto_endings() -> void:
	await _fade_to(1.0, 0.4)
	if ResourceLoader.exists(ENDINGS_SCENE_PATH):
		get_tree().change_scene_to_file(ENDINGS_SCENE_PATH)
	await _fade_to(0.0, 0.4)
