extends Control

# ---- JSON paths ----
const JSON_ENTRY: String        = "res://Data/Marko/FirstEvent/00_Entry.json"
const JSON_STUDY_SWAY: String   = "res://Data/Marko/FirstEvent/01_Study_Sway.json"
const JSON_GOTO_STUDY: String   = "res://Data/Marko/FirstEvent/02_Goto_StudyScene.json"
const JSON_ALONE_PUSH: String   = "res://Data/Marko/FirstEvent/10_StudyAlone_Push.json"
const JSON_SOLO_END: String     = "res://Data/Marko/FirstEvent/11_Solo_Study_End.json"
const JSON_HANGOUT_END: String  = "res://Data/Marko/FirstEvent/12_Hangout_End.json"

const FALLBACK_HOME: String     = "res://Scenes/Reusable/Map/Home.tscn"

# ---- Hangout scene (lightweight time-waster) ----
const HANGOUT_SCENE: String     = "res://Scenes/Reusable/Events/MarkoHangout.tscn"

# keys shared with Study/MarkoStudy
const KEY_STUDY_MODE: String    = "__study_mode"
const KEY_SUBJECT_PICK: String  = "__study_subject_pick"
const KEY_RETURN_SCENE: String  = "__study_return_scene"

# task we add after hangout (done in code, not JSON)
const TASK_VISIT_PROF: String   = "visit_professor_office"

# comeback flag set by the Hangout scene so we know to play the end JSON
const F_BACK_FROM_HANGOUT: String = "marko_first_event_hangout_done"

@onready var choice_panel_scene: PackedScene = preload("res://Scenes/Reusable/CharacterChoiceButtons.tscn")

var _panel: Control = null
var _transitioning: bool = false

func _ready() -> void:
	GameState.location = "MarkoFirstEvent"
	_clear_panel()

	# Make sure we always have a valid return path stored (used by Hangout scene)
	var ret_path: String = ""
	if get_tree() and get_tree().current_scene:
		ret_path = String(get_tree().current_scene.get_scene_file_path())
	if ret_path.strip_edges() == "":
		ret_path = FALLBACK_HOME
	GameState.features_unlocked[KEY_RETURN_SCENE] = ret_path

	# If we just returned from the Hangout scene, play the end JSON and then go Home
	if GameState.has_flag(F_BACK_FROM_HANGOUT):
		GameState.clear_flag(F_BACK_FROM_HANGOUT)
		_start_json(JSON_HANGOUT_END, "_on_hangout_json_finished")
		return

	# Otherwise start the normal entry flow
	_start_json(JSON_ENTRY, "")

# ---------- helpers ----------
func _clear_panel() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null

func _safe_end_dialogue() -> void:
	if _transitioning:
		return
	DialogueManager.end_active_dialogue()

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

func _start_json(path: String, finish_cb: String) -> void:
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
			_start_json(JSON_STUDY_SWAY, "")
		"study_alone":
			_clear_panel()
			_safe_end_dialogue()
			_start_json(JSON_ALONE_PUSH, "")
		"hangout":
			_clear_panel()
			_safe_end_dialogue()
			# Round-trip via Hangout scene:
			# - store return path (already set), set a comeback flag, jump to Hangout scene
			GameState.set_flag(F_BACK_FROM_HANGOUT, true)
			_safe_change_scene(HANGOUT_SCENE)

func _show_study_sway_choices() -> void:
	_clear_panel()
	var options: Array = [
		{ "text": "No, seriously. Let’s study.",    "id": "study_now" },
		{ "text": "Alright, let’s hang out a bit.", "id": "hangout_now" }
	]
	_panel = choice_panel_scene.instantiate()
	add_child(_panel)
	_panel.call("show_options", options, Callable(self, "_on_study_sway_choice"))

func _on_study_sway_choice(id: String) -> void:
	match id:
		"study_now":
			# Prepare Marko study (Subject 1) with a valid return path
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
			# Your JSON can still perform the 'goto' to StudyWithMarko.tscn
			_start_json(JSON_STUDY_SWAY, "")
			# or use the dedicated one:
			# _start_json(JSON_GOTO_STUDY, "")
		"hangout_now":
			_clear_panel()
			_safe_end_dialogue()
			# Same round-trip logic for hangout from the sway branch
			GameState.set_flag(F_BACK_FROM_HANGOUT, true)
			_safe_change_scene(HANGOUT_SCENE)

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
			_start_json(JSON_SOLO_END, "_on_solo_end_finished")
		"hangout_now":
			_clear_panel()
			_safe_end_dialogue()
			GameState.set_flag(F_BACK_FROM_HANGOUT, true)
			_safe_change_scene(HANGOUT_SCENE)

# ---- JSON finish handlers ----
func _on_hangout_json_finished() -> void:
	# Add the task after the hangout-end dialogue, then go Home.
	GameState.ensure_task(TASK_VISIT_PROF)
	_safe_change_scene(FALLBACK_HOME)

func _on_solo_end_finished() -> void:
	_safe_change_scene(FALLBACK_HOME)
