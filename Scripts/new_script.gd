extends Control

@onready var dialogue_label = $DialogueBox/Control2/Dialogue
@onready var speaker_label = $DialogueBox/SpeakerBox/SpeakerLABEL
@onready var portrait = $DialogueBox/Control/PlaceHolderFrame
@onready var choices_box = $ChoiceControlNode
@onready var confirm_button = $ChoiceControlNode/ConfirmButton

# These will be set via the editor (drag your textures here)
@export var Homeroomteacher: Texture2D
@export var Director: Texture2D
@export var Secretary: Texture2D
@export var MVRclerk: Texture2D
@export var Professor: Texture2D
@export var Daniel: Texture2D
@export var Marko: Texture2D
@export var Janitor: Texture2D

var dialogue_data = []
var line_index := 0
var selected_ids := []

func start(data: Array):
	dialogue_data = data
	line_index = 0
	show()
	display_next()

func _unhandled_input(event):
	if event.is_action_pressed("ui_accept") and not choices_box.visible:
		display_next()

func display_next():
	if line_index >= dialogue_data.size():
		queue_free()
		return

	var line = dialogue_data[line_index]

	if line.has("text"):
		speaker_label.text = line.get("speaker", "")
		dialogue_label.text = line["text"]
		_update_portrait(speaker_label.text)
	elif line.has("choice_type"):
		show_multi_select(line)
		return
	elif line.has("action"):
		process_action(line)
		line_index += 1
		display_next()
		return

	line_index += 1

func show_multi_select(line):
	choices_box.show()
	confirm_button.show()
	selected_ids.clear()

	for btn in choices_box.get_children():
		if btn != confirm_button:
			btn.queue_free()

	for opt in line["options"]:
		var b = Button.new()
		b.text = opt["text"]
		b.toggle_mode = true
		b.pressed.connect(func(): _on_choice_pressed(opt["id"], b))
		choices_box.add_child(b)

	confirm_button.pressed.connect(_on_confirm_pressed.bind(line))

func _on_choice_pressed(id, button):
	if button.button_pressed:
		selected_ids.append(id)
	else:
		selected_ids.erase(id)

func _on_confirm_pressed(line):
	if selected_ids.size() != line["max_select"]:
		print("You must select exactly %d option(s)." % line["max_select"])
		return

	GameState.selected_subjects = selected_ids.duplicate()
	choices_box.hide()
	confirm_button.hide()
	display_next()

func process_action(line):
	match line["action"]:
		"add_task":
			for task in line["tasks"]:
				GameState.add_task(task)
		"adjust_time":
			GameState.adjust_time(line["value"])
		"schedule_event":
			GameState.schedule_event(line["event"], line["day"], line["time"])
		"unlock_feature":
			GameState.unlock_feature(line["feature"])
		"load_scene":
			get_tree().change_scene_to_file(line["scene"])

func _update_portrait(speaker: String):
	match speaker.to_lower():
		"homeroomteacher":
			portrait.texture = Homeroomteacher
		"principal", "director":
			portrait.texture = Director
		"secretary":
			portrait.texture = Secretary
		"mvrclerk":
			portrait.texture = MVRclerk
		"professor":
			portrait.texture = Professor
		"daniel":
			portrait.texture = Daniel
		"marko":
			portrait.texture = Marko
		"janitor":
			portrait.texture = Janitor
		_:
			portrait.texture = null  # or keep the current one
