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
const CLASS_LOCK_START := 8 * 60 + 30
const CLASS_LOCK_END_ATTENDED := 12 * 60 + 30
const CLASS_LOCK_END_SKIPPED  := 13 * 60

# Campus hard close
const CAMPUS_CLOSE := 19 * 60

# “Locked” dialogue for class in session (relative IDs under Data/)
const CLASS_LOCKED_JSON := "School/Classroom_Door_Locked.json"
const JSON_PROF_CLOSED  := "School/Professor_Office_Closed.json"
const JSON_SEC_CLOSED   := "School/Secretary_Office_Closed.json"

@onready var popup_label: Label = $PopUp
@onready var show_menu_button: Button = $background/ShowMenuButton

var _panel: Control = null
var _is_fading: bool = false

func _ready() -> void:
	GameState.start_music_if_needed()
	if GameState.subject1.strip_edges() == "":
		GameState.subject1 = "math"
	if GameState.subject2.strip_edges() == "":
		GameState.subject2 = "geography"
	if GameState.player_name == "":
		GameState.player_name = "TEST"

	_show_control_hints_once()
	GameUi.visible = true
	GameState.location = "School"
	popup_label.visible = false

	if not show_menu_button.pressed.is_connected(Callable(self, "_show_menu")):
		show_menu_button.pressed.connect(_show_menu)

	if GameState.time >= CAMPUS_CLOSE:
		await _kick_out_of_school()
		return

func _show_menu() -> void:
	_clear_panel()
	var options = [
		{ "text": tr("Classroom"),        "id": "classroom" },
		{ "text": tr("Professor Office"), "id": "prof_office" },
		{ "text": tr("Secretary Office"), "id": "sec_office" },
		{ "text": tr("City"),             "id": "city" },
		{ "text": tr("Back"),             "id": "back" }
	]
	_panel = preload(CCB_SCENE_PATH).instantiate()
	add_child(_panel)
	_panel.call("show_options", options, Callable(self, "_on_choice"))

func _on_choice(id: String) -> void:
	match id:
		"classroom":
			await _try_enter_classroom()
		"prof_office":
			await _try_enter_generic(PROFESSOR_OFFICE_SCENE, PROFESSOR_OPEN, PROFESSOR_CLOSE, "ProfessorOffice", JSON_PROF_CLOSED)
		"sec_office":
			await _try_enter_generic(SECRETARY_OFFICE_SCENE, SECRETARY_OPEN, SECRETARY_CLOSE, "SecretaryOffice", JSON_SEC_CLOSED)
		"city":
			_clear_panel()
			GameState.location = "CITY"
			await _fade_and_change_scene(CITY_SCENE)
		"back":
			_clear_panel()

# ---------------- Offices ----------------
func _try_enter_generic(scene_path: String, open_time: int, close_time: int, loc_name: String, json_rel: String) -> void:
	var now := GameState.time

	if now >= CAMPUS_CLOSE:
		await _kick_out_of_school()
		return

	if now >= open_time and now < close_time:
		_clear_panel()
		GameState.location = loc_name
		await _fade_and_change_scene(scene_path)
		return

	_clear_panel()
	var path := _dp(json_rel)
	if path != "" and FileAccess.file_exists(path):
		var ui := DialogueManager.start_dialogue(path, self)
		if ui and ui.has_signal("dialogue_finished"):
			await ui.dialogue_finished
	else:
		push_warning("Closed JSON missing for: " + loc_name)

# ---------------- Classroom ----------------
func _try_enter_classroom() -> void:
	var d := GameState.day
	var t := GameState.time

	if t >= CAMPUS_CLOSE:
		await _kick_out_of_school()
		return

	if d == 1:
		if t >= 12 * 60 + 30 and t < 18 * 60:
			_clear_panel()
			GameState.location = "Classroom"
			await _fade_and_change_scene(CLASSROOM_SCENE)
		else:
			popup_label.text = tr("The classroom is closed. (Open after 12:30 on Day 1.)")
			popup_label.visible = true
			_clear_panel()
		return

	if d >= 2 and d <= 4:
		if t >= 18 * 60 and t < CAMPUS_CLOSE:
			popup_label.text = tr("The classroom is closed for the day.")
			popup_label.visible = true
			_clear_panel()
			return

		var attended_today := GameState.has_flag("attended_morning_day_" + str(d))
		if t >= CLASS_LOCK_START:
			if attended_today and t < CLASS_LOCK_END_ATTENDED:
				await _show_locked_dialogue()
				_clear_panel()
				return
			elif not attended_today and t < CLASS_LOCK_END_SKIPPED:
				await _show_locked_dialogue()
				_clear_panel()
				return

		_clear_panel()
		GameState.location = "Classroom"
		await _fade_and_change_scene(CLASSROOM_SCENE)
		return

	_clear_panel()
	GameState.location = "Classroom"
	await _fade_and_change_scene(CLASSROOM_SCENE)

func _show_locked_dialogue() -> void:
	var path := _dp(CLASS_LOCKED_JSON)
	if path != "" and FileAccess.file_exists(path):
		var ui := DialogueManager.start_dialogue(path, self)
		if ui and ui.has_signal("dialogue_finished"):
			await ui.dialogue_finished
	else:
		popup_label.text = tr("Class is in session. The door's locked.")
		popup_label.visible = true
	await get_tree().process_frame

func _minutes_to_time_str(minutes: int) -> String:
	var hours := int(minutes / 60)
	var mins := int(minutes % 60)
	return "%02d:%02d" % [hours, mins]

func _kick_out_of_school() -> void:
	popup_label.text = tr("School is closed for the day.")
	popup_label.visible = true
	await get_tree().process_frame
	_clear_panel()
	GameState.location = "CITY"
	await _fade_and_change_scene(CITY_SCENE)

func _clear_panel() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null

# ================= Fade =================
func _fade_and_change_scene(path: String) -> void:
	if path == "" or _is_fading:
		return
	if not ResourceLoader.exists(path):
		push_warning("Invalid scene path: " + path)
		return
	_is_fading = true
	await fade.fade_to_scene(path, 0.4, 0.35)
	_is_fading = false

# ---------------- One-time hints ----------------
func _show_control_hints_once() -> void:
	if GameState.has_flag("shown_school_hints"):
		return
	GameState.set_flag("shown_school_hints", true)
	await get_tree().create_timer(10.0).timeout
	if is_instance_valid(GameUi):
		GameUi.notify(tr("📘 Press T to open your Tasks"))
	if is_instance_valid(GameUi):
		GameUi.notify(tr("⚙️ Press ESC to open Settings"))

# -------- Locale path resolver (JSON) --------
func _dp(relative: String) -> String:
	var rel := String(relative).strip_edges().trim_prefix("/")
	if GameState.has_method("get_data_path"):
		return String(GameState.get_data_path(rel))
	return "res://Data/" + rel
