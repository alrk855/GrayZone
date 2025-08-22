extends Control

@onready var name_input: LineEdit = $Background/MarginContainer/VBoxContainer/NameRow/EnterName
@onready var male_button: Button = $Background/MarginContainer/VBoxContainer/PanelContainer/VBoxContainer/ButtonRow/Male
@onready var female_button: Button = $Background/MarginContainer/VBoxContainer/PanelContainer/VBoxContainer/ButtonRow/Female
@onready var continue_button: Button = $Background/MarginContainer/VBoxContainer/ContinueRow/NEXT
@onready var click_sound: AudioStreamPlayer2D = $ClickSound

var selected_gender: String = ""

func _ready():
	# Use button_up to avoid signal name collisions
	self.modulate = Color(0, 0, 0, 1)
	create_tween().tween_property(self, "modulate", Color(1, 1, 1, 1), 2)
	male_button.button_up.connect(_on_gender_selected.bind("male"))
	female_button.button_up.connect(_on_gender_selected.bind("female"))
	continue_button.pressed.connect(_on_continue_pressed)

func _on_gender_selected(gender: String) -> void:
	click_sound.play()

	selected_gender = gender

	# Make only one selected
	if gender == "male":
		male_button.button_pressed = true
		female_button.button_pressed = false
	else:
		male_button.button_pressed = false
		female_button.button_pressed = true

func _on_continue_pressed() -> void:
	click_sound.play()

	var player_name = name_input.text.strip_edges()
	if player_name == "" or selected_gender == "":
		print("Please enter your name and select a gender.")
		return
	elif player_name.to_lower() == "ostaver":
		get_tree().change_scene_to_file("res://Themes/28112005.tscn")
		return


	GameState.player_name = player_name
	GameState.player_gender = selected_gender

	get_tree().change_scene_to_file("res://Scenes/Intro.tscn")
