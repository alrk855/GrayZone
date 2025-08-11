extends Button

@export var office_scene_path: String = "res://Scenes/Reusable/Map/ProfessorsOffice.tscn"
@export var popup_label_path: NodePath = "../../PopUp"

# Enter allowed from 13:00 up to 17:45 (office locks 17:45–18:00)
@export var open_minutes: int = 13 * 60
@export var lock_minutes: int = 17 * 60 + 45

@onready var popup_label: Label = get_node(popup_label_path)

func _ready() -> void:
	pressed.connect(_on_door_pressed)

func _on_door_pressed() -> void:
	var now: int = GameState.time
	if now >= open_minutes and now < lock_minutes:
		get_tree().change_scene_to_file("res://Scenes/Reusable/Map/ProfessorOffice.tscn")
	else:
		popup_label.text = "The door is locked. Looks like the professor has already left for the day."
		popup_label.visible = true
