extends Control

@onready var dialogue_label = $"Dialogue Box/Control2/Dialogue"
@onready var speaker_label = $"Speaker Box/SpeakerLABEL"
@onready var portrait = $"Dialogue Box/Control/PlaceHolderFrame"
@onready var choices_box = $"Choice Control Node/ChoiceBox"

@onready var choice_buttons := [
	choices_box.get_node("Button"),
	choices_box.get_node("Button2"),
	choices_box.get_node("Button3"),
	choices_box.get_node("Button4"),
	choices_box.get_node("Button5")
]

@export var portraits := {
	"teacher": preload("res://Images/CharacterFrames/KlasenFrame.png"),
	"principal": preload("res://Images/CharacterFrames/direktorframe.png"),
	"secretary": preload("res://Images/CharacterFrames/secretaryframe.png"),
	"janitor": preload("res://Images/CharacterFrames/JanitorFrame.png"),
	"professor": preload("res://Images/CharacterFrames/Prof1Frame.png"),
	"marko": preload("res://Images/CharacterFrames/MarkoFrame.png"),
	"mvrclerk": preload("res://Images/CharacterFrames/MvrClerkFrame.png")
}

var dialogue_data: Array = []
var line_index := 0
var is_typing := false
var typing_speed := 0.04 # slower now
var selected_ids: Array = []
var max_select := 1
var caller: Node = null

func start(lines: Array, caller_node: Node = null):
	dialogue_data = lines
	caller = caller_node
	line_index = 0
	show()
	display_next()

func _unhandled_input(event):
	if event.is_action_pressed("ui_accept") and not choices_box.visible and not is_typing:
		display_next()

func display_next():
	if line_index >= dialogue_data.size():
		queue_free()
		return

	var line = dialogue_data[line_index]

	# Handle scene_transition only when it's a standalone line
	if line.has("scene_transition") and not line.has("text"):
		if caller:
			await caller.call("on_scene_transition", line["scene_transition"])
		line_index += 1
		display_next()
		return

	if line.has("text"):
		speaker_label.text = line.get("speaker", "")
		_update_portrait(speaker_label.text)
		await _type_text(line["text"])
		await get_tree().create_timer(0.5).timeout
		line_index += 1
		display_next()
	elif line.has("choice_type"):
		show_choices(line)
		return
	elif line.has("action"):
		if caller:
			caller.call("on_dialogue_action", line)
		line_index += 1
		display_next()
	else:
		line_index += 1
		display_next()

func _type_text(text: String) -> void:
	is_typing = true
	dialogue_label.text = ""
	for i in range(text.length()):
		dialogue_label.text += text[i]
		await get_tree().create_timer(typing_speed).timeout
	is_typing = false

func show_choices(line: Dictionary):
	selected_ids.clear()
	max_select = int(line.get("max_select", 1))

	for btn in choice_buttons:
		btn.hide()
		btn.text = ""
		btn.disabled = true
		for conn in btn.pressed.get_connections():
			btn.pressed.disconnect(conn.callable)

	var options = line["options"]
	var num_options = min(options.size(), choice_buttons.size())

	for i in range(num_options):
		var btn = choice_buttons[choice_buttons.size() - 1 - i]
		var opt = options[i]
		btn.text = opt["text"]
		btn.disabled = false
		btn.show()

		btn.pressed.connect(func():
			if selected_ids.has(opt["id"]):
				return

			selected_ids.append(opt["id"])
			btn.disabled = true

			if selected_ids.size() == max_select:
				if caller and caller.has_method("on_choices_selected"):
					caller.on_choices_selected(selected_ids)
				choices_box.hide()
				line_index += 1
				display_next()
		)

func _update_portrait(speaker: String):
	var key = speaker.strip_edges().to_lower()
	if portraits.has(key):
		portrait.texture = portraits[key]
	else:
		portrait.texture = null
