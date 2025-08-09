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
