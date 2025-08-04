extends Button

@onready var popup_label := $"../../PopUp"

const OFFICE_OPEN := 13 * 60   # 13:00 in minutes
const OFFICE_CLOSE := 16 * 60  # 16:00 in minutes

func _ready():
	pressed.connect(_on_door_pressed)

func _on_door_pressed():
	var now = GameState.time

	if now >= OFFICE_OPEN and now < OFFICE_CLOSE:
		# Office is open — enter the scene
		get_tree().change_scene_to_file("res://Scenes/Reusable/Map/SecretaryOffice.tscn")
	else:
		# Office is closed — show locked message
		popup_label.text = "The door is locked. Looks like the secretary has already clocked out for the day."
		popup_label.visible = true
