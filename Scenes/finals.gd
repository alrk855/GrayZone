extends Control

# ---------- Scene paths ----------
@export var quiz_scene_path: String = "res://Scenes/reusable/Quiz.tscn"
const SCHOOL_SCENE_PATH := "res://Scenes/Reusable/Map/School.tscn"

# ---------- Finals JSONs (relative IDs; resolved via GameState.get_data_path) ----------
const J_PRINCIPAL_INTRO := "School/Finals/Finals_Principal_Intro.json"
const J_BREAK           := "School/Finals/Finals_Break.json"
const J_END             := "School/Finals/Finals_End.json"

# ---------- Flags ----------
const FLAG_FINALS_DONE := "finals_done"
const F_BOUGHT_S1 := "bought_answers_s1"
const F_BOUGHT_S2 := "bought_answers_s2"

# ---------- State ----------
var _running := false
var _active_quiz: Node = null

func _ready() -> void:
	GameState.location = "Finals"

	# Make GameUi visible if it exists (safe check)
	var ui := get_node_or_null("/root/GameUi")
	if ui and ui is CanvasItem:
		(ui as CanvasItem).visible = true

	# Defaults if subjects somehow empty
	if GameState.subject1.strip_edges() == "":
		GameState.subject1 = "math"
	if GameState.subject2.strip_edges() == "":
		GameState.subject2 = "geography"

	# Re-entry protection
	if GameState.has_flag(FLAG_FINALS_DONE):
		_redirect_to_school()
		return

	if not _running:
		_running = true
		call_deferred("_run_finals")

# ============ Flow ============
func _run_finals() -> void:
	# 08:00 start (never go backwards)
	_bump_time_to(8 * 60)

	# 1) Principal intro
	await _play_json(J_PRINCIPAL_INTRO)

	# 2) Quiz #1 (subject1)
	var s1_raw := String(GameState.subject1)
	if s1_raw.strip_edges() != "":
		var s1_key := GameState._get_subject_key_from_choice(s1_raw)
		if s1_key.strip_edges() != "":
			await _run_quiz_for_subject(s1_key, 1)

	# Move to 10:00 after first exam
	_bump_time_to(10 * 60)

	# 3) Break JSON
	await _play_json(J_BREAK)

	# 4) Quiz #2 (subject2)
	var s2_raw := String(GameState.subject2)
	if s2_raw.strip_edges() != "":
		var s2_key := GameState._get_subject_key_from_choice(s2_raw)
		if s2_key.strip_edges() != "":
			await _run_quiz_for_subject(s2_key, 2)

	# Move to 12:00 after second exam
	_bump_time_to(12 * 60)

	# 5) Finals wrap-up
	await _play_json(J_END)

	# Done → flag + go to School
	GameState.set_flag(FLAG_FINALS_DONE, true)
	_redirect_to_school()

# ============ Helpers ============
func _bump_time_to(target_min_of_day: int) -> void:
	var delta := target_min_of_day - GameState.time
	if delta > 0:
		GameState.adjust_time(delta)

func _redirect_to_school() -> void:
	_clear_active_quiz()
	if ResourceLoader.exists(SCHOOL_SCENE_PATH):
		await fade.fade_to_scene(SCHOOL_SCENE_PATH)
	else:
		push_warning("Finals.gd: School scene not found at " + SCHOOL_SCENE_PATH)

# -------- JSON runner (locale-aware) --------
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

# -------- Determine mode from flags for S1/S2 --------
func _resolve_mode_for_subject(slot_index: int) -> String:
	# slot_index: 1 for subject1, 2 for subject2
	if slot_index == 1 and GameState.has_flag(F_BOUGHT_S1):
		return "bought"
	if slot_index == 2 and GameState.has_flag(F_BOUGHT_S2):
		return "bought"
	return "legit"

# -------- Run one quiz (Quiz pushes score itself) --------
func _run_quiz_for_subject(subject_key: String, slot_index: int) -> bool:
	_clear_active_quiz()

	if not ResourceLoader.exists(quiz_scene_path):
		push_error("Finals.gd: Quiz scene not found at " + quiz_scene_path)
		return false

	var ps := load(quiz_scene_path) as PackedScene
	if ps == null:
		push_error("Finals.gd: Failed to load PackedScene: " + quiz_scene_path)
		return false

	var quiz := ps.instantiate()

	# Set properties BEFORE adding to tree so _ready() picks them up (overrides Inspector).
	var resolved_mode := _resolve_mode_for_subject(slot_index)
	quiz.subject = subject_key
	quiz.mode = resolved_mode
	if "auto_return_to_finals" in quiz:
		quiz.auto_return_to_finals = false  # we are embedding it

	_active_quiz = quiz
	add_child(quiz)

	# Wait for the emitted completion (preferred)
	var finished := false
	if quiz.has_signal("quiz_finished"):
		quiz.quiz_finished.connect(func(_total: int, _correct: int, _score: int) -> void:
			finished = true
		)
		while not finished and is_instance_valid(quiz):
			await get_tree().process_frame
	else:
		# Fallback: give it a moment to run if the signal isn't present
		var frames := 0
		while frames < 3 and is_instance_valid(quiz):
			await get_tree().process_frame
			frames += 1

	_clear_active_quiz()
	return true

func _clear_active_quiz() -> void:
	if _active_quiz and is_instance_valid(_active_quiz):
		_active_quiz.queue_free()
	_active_quiz = null
