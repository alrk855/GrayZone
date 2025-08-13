extends Control

# ---------------- MANUAL PATHS ----------------
const LABELS_CONTAINER_PATH: NodePath = ^"TextureRect/VBoxContainer"
const DONE_BUTTON_PATH: NodePath      = ^"TextureRect/Done"
const HOME_SCENE_PATH: String         = "res://Scenes/Reusable/Map/Home.tscn"

const FONT_SIZE: int = 45
const TEXT_COLOR := Color.BLACK

# ---------------- KEYS ----------------
const KEY_STUDY_MODE: String    = "__study_mode"
const KEY_SUBJECT_PICK: String  = "__study_subject_pick"
const KEY_RETURN_SCENE: String  = "__study_return_scene"

# Regular study bookkeeping
const REGULAR_STUDY_TIME_MIN: int = 30

func _ready() -> void:
	GameState.location = "Study"

	var container: Node = get_node_or_null(LABELS_CONTAINER_PATH)
	if container == null:
		push_error("StudyShell: LABELS_CONTAINER_PATH not found: " + str(LABELS_CONTAINER_PATH))
		return

	var done_btn: Button = get_node_or_null(DONE_BUTTON_PATH) as Button
	if done_btn and not done_btn.pressed.is_connected(Callable(self, "_on_done_pressed")):
		done_btn.pressed.connect(_on_done_pressed)

	# Locate labels
	var q_labels: Array[Label] = []
	var a_labels: Array[Label] = []
	for i in range(1, 6):
		var ql := container.get_node_or_null("Question%d" % i) as Label
		var al := container.get_node_or_null("Answer%d" % i)   as Label
		if ql: q_labels.append(ql)
		if al: a_labels.append(al)
	if q_labels.size() != 5 or a_labels.size() != 5:
		push_error("StudyShell: Need exactly 5 Question* and 5 Answer* labels.")
		return

	# Style defaults
	for i in range(5):
		var ql: Label = q_labels[i]
		var al: Label = a_labels[i]
		ql.add_theme_font_size_override("font_size", FONT_SIZE)
		al.add_theme_font_size_override("font_size", FONT_SIZE)
		ql.add_theme_color_override("font_color", TEXT_COLOR)
		al.add_theme_color_override("font_color", TEXT_COLOR)
		ql.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ql.visible = false
		al.visible = false
		ql.text = ""
		al.text = ""

	# Mode + subject
	var mode: String = String(GameState.features_unlocked.get(KEY_STUDY_MODE, "regular")).to_lower()
	var pick: String = String(GameState.features_unlocked.get(KEY_SUBJECT_PICK, "subject1")).to_lower()

	var subject_raw: String = ""
	if pick == "subject2":
		subject_raw = GameState.subject2
	else:
		subject_raw = GameState.subject1

	if subject_raw.strip_edges() == "":
		subject_raw = GameState.subject1

	# Finals pair for today
	var finals_pair: Array[String] = GameState.get_today_finals_pair_ids(subject_raw)
	var pair_q: Array[Dictionary] = []
	for id in finals_pair:
		var qd: Dictionary = GameState.get_question_by_id(subject_raw, id)
		if not qd.is_empty():
			pair_q.append(qd)
	if pair_q.size() < 2:
		var tmp := GameState.build_exam_paper(subject_raw)
		pair_q.clear()
		for i in range(min(2, tmp.size())):
			var id := String((tmp[i] as Dictionary).get("id",""))
			var qd := GameState.get_question_by_id(subject_raw, id)
			if not qd.is_empty():
				pair_q.append(qd)

	if mode == "marko":
		_fill_slot(q_labels[1], a_labels[1], pair_q[0])
		_fill_slot(q_labels[3], a_labels[3], pair_q[1])
		return

	# REGULAR mode
	var daily_batch: Array = GameState.get_daily_study_sheet(subject_raw)
	for i in range(min(5, daily_batch.size())):
		_fill_slot(q_labels[i], a_labels[i], daily_batch[i])

	GameState.count_study_if_new(subject_raw, REGULAR_STUDY_TIME_MIN)

func _fill_slot(ql: Label, al: Label, qd: Dictionary) -> void:
	ql.text = String(qd.get("q",""))
	al.text = "Answer: " + String(qd.get("correct",""))
	ql.visible = true
	al.visible = true

func _on_done_pressed() -> void:
	var return_path: String = String(GameState.features_unlocked.get(KEY_RETURN_SCENE, HOME_SCENE_PATH))
	if return_path == "":
		return_path = HOME_SCENE_PATH
	get_tree().change_scene_to_file(return_path)
