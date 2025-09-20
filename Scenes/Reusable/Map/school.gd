extends Control 

const CCB_SCENE_PATH := "res://Scenes/Reusable/CharacterChoiceButtons.tscn"

# --- Paths for each location ---
const CLASSROOM_SCENE := "res://Scenes/Reusable/Map/classroom.tscn"
const PROFESSOR_OFFICE_SCENE := "res://Scenes/Reusable/Map/ProfessorOffice.tscn"
const SECRETARY_OFFICE_SCENE := "res://Scenes/Reusable/Map/SecretaryOffice.tscn"
const CITY_SCENE := "res://Scenes/Reusable/Map/City.tscn"

# --- Time limits (minutes from 00:00) ---
const PROFESSOR_OPEN := 13 * 60
const PROFESSOR_CLOSE := 19 * 60
const SECRETARY_OPEN := 13 * 60
const SECRETARY_CLOSE := 19 * 60

# Classroom lock window (Days 2–4) for morning classes
const CLASS_LOCK_START := 8 * 60 + 30   # 08:30
const CLASS_LOCK_END   := 12 * 60 + 30  # 12:30

# Campus hard close (everything)
const CAMPUS_CLOSE := 19 * 60           # 19:00

# Narrated “locked” dialogue (only for 08:30–12:30 tries)
const CLASS_LOCKED_JSON := "res://Data/Classroom/Classroom_Door_Locked.json"

@onready var popup_label: Label = $PopUp
@onready var show_menu_button: Button = $background/ShowMenuButton

var _panel: Control = null

# Fade overlay
var _fade_layer: CanvasLayer = null
var _fade_rect: ColorRect = null

func _ready() -> void:
	if GameState.subject1.strip_edges() == "":
		GameState.subject1 = "math"
	if GameState.subject2.strip_edges() == "":
		GameState.subject2 = "geography"

	GameUi.visible = true
	GameState.location = "School"
	popup_label.visible = false
	show_menu_button.pressed.connect(_show_menu)

	# If campus is closed already, kick out immediately
	if GameState.time >= CAMPUS_CLOSE:
		_kick_out_of_school()
		return

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
			_try_enter_generic(PROFESSOR_OFFICE_SCENE, PROFESSOR_OPEN, PROFESSOR_CLOSE, "The professor's office is closed.")
		"sec_office":
			_try_enter_generic(SECRETARY_OFFICE_SCENE, SECRETARY_OPEN, SECRETARY_CLOSE, "The secretary's office is closed.")
		"city":
			_fade_and_change_scene(CITY_SCENE)
		"back":
			_clear_panel()

func _try_enter_generic(scene_path: String, open_time: int, close_time: int, closed_msg: String) -> void:
	var now := GameState.time

	if now >= CAMPUS_CLOSE:
		_kick_out_of_school()
		_clear_panel()
		return

	if now >= open_time and now < close_time:
		_fade_and_change_scene(scene_path)
	else:
		var open_str := _minutes_to_time_str(open_time)
		var close_str := _minutes_to_time_str(close_time)
		popup_label.text = "%s (Open: %s – %s)" % [closed_msg, open_str, close_str]
		popup_label.visible = true
	_clear_panel()

func _try_enter_classroom() -> void:
	var d := GameState.day
	var t := GameState.time

	if t >= CAMPUS_CLOSE:
		_kick_out_of_school()
		_clear_panel()
		return

	if d == 1:
		if t >= 12 * 60 + 30 and t < 18 * 60:
			_fade_and_change_scene(CLASSROOM_SCENE)
		else:
			popup_label.text = "The classroom is closed. (Open after 12:30 on Day 1.)"
			popup_label.visible = true
		_clear_panel()
		return

	if d >= 2 and d <= 4:
		if t >= 18 * 60 and t < CAMPUS_CLOSE:
			popup_label.text = "The classroom is closed for the day."
			popup_label.visible = true
			_clear_panel()
			return

		if t >= CLASS_LOCK_START and t < CLASS_LOCK_END:
			if FileAccess.file_exists(CLASS_LOCKED_JSON):
				DialogueManager.start_dialogue(CLASS_LOCKED_JSON, self)
			else:
				popup_label.text = "Class is in session. The door's locked."
				popup_label.visible = true
			_clear_panel()
			return

		_fade_and_change_scene(CLASSROOM_SCENE)
		_clear_panel()
		return

	_fade_and_change_scene(CLASSROOM_SCENE)
	_clear_panel()

func _minutes_to_time_str(minutes: int) -> String:
	var hours := int(minutes / 60)
	var mins := int(minutes % 60)
	return "%02d:%02d" % [hours, mins]

func _kick_out_of_school() -> void:
	popup_label.text = "School is closed for the day."
	popup_label.visible = true
	await get_tree().process_frame
	_fade_and_change_scene(CITY_SCENE)

func _clear_panel() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null

# ================= Fade helpers =================
func _ensure_fader() -> void:
	if _fade_layer == null or not is_instance_valid(_fade_layer):
		_fade_layer = CanvasLayer.new()
		_fade_layer.layer = 100
		add_child(_fade_layer)
	if _fade_rect == null or not is_instance_valid(_fade_rect):
		_fade_rect = ColorRect.new()
		_fade_rect.color = Color(0, 0, 0, 1)
		_fade_rect.modulate = Color(1, 1, 1, 0)
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fade_layer.add_child(_fade_rect)

func _fade_to(alpha: float, duration: float) -> void:
	_ensure_fader()
	var tw := create_tween()
	tw.tween_property(_fade_rect, "modulate:a", alpha, duration)
	await tw.finished

func _fade_and_change_scene(path: String) -> void:
	if path == "":
		return
	await _fade_to(1.0, 0.4)
	if ResourceLoader.exists(path):
		get_tree().change_scene_to_file(path)
	await _fade_to(0.0, 0.4)
