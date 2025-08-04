extends Button

@onready var choice_panel := $"res://Scenes/Reusable/CharacterChoiceButtons.tscn"

func _ready():
	# Optional: Only show interaction if during valid hours
	if not is_during_work_hours():
		disabled = true

func _pressed():
	if is_during_work_hours():
		start_interaction()
	else:
		show_locked_popup()

func is_during_work_hours() -> bool:
	return GameState.time >= 13 * 60 and GameState.time < 16 * 60

func start_interaction():
	# First visit auto-dialogue
	if GameState.day == 1 and not GameState.flags.has("secretary_met"):
		GameState.flags["secretary_met"] = true
		DialogueManager.start_dialogue("res://Dialogue/Secretary_Initial.json")
		GameState.update_task_step("Visit Secretary", "Visit the Secretary", true)
		GameState.add_task("Gather Scholarship Requirements")
		return

	# Otherwise show interaction choices
	var options = [
		{ "text": "Ask about scholarship", "id": "talk" },
		{ "text": "Print a document", "id": "print" },
		{ "text": "Submit documents", "id": "submit" },
		{ "text": "Go back", "id": "back" }
	]
	choice_panel.show_options(options, Callable(self, "_on_choice_selected"))

func _on_choice_selected(choice_id):
	match choice_id:
		"talk":
			DialogueManager.start_dialogue("res://Dialogue/Secretary_Talk.json")
		"print":
			DialogueManager.start_dialogue("res://Dialogue/Secretary_Print.json")
		"submit":
			DialogueManager.start_dialogue("res://Dialogue/Secretary_Submit.json")
		"back":
			get_tree().change_scene_to_file("res://Scenes/School.tscn")

func show_locked_popup():
	# Show message like: “The office is locked. Come back between 13:00–16:00.”
	var popup := AcceptDialog.new()
	popup.dialog_text = "🔒 The office is locked.\nCome back between 13:00 and 16:00."
	add_child(popup)
	popup.popup_centered()
