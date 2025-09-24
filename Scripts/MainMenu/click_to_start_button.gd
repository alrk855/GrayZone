# res://Scripts/Scenes/ProjectQuiz.gd
extends Node

# ---------- UI & Nodes ----------
@onready var leave: Label                  = $"Leave"
@onready var begin: Label                  = $"Begin"
@onready var anim: AnimationPlayer         = $"StartAnimation"
@onready var option_buttons: Array[Label]  = [$"Option1", $"Option2", $"Option3"]
@onready var timer: Timer                  = $"tweenTimer"
@onready var question_label: Label         = $"Question"

@onready var ans: Label                    = $"Outro/answers"
@onready var stats: Label                  = $"Outro/stats"
@onready var quest: Label                  = $"Outro/questions"
@onready var taken: Label                  = $"Outro/taken"
@onready var outro: Control                = $"Outro"

# ---------- Config ----------
# Store a RELATIVE ID (under Data/), not a res:// path.
# Example JSON lives at: res://Data/Quizzes/Project_Quiz.json
# Localized override would be:   res://Data/<locale>/Quizzes/Project_Quiz.json
@export var QUESTIONS_JSON_ID: String = "Quizzes/Project_Quiz.json"

const LEAVE_BUTTON_PATH: NodePath = NodePath("Leave/button2")
const EXIT_BUTTON_PATH:  NodePath  = NodePath("Exit/button2")
const EXIT_LABEL_PATH:   NodePath  = NodePath("Exit")
const SCORE_LABEL_PATH:  NodePath  = NodePath("UI/ScoreLabel")
const HOME_SCENE_PATH:   String    = "res://Scenes/Reusable/Map/Home.tscn"

# ---------- State ----------
var score: int = 0
var current_question: int = 0
var _started: bool = false
var _finished: bool = false
var _score_out_of_5: int = 0
var _exiting: bool = false

# ---------- Quiz Data ----------
# Each item: { "question": String, "options": [String, String, String], "answer": int(0..2) }
var questions: Array[Dictionary] = []

func _ready() -> void:
	_load_questions_from_json()
	GameState.location = "Unknown"

	# Initial UI state
	for b in option_buttons:
		b.visible = false
	outro.visible = false
	if anim:
		anim.play("CvAnim")

	# Wire controls
	var leave_btn := get_node_or_null(LEAVE_BUTTON_PATH) as Button
	if leave_btn and not leave_btn.pressed.is_connected(Callable(self, "_on_leave_pressed")):
		leave_btn.pressed.connect(_on_leave_pressed)

	var exit_btn := get_node_or_null(EXIT_BUTTON_PATH) as Button
	if exit_btn:
		exit_btn.visible = false
		if not exit_btn.pressed.is_connected(Callable(self, "_on_exit_pressed")):
			exit_btn.pressed.connect(_on_exit_pressed)

	var exit_label := get_node_or_null(EXIT_LABEL_PATH) as Control
	if exit_label:
		exit_label.visible = false
		if not exit_label.gui_input.is_connected(Callable(self, "_on_exit_label_input")):
			exit_label.gui_input.connect(_on_exit_label_input)

	var score_lbl := get_node_or_null(SCORE_LABEL_PATH) as Label
	if score_lbl:
		score_lbl.visible = false

# ---------- JSON loader (relative ID → locale-aware absolute path) ----------
func _load_questions_from_json() -> void:
	questions.clear()

	var p := _jp_id(QUESTIONS_JSON_ID).strip_edges()
	if p == "" or not FileAccess.file_exists(p):
		push_warning("Questions JSON not found: " + p)
		return

	var raw := FileAccess.get_file_as_string(p)
	var parsed := JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Invalid questions JSON root. Expected Dictionary.")
		return

	var arr: Variant = (parsed as Dictionary).get("questions", [])
	if not (arr is Array):
		push_warning("'questions' missing or not an Array.")
		return

	for item in (arr as Array):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var q := String(item.get("question", ""))
		var opts_v := item.get("options", [])
		var ans := int(item.get("answer", 0))
		if q == "" or not (opts_v is Array) or (opts_v as Array).size() < 3:
			continue
		var opts_arr := opts_v as Array
		questions.append({
			"question": q,  # already localized by file
			"options": [String(opts_arr[0]), String(opts_arr[1]), String(opts_arr[2])],
			"answer": clamp(ans, 0, 2)
		})

	if questions.is_empty():
		push_warning("No valid questions loaded from: " + p)

# ---------- Buttons from the scene ----------
func _on_button_pressed() -> void: # Begin
	begin_project()

func _on_button_2_pressed() -> void: # (legacy) Leave label button
	_on_leave_pressed()

func _on_button1_pressed() -> void: # Option 1
	_answer(0)

func _on_button2_pressed() -> void: # Option 2
	_answer(1)

func _on_button3_pressed() -> void: # Option 3
	_answer(2)

# ---------- Flow ----------
func begin_project() -> void:
	mark_started()
	if timer:
		timer.start()
	create_tween().tween_property(begin, "modulate:a", 0.0, 1.0).set_trans(Tween.TRANS_CUBIC)
	create_tween().tween_property(leave, "modulate:a", 0.0, 1.0).set_trans(Tween.TRANS_CUBIC)
	loadQ()
	if timer:
		await timer.timeout
	for b in option_buttons:
		b.visible = true
	begin.visible = false
	leave.visible = false

