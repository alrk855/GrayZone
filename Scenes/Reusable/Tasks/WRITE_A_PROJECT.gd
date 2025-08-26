extends Node

# ---------- UI & Nodes ----------
@onready var leave: Label            = $"Leave"
@onready var begin: Label            = $"Begin"
@onready var anim: AnimationPlayer   = $"StartAnimation"
@onready var option_buttons: Array[Label] = [$"Option1", $"Option2", $"Option3"]
@onready var timer: Timer            = $"tweenTimer"
@onready var question_label: Label   = $"Question"

@onready var ans: Label              = $"Outro/answers"
@onready var stats: Label            = $"Outro/stats"
@onready var quest: Label            = $"Outro/questions"
@onready var taken: Label            = $"Outro/taken"
@onready var outro: Control          = $"Outro"

# ---------- State ----------
var score: int = 0
var current_question: int = 0
var _started: bool = false
var _finished: bool = false
var _score_out_of_5: int = 0

# ---------- Config ----------
const LEAVE_BUTTON_PATH: NodePath = NodePath("Leave/button2")   # visible at start
const EXIT_BUTTON_PATH: NodePath  = NodePath("Exit/button2")    # hidden until finish
const EXIT_LABEL_PATH: NodePath   = NodePath("Exit")            # Label named "Exit", hidden until finish
const SCORE_LABEL_PATH: NodePath  = NodePath("UI/ScoreLabel")   # optional
const HOME_SCENE_PATH: String     = "res://Scenes/Reusable/Map/Home.tscn"

# ---------- Quiz Data ----------
var questions: Array[Dictionary] = [
	{
		"question": "What’s the title and general theme of your project?",
		"options": ["The Role of Civic Education in Modern Democracy",
					"Youth and Society: A Reflection",
					"How to Not Fail High School"],
		"answer": 0
	},
	{
		"question": "Where did you get most of your information?",
		"options": ["Wikipedia, mostly. And a TikTok video.",
					"Some blogs, an old project I found, and a few quotes.",
					"Peer-reviewed articles, civic textbooks, and official statistics."],
		"answer": 2
	},
	{
		"question": "Include a relevant example or case study?",
		"options": ["That one time our teacher forgot to mark us present.",
					"A general mention of student activism.",
					"The Anti-Corruption Protests and their impact on reforms."],
		"answer": 2
	},
	{
		"question": "Add a brief personal viewpoint?",
		"options": ["I believe civic awareness should be taught from a young age.",
					"Everyone has their own opinion.",
					"This was boring. But here we are."],
		"answer": 0
	},
	{
		"question": "How’s the formatting and final check?",
		"options": ["I skimmed it and stapled it last minute.",
					"Proofread, formatted, and printed neatly.",
					"Wrote it on loose paper. Might’ve spilled juice on it."],
		"answer": 1
	}
]

func _ready() -> void:
	# Initial visibility
	for b in option_buttons:
		b.visible = false
	outro.visible = false
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
	timer.start()
	create_tween().tween_property(begin, "modulate:a", 0.0, 1.0).set_trans(Tween.TRANS_CUBIC)
	create_tween().tween_property(leave, "modulate:a", 0.0, 1.0).set_trans(Tween.TRANS_CUBIC)
	loadQ()
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

	question_label.text = "🎓 Project Completed!"

	# Outro animation
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
	ans.text = "You answered: %d" % score
	t3.tween_property(ans, "position", Vector2(116.5, 240), 0.6).set_trans(Tween.TRANS_CUBIC)
	create_tween().tween_property(ans, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_CUBIC)
	await t3.finished

	var t4 := create_tween()
	var hours_taken: int = int(floor(float(GameState.time) / 60.0))
	taken.text = "Time Taken: %d h" % hours_taken
	t4.tween_property(taken, "position", Vector2(116.5, 330), 0.6).set_trans(Tween.TRANS_CUBIC)
	create_tween().tween_property(taken, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_CUBIC)

	finish_project_with_score(score)

# ---------- Bookkeeping ----------
func change_score() -> void:
	score += 1

func mark_started() -> void:
	_started = true
	# Optional: if you want to prevent leaving right after start
	var leave_btn := get_node_or_null(LEAVE_BUTTON_PATH) as Button
	if leave_btn:
		leave_btn.disabled = true

func finish_project_with_score(score_in: int) -> void:
	if _finished:
		return
	_finished = true
	_score_out_of_5 = clamp(score_in, 1, 5)

	# Store score & state using GameState's typed helpers
	GameState.set_int("project_score", _score_out_of_5)
	GameState.set_int("project_score_day_%d" % GameState.day, _score_out_of_5)
	GameState.set_flag("project_written", true)

	# Make project submit-ready (professor also checks print if it's self-written)
	GameState.ensure_task_progress_at_least("project", 2)

	# Reveal exit routes; hide Leave
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
		score_lbl.text = "Score: %d / 5" % _score_out_of_5
		score_lbl.visible = true

# ---------- Exits ----------
func _on_leave_pressed() -> void:
	# Only before the work actually starts
	if _started:
		return
	_go_home()

func _on_exit_pressed() -> void:
	if not _finished:
		return
	_go_home()

func _on_exit_label_input(event: InputEvent) -> void:
	if not _finished:
		return
	if event is InputEventMouseButton and event.pressed:
		_go_home()

func _go_home() -> void:
	if HOME_SCENE_PATH == "":
		return
	get_tree().change_scene_to_file(HOME_SCENE_PATH)
