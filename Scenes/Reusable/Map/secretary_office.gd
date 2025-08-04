extends Control

@onready var secretary := $background/Secretary

func _ready():
	GameState.location = "SecretaryOffice"  # ✅ Ensure current location is known

	if GameState.day == 1 and GameState.time >= 13 * 60 and GameState.time < 16 * 60:
		if not GameState.flags.has("secretary_met"):
			GameState.flags["secretary_met"] = true
			GameState.update_task_step("Visit Secretary", "Visit the Secretary", true)
			GameState.add_task("Gather Scholarship Requirements")

			await get_tree().create_timer(0.1).timeout
			DialogueManager.start_dialogue("res://Dialogue/Secretary_Initial.json")  # ⚠ Replace once file exists

func _process(_delta):
	if GameState.time >= 16 * 60:
		if is_inside_tree():
			_show_office_closed()
			get_tree().change_scene_to_file("res://Scenes/School.tscn")

func _show_office_closed():
	var popup := AcceptDialog.new()
	popup.dialog_text = "🔒 The secretary has left for the day."
	add_child(popup)
	popup.popup_centered()
