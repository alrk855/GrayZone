extends Control

const STUDY_SCENE_PATH: String       = "res://Scenes/Reusable/Tasks/Study.tscn"
const RETURN_SCENE_FALLBACK: String  = "res://Scenes/Reusable/Events/MarkoFirstEvent.tscn"

const KEY_STUDY_MODE: String     = "__study_mode"
const KEY_SUBJECT_PICK: String   = "__study_subject_pick"
const KEY_RETURN_SCENE: String   = "__study_return_scene"

# Phase flags to drive the round-trip flow
const F_PHASE_POST_S1: String = "marko_study_phase_post_s1"
const F_PHASE_POST_S2: String = "marko_study_phase_post_s2"

@onready var choice_panel_scene: PackedScene = preload("res://Scenes/Reusable/CharacterChoiceButtons.tscn")
var _panel: Control = null

func _ready() -> void:
	GameState.location = "MarkoStudy"
	_clear_panel()

	# Always set a return path so STUDY → DONE comes back here
	var ret_path: String = ""
	if get_tree() and get_tree().current_scene:
		ret_path = String(get_tree().current_scene.get_scene_file_path())
	if ret_path.strip_edges() == "":
		ret_path = RETURN_SCENE_FALLBACK
	GameState.features_unlocked[KEY_RETURN_SCENE] = ret_path

	# Decide which part of the flow to show
	if GameState.has_flag(F_PHASE_POST_S2):
		GameState.clear_flag(F_PHASE_POST_S2)
		# End wrap-up after Subject 2 (or skipping it)
		DialogueManager.start_dialogue("res://Data/Marko/Study/25_StudyWithMarko_End.json", self)
		return

	if GameState.has_flag(F_PHASE_POST_S1):
		GameState.clear_flag(F_PHASE_POST_S1)
		# Back from Subject 1 → ask if we do Subject 2
		DialogueManager.start_dialogue("res://Data/Marko/Study/21_StudyWithMarko_Subject2.json", self)
		return

	# Initial prompt (Subject 1)
	DialogueManager.start_dialogue("res://Data/Marko/Study/20_StudyWithMarko_Start.json", self)

func on_dialogue_action(line: Dictionary) -> void:
	var act: String = String(line.get("action", ""))

	if act == "marko_study_show_choices":
		_show_choice_s1()
		return
	if act == "marko_study_show_choices_s2":
		_show_choice_s2()
		return

	# Pass other actions through to GameState (set_flags, adjust_rep, etc.)
	GameState.apply_action(line)

# ---------- Choice: Subject 1 ----------
func _show_choice_s1() -> void:
	_clear_panel()
	var s1_label: String = GameState.subject1
	if s1_label.strip_edges() == "":
		s1_label = "[Subject 1]"

	var opts: Array = [
		{"id":"do_s1","text":"Study " + s1_label + " now"},
		{"id":"end","text":"We’re done for today"}
	]
	_panel = choice_panel_scene.instantiate()
	add_child(_panel)
	_panel.call("show_options", opts, Callable(self, "_on_choice_s1"))

func _on_choice_s1(id: String) -> void:
	_clear_panel()
	if id == "do_s1":
		# Prep: Marko mode, subject1, finals-only for TODAY
		GameState.features_unlocked[KEY_STUDY_MODE] = "marko"
		GameState.features_unlocked[KEY_SUBJECT_PICK] = "subject1"
		GameState.features_unlocked["__study_session_index"] = 0  # clear Home session override
		GameState.mark_today_finals_revealed(GameState.subject1)

		# After STUDY → Done, come back here and show Subject 2 prompt
		GameState.set_flag(F_PHASE_POST_S1, true)
		DialogueManager.end_active_dialogue()
		get_tree().change_scene_to_file(STUDY_SCENE_PATH)
		return

	if id == "end":
		DialogueManager.end_active_dialogue()
		DialogueManager.start_dialogue("res://Data/Marko/Study/25_StudyWithMarko_End.json", self)
		return

# ---------- Choice: Subject 2 ----------
func _show_choice_s2() -> void:
	_clear_panel()
	var s2_label: String = GameState.subject2
	if s2_label.strip_edges() == "":
		s2_label = "[Subject 2]"

	var opts: Array = [
		{"id":"do_s2","text":"Study " + s2_label + " now"},
		{"id":"end","text":"We’re done"}
	]
	_panel = choice_panel_scene.instantiate()
	add_child(_panel)
	_panel.call("show_options", opts, Callable(self, "_on_choice_s2"))

func _on_choice_s2(id: String) -> void:
	_clear_panel()
	if id == "do_s2":
		GameState.features_unlocked[KEY_STUDY_MODE] = "marko"
		GameState.features_unlocked[KEY_SUBJECT_PICK] = "subject2"
		GameState.features_unlocked["__study_session_index"] = 0
		GameState.mark_today_finals_revealed(GameState.subject2)

		GameState.set_flag(F_PHASE_POST_S2, true)
		DialogueManager.end_active_dialogue()
		get_tree().change_scene_to_file(STUDY_SCENE_PATH)
		return

	if id == "end":
		DialogueManager.end_active_dialogue()
		DialogueManager.start_dialogue("res://Data/Marko/Study/25_StudyWithMarko_End.json", self)
		return

# ---------- Utils ----------
func _clear_panel() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null
