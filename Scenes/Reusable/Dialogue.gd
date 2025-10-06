extends Control

signal dialogue_finished
signal choices_requested(options: Array, max_select: int)

@onready var dialogue_label: RichTextLabel = $"Dialogue Box/Control2/Dialogue"  # BBCode enabled in Inspector
@onready var speaker_label: Label          = $"Speaker Box/SpeakerLABEL"
@onready var portrait: TextureRect         = $"Dialogue Box/Control/PlaceHolderFrame"
@onready var timerr: Timer                 = $"change_text"

@export var narrator_italic_font: Font
@export var typing_speed: float = 0.04

var portraits: Dictionary = {
	"homeroom teacher": preload("res://Images/CharacterFrames/KlasenFrame.png"),
	"класен раководител": preload("res://Images/CharacterFrames/KlasenFrame.png"),
	"principal": preload("res://Images/CharacterFrames/direktorframe.png"),
	"директор": preload("res://Images/CharacterFrames/direktorframe.png"),
	"secretary": preload("res://Images/CharacterFrames/secretaryframe.png"),
	"секретарка": preload("res://Images/CharacterFrames/secretaryframe.png"),
	"janitor": preload("res://Images/CharacterFrames/JanitorFrame.png"),
	"хигиеничар": preload("res://Images/CharacterFrames/JanitorFrame.png"),
	"professor": preload("res://Images/CharacterFrames/Prof1Frame.png"),
	"професор": preload("res://Images/CharacterFrames/Prof1Frame.png"),
	"marko": preload("res://Images/CharacterFrames/MarkoFrame.png"),
	"марко": preload("res://Images/CharacterFrames/MarkoFrame.png"),
	"clerk": preload("res://Images/CharacterFrames/MvrClerkFrame.png"),
	"шалтерски службеник": preload("res://Images/CharacterFrames/MvrClerkFrame.png"),
	"daniel": preload("res://Images/CharacterFrames/DanielFrame.png"),
	"даниел": preload("res://Images/CharacterFrames/DanielFrame.png"),
	"narrator": null, "наратор": null
}

var dialogue_data: Array = []
var line_index: int = 0
var is_typing: bool = false
var caller: Node = null

var _waiting_for_external_choice := false
var _pending_choice_options: Array = []
var _pending_max_select: int = 1

# reentrancy / spam guards
var _advancing := false
var _last_advance_time := 0.0
const ADV_DEBOUNCE := 0.08  # seconds

func _ready() -> void:
	# Make the label inert to selection/scroll/hover while we animate it
	dialogue_label.selection_enabled = false
	dialogue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_label.focus_mode = Control.FOCUS_NONE
	dialogue_label.text_direction = Control.TEXT_DIRECTION_LTR  # you’re using Cyrillic LTR; keeps BiDi stable
	dialogue_label.structured_text_bidi_override = TextServer.STRUCTURED_TEXT_DEFAULT

func start(lines: Array, caller_node: Node = null) -> void:
	dialogue_data = lines
	caller = caller_node
	line_index = 0

	if narrator_italic_font:
		dialogue_label.add_theme_font_override("italics_font", narrator_italic_font)
		dialogue_label.add_theme_font_override("bold_italics_font", narrator_italic_font)

	dialogue_label.clear()
	dialogue_label.deselect()
	show()
	display_next()

func _unhandled_input(event: InputEvent) -> void:
	# Eat Ctrl + MouseWheel (prevents accidental zoom/scroll style interactions on some setups)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.ctrl_pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			accept_event()
			return

	if event.is_action_pressed("ui_accept"):
		accept_event()  # stop propagation
		var now := Time.get_ticks_msec() / 1000.0
		if now - _last_advance_time < ADV_DEBOUNCE:
			return
		_last_advance_time = now

		if not is_typing and not _waiting_for_external_choice:
			display_next()

func display_next() -> void:
	if _advancing:
		return
	_advancing = true

	if line_index >= dialogue_data.size():
		_advancing = false
		emit_signal("dialogue_finished")
		queue_free()
		return

	var line: Dictionary = dialogue_data[line_index]

	# scene transition without text
	if line.has("scene_transition") and not line.has("text"):
		if caller and caller.has_method("on_scene_transition"):
			await caller.call("on_scene_transition", String(line["scene_transition"]))
		line_index += 1
		_advancing = false
		display_next()
		return

	# spoken line
	if line.has("text"):
		var raw_speaker := String(line.get("speaker", ""))
		var raw_text := String(line.get("text", ""))

		var show_speaker := GameState.format_placeholders(raw_speaker)
		var show_text := GameState.format_placeholders(raw_text)

		speaker_label.text = show_speaker
		_update_portrait(speaker_label.text)

		var sp_key := show_speaker.strip_edges().to_lower()
		var narrator_line := (sp_key == "" or sp_key == tr("narrator") or sp_key == "наратор")

		await _type_text(show_text, narrator_line)

		# small post-line pause (keeps your original pacing via the Timer node)
		if is_instance_valid(timerr):
			timerr.start()  # use the scene’s timer as before
			await timerr.timeout
		else:
			await get_tree().create_timer(0.35).timeout

		line_index += 1
		_advancing = false
		display_next()
		return

	# choices → external UI
	if line.has("choice_type"):
		_request_external_choices(line)
		_advancing = false
		return

	# action (caller first, fallback to GameState)
	if line.has("action"):
		if caller and caller.has_method("on_dialogue_action"):
			caller.call("on_dialogue_action", line)
		else:
			GameState.apply_action(line)
		line_index += 1
		_advancing = false
		display_next()
		return

	# fallback
	line_index += 1
	_advancing = false
	display_next()

# unified typing: set once, reveal with visible_characters (stable shaping, no backwards glyphs)
func _type_text(text: String, italics: bool = false) -> void:
	is_typing = true
	dialogue_label.deselect()
	dialogue_label.scroll_to_line(0)  # ensure top; avoid flicker

	var bb: String = ""
	if italics:
		bb = "[i]" + text + "[/i]"
	else:
		bb = text

	dialogue_label.bbcode_text = bb
	dialogue_label.visible_characters = 0

	var total := text.length()
	for i in range(total):
		dialogue_label.visible_characters = i + 1
		await get_tree().create_timer(typing_speed).timeout

	is_typing = false


# ---------- External choices flow ----------
func _request_external_choices(line: Dictionary) -> void:
	_pending_choice_options = []
	_pending_max_select = int(line.get("max_select", 1))

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

func apply_choices(selected: Array) -> void:
	if not _waiting_for_external_choice:
		return
	_waiting_for_external_choice = false

	if caller and caller.has_method("on_choices_selected"):
		caller.call("on_choices_selected", selected)

	line_index += 1
	display_next()

func receive_choice(selected: Array) -> void:
	apply_choices(selected)

# ---------- Portraits ----------
func _update_portrait(speaker: String) -> void:
	var key := speaker.strip_edges().to_lower()
	if key == tr("narrator") or key == "":
		portrait.texture = null
		return
	if portraits.has(key):
		portrait.texture = portraits[key]
	else:
		portrait.texture = null
