# res://Scripts/Scenes/MarkoStudy.gd
extends Control

# --- Scenes ---
const STUDY_SCENE_PATH: String       = "res://Scenes/Reusable/Tasks/Study.tscn"
const RETURN_SCENE_FALLBACK: String  = "res://Scenes/Reusable/Events/MarkoFirstEvent.tscn"
const HOME_SCENE_PATH: String        = "res://Scenes/Reusable/Map/Home.tscn"

# --- JSONs (RELATIVE IDs under Data/, resolved via GameState.get_data_path) ---
# Example resolved path (EN): res://Data/Marko/StudyWithMarko_Start.json
# Example resolved path (MK): res://DataMK/Marko/StudyWithMarko_Start.json
const JSON_S1_START_ID: String = "Marko/StudyWithMarko_Start.json"
const JSON_CONTINUE_ID: String = "Marko/Marko_Study_Continue.json"
const JSON_S2_START_ID: String = "Marko/Study_Subject2.json"
const JSON_END_ID: String      = "Marko/StudyWithMarko_End.json"

# --- Feature flags for Study scene ---
const KEY_STUDY_MODE: String     = "__study_mode"          # "marko"
const KEY_SUBJECT_PICK: String   = "__study_subject_pick"  # "subject1"/"subject2"
const KEY_RETURN_SCENE: String   = "__study_return_scene"  # MarkoStudy scene path
const KEY_SESSION_INDEX: String  = "__study_session_index" # 0 = today's set

# --- Phase flags (persist across scene swaps) ---
const F_PHASE_POST_S1: String = "marko_study_phase_post_s1"
const F_PHASE_POST_S2: String = "marko_study_phase_post_s2"

# --- Local phase labels for dialogue_finished routing ---
const P_S1_START: String   = "S1_START"
const P_S2_PROMPT: String  = "S2_PROMPT"
const P_S2_START: String   = "S2_START"
const P_END: String        = "END"

# --- BG (Inspector) ---
@export var bg_rect_path: NodePath
@export var bg_male: Texture2D
@export var bg_female: Texture2D

@onready var choice_panel_scene: PackedScene = preload("res://Scenes/Reusable/CharacterChoiceButtons.tscn")
var _panel: Control = null
var _current_phase: String = ""

func _ready() -> void:
	GameState.location = "MarkoStudy"
	_apply_bg_by_gender()
	_clear_panel()

	# Ensure Study.tscn returns HERE when Done
	var ret_path: String = ""
	if get_tree() and get_tree().current_scene:
		ret_path = String(get_tree().current_scene.get_scene_file_path())
	if ret_path.strip_edges() == "":
		ret_path = RETURN_SCENE_FALLBACK
	GameState.features_unlocked[KEY_RETURN_SCENE] = ret_path

	# Decide which JSON to start based on persisted phase flags
	if GameState.has_flag(F_PHASE_POST_S2):
		GameState.clear_flag(F_PHASE_POST_S2)
		_start_dialogue(JSON_END_ID, P_END)
		return

	if GameState.has_flag(F_PHASE_POST_S1):
		GameState.clear_flag(F_PHASE_POST_S1)
		_start_dialogue(JSON_CONTINUE_ID, P_S2_PROMPT)
		return

	# First entry: Subject 1 intro → auto Study after the JSON ends
	_start_dialogue(JSON_S1_START_ID, P_S1_START)

func on_dialogue_action(line: Dictionary) -> void:
	var act: String = String(line.get("action", ""))

	# Only the CONTINUE JSON should emit this to show Yes/No for S2
	if act == "marko_study_show_choices_s2":
		_show_choice_s2()
		return

	# All other standard actions (set_flags, adjust_rep, etc.)
	GameState.apply_action(line)

# ---------------------- Dialogue helpers ----------------------
func _start_dialogue(json_id: String, phase: String) -> void:
	_current_phase = phase
	var path := _dp(json_id)
	if path == "" or not FileAccess.file_exists(path):
		push_warning("MarkoStudy: missing dialogue JSON → " + json_id + " (resolved: " + path + ")")
		return
	var ui := DialogueManager.start_dialogue(path, self)
	if ui and ui.has_signal("dialogue_finished"):
		if not ui.is_connected("dialogue_finished", Callable(self, "_on_dialogue_finished")):
			ui.connect("dialogue_finished", Callable(self, "_on_dialogue_finished"))

func _on_dialogue_finished() -> void:
	# Route next step based on which JSON just finished
	if _current_phase == P_S1_START:
		GameState.features_unlocked[KEY_STUDY_MODE] = "marko"
		GameState.features_unlocked[KEY_SUBJECT_PICK] = "subject1"
		GameState.features_unlocked[KEY_SESSION_INDEX] = 0
		if GameState.has_method("mark_today_finals_revealed"):
			GameState.mark_today_finals_revealed(GameState.subject1)
		GameState.set_flag(F_PHASE_POST_S1, true)
		await _go_to(STUDY_SCENE_PATH)
		return

	if _current_phase == P_S2_PROMPT:
		return

	if _current_phase == P_S2_START:
		GameState.features_unlocked[KEY_STUDY_MODE] = "marko"
		GameState.features_unlocked[KEY_SUBJECT_PICK] = "subject2"
		GameState.features_unlocked[KEY_SESSION_INDEX] = 0
		if GameState.has_method("mark_today_finals_revealed"):
			GameState.mark_today_finals_revealed(GameState.subject2)
		GameState.set_flag(F_PHASE_POST_S2, true)
		await _go_to(STUDY_SCENE_PATH)
		return

	if _current_phase == P_END:
		await _go_to(HOME_SCENE_PATH)
		return

# ---------------------- S2 Choice panel ----------------------
func _show_choice_s2() -> void:
	# Close dialogue UI so the panel is cleanly visible
	DialogueManager.end_active_dialogue()

	_clear_panel()
	var s2_label: String = GameState.subject2
	if s2_label.strip_edges() == "":
		s2_label = tr("[Subject 2]")

	var opts: Array = [
		{"id":"do_s2","text": tr("Study %s now") % s2_label},
		{"id":"end","text": tr("We’re done")}
	]
	_panel = choice_panel_scene.instantiate()
	add_child(_panel)
	_panel.call("show_options", opts, Callable(self, "_on_choice_s2"))

func _on_choice_s2(id: String) -> void:
	_clear_panel()

	if id == "do_s2":
		_start_dialogue(JSON_S2_START_ID, P_S2_START)
		return

	if id == "end":
		_start_dialogue(JSON_END_ID, P_END)
		return

# ---------------------- BG + Utils ----------------------
func _apply_bg_by_gender() -> void:
	if bg_rect_path == NodePath():
		return
	var node := get_node_or_null(bg_rect_path)
	if node == null or not (node is TextureRect):
		push_error("MarkoStudy: bg_rect_path is invalid or not a TextureRect.")
		return
	var rect := node as TextureRect
	var g := String(GameState.player_gender).to_lower()
	rect.texture = bg_female if g == "female" else bg_male

func _clear_panel() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null

func _go_to(path: String) -> void:
	# Global fade only (no fallback)
	await fade.fade_to_scene(path)

# ---- Golden data-path resolver (RELATIVE → ABSOLUTE, locale-aware) ----
# Uses your provided GameState.get_data_path(relative) implementation.
func _dp(relative: String) -> String:
	var rel := String(relative).strip_edges().trim_prefix("/")
	if GameState.has_method("get_data_path"):
		return String(GameState.get_data_path(rel))
	# Fallback if helper is missing:
	return "res://Data/" + rel
