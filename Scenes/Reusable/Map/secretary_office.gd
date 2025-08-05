extends Control

@onready var secretary := $background/Secretary
@onready var choice_panel_scene := preload("res://Scenes/Reusable/CharacterChoiceButtons.tscn")

func _ready():
	GameState.location = "SecretaryOffice"

	if GameState.day == 1 and GameState.time >= 13 * 60 and GameState.time < 16 * 60:
		if not GameState.flags.has("secretary_met"):
			GameState.flags["secretary_met"] = true
			GameState.add_task("Gather Scholarship Requirements")

			await get_tree().create_timer(0.1).timeout
			DialogueManager.start_dialogue("res://Data/Dialogue/Secretary/Secretary_Initial.json")

func _process(_delta):
	if GameState.time >= 16 * 60:
		if is_inside_tree():
			_show_office_closed()
			get_tree().change_scene_to_file("res://Scenes/Reusable/Map/School.tscn")

func _show_office_closed():
	var popup := AcceptDialog.new()
	popup.title = ""
	popup.dialog_text = "🔒 The secretary has left for the day."
	add_child(popup)
	popup.popup_centered()

func start_interaction():
	var choice_panel = choice_panel_scene.instantiate()

	var options = [
		{ "text": "Ask about scholarship", "id": "talk" },
		{ "text": "Print a document", "id": "print" },
		{ "text": "Submit documents", "id": "submit" },
		{ "text": "Go back", "id": "back" }
	]
	add_child(choice_panel)
	choice_panel.show_options(options, Callable(self, "_on_choice_selected"))

func _on_choice_selected(choice_id):
	match choice_id:
		"talk":
			DialogueManager.start_dialogue("res://Data/Dialogue/Secretary/Secretary_Talk.json")
		"print":
			show_printable_options()
		"submit":
			if GameState.day >= 4:
				DialogueManager.start_dialogue("res://Data/Dialogue/Secretary/Secretary_Submit.json")
			else:
				var popup := AcceptDialog.new()
				popup.title = ""
				popup.dialog_text = "You can only submit documents later this week."
				add_child(popup)
				popup.popup_centered()
		"back":
			# Exit dialogue only, no scene change
			pass

func show_printable_options():
	var options = []

	if GameState.has_feature("transcript") and not GameState.flags.has("printed_transcript"):
		options.append({ "text": "Print transcript (10$)", "id": "transcript" })

	if GameState.has_feature("final_project") and not GameState.flags.has("printed_project"):
		options.append({ "text": "Print final project (10$)", "id": "project" })

	if GameState.has_feature("cv") and not GameState.flags.has("printed_cv"):
		options.append({ "text": "Print CV (10$)", "id": "cv" })

	if options.is_empty():
		var popup := AcceptDialog.new()
		popup.title = ""
		popup.dialog_text = "You have nothing to print right now."
		add_child(popup)
		popup.popup_centered()
		return

	var print_choices = choice_panel_scene.instantiate()
	add_child(print_choices)
	print_choices.show_options(options, Callable(self, "_on_print_selected"))

func _on_print_selected(id):
	if GameState.money < 10:
		var popup := AcceptDialog.new()
		popup.title = ""
		popup.dialog_text = "You don’t have enough money to print."
		add_child(popup)
		popup.popup_centered()
		return

	GameState.money -= 10

	match id:
		"transcript":
			GameState.flags["printed_transcript"] = true
			GameState.update_task_step("Gather Scholarship Requirements")
		"project":
			GameState.flags["printed_project"] = true
			GameState.update_task_step("Gather Scholarship Requirements")
		"cv":
			GameState.flags["printed_cv"] = true
			GameState.update_task_step("Gather Scholarship Requirements")

	var popup := AcceptDialog.new()
	popup.title = ""
	popup.dialog_text = "📄 Document printed successfully!"
	add_child(popup)
	popup.popup_centered()
