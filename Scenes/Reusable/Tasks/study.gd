extends Control

const LABELS_CONTAINER_PATH: NodePath = ^"TextureRect/VBoxContainer"
const DONE_BUTTON_PATH: NodePath      = ^"TextureRect/Done"
const HOME_SCENE_PATH: String         = "res://Scenes/Reusable/Map/Home.tscn"

const KEY_STUDY_MODE: String     = "__study_mode"          # kept for compatibility; not branching on it anymore
const KEY_SUBJECT_PICK: String   = "__study_subject_pick"  # "subject1" | "subject2"
const KEY_RETURN_SCENE: String   = "__study_return_scene"  # where Done returns
const KEY_SESSION_INDEX: String  = "__study_session_index" # 0 = today; 1..4 = specific session

const REGULAR_STUDY_TIME_MIN: int = 45  # +45 minutes per session (every time)

# ---- locals to commit correct session on exit ----
var _subject_raw: String = ""
var _effective_session: int = 0    # 1..4

func _ready() -> void:
	GameState.location = "Unknown"

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

	# --- clear labels ---
	for i in range(5):
		q_labels[i].visible = false
		a_labels[i].visible = false
		q_labels[i].text = ""
		a_labels[i].text = ""

	# --- resolve subject from feature flag ---
	var pick: String = String(GameState.features_unlocked.get(KEY_SUBJECT_PICK, "subject1")).to_lower()
	if pick == "subject2":
		_subject_raw = GameState.subject2
	else:
		_subject_raw = GameState.subject1
	if _subject_raw.strip_edges() == "":
		_subject_raw = GameState.subject1

	# --- compute effective session index (1..4) ---
	var requested_idx: int = int(GameState.features_unlocked.get(KEY_SESSION_INDEX, 0))
	if requested_idx >= 1 and requested_idx <= 4:
		_effective_session = requested_idx
	else:
		# fallback to today's day clamped to 1..4
		_effective_session = clamp(GameState.day, 1, 4)

	# --- choose the sheet: explicit session or today's sheet ---
	var batch: Array
	if requested_idx >= 1 and requested_idx <= 4:
		batch = GameState.get_study_sheet_for_session(_subject_raw, _effective_session)
	else:
		batch = GameState.get_daily_study_sheet(_subject_raw)

	# --- render ---
	if batch.size() == 0:
		var mid := 2
		q_labels[mid].text = "No questions available."
		a_labels[mid].text = ""
		q_labels[mid].visible = true
	else:
		var n = min(5, batch.size())
		for i in range(n):
			_fill_slot(q_labels[i], a_labels[i], batch[i])

	# NOTE: no time added on enter; time is added on Done every time.

func _fill_slot(ql: Label, al: Label, qd: Dictionary) -> void:
	ql.text = String(qd.get("q",""))
	al.text = "Answer: " + String(qd.get("correct",""))
	ql.visible = true
	al.visible = true

func _on_done_pressed() -> void:
	_commit_study_session()  # awards time every session; marks session as done once

	var return_path: String = String(GameState.features_unlocked.get(KEY_RETURN_SCENE, HOME_SCENE_PATH))
	if return_path.strip_edges() == "":
		return_path = HOME_SCENE_PATH
	get_tree().change_scene_to_file(return_path)

func _commit_study_session() -> void:
	var subj_key: String = GameState._get_subject_key_from_choice(_subject_raw)
	if subj_key.strip_edges() == "":
		return

	var guard_key := "%s|%d" % [subj_key, _effective_session]

	# Always award time, even on repeats
	GameState.adjust_time(REGULAR_STUDY_TIME_MIN)

	# Mark the specific session as done the first time we ever complete it
	if not GameState.study_guard.has(guard_key):
		GameState.study_guard[guard_key] = true
