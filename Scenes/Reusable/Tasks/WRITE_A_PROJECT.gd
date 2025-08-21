extends Node

@onready var leave : Label = $"Leave"
@onready var begin : Label = $"Begin"
@onready var anim : AnimationPlayer = $"StartAnimation"
@onready var option_buttons : Array[Label] = [$"Option1", $"Option2", $"Option3"]
@onready var timer : Timer = $"tweenTimer"
@onready var question_label : Label = $"Question"

@onready var ans: Label = $"Outro/answers"
var tween: Tween
@onready var stats: Label = $"Outro/stats"
@onready var quest: Label = $"Outro/questions"
@onready var taken: Label = $"Outro/taken"
@onready var outro: Control = $"Outro"

var score : float = 0
var current_question : int = 0

var questions : Array[Dictionary] = [ 
	{
		"question": "What’s the title and general theme of your project?",
		"options": ["The Role of Civic Education in Modern Democracy", 
		"Youth and Society: A Reflection", "How to Not Fail High School"],
		"answer": 0
	},
	{
		"question": "Where did you get most of your information?",
		"options": ["Wikipedia, mostly. And a TikTok video.", 
		"Some blogs, an old project I found, and a few quotes.", "Peer-reviewed articles, civic textbooks, and official statistics."],
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
	option_buttons[0].visible = 0
	option_buttons[1].visible = 0
	option_buttons[2].visible = 0
	outro.visible = 0
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

func _on_button_pressed() -> void: #begin writing
	begin_project()
func _on_button_2_pressed() -> void: #Leave
	print("Leave")

func begin_project() -> void:
	timer.start()
	create_tween().tween_property(begin, "modulate:a", 0, 1).set_trans(Tween.TRANS_CUBIC)
	create_tween().tween_property(leave, "modulate:a", 0, 1).set_trans(Tween.TRANS_CUBIC)
	loadQ()
	await timer.timeout
	option_buttons[0].visible = 1
	option_buttons[1].visible = 1
	option_buttons[2].visible = 1
	begin.visible = false
	leave.visible = false

func loadQ() -> void:
	if current_question >= questions.size(): 
		endQ()
		return
	
	question_label.visible_ratio = 0
	question_label.text = questions[current_question]["question"]
	create_tween().tween_property(question_label, "visible_ratio", 1, 2)
	for i in range(option_buttons.size()):
		option_buttons[i].text = questions[current_question]["options"][i]

func endQ() -> void:
	option_buttons[0].queue_free()
	option_buttons[1].queue_free()
	option_buttons[2].queue_free()
	question_label.text = "🎓 “Project Completed!"
	
	# ANIMATE
	outro.visible = 1
	var tween1 = create_tween()
	tween1.tween_property(stats, "position", Vector2(209.5, 60), 1).set_trans(Tween.TRANS_CUBIC)
	create_tween().tween_property(stats, "modulate:a", 1, 1).set_trans(Tween.TRANS_CUBIC)
	await tween1.finished

	var tween2 = create_tween()
	tween2.tween_property(quest, "position", Vector2(151.5, 150), 1).set_trans(Tween.TRANS_CUBIC)
	create_tween().tween_property(quest, "modulate:a", 1, 1).set_trans(Tween.TRANS_CUBIC)
	await tween2.finished

	var tween3 = create_tween()
	ans.text = "You answered : %d" % score
	tween3.tween_property(ans, "position", Vector2(116.5, 240), 1).set_trans(Tween.TRANS_CUBIC)
	create_tween().tween_property(ans, "modulate:a", 1, 1).set_trans(Tween.TRANS_CUBIC)
	await tween3.finished

	var tween4 = create_tween()
	var tmp : float = GameState.time/60
	taken.text = "Time Taken : %d" %tmp
	tween4.tween_property(taken, "position", Vector2(116.5, 330), 1).set_trans(Tween.TRANS_CUBIC)
	create_tween().tween_property(taken, "modulate:a", 1, 1).set_trans(Tween.TRANS_CUBIC)
	finish_project_with_score(int(score))
	
	
func _on_button1_pressed() -> void: #OPTION1
	var correct_index : int = questions[current_question]["answer"]
	if(correct_index == 0):
		current_question += 1
		change_score()
	else:
		current_question += 1
	loadQ()


func _on_button2_pressed() -> void: #OPTION2
	var correct_index : int = questions[current_question]["answer"]
	if(correct_index == 1):
		current_question += 1
		change_score()
	else:
		current_question += 1
	loadQ()

func _on_button3_pressed() -> void: #OPTION3
	var correct_index : int = questions[current_question]["answer"]
	if(correct_index == 2):
		current_question += 1
		change_score()
	else:
		current_question += 1
	loadQ()

func change_score():
	score+=1

## ---------- SET THESE PATHS ----------
const LEAVE_BUTTON_PATH: NodePath = NodePath("Leave/button2")     # visible at start
const EXIT_BUTTON_PATH: NodePath  = NodePath("Exit/button2")      # hidden until finish
const EXIT_LABEL_PATH: NodePath   = NodePath("Exit")              # Label named "Exit", hidden until finish
const SCORE_LABEL_PATH: NodePath  = NodePath("UI/ScoreLabel")     # optional; leave as NodePath("") if you don’t have it
const HOME_SCENE_PATH: String     = "res://Scenes/Reusable/Map/Home.tscn"
# ------------------------------------

var _started: bool = false
var _finished: bool = false
var _score_out_of_5: int = 0


# Call this when the player actually starts working (first real action)
func mark_started() -> void:
	_started = true

# Call once when the project is finished. score must be in 1..5.
func finish_project_with_score(score: int) -> void:
	if _finished:
		return
	_finished = true
	_score_out_of_5 = clamp(score, 1, 5)

	# Store score
	GameState.flags["project_score"] = _score_out_of_5
	GameState.flags["project_score_day_%d" % GameState.day] = _score_out_of_5
	GameState.set_flag("project_written", true)

	# Make project submit-ready (your professor script checks >=2)
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

# -------- Buttons / Label --------
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
