# res://Scripts/Scenes/Home.gd
extends Control

@export var home_button: Button

const CCB_SCENE_PATH := "res://Scenes/Reusable/CharacterChoiceButtons.tscn"

const CITY_SCENE_PATH        := "res://Scenes/Reusable/Map/City.tscn"
const STUDY_SCENE_PATH       := "res://Scenes/Reusable/Tasks/Study.tscn"
const WRITE_CV_SCENE_PATH    := "res://Scenes/Reusable/Tasks/WRITE_A_CV.tscn"
const WRITE_MOTIVATION_PATH  := "res://Scenes/Reusable/Tasks/WRITE_A_MLETTER.tscn"
const WRITE_PROJECT_PATH     := "res://Scenes/Reusable/Tasks/WRITE_A_PROJECT.tscn"
const MAILBOX_SCENE_PATH     := "res://Scenes/Reusable/Tasks/MailboxCheck.tscn"
const SOCIAL_SCENE_PATH      := "res://Scenes/Reusable/Tasks/Social.tscn"

var _panel: Control = null
const SLEEP_AVAILABLE_MIN := 19 * 60  # 19:00

const KEY_STUDY_MODE := "__study_mode"           # "regular" | "marko"
const KEY_SUBJECT_PICK := "__study_subject_pick" # "subject1" | "subject2"

func _ready() -> void:
	GameState.location = "Home"
	if home_button:
		home_button.pressed.connect(_on_home_btn_pressed)

func _on_home_btn_pressed() -> void:
	show_home_menu()

# ================= Menus =================

func show_home_menu() -> void:
	var choices := [
		{"id":"activities", "text":"Activities"},
		{"id":"city",       "text":"City"}
	]
	if GameState.time >= SLEEP_AVAILABLE_MIN and not GameState.is_time_frozen():
		choices.append({"id":"sleep", "text":"Sleep"})
	else:
		choices.append({"id":"sleep_locked", "text":"Sleep (Locked)"})
	choices.append({"id":"back", "text":"Back"})
	_show_choices(choices, Callable(self, "_on_home_choice"))

func _on_home_choice(id: String) -> void:
	match id:
		"activities":
			_show_activities_menu()
		"city":
			_change_scene(CITY_SCENE_PATH)
		"sleep":
			_do_sleep()
		"sleep_locked":
			print("🛌 Too early to sleep. Come back after 19:00.")
			show_home_menu()
		"back":
			_clear_panel()

func _show_activities_menu() -> void:
	var choices := [
		{"id":"study",      "text":"Study"},
		{"id":"schoolwork", "text":"Schoolwork"},
		{"id":"mailbox",    "text":"Check Mailbox"},
		{"id":"social",     "text":"Social Media"},
		{"id":"back",       "text":"Back"}
	]
	_show_choices(choices, Callable(self, "_on_activities_choice"))

func _on_activities_choice(id: String) -> void:
	match id:
		"study":
			_show_study_menu()
		"schoolwork":
			_show_schoolwork_menu()
		"mailbox":
			_change_scene(MAILBOX_SCENE_PATH)
		"social":
			_change_scene(SOCIAL_SCENE_PATH)
		"back":
			show_home_menu()

func _show_study_menu() -> void:
	var s1 := GameState.subject1.strip_edges()
	var s2 := GameState.subject2.strip_edges()
	if s1 == "":
		s1 = "[Subject 1]"
	if s2 == "":
		s2 = "[Subject 2]"
	var choices := [
		{"id":"s1",   "text":"Study " + s1},
		{"id":"s2",   "text":"Study " + s2},
		{"id":"back", "text":"Back"}
	]
	_show_choices(choices, Callable(self, "_on_study_choice"))

func _on_study_choice(id: String) -> void:
	match id:
		"s1":
			GameState.features_unlocked[KEY_STUDY_MODE] = "regular"
			GameState.features_unlocked[KEY_SUBJECT_PICK] = "subject1"
			_change_scene(STUDY_SCENE_PATH)
		"s2":
			GameState.features_unlocked[KEY_STUDY_MODE] = "regular"
			GameState.features_unlocked[KEY_SUBJECT_PICK] = "subject2"
			_change_scene(STUDY_SCENE_PATH)
		"back":
			_show_activities_menu()

func _show_schoolwork_menu() -> void:
	var choices := [
		{"id":"cv",         "text":"Write CV"},
		{"id":"motivation", "text":"Write Motivation Letter"}
	]
	# Only add "Write Project" when available.
	if _is_project_available_now():
		choices.append({"id":"project", "text":"Write Project"})
	choices.append({"id":"back", "text":"Back"})
	_show_choices(choices, Callable(self, "_on_schoolwork_choice"))

func _on_schoolwork_choice(id: String) -> void:
	match id:
		"cv":
			_change_scene(WRITE_CV_SCENE_PATH)
		"motivation":
			_change_scene(WRITE_MOTIVATION_PATH)
		"project":
			_change_scene(WRITE_PROJECT_PATH)
		"back":
			_show_activities_menu()

# ================= CCB wrapper =================

func _show_choices(options: Array, cb: Callable) -> void:
	_clear_panel()
	var ps := load(CCB_SCENE_PATH) as PackedScene
	if ps == null:
		push_error("CharacterChoiceButtons not found at: " + CCB_SCENE_PATH)
		return
	_panel = ps.instantiate()
	add_child(_panel)
	_panel.call("show_options", options, cb)

func _clear_panel() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null

# ================= Actions =================

func _change_scene(path: String) -> void:
	_clear_panel()
	if path == "" or not ResourceLoader.exists(path):
		push_warning("Scene missing or invalid: " + path)
		return
	get_tree().change_scene_to_file(path)

func _do_sleep() -> void:
	if GameState.is_time_frozen():
		print("⏸️ Finish the conversation first.")
		show_home_menu()
		return
	if GameState.time < SLEEP_AVAILABLE_MIN:
		print("🛌 Too early to sleep. Come back after 19:00.")
		show_home_menu()
		return
	if GameState.has_method("sleep_now"):
		GameState.sleep_now()
	else:
		var wake_base := 7 * 60 + 30
		var penalty := 0
		if GameState.time >= 23 * 60:
			var after_23 := GameState.time - 23 * 60
			penalty = int(ceil(float(after_23) / 4.0))
		var wake := wake_base + penalty
		while wake >= 24 * 60:
			wake -= 24 * 60
		GameState.day += 1
		GameState.time = wake
		print("🛌 Slept. Wake at %02d:%02d (Day %d), penalty +%d min" % [wake/60, wake%60, GameState.day, penalty])
	_clear_panel()

# ================= Availability logic =================

func _is_project_available_now() -> bool:
	# Must have accepted with professor OR be on a second chance
	if not (GameState.has_flag("project_accepted") or GameState.has_flag("project_second_chance")):
		return false

	# Still blocked if already finished/bought/submitted
	if GameState.has_flag("project_submitted"):
		return false
	if GameState.has_flag("have_old_project"):  # bought from janitor
		return false
	if GameState.has_flag("project_written"):   # finished writing already
		return false

	return true
