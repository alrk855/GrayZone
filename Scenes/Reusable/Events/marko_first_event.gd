extends Control

# ---------- JSON IDs (relative under Data/) ----------
const JSON_ENTRY_ID:       String = "Marko/FirstEvent/00_Entry.json"
const JSON_STUDY_SWAY_ID:  String = "Marko/FirstEvent/01_Study_Sway.json"
const JSON_GOTO_STUDY_ID:  String = "Marko/FirstEvent/02_Goto_StudyScene.json"
const JSON_ALONE_PUSH_ID:  String = "Marko/FirstEvent/10_StudyAlone_Push.json"
const JSON_SOLO_END_ID:    String = "Marko/FirstEvent/11_Solo_Study_End.json"
const JSON_HANGOUT_END_ID: String = "Marko/FirstEvent/12_Hangout_End.json"

const FALLBACK_HOME: String = "res://Scenes/Reusable/Map/Home.tscn"
const HANGOUT_SCENE: String = "res://Scenes/Reusable/Tasks/Hangout.tscn"

# keys shared with Study/MarkoStudy
const KEY_STUDY_MODE: String      = "__study_mode"
const KEY_SUBJECT_PICK: String    = "__study_subject_pick"
const KEY_RETURN_SCENE: String    = "__study_return_scene"
const KEY_HANGOUT_CONTEXT: String = "__hangout_context" # "event" | ""

# task we add after hangout
const TASK_VISIT_PROF: String = "visit_professor_office"
const F_BACK_FROM_HANGOUT: String = "marko_first_event_hangout_done"

@onready var choice_panel_scene: PackedScene = preload("res://Scenes/Reusable/CharacterChoiceButtons.tscn")

var _panel: Control = null
var _transitioning: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.location = "MarkoFirstEvent"
	_clear_panel()

	# Return path for hangout/study round-trips
	var ret_path: String = ""
	if get_tree() and get_tree().current_scene:
		ret_path = String(get_tree().current_scene.get_scene_file_path())
	if ret_path.strip_edges() == "":
		ret_path = FALLBACK_HOME
	GameState.features_unlocked[KEY_RETURN_SCENE] = ret_path

	# Handle comeback from hangout
	if GameState.has_flag(F_BACK_FROM_HANGOUT):
		GameState.clear_flag(F_BACK_FROM_HANGOUT)
		_start_json(JSON_HANGOUT_END_ID, "_on_hangout_json_finished")
		return

	# Otherwise, normal entry
	_start_json(JSON_ENTRY_ID, "")

# ---------- helpers ----------
func _clear_panel() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null

func _safe_end_dialogue() -> void:
	if _transitioning:
		return
	if Engine.has_singleton("DialogueManager"):
		DialogueManager.end_active_dialogue()

func _safe_change_scene(path: String) -> void:
	if _transitioning:
		return
	_transitioning = true
	var tree := get_tree()
	if tree.paused:
		tree.paused = false
	call_deferred("_do_change_scene", path)

func _do_change_scene(path: String) -> void:
	if path != "" and ResourceLoader.exists(path):
		get_tree().change_scene_to_file(path)
	else:
		push_warning("MarkoFirstEvent: invalid scene path: " + path)
	_transitioning = false

func _start_json(json_id: String, finish_cb: String) -> void:
	var path := _dp(json_id)
	if path == "" or not FileAccess.file_exists(path):
		push_warning("MarkoFirstEvent: missing JSON → " + json_id + " (resolved: " + path + ")")
		return
	var ui: Control = DialogueManager.start_dialogue(path, self)
	if ui and finish_cb != "":
		if ui.has_signal("dialogue_finished"):
			var cb := Callable(self, finish_cb)
			if not ui.is_connected("dialogue_finished", cb):
				ui.connect("dialogue_finished", cb)

# ---- DialogueManager action hook ----
func on_dialogue_action(line: Dictionary) -> void:
	var act: String = String(line.get("action", ""))

	match act:
		"marko_show_entry_choices":
			_show_entry_choices()
		"marko_show_study_sway_choices":
			_show_study_sway_choices()
		"marko_show_alone_push_choices":
			_show_alone_push_choices()
		"goto":
			var scene_path: String = String(line.get("scene", ""))
			if scene_path != "":
				_safe_end_dialogue()
				_safe_change_scene(scene_path)
		"end_event":
			_safe_end_dialogue()
			_safe_change_scene(FALLBACK_HOME)
		_:
			GameState.apply_action(line)

