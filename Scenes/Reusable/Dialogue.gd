extends Control

signal dialogue_finished

@onready var dialogue_label: RichTextLabel = $"Dialogue Box/Control2/Dialogue"
@onready var speaker_label: Label = $"Speaker Box/SpeakerLABEL"
@onready var portrait: TextureRect = $"Dialogue Box/Control/PlaceHolderFrame"
@onready var choices_box: Control = $"Choice Control Node/ChoiceBox"

@onready var choice_buttons: Array[Button] = [
	choices_box.get_node("Button") as Button,
	choices_box.get_node("Button2") as Button,
	choices_box.get_node("Button3") as Button,
	choices_box.get_node("Button4") as Button,
	choices_box.get_node("Button5") as Button
]

@export var portraits: Dictionary = {
	"teacher":   preload("res://Images/CharacterFrames/KlasenFrame.png"),
	"principal": preload("res://Images/CharacterFrames/direktorframe.png"),
	"secretary": preload("res://Images/CharacterFrames/secretaryframe.png"),
	"janitor":   preload("res://Images/CharacterFrames/JanitorFrame.png"),
	"professor": preload("res://Images/CharacterFrames/Prof1Frame.png"),
	"marko":     preload("res://Images/CharacterFrames/MarkoFrame.png"),
	"mvrclerk":  preload("res://Images/CharacterFrames/MvrClerkFrame.png")
}

var dialogue_data: Array = []
var line_index: int = 0
var is_typing: bool = false
var typing_speed: float = 0.04
var selected_ids: Array[String] = []
var max_select: int = 1
var caller: Node = null

func start(lines: Array, caller_node: Node = null) -> void:
	dialogue_data = lines
	caller = caller_node
	line_index = 0
	show()
	display_next()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and not choices_box.visible and not is_typing:
		display_next()

func display_next() -> void:
	if line_index >= dialogue_data.size():
		emit_signal("dialogue_finished")
		queue_free()
		return

	var line: Dictionary = dialogue_data[line_index]

	# Scene transition (rare)
	if line.has("scene_transition") and not line.has("text"):
		if caller and caller.has_method("on_scene_transition"):
			await caller.call("on_scene_transition", String(line["scene_transition"]))
		line_index += 1
		display_next()
		return

	# Spoken line
	if line.has("text"):
		var raw_speaker := String(line.get("speaker", ""))
		var raw_text := String(line.get("text", ""))

		var show_speaker := GameState.format_placeholders(raw_speaker)
		var show_text := GameState.format_placeholders(raw_text)

		speaker_label.text = show_speaker
		_update_portrait(speaker_label.text)

		await _type_text(show_text)
		await get_tree().create_timer(0.5).timeout
		line_index += 1
		display_next()
		return

	# Choices
	if line.has("choice_type"):
		show_choices(line)
		return

	# Action (let caller handle; fallback to GameState)
	if line.has("action"):
		if caller and caller.has_method("on_dialogue_action"):
			caller.call("on_dialogue_action", line)
		else:
			GameState.apply_action(line)
		line_index += 1
		display_next()
		return

	# Fallback
	line_index += 1
	display_next()

func _type_text(text: String) -> void:
	is_typing = true
	dialogue_label.text = ""
	for i in range(text.length()):
		dialogue_label.text += text[i]
		await get_tree().create_timer(typing_speed).timeout
	is_typing = false

func show_choices(line: Dictionary) -> void:
	selected_ids.clear()
	max_select = int(line.get("max_select", 1))

	for btn in choice_buttons:
		btn.hide()
		btn.text = ""
		btn.disabled = true
		for conn in btn.pressed.get_connections():
			btn.pressed.disconnect(conn.callable)

	var options: Array = line["options"]
	var num_options: int = min(options.size(), choice_buttons.size())

	for i in range(num_options):
		var btn: Button = choice_buttons[choice_buttons.size() - 1 - i]
		var opt: Dictionary = options[i]
		btn.text = GameState.format_placeholders(String(opt.get("text","")))
		btn.disabled = false
		btn.show()

		btn.pressed.connect(func() -> void:
			var opt_id := String(opt.get("id",""))
			if selected_ids.has(opt_id):
				return
			selected_ids.append(opt_id)
			btn.disabled = true
			if selected_ids.size() == max_select:
				if caller and caller.has_method("on_choices_selected"):
					caller.on_choices_selected(selected_ids)
				choices_box.hide()
				line_index += 1
				display_next()
		)

func _update_portrait(speaker: String) -> void:
	var key := speaker.strip_edges().to_lower()
	if portraits.has(key):
		portrait.texture = portraits[key]
	else:
		portrait.texture = null
