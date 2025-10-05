extends Control

# ---------- Scene paths ----------
@export var quiz_scene_path: String = "res://Scenes/reusable/Quiz.tscn"   # set in Inspector if different
const SCHOOL_SCENE_PATH := "res://Scenes/Reusable/Map/School.tscn"

# If your Finals scene lives elsewhere, point Quiz’s finals_scene_path to this.
@export var finals_scene_path: String = "res://Scenes/Reusable/Events/Finals.tscn"

# ---------- Finals JSONs (relative IDs; resolved via GameState.get_data_path) ----------
const J_PRINCIPAL_INTRO := "School/Finals/Finals_Principal_Intro.json"
const J_BREAK           := "School/Finals/Finals_Break.json"
const J_END             := "School/Finals/Finals_End.json"

# ---------- Keys / Flags ----------
const K_FINALS_COUNTER := "__finals_counter"   # 0 -> 1 -> 2
const FLAG_FINALS_DONE := "finals_done"

func _ready() -> void:
	GameUi.visible = true
	GameState.location = "Finals"
	if GameState.subject1.strip_edges() == "":
		GameState.subject1 = "math"
	if GameState.subject2.strip_edges() == "":
		GameState.subject2 = "geography"
	# If finals already completed, never replay. Bounce to School.
	if GameState.has_flag(FLAG_FINALS_DONE):
		await _goto_school()
		return

	# Read once; branch by counter only. Quiz will come back here after finishing.
	var cnt := GameState.get_int(K_FINALS_COUNTER, 0)

	if cnt <= 0:
		# 08:00 + Principal + Quiz #1 (Subject 1)
		_bump_time_to(8 * 60)
		await _play_json(J_PRINCIPAL_INTRO)
		await _goto_quiz()
		return

	if cnt == 1:
		# 10:00 + Break + Quiz #2 (Subject 2)
		_bump_time_to(10 * 60)
		await _play_json(J_BREAK)
		await _goto_quiz()
		return

	# cnt >= 2
	# 12:00 + End + mark finals done + go to School
	_bump_time_to(12 * 60)
	await _play_json(J_END)
	GameState.set_flag(FLAG_FINALS_DONE, true)
	# optional: reset counter to avoid any stray replays if someone forces this scene
	GameState.set_int(K_FINALS_COUNTER, 0)
	await _goto_school()
	return

# ---------- Helpers ----------
func _goto_quiz() -> void:
	if quiz_scene_path == "" or not ResourceLoader.exists(quiz_scene_path):
		push_error("Finals.gd: Quiz scene not found at: " + quiz_scene_path)
		return
	await fade.fade_to_scene(quiz_scene_path)

func _goto_school() -> void:
	# --- Finals → ensure Transcript task reflects exam phase done ---
	GameState.ensure_task("transcript")
	var cur := GameState.get_task_progress("transcript")
	if cur <= 0:
		# Jump straight to 2/3 if the player never asked before Day 5
		GameState.task_step_index["transcript"] = 2
	elif cur == 1:
		# 1/3 → 2/3
		GameState.update_task_step("transcript")

	if not ResourceLoader.exists(SCHOOL_SCENE_PATH):
		push_error("Finals.gd: School scene not found at: " + SCHOOL_SCENE_PATH)
		return
	await fade.fade_to_scene(SCHOOL_SCENE_PATH)

func _bump_time_to(target_min_of_day: int) -> void:
	var delta := target_min_of_day - GameState.time
	if delta > 0:
		GameState.adjust_time(delta)

func _play_json(relative_id: String) -> void:
	var dm := get_node_or_null("/root/DialogueManager")
	if dm == null or not dm.has_method("start_dialogue"):
		push_warning("Finals.gd: DialogueManager missing; skipping " + relative_id)
		await get_tree().process_frame
		return

	var path := relative_id
	if GameState.has_method("get_data_path"):
		path = GameState.get_data_path(relative_id)

	if not FileAccess.file_exists(path):
		push_warning("Finals.gd: JSON not found: " + path)
		await get_tree().process_frame
		return

	var ui: Control = dm.start_dialogue(path, self)
	if ui and ui.has_signal("dialogue_finished"):
		await ui.dialogue_finished
	elif dm.has_signal("dialogue_finished"):
		await dm.dialogue_finished
	else:
		await get_tree().process_frame