# ---- Choice panels ----
func _show_entry_choices() -> void:
	_clear_panel()
	var options: Array = [
		{ "text": tr("Let’s study together."), "id": "study_together" },
		{ "text": tr("I’m studying alone."),   "id": "study_alone" },
		{ "text": tr("We can hang out."),      "id": "hangout" }
	]
	_panel = choice_panel_scene.instantiate()
	add_child(_panel)
	_panel.call("show_options", options, Callable(self, "_on_entry_choice"))

func _on_entry_choice(id: String) -> void:
	match id:
		"study_together":
			_clear_panel()
			_safe_end_dialogue()
			_start_json(JSON_STUDY_SWAY_ID, "")
		"study_alone":
			_clear_panel()
			_safe_end_dialogue()
			_start_json(JSON_ALONE_PUSH_ID, "")
		"hangout":
			_clear_panel()
			_safe_end_dialogue()
			GameState.set_flag(F_BACK_FROM_HANGOUT, true)
			GameState.features_unlocked[KEY_HANGOUT_CONTEXT] = "event"
			GameState.features_unlocked["__hangout_return_scene"] = FALLBACK_HOME
			_safe_change_scene(HANGOUT_SCENE)

func _show_study_sway_choices() -> void:
	_clear_panel()
	var options: Array = [
		{ "text": tr("No, seriously. Let’s study."),    "id": "study_now" },
		{ "text": tr("Alright, let’s hang out a bit."), "id": "hangout_now" }
	]
	_panel = choice_panel_scene.instantiate()
	add_child(_panel)
	_panel.call("show_options", options, Callable(self, "_on_study_sway_choice"))

func _on_study_sway_choice(id: String) -> void:
	match id:
		"study_now":
			GameState.features_unlocked[KEY_STUDY_MODE] = "marko"
			GameState.features_unlocked[KEY_SUBJECT_PICK] = "subject1"

			var ret: String = ""
			if get_tree() and get_tree().current_scene:
				ret = String(get_tree().current_scene.get_scene_file_path())
			if ret == "":
				ret = FALLBACK_HOME
			GameState.features_unlocked[KEY_RETURN_SCENE] = ret

			_clear_panel()
			_safe_end_dialogue()
			_start_json(JSON_GOTO_STUDY_ID, "")
		"hangout_now":
			_clear_panel()
			_safe_end_dialogue()
			GameState.adjust_integrity(-10)
			GameState.set_flag(F_BACK_FROM_HANGOUT, true)
			GameState.features_unlocked[KEY_HANGOUT_CONTEXT] = "event"
			GameState.features_unlocked["__hangout_return_scene"] = FALLBACK_HOME
			_safe_change_scene(HANGOUT_SCENE)

func _show_alone_push_choices() -> void:
	_clear_panel()
	var options: Array = [
		{ "text": tr("No. I’ll study on my own."), "id": "solo_study" },
		{ "text": tr("Fine, we can hang out."),    "id": "hangout_now" }
	]
	_panel = choice_panel_scene.instantiate()
	add_child(_panel)
	_panel.call("show_options", options, Callable(self, "_on_alone_push_choice"))

func _on_alone_push_choice(id: String) -> void:
	match id:
		"solo_study":
			_clear_panel()
			_safe_end_dialogue()
			_start_json(JSON_SOLO_END_ID, "_on_solo_end_finished")
		"hangout_now":
			_clear_panel()
			_safe_end_dialogue()
			GameState.adjust_integrity(-10)
			GameState.set_flag(F_BACK_FROM_HANGOUT, true)
			GameState.features_unlocked[KEY_HANGOUT_CONTEXT] = "event"
			GameState.features_unlocked["__hangout_return_scene"] = FALLBACK_HOME
			_safe_change_scene(HANGOUT_SCENE)

# ---- JSON finish handlers ----
func _on_hangout_json_finished() -> void:
	GameState.ensure_task(TASK_VISIT_PROF)
	_safe_change_scene(FALLBACK_HOME)

func _on_solo_end_finished() -> void:
	_safe_change_scene(FALLBACK_HOME)

# ---- Golden data-path resolver ----
func _dp(relative: String) -> String:
	var rel := String(relative).strip_edges().trim_prefix("/")
	if GameState.has_method("get_data_path"):
		return String(GameState.get_data_path(rel))
	return "res://Data/" + rel
