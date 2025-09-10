extends Control

const LABELS_CONTAINER_PATH: NodePath = ^"TextureRect/VBoxContainer"
const DONE_BUTTON_PATH: NodePath      = ^"TextureRect/Done"
const HOME_SCENE_PATH: String         = "res://Scenes/Reusable/Map/Home.tscn"

const KEY_STUDY_MODE: String     = "__study_mode"          # kept for compatibility; not branching on it anymore
const KEY_SUBJECT_PICK: String   = "__study_subject_pick"  # "subject1" | "subject2"
const KEY_RETURN_SCENE: String   = "__study_return_scene"  # where Done returns
const KEY_SESSION_INDEX: String  = "__study_session_index" # 0 = today; 1..4 = specific session

const REGULAR_STUDY_TIME_MIN: int = 45  # Study owns +45 min per session

func _ready() -> void:
	GameState.location = "Study"

	# --- find container + Done button ---
	var container: Node = get_node_or_null(LABELS_CONTAINER_PATH)
	if container == null:
		push_error("Study: LABELS_CONTAINER_PATH not found: " + str(LABELS_CONTAINER_PATH))
		return

	var done_btn: Button = get_node_or_null(DONE_BUTTON_PATH) as Button
	if done_btn and not done_btn.pressed.is_connected(Callable(self, "_on_done_pressed")):
		done_btn.pressed.connect(_on_done_pressed)

	# --- collect label refs ---
	var q_labels: Array[Label] = []
	var a_labels: Array[Label] = []
	for i in range(1, 6):
		var ql := container.get_node_or_null("Question%d" % i) as Label
		var al := container.get_node_or_null("Answer%d" % i)   as Label
		if ql == null or al == null:
			push_error("Study: Need Question%d and Answer%d under %s" % [i, i, str(LABELS_CONTAINER_PATH)])
			return
		q_labels.append(ql)
		a_labels.append(al)

	# --- clear labels (no theme overrides) ---
	for i in range(5):
		var ql: Label = q_labels[i]
		var al: Label = a_labels[i]
		ql.visible = false
		al.visible = false
		ql.text = ""
		al.text = ""

	# --- resolve subject from feature flag ---
	var pick: String = String(GameState.features_unlocked.get(KEY_SUBJECT_PICK, "subject1")).to_lower()
	var subject_raw: String = ""
	if pick == "subject2":
		subject_raw = GameState.subject2
	else:
		subject_raw = GameState.subject1
	if subject_raw.strip_edges() == "":
		subject_raw = GameState.subject1

	# --- choose the sheet: explicit session (1..4) or today's ---
	var session_idx: int = int(GameState.features_unlocked.get(KEY_SESSION_INDEX, 0))
	var batch: Array
	if session_idx >= 1 and session_idx <= 4:
		batch = GameState.get_study_sheet_for_session(subject_raw, session_idx)
	else:
		batch = GameState.get_daily_study_sheet(subject_raw)

	# --- render ---
	if batch.size() == 0:
		# Friendly placeholder instead of a blank screen
		var mid: int = 2
		q_labels[mid].text = "No questions available."
		a_labels[mid].text = ""
		q_labels[mid].visible = true
	else:
		var n: int = min(5, batch.size())
		for i in range(n):
			_fill_slot(q_labels[i], a_labels[i], batch[i])

	# --- once-per-day count (+45 min inside) ---
	GameState.count_study_if_new(subject_raw, REGULAR_STUDY_TIME_MIN)

func _fill_slot(ql: Label, al: Label, qd: Dictionary) -> void:
	ql.text = String(qd.get("q",""))
	al.text = "Answer: " + String(qd.get("correct",""))
	ql.visible = true
	al.visible = true

func _on_done_pressed() -> void:
	var return_path: String = String(GameState.features_unlocked.get(KEY_RETURN_SCENE, HOME_SCENE_PATH))
	if return_path.strip_edges() == "":
		return_path = HOME_SCENE_PATH
	get_tree().change_scene_to_file(return_path)
