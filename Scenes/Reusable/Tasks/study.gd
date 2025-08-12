extends Control

# ---------------- MANUAL PATHS ----------------
# Use NodePath literals (Godot 4): ^"Path/To/Node"
# Container with 10 Labels: Question1..5 and Answer1..5
const LABELS_CONTAINER_PATH: NodePath = ^"TextureRect/VBoxContainer"   # <-- set me
# The “Done” button
const DONE_BUTTON_PATH: NodePath      = ^"TextureRect/Done"             # <-- set me
# Where to go if no explicit return target was set (regular study fallback)
const HOME_SCENE_PATH: String         = "res://Scenes/Reusable/Map/Home.tscn"   # <-- adjust if needed

# Optional custom font (leave "" to skip)
const CUSTOM_FONT_PATH: String = "res://Fonts/BellavoirSerif_PERSONAL_USE_ONLY.otf"
const FONT_SIZE: int = 45

# ---------------- KEYS (short-lived flags in GameState.features_unlocked) ----------------
const KEY_STUDY_MODE: String    = "__study_mode"         # "regular" | "marko"
const KEY_SUBJECT_PICK: String  = "__study_subject_pick" # "subject1" | "subject2"
const KEY_RETURN_SCENE: String  = "__study_return_scene" # scene path to return to on Done

# Regular study bookkeeping
const REGULAR_STUDY_TIME_MIN: int = 30
const UPDATE_TASK_FOR_REGULAR: bool = true
const APPLY_TIME_FOR_REGULAR: bool  = true

func _ready() -> void:
	GameState.location = "Study"

	var container: Node = get_node_or_null(LABELS_CONTAINER_PATH)
	if container == null:
		push_error("StudyShell: LABELS_CONTAINER_PATH not found: " + str(LABELS_CONTAINER_PATH))
		return

	var done_btn: Button = get_node_or_null(DONE_BUTTON_PATH) as Button
	if done_btn:
		if not done_btn.pressed.is_connected(Callable(self, "_on_done_pressed")):
			done_btn.pressed.connect(_on_done_pressed)
	else:
		push_warning("StudyShell: DONE_BUTTON_PATH not found (" + str(DONE_BUTTON_PATH) + "); no way to exit via button.")

	# Build label arrays: Question1..5 / Answer1..5
	var q_labels: Array[Label] = []
	var a_labels: Array[Label] = []
	for i in range(1, 6):
		var q_name: String = "Question%d" % i
		var a_name: String = "Answer%d"   % i
		var ql: Label = container.get_node_or_null(q_name) as Label
		var al: Label = container.get_node_or_null(a_name) as Label
		if ql: q_labels.append(ql)
		if al: a_labels.append(al)

	if q_labels.size() != 5 or a_labels.size() != 5:
		push_error("StudyShell: Need exactly 5 Question* and 5 Answer* Labels.")
		return

	# Styling
	var custom_font: Font = null
	if CUSTOM_FONT_PATH != "" and ResourceLoader.exists(CUSTOM_FONT_PATH):
		custom_font = load(CUSTOM_FONT_PATH)
	for i in range(5):
		var ql: Label = q_labels[i]
		var al: Label = a_labels[i]
		if custom_font:
			ql.add_theme_font_override("font", custom_font)
			al.add_theme_font_override("font", custom_font)
		ql.add_theme_font_size_override("font_size", FONT_SIZE)
		al.add_theme_font_size_override("font_size", FONT_SIZE)
		ql.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ql.visible = false
		al.visible = false
		ql.text = ""
		al.text = ""

	# Mode + subject
	var mode: String = String(GameState.features_unlocked.get(KEY_STUDY_MODE, "regular")).to_lower()
	var pick: String = String(GameState.features_unlocked.get(KEY_SUBJECT_PICK, "subject1")).to_lower()
	if GameState.features_unlocked.has(KEY_STUDY_MODE):
		GameState.features_unlocked.erase(KEY_STUDY_MODE)
	if GameState.features_unlocked.has(KEY_SUBJECT_PICK):
		GameState.features_unlocked.erase(KEY_SUBJECT_PICK)

	var subject_raw: String = ""
	if pick == "subject2":
		subject_raw = GameState.subject2
	else:
		subject_raw = GameState.subject1
	if subject_raw.strip_edges() == "":
		subject_raw = GameState.subject1

	# Finals for “today” (pair by day: (0,1),(2,3),(4,5),(6,7),(8,9))
	var pair: Array[Dictionary] = _get_finals_pair_for_today(subject_raw)
	if pair.size() < 2:
		pair = _fallback_two_finals(subject_raw)

	if mode == "marko":
		# Fill ONLY Q2/A2 and Q4/A4
		_fill_slot(q_labels[1], a_labels[1], pair[0])  # index 1 → Q2/A2
		_fill_slot(q_labels[3], a_labels[3], pair[1])  # index 3 → Q4/A4
		return

	# REGULAR: 2 finals + 3 fillers, fill Q1..Q5 sequentially
	var fillers: Array[Dictionary] = _pick_fillers(subject_raw, 3, pair)
	var batch: Array[Dictionary] = []
	batch.append(pair[0])
	batch.append(pair[1])
	for f in fillers:
		batch.append(f)

	for i in range(min(5, batch.size())):
		_fill_slot(q_labels[i], a_labels[i], batch[i])

	# Bookkeeping
	if UPDATE_TASK_FOR_REGULAR:
		var tid: String = "study_subject1"
		if pick == "subject2":
			tid = "study_subject2"
		GameState.update_task_step(tid)
	if APPLY_TIME_FOR_REGULAR:
		GameState.adjust_time(REGULAR_STUDY_TIME_MIN)

