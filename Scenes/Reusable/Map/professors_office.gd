extends Control

@onready var professor_btn: Node = $background/Professor
@onready var janitor_btn: Node   = $background/Janitor
@onready var back_btn: Button    = $background/Back
@onready var choice_panel_scene: PackedScene = preload("res://Scenes/Reusable/CharacterChoiceButtons.tscn")

const D_PROF := "res://Data/Dialogue/Professor/"
const JSON_PROF_INITIAL    := D_PROF + "Prof_Office_Initial.json"
const JSON_PROF_NOT_HERE   := D_PROF + "Prof_NotHere.json"
const JSON_PROF_SUBMIT     := D_PROF + "Prof_Submit_Generic.json"
const JSON_PROF_FOLLOWUP   := D_PROF + "Prof_Followup_Accepted.json"

const JSON_JANITOR_TIPPED  := D_PROF + "Janitor_Office_Tipped_Intro.json"
const JSON_JANITOR_NOTIP   := D_PROF + "Janitor_Office_NoTip_Intro.json"
const JSON_JANITOR_HIGHREP := D_PROF + "Janitor_Office_NoAccess_HighRep.json"

const T_13_00 := 13 * 60
const T_15_00 := 15 * 60
const T_17_00 := 17 * 60
const T_17_45 := 17 * 60 + 45

const TASK_PROJECT := "project"

var _panel: Control = null

func _ready() -> void:
	GameState.location = "ProfessorOffice"

	# Start hidden; we toggle by schedule
	professor_btn.visible = false
	janitor_btn.visible   = false

	# Hook buttons (TextureButton/Button both expose "pressed")
	if professor_btn and professor_btn.has_signal("pressed"):
		professor_btn.connect("pressed", Callable(self, "_on_professor_pressed"))
	if janitor_btn and janitor_btn.has_signal("pressed"):
		janitor_btn.connect("pressed", Callable(self, "_on_janitor_pressed"))
	back_btn.pressed.connect(_on_back_pressed)

	_update_presence()
	_maybe_show_not_here_on_enter()  # no "locked" here; door handles that

func _process(_delta: float) -> void:
	_update_presence()

# ---------- Presence ----------
func _update_presence() -> void:
	var d: int = GameState.day
	var t: int = GameState.time

	# Professor visible Day 1 (13–15) for intro; Day ≥2 (13–15) for submit/follow-up
	var prof_visible: bool = ((d == 1 and _in(t, T_13_00, T_15_00)) or (d >= 2 and _in(t, T_13_00, T_15_00)))
	professor_btn.visible = prof_visible

	# Janitor in this office only Day 1–2, 17:00–17:45
	var jan_vis: bool = (d >= 1 and d <= 2 and _in(t, T_17_00, T_17_45))
	janitor_btn.visible = jan_vis

func _in(now: int, start_incl: int, end_excl: int) -> bool:
	return now >= start_incl and now < end_excl

func _maybe_show_not_here_on_enter() -> void:
	# Day 1, 15:00–17:00 the office is open but Professor is away
	if GameState.day == 1 and _in(GameState.time, T_15_00, T_17_00):
		DialogueManager.start_dialogue(JSON_PROF_NOT_HERE, self)

# ---------- Professor ----------
func _on_professor_pressed() -> void:
	_clear_panel()

	var d: int = GameState.day
	var t: int = GameState.time
	var options: Array = []

	if d == 1 and _in(t, T_13_00, T_15_00):
		options.append({ "text": "Talk to Professor", "id": "talk_initial" })
	elif d >= 2 and _in(t, T_13_00, T_15_00):
		if _project_ready_for_submit():
			options.append({ "text": "Submit Final Project", "id": "submit" })
		options.append({ "text": "Talk", "id": "talk_followup" })
	else:
		# Outside prof windows (but inside scene): show "not here" if relevant
		if GameState.day == 1 and _in(GameState.time, T_15_00, T_17_00):
			DialogueManager.start_dialogue(JSON_PROF_NOT_HERE, self)
		return

	options.append({ "text": "Back", "id": "back" })

	_panel = choice_panel_scene.instantiate()
	add_child(_panel)
	_panel.call("show_options", options, Callable(self, "_on_professor_choice"))

func _on_professor_choice(id: String) -> void:
	match id:
		"talk_initial":
			DialogueManager.start_dialogue(JSON_PROF_INITIAL, self)
			_clear_panel()
		"talk_followup":
			if GameState.tasks.has(TASK_PROJECT):
				DialogueManager.start_dialogue(JSON_PROF_FOLLOWUP, self)
			else:
				DialogueManager.start_dialogue(JSON_PROF_INITIAL, self)
			_clear_panel()
		"submit":
			DialogueManager.start_dialogue(JSON_PROF_SUBMIT, self)
			_clear_panel()
		"back":
			_clear_panel()

func _project_ready_for_submit() -> bool:
	var prog: int = GameState.get_task_progress(TASK_PROJECT)
	return prog >= 2 and not GameState.has_flag("project_submitted")

# ---------- Janitor (Day 1–2, 17:00–17:45) ----------
func _on_janitor_pressed() -> void:
	_clear_panel()
	var has_tip: bool = GameState.has_flag("janitor_tip") or GameState.has_flag("tipped_by_marko") or GameState.has_flag("marko_tip")
	var rep: int = GameState.reputation

	if has_tip:
		DialogueManager.start_dialogue(JSON_JANITOR_TIPPED, self)
	elif rep >= 30:
		DialogueManager.start_dialogue(JSON_JANITOR_HIGHREP, self)
	else:
		DialogueManager.start_dialogue(JSON_JANITOR_NOTIP, self)

# ---------- Back ----------
func _on_back_pressed() -> void:
	if GameState.is_time_frozen():
		print("⏸️ Finish the conversation first.")
		return
	get_tree().change_scene_to_file("res://Scenes/Reusable/Map/School.tscn")

# ---------- Helpers ----------
func _clear_panel() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null

func on_dialogue_action(line: Dictionary) -> void:
	GameState.apply_action(line)
