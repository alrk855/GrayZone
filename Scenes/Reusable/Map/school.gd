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

# Classroom lock windows (Days 2–4)
const CLASS_LOCK_START := 8 * 60 + 30     # 08:30
const CLASS_LOCK_END_ATTENDED := 12 * 60 + 30  # 12:30 (if attended)
const CLASS_LOCK_END_SKIPPED  := 13 * 60       # 13:00 (if skipped)

# Campus hard close
const CAMPUS_CLOSE := 19 * 60              # 19:00

# “Locked” dialogue for class in session
const CLASS_LOCKED_JSON := "res://Data/School/Classroom_Door_Locked.json"
const JSON_PROF_CLOSED := "res://Data/School/Professor_Office_Closed.json"
const JSON_SEC_CLOSED  := "res://Data/School/Secretary_Office_Closed.json"

@onready var popup_label: Label = $PopUp
@onready var show_menu_button: Button = $background/ShowMenuButton

var _panel: Control = null
var _is_fading: bool = false   # guard only; no local fade UI

func _ready() -> void:
	if GameState.subject1.strip_edges() == "":
		GameState.subject1 = "math"
	if GameState.subject2.strip_edges() == "":
		GameState.subject2 = "geography"

	GameUi.visible = true
	GameState.location = "School"
	popup_label.visible = false

	if not show_menu_button.pressed.is_connected(Callable(self, "_show_menu")):
		show_menu_button.pressed.connect(_show_menu)

	# If campus is closed already, kick out immediately
	if GameState.time >= CAMPUS_CLOSE:
		await _kick_out_of_school()
		return

func _show_menu() -> void:
	_clear_panel()
	var options = [
		{ "text": "Classroom",        "id": "classroom" },
		{ "text": "Professor Office", "id": "prof_office" },
		{ "text": "Secretary Office", "id": "sec_office" },
		{ "text": "City",             "id": "city" },
		{ "text": "Back",             "id": "back" }
	]
	_panel = preload(CCB_SCENE_PATH).instantiate()
	add_child(_panel)
	_panel.call("show_options", options, Callable(self, "_on_choice"))

func _on_choice(id: String) -> void:
	match id:
		"classroom":
			await _try_enter_classroom()
		"prof_office":
			await _try_enter_generic(PROFESSOR_OFFICE_SCENE, PROFESSOR_OPEN, PROFESSOR_CLOSE, "ProfessorOffice")
		"sec_office":
			await _try_enter_generic(SECRETARY_OFFICE_SCENE, SECRETARY_OPEN, SECRETARY_CLOSE, "SecretaryOffice")
		"city":
			_clear_panel()
			GameState.location = "CITY"
			await _fade_and_change_scene(CITY_SCENE)
		"back":
			_clear_panel()

# ---------------- Offices: JSON when closed (no popup texts) ----------------
func _try_enter_generic(scene_path: String, open_time: int, close_time: int, loc_name: String) -> void:
	var now := GameState.time

	# Campus fully closed?
	if now >= CAMPUS_CLOSE:
		await _kick_out_of_school()
		return

	# Inside hours → enter
	if now >= open_time and now < close_time:
		_clear_panel()
		GameState.location = loc_name
		await _fade_and_change_scene(scene_path)
		return

	# Outside hours → play the location-specific 'closed' JSON
	_clear_panel()
	var json_path := ""
	match loc_name:
		"ProfessorOffice":
			json_path = JSON_PROF_CLOSED
		"SecretaryOffice":
			json_path = JSON_SEC_CLOSED
		_:
			json_path = ""

	if json_path != "" and FileAccess.file_exists(json_path):
		var ui := DialogueManager.start_dialogue(json_path, self)
		if ui and ui.has_signal("dialogue_finished"):
			await ui.dialogue_finished
	else:
		# Silent fallback (no popup)
		push_warning("Closed JSON missing for: " + loc_name)

# ---------------- Classroom logic (unchanged) ----------------
func _try_enter_classroom() -> void:
	var d := GameState.day
	var t := GameState.time

	# Campus closed?
	if t >= CAMPUS_CLOSE:
		await _kick_out_of_school()
		return

	# Day 1: open 12:30–18:00
	if d == 1:
		if t >= 12 * 60 + 30 and t < 18 * 60:
			_clear_panel()
			GameState.location = "Classroom"
			await _fade_and_change_scene(CLASSROOM_SCENE)
		else:
			# (left as-is; you can swap to a JSON later if desired)
			popup_label.text = "The classroom is closed. (Open after 12:30 on Day 1.)"
			popup_label.visible = true
			_clear_panel()
		return

	# Days 2–4 rules
	if d >= 2 and d <= 4:
		# hard close after 18:00 (but before campus-wide 19:00)
		if t >= 18 * 60 and t < CAMPUS_CLOSE:
			# (left as-is; you can swap to a JSON later if desired)
			popup_label.text = "The classroom is closed for the day."
			popup_label.visible = true
			_clear_panel()
			return

		var attended_today := GameState.has_flag("attended_morning_day_" + str(d))

		# Gate:
		# - before 08:30 => allowed (so you can be on time/late)
		# - 08:30..12:30 => locked if attended; 08:30..13:00 => locked if skipped
		if t >= CLASS_LOCK_START:
			if attended_today:
				if t < CLASS_LOCK_END_ATTENDED:
					await _show_locked_dialogue()
					_clear_panel()
					return
			else:
				if t < CLASS_LOCK_END_SKIPPED:
					await _show_locked_dialogue()
					_clear_panel()
					return

		_clear_panel()
		GameState.location = "Classroom"
		await _fade_and_change_scene(CLASSROOM_SCENE)
		return

	# Any other day (failsafe)
	_clear_panel()
	GameState.location = "Classroom"
	await _fade_and_change_scene(CLASSROOM_SCENE)

func _show_locked_dialogue() -> void:
	if FileAccess.file_exists(CLASS_LOCKED_JSON):
		var ui = DialogueManager.start_dialogue(CLASS_LOCKED_JSON, self)
		if ui and ui.has_signal("dialogue_finished"):
			await ui.dialogue_finished
	else:
		# (left as-is; you can swap to a JSON later if desired)
		popup_label.text = "Class is in session. The door's locked."
		popup_label.visible = true
	await get_tree().process_frame

func _minutes_to_time_str(minutes: int) -> String:
	var hours := int(minutes / 60)
	var mins := int(minutes % 60)
	return "%02d:%02d" % [hours, mins]

func _kick_out_of_school() -> void:
	# (left as-is; you can swap to a JSON later if desired)
	popup_label.text = "School is closed for the day."
	popup_label.visible = true
	await get_tree().process_frame
	_clear_panel()
	GameState.location = "CITY"
	await _fade_and_change_scene(CITY_SCENE)

func _clear_panel() -> void:
	if _panel != null and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null

# ================= Scene change / fade (singleton only) =================
func _fade_and_change_scene(path: String) -> void:
	if path == "" or _is_fading:
		return
	if not ResourceLoader.exists(path):
		push_warning("Invalid scene path: " + path)
		return

	_is_fading = true
	await fade.fade_to_scene(path, 0.4, 0.35)
	_is_fading = false