# ---------- Actions ----------
func _on_done_pressed() -> void:
	var return_path: String = String(GameState.features_unlocked.get(KEY_RETURN_SCENE, HOME_SCENE_PATH))
	if GameState.features_unlocked.has(KEY_RETURN_SCENE):
		GameState.features_unlocked.erase(KEY_RETURN_SCENE)
	if return_path == "":
		return_path = HOME_SCENE_PATH
	get_tree().change_scene_to_file(return_path)

# ---------- Helpers ----------
func _fill_slot(ql: Label, al: Label, qd: Dictionary) -> void:
	var q_text: String = String(qd.get("q",""))
	var correct: String = String(qd.get("correct",""))
	ql.text = q_text
	al.text = "Answer: " + correct
	ql.visible = true
	al.visible = true

func _get_finals_pair_for_today(subject_raw: String) -> Array[Dictionary]:
	var key: String = GameState._get_subject_key_from_choice(subject_raw)
	GameState._ensure_finals(key)
	var finals: Array = GameState.exam_finals.get(key, [])
	if finals.size() < 2:
		return []
	var base_index: int = int(((GameState.day - 1) % 5) * 2)
	if base_index + 1 >= finals.size():
		base_index = max(0, finals.size() - 2)
	var id1: String = String(finals[base_index])
	var id2: String = String(finals[base_index + 1])
	var q1: Dictionary = GameState.get_question_by_id(subject_raw, id1)
	var q2: Dictionary = GameState.get_question_by_id(subject_raw, id2)
	var out: Array[Dictionary] = []
	if not q1.is_empty():
		out.append(q1)
	if not q2.is_empty():
		out.append(q2)
	return out

func _fallback_two_finals(subject_raw: String) -> Array[Dictionary]:
	var paper: Array = GameState.build_exam_paper(subject_raw)
	var out: Array[Dictionary] = []
	for i in range(min(2, paper.size())):
		var id: String = String((paper[i] as Dictionary).get("id",""))
		var qd: Dictionary = GameState.get_question_by_id(subject_raw, id)
		if not qd.is_empty():
			out.append(qd)
	return out

func _pick_fillers(subject_raw: String, count: int, today_pair: Array[Dictionary]) -> Array[Dictionary]:
	var key: String = GameState._get_subject_key_from_choice(subject_raw)
	var pool: Array = GameState._load_pool(key)

	var finals_ids: Array = GameState.exam_finals.get(key, [])
	var finals_set: Dictionary = {}
	for id in finals_ids:
		finals_set[String(id)] = true
	for d in today_pair:
		finals_set[String((d as Dictionary).get("id",""))] = true

	var candidates: Array[Dictionary] = []
	for qv in pool:
		var qd: Dictionary = qv
		var qid: String = String(qd.get("id",""))
		if not finals_set.has(qid):
			candidates.append(qd)

	var picked: Array[Dictionary] = []
	var N: int = min(count, candidates.size())
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var used: Dictionary = {}
	while picked.size() < N and candidates.size() > 0:
		var idx: int = rng.randi_range(0, candidates.size() - 1)
		if not used.has(idx):
			used[idx] = true
			picked.append(candidates[idx])
	return picked
