# MarkoFirstEvent.gd (reentrant-safe)
extends Control

# ---- JSON paths (your corrected folder) ----
const JSON_ENTRY        := "res://Data/Marko/FirstEvent/00_Entry.json"
const JSON_STUDY_SWAY   := "res://Data/Marko/FirstEvent/01_Study_Sway.json"
const JSON_GOTO_STUDY   := "res://Data/Marko/FirstEvent/02_Goto_StudyScene.json"
const JSON_ALONE_PUSH   := "res://Data/Marko/FirstEvent/10_StudyAlone_Push.json"
const JSON_SOLO_END     := "res://Data/Marko/FirstEvent/11_SoloStudy_End.json"
const JSON_HANGOUT_END  := "res://Data/Marko/FirstEvent/12_Hangout_End.json"

const FALLBACK_HOME     := "res://Scenes/Reusable/Map/Home.tscn"

@onready var choice_panel_scene: PackedScene = preload("res://Scenes/Reusable/CharacterChoiceButtons.tscn")
var _panel: Control = null
var _transitioning := false

func _ready() -> void:
	GameState.location = "MarkoFirstEvent"
	DialogueManager.start_dialogue(JSON_ENTRY, self)

func _clear_panel() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null

# ------- Safe transition helpers -------
func _safe_end_dialogue() -> void:
	if _transitioning:
		return
	DialogueManager.end_active_dialogue()

func _safe_start_dialogue(path: String) -> void:
	if _transitioning:
		return
	_transitioning = true
	# Give the DM one or two frames to fully unwind its stack
	await get_tree().process_frame
	await get_tree().process_frame
	call_deferred("_do_start_dialogue", path)

func _do_start_dialogue(path: String) -> void:
	_transitioning = false
	DialogueManager.start_dialogue(path, self)

func _safe_change_scene(path: String) -> void:
	if _transitioning:
		return
	_transitioning = true
	await get_tree().process_frame
	call_deferred("_do_change_scene", path)

func _do_change_scene(path: String) -> void:
	_transitioning = false
	if path != "" and ResourceLoader.exists(path):
		get_tree().change_scene_to_file(path)
	else:
		push_warning("MarkoFirstEvent: invalid scene path: " + path)

# ---- DM action hook ----
func on_dialogue_action(line: Dictionary) -> void:
	var act: String = String(line.get("action", ""))
	match act:
		# our custom tokens → spawn a choice panel
		"marko_show_entry_choices":
			_show_entry_choices()
		"marko_show_study_sway_choices":
			_show_study_sway_choices()
		"marko_show_alone_push_choices":
			_show_alone_push_choices()

		# scene control (deferred)
		"goto":
			var scene_path: String = String(line.get("scene", ""))
			if scene_path != "":
				_safe_end_dialogue()
				_safe_change_scene(scene_path)
		"end_event":
			_safe_end_dialogue()
			_safe_change_scene(FALLBACK_HOME)

		# everything else → let GameState handle (time, flags, tasks, rep…)
		_:
			GameState.apply_action(line)

# ---- Choice panels ----
func _show_entry_choices() -> void:
	_clear_panel()
	var options: Array = [
		{ "text": "Let’s study together.", "id": "study_together" },
		{ "text": "I’m studying alone.",   "id": "study_alone" },
		{ "text": "We can hang out.",      "id": "hangout" }
	]
	_panel = choice_panel_scene.instantiate()
	add_child(_panel)
	_panel.call("show_options", options, Callable(self, "_on_entry_choice"))

func _on_entry_choice(id: String) -> void:
	match id:
		"study_together":
			_clear_panel()
			_safe_end_dialogue()
			_safe_start_dialogue(JSON_STUDY_SWAY)
		"study_alone":
			_clear_panel()
			_safe_end_dialogue()
			_safe_start_dialogue(JSON_ALONE_PUSH)
		"hangout":
			_clear_panel()
			_safe_end_dialogue()
			_safe_start_dialogue(JSON_HANGOUT_END)

func _show_study_sway_choices() -> void:
	_clear_panel()
	var options: Array = [
		{ "text": "No, seriously. Let’s study.",   "id": "study_now" },
		{ "text": "Alright, let’s hang out a bit.", "id": "hangout_now" }
	]
	_panel = choice_panel_scene.instantiate()
	add_child(_panel)
	_panel.call("show_options", options, Callable(self, "_on_study_sway_choice"))

func _on_study_sway_choice(id: String) -> void:
	match id:
		"study_now":
			_clear_panel()
			_safe_end_dialogue()
			_safe_start_dialogue(JSON_GOTO_STUDY) # JSON handles scene jump (no study scene yet is fine; it’ll just exit)
		"hangout_now":
			_clear_panel()
			_safe_end_dialogue()
			_safe_start_dialogue(JSON_HANGOUT_END)

func _show_alone_push_choices() -> void:
	_clear_panel()
	var options: Array = [
		{ "text": "No. I’ll study on my own.", "id": "solo_study" },
		{ "text": "Fine, we can hang out.",    "id": "hangout_now" }
	]
	_panel = choice_panel_scene.instantiate()
	add_child(_panel)
	_panel.call("show_options", options, Callable(self, "_on_alone_push_choice"))

func _on_alone_push_choice(id: String) -> void:
	match id:
		"solo_study":
			_clear_panel()
			_safe_end_dialogue()
			_safe_start_dialogue(JSON_SOLO_END)
		"hangout_now":
			_clear_panel()
			_safe_end_dialogue()
			_safe_start_dialogue(JSON_HANGOUT_END)

# Fallback if a JSON ends without scene jump
func on_dialogue_finished() -> void:
	_safe_change_scene(FALLBACK_HOME)
