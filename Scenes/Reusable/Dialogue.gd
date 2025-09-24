extends Control

signal dialogue_finished
signal choices_requested(options: Array, max_select: int) # external UI can listen

@onready var dialogue_label: RichTextLabel = $"Dialogue Box/Control2/Dialogue"  # BBCode already enabled in Inspector
@onready var speaker_label: Label = $"Speaker Box/SpeakerLABEL"
@onready var portrait: TextureRect = $"Dialogue Box/Control/PlaceHolderFrame"

# Optional: export an italic font for Narrator lines
@export var narrator_italic_font: Font

var portraits: Dictionary = {
	tr("homeroom teacher"): preload("res://Images/CharacterFrames/KlasenFrame.png"),
	tr("principal"):        preload("res://Images/CharacterFrames/direktorframe.png"),
	tr("secretary"):        preload("res://Images/CharacterFrames/secretaryframe.png"),
	tr("janitor"):          preload("res://Images/CharacterFrames/JanitorFrame.png"),
	tr("professor"):        preload("res://Images/CharacterFrames/Prof1Frame.png"),
	tr("marko"):            preload("res://Images/CharacterFrames/MarkoFrame.png"),
	tr("clerk"):            preload("res://Images/CharacterFrames/MvrClerkFrame.png"),
	tr("daniel"):           preload("res://Images/CharacterFrames/DanielFrame.png")
}


var dialogue_data: Array = []
var line_index: int = 0
var is_typing: bool = false
var typing_speed: float = 0.04
var caller: Node = null

var _waiting_for_external_choice := false
var _pending_choice_options: Array = []
var _pending_max_select: int = 1

func start(lines: Array, caller_node: Node = null) -> void:
	dialogue_data = lines
	caller = caller_node
	line_index = 0

	# If you supplied an italic font, make sure the label knows to use it for [i] tags too.
	if narrator_italic_font:
		dialogue_label.add_theme_font_override("italics_font", narrator_italic_font)
		dialogue_label.add_theme_font_override("bold_italics_font", narrator_italic_font)

	dialogue_label.clear() # BBCode already enabled in Inspector
	show()
	display_next()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and not is_typing and not _waiting_for_external_choice:
		display_next()

func display_next() -> void:
	if line_index >= dialogue_data.size():
		emit_signal("dialogue_finished")
		queue_free()
		return

	var line: Dictionary = dialogue_data[line_index]

	# Scene transition (no text)
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

		# Narrator = italics (empty speaker also treated as Narrator)
		var sp_key := show_speaker.strip_edges().to_lower()
		var narrator_line := (sp_key == "" or sp_key == tr("narrator"))

		await _type_text(show_text, narrator_line)
		await get_tree().create_timer(0.5).timeout
		line_index += 1
		display_next()
		return

	# Choice request → hand off to external UI and pause here
	if line.has("choice_type"):
		_request_external_choices(line)
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

# ---------- Typing with reliable italics ----------
# If you exported a narrator_italic_font, we push it on the stack while typing.
# Otherwise, we wrap with [i]...[/i] so it still renders italic if the label has an 'Italics Font' override.
func _type_text(text: String, italics: bool=false) -> void:
	is_typing = true
	dialogue_label.clear()

	if italics and narrator_italic_font and dialogue_label.has_method("push_font"):
		# Use the supplied italic font directly.
		dialogue_label.push_font(narrator_italic_font)
		for i in range(text.length()):
			dialogue_label.append_text(text.substr(i, 1))
			await get_tree().create_timer(typing_speed).timeout
		dialogue_label.pop()
	elif italics:
		# BBCode fallback: ensure the label knows what font to use (see start()).
		dialogue_label.text = "[i]" + text + "[/i]"
		dialogue_label.visible_characters = 0
		for i in range(text.length()):
			dialogue_label.visible_characters = i + 1
			await get_tree().create_timer(typing_speed).timeout
	else:
		# Normal typing
		for i in range(text.length()):
			dialogue_label.append_text(text.substr(i, 1))
			await get_tree().create_timer(typing_speed).timeout

	is_typing = false

# ---------- External choices flow ----------
func _request_external_choices(line: Dictionary) -> void:
	_pending_choice_options = []
	_pending_max_select = int(line.get("max_select", 1))

	# Accept "options": [{id,text}, ...] or ["Math","Physics",...]
	var opt_raw = line.get("options", [])
	if opt_raw is Array:
		for o in opt_raw:
			if typeof(o) == TYPE_DICTIONARY:
				var id := String(o.get("id",""))
				var text := String(o.get("text", id))
				if id == "" and text != "":
					id = text
				_pending_choice_options.append({"id": id, "text": text})
			else:
				var s := String(o)
				_pending_choice_options.append({"id": s, "text": s})

	_waiting_for_external_choice = true

	emit_signal("choices_requested", _pending_choice_options, _pending_max_select)

	if caller and caller.has_method("on_dialogue_action"):
		var normalized := {
			"action": "show_choices",
			"options": _pending_choice_options,
			"max_select": _pending_max_select
		}
		caller.call("on_dialogue_action", normalized)

# Call this from your controller after the player picks via CharacterChoiceButtons
func apply_choices(selected: Array) -> void:
	if not _waiting_for_external_choice:
		return
	_waiting_for_external_choice = false

	if caller and caller.has_method("on_choices_selected"):
		caller.call("on_choices_selected", selected)

	line_index += 1
	display_next()

# Alias for controllers that call "receive_choice(...)"
func receive_choice(selected: Array) -> void:
	apply_choices(selected)

# ---------- Portraits ----------
func _update_portrait(speaker: String) -> void:
	var key := speaker.strip_edges().to_lower()
	if key == "narrator" or key == "":
		portrait.texture = null
		return
	if portraits.has(key):
		portrait.texture = portraits[key]
	else:
		portrait.texture = null
