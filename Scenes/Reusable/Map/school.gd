extends Control

const CCB_SCENE_PATH := "res://Scenes/Reusable/CharacterChoiceButtons.tscn"

# --- Paths for each location ---
const CLASSROOM_SCENE := "res://Scenes/Reusable/Map/classroom.tscn"
const PROFESSOR_OFFICE_SCENE := "res://Scenes/Reusable/Map/ProfessorOffice.tscn"
const SECRETARY_OFFICE_SCENE := "res://Scenes/Reusable/Map/SecretaryOffice.tscn"
const CITY_SCENE := "res://Scenes/Reusable/Map/City.tscn"

# --- Time limits (minutes from 00:00) ---
const PROFESSOR_OPEN := 13 * 60
const PROFESSOR_CLOSE := 18 * 60
const SECRETARY_OPEN := 13 * 60
const SECRETARY_CLOSE := 18 * 60

# Classroom has custom rules (handled in _try_enter_classroom)
const CLASS_LOCK_START := 8 * 60 + 30    # 08:30
const CLASS_LOCK_END := 12 * 60 + 30     # 12:30

@onready var popup_label: Label = $PopUp
@onready var show_menu_button: Button = $background/ShowMenuButton

var _panel: Control = null

func _ready() -> void:
	if GameState.subject1.strip_edges() == "":
		GameState.subject1 = "Geography"
	if GameState.subject2.strip_edges() == "":
		GameState.subject2 = "Math"

	GameUi.visible = true
	GameState.location = "School"
	popup_label.visible = false
	show_menu_button.pressed.connect(_show_menu)

func _show_menu() -> void:
	_clear_panel()
	var options = [
		{ "text": "Classroom", "id": "classroom" },
		{ "text": "Professor Office", "id": "prof_office" },
		{ "text": "Secretary Office", "id": "sec_office" },
		{ "text": "City", "id": "city" },
		{ "text": "Back", "id": "back" }
	]
	_panel = preload(CCB_SCENE_PATH).instantiate()
	add_child(_panel)
	_panel.call("show_options", options, Callable(self, "_on_choice"))

func _on_choice(id: String) -> void:
	match id:
		"classroom":
			_try_enter_classroom()
		"prof_office":
			_try_enter_generic(PROFESSOR_OFFICE_SCENE, PROFESSOR_OPEN, PROFESSOR_CLOSE,
				"The professor's office is closed.")
		"sec_office":
			_try_enter_generic(SECRETARY_OFFICE_SCENE, SECRETARY_OPEN, SECRETARY_CLOSE,
				"The secretary's office is closed.")
		"city":
			get_tree().change_scene_to_file(CITY_SCENE)
		"back":
			_clear_panel()

func _try_enter_generic(scene_path: String, open_time: int, close_time: int, closed_msg: String) -> void:
	var now: int = GameState.time
	if now >= open_time and now < close_time:
		get_tree().change_scene_to_file(scene_path)
	else:
		var open_str := _minutes_to_time_str(open_time)
		var close_str := _minutes_to_time_str(close_time)
		popup_label.text = "%s (Open: %s – %s)" % [closed_msg, open_str, close_str]
		popup_label.visible = true
	_clear_panel()

func _try_enter_classroom() -> void:
	var d: int = GameState.day
	var t: int = GameState.time

	# Day 1: allow 12:30–18:00 so the Classroom scene can show the "empty classroom" JSON inside.
	if d == 1:
		if t >= 12 * 60 + 30 and t < 18 * 60:
			get_tree().change_scene_to_file(CLASSROOM_SCENE)
		else:
			# still closed; just inform
			var ui := DialogueManager.start_dialogue("res://Data/Classroom/Class_Locked.json", self)
		_clear_panel()
		return

	# Day 2–4: lock during 08:30–12:30 (run the Narrator lock JSON instead of popup)
	if t >= (8 * 60 + 30) and t < (12 * 60 + 30):
		DialogueManager.start_dialogue("res://Data/Classroom/Class_Locked.json", self)
		_clear_panel()
		return

	# Otherwise allowed (morning 08:00–08:30; afternoons/evenings)
	get_tree().change_scene_to_file(CLASSROOM_SCENE)
	_clear_panel()


func _minutes_to_time_str(minutes: int) -> String:
	var hours := int(minutes / 60)
	var mins := int(minutes % 60)
	return "%02d:%02d" % [hours, mins]

func _clear_panel() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null
