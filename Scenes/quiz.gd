extends Control

@onready var question_label : Label = $ColorRect/Label
@onready var option_buttons : Array[Button] = [$"Option 1", $"Option 2", $"Option 3"]
@onready var score_label : Label = $score

@onready var timer : Timer = $Timer
@onready var timePAN : Panel = $ColorRect/TimePanel

var questions : Array[Dictionary] = [ 
	{
		"question": "What is the capital of France?",
		"options": ["Berlin", "Madrid", "Paris"],
		"answer": 2
	},
	{
		"question": "What is 2 + 2?",
		"options": ["3", "4", "5"],
		"answer": 1
	},
	{
		"question": "Which is the largest planet?",
		"options": ["Mars", "Earth", "Jupiter"],
		"answer": 2
	}
]

var current_question : int = 0
var score : int = 0

func _ready() -> void:
	load_question()
	timer.start()

func _process(_delta: float) -> void:
	timePAN.size = Vector2(timer.time_left * 97, 15)


func load_question() -> void:
	question_label.visible_characters = 0
	if current_question >= questions.size(): 
		end_quiz()
		return
	
	var q : Dictionary = questions[current_question]
	question_label.text = q["question"]
	
	create_tween().tween_property(question_label, "visible_characters", question_label.text.length(), 1)
	@warning_ignore("inferred_declaration") # for i
	for i in range(option_buttons.size()):
		var button : Button = option_buttons[i]
		button.text = q["options"][i]
		
		if button.pressed.is_connected(_on_option_pressed):
			button.pressed.disconnect(_on_option_pressed)
		
		button.pressed.connect(_on_option_pressed.bind(i))
	

func _on_option_pressed(selected_index: int) -> void:
	var correct_index : int = questions[current_question]["answer"]
	timer.start()
	
	if selected_index == correct_index:
		score += 10
	
	current_question += 1
	load_question()
	update_score()

func update_score() -> void:
	score_label.text = "Score: %d" % score

func end_quiz() -> void:
	timePAN.visible = false
	question_label.text = "Quiz Finished!"
	@warning_ignore("inferred_declaration") #for btn
	for btn in option_buttons: 
		btn.visible = false
	question_label.visible_characters = 100


func _on_timer_timeout() -> void:
	end_quiz()
