extends Control

var tekst_za_pisuvanje : String = "Name: [YourName]
Date of Birth: [DD/MM/YYYY]
Education: High School (Current)
Skills: Typing, Teamwork, Basic Research
Experience: None yet — willing to learn"

@onready var animIntro : AnimationPlayer = $SceneAnimation
@onready var edit : TextEdit = $TextEdit

func _ready() -> void:
	#Animation
	animIntro.play("CV_anim")
	
	#Text
	tekst_za_pisuvanje = "Name: " + GameState.player_name + "
	Date of Birth: 28/11/2005
	Education: High School
	Skills: Typing, Teamwork, Basic Research
	Experience: None yet - willing to learn"
	GameState.location = "Unknown" # Location Unknown


func _on_button_pressed() -> void:
	if tekst_za_pisuvanje == edit.text:
		print("GOOD SHIT")
	else: print ("BAD SHIT")
