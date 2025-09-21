extends Control

var tekst_za_pisuvanje : String = "Name: Aco
Date of Birth: 28/11/2005
Education: High School
Skills: Typing, Teamwork, Basic Research
Experience: None yet - willing to learn"

@onready var animIntro : AnimationPlayer = $SceneAnimation
@onready var edit : TextEdit = $TextEdit
@onready var peek : Button = $"PeekButton"
@onready var box : Control = $CVBOX
@onready var write : Button = $WriteButton

func _ready() -> void:
	#Animation
	animIntro.play("CV_anim")
	
	if(GameState.player_name == ""): #Default player_name - da ne bide prazno
		GameState.player_name = "Aco"
	
	#Text
	tekst_za_pisuvanje = "Name: " + GameState.player_name + "\nDate of Birth: 28/11/2005 \nEducation: High School \nSkills: Typing, Teamwork, Basic Research \nExperience: None yet - willing to learn"
	GameState.location = "Unknown" # Location Unknown


func _on_button_pressed() -> void: #Peek
	create_tween().tween_property(edit, "position", Vector2(2100, 278), 1) #edit
	create_tween().tween_property(box, "position", Vector2(517, 255), 1) #CV text
	create_tween().tween_property(peek, "position", Vector2(1602, -120), 1) #peek
	create_tween().tween_property(write, "position", Vector2(0.0, 0), 1) #write


func _on_scene_animation_animation_finished(anim_name: StringName) -> void:
	create_tween().tween_property(edit, "position", Vector2(580.5, 278.5), 1)
	create_tween().tween_property(peek, "position", Vector2(1602, 1), 1)


func _on_write_button_pressed() -> void:
	create_tween().tween_property(write, "position", Vector2(0.0, -120), 1)
	create_tween().tween_property(peek, "position", Vector2(1602, 0), 1)
	create_tween().tween_property(edit, "position", Vector2(580.5, 278.5), 1) #edit
	create_tween().tween_property(box, "position", Vector2(-1000, 255), 1) #CV text


func _on_finish_button_pressed() -> void:
	var last_char = edit.text[edit.text.length() - 1]
	if (last_char == " " or last_char == "\n" or last_char == "\t" or last_char == "\r"):
		edit.text = edit.text.substr(0, edit.text.length() - 1)
	
	if(edit.text == tekst_za_pisuvanje):
		print("Finished")
		finish_game()
	else: print(tekst_za_pisuvanje)

func finish_game():
	pass #zavrsetok