func loadQ() -> void:
	if current_question >= questions.size():
		endQ()
		return
	question_label.visible_ratio = 0.0
	question_label.text = String(questions[current_question]["question"])
	create_tween().tween_property(question_label, "visible_ratio", 1.0, 0.6)
	for i in range(option_buttons.size()):
		option_buttons[i].text = String((questions[current_question]["options"] as Array)[i])

func _answer(choice_index: int) -> void:
	var correct_index: int = int(questions[current_question]["answer"])
	if choice_index == correct_index:
		change_score()
	current_question += 1
	loadQ()

func endQ() -> void:
	# Cleanup options
	for b in option_buttons:
		if is_instance_valid(b):
			b.queue_free()

	question_label.text = tr("🎓 Project Completed!")

	outro.visible = true

	var t1 := create_tween()
	t1.tween_property(stats, "position", Vector2(209.5, 60), 0.6).set_trans(Tween.TRANS_CUBIC)
	create_tween().tween_property(stats, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_CUBIC)
	await t1.finished

	var t2 := create_tween()
	t2.tween_property(quest, "position", Vector2(151.5, 150), 0.6).set_trans(Tween.TRANS_CUBIC)
	create_tween().tween_property(quest, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_CUBIC)
	await t2.finished

	var t3 := create_tween()
	ans.text = tr("You answered: %d") % score
	t3.tween_property(ans, "position", Vector2(116.5, 240), 0.6).set_trans(Tween.TRANS_CUBIC)
	create_tween().tween_property(ans, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_CUBIC)
	await t3.finished

	var t4 := create_tween()
	var mins_taken: int = int(floor(float(GameState.time)))
	taken.text = tr("Time Taken: %d min") % mins_taken
	t4.tween_property(taken, "position", Vector2(116.5, 330), 0.6).set_trans(Tween.TRANS_CUBIC)
	create_tween().tween_property(taken, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_CUBIC)

	finish_project_with_score(score)

# ---------- Bookkeeping ----------
func change_score() -> void:
	score += 1

func mark_started() -> void:
	_started = true
	var leave_btn := get_node_or_null(LEAVE_BUTTON_PATH) as Button
	if leave_btn:
		leave_btn.disabled = true

func finish_project_with_score(score_in: int) -> void:
	if _finished:
		return
	_finished = true
	_score_out_of_5 = clamp(score_in, 1, 5)

	GameState.set_int("project_score", _score_out_of_5)
	GameState.set_int("project_score_day_%d" % GameState.day, _score_out_of_5)
	GameState.set_flag("project_written", true)
	GameState.ensure_task_progress_at_least("project", 2)

	var leave_btn := get_node_or_null(LEAVE_BUTTON_PATH) as Button
	if leave_btn:
		leave_btn.visible = false
	var exit_btn := get_node_or_null(EXIT_BUTTON_PATH) as Button
	if exit_btn:
		exit_btn.visible = true
	var exit_label := get_node_or_null(EXIT_LABEL_PATH) as Control
	if exit_label:
		exit_label.visible = true

	var score_lbl := get_node_or_null(SCORE_LABEL_PATH) as Label
	if score_lbl:
		score_lbl.text = tr("Score: %d / 5") % _score_out_of_5
		score_lbl.visible = true

# ---------- Exits ----------
func _on_leave_pressed() -> void:
	if _started or _exiting:
		return
	_go_home()

func _on_exit_pressed() -> void:
	if not _finished or _exiting:
		return
	_go_home()

func _on_exit_label_input(event: InputEvent) -> void:
	if not _finished or _exiting:
		return
	if event is InputEventMouseButton and event.pressed:
		_go_home()

func _go_home() -> void:
	if _exiting:
		return
	_exiting = true

	var leave_btn := get_node_or_null(LEAVE_BUTTON_PATH) as Button
	if leave_btn:
		leave_btn.disabled = true
	var exit_btn := get_node_or_null(EXIT_BUTTON_PATH) as Button
	if exit_btn:
		exit_btn.disabled = true
	var exit_label := get_node_or_null(EXIT_LABEL_PATH) as Control
	if exit_label:
		exit_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if HOME_SCENE_PATH == "" or not ResourceLoader.exists(HOME_SCENE_PATH):
		push_error("Invalid HOME_SCENE_PATH: " + String(HOME_SCENE_PATH))
		return

	GameState.location = "Home"
	await fade.fade_to_scene(HOME_SCENE_PATH)

# ---------- Locale-aware resolver for RELATIVE IDs ----------
# Input: "Quizzes/Project_Quiz.json"
# Tries: res://Data/<locale>/Quizzes/Project_Quiz.json -> res://Data/Quizzes/Project_Quiz.json
func _jp_id(id: String) -> String:
	var base := String(id).strip_edges().trim_prefix("/")

	# Prefer a GameState-provided resolver if present
	if GameState.has_method("resolve_json_id"):
		return String(GameState.resolve_json_id(base))

	# Manual resolution
	var base_abs := "res://Data/" + base
	var loc := ""
	if GameState.has_method("current_locale"):
		loc = String(GameState.current_locale())
	elif GameState.has_method("get_locale"):
		loc = String(GameState.get_locale())
	loc = loc.strip_edges()

	if loc != "":
		var loc_abs := "res://Data/%s/%s" % [loc, base]
		if FileAccess.file_exists(loc_abs):
			return loc_abs

	return base_abs
