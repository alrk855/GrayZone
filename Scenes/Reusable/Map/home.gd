extends Control

@export var home_button: Button
const CCB_SCENE_PATH := "res://Scenes/Reusable/CharacterChoiceButtons.tscn"

const CITY_SCENE_PATH := "res://Scenes/Reusable/Map/City.tscn"
const STUDY_SCENE_PATH := "res://Scenes/Reusable/Tasks/Study.tscn"
const WRITE_CV_SCENE_PATH := "res://Scenes/Reusable/Tasks/WRITE_A_CV.tscn"
const WRITE_MOTIVATION_PATH := "res://Scenes/Reusable/Tasks/WRITE_A_MLETTER.tscn"
const WRITE_PROJECT_PATH := "res://Scenes/Reusable/Tasks/WRITE_A_PROJECT.tscn"
const MAILBOX_SCENE_PATH := "res://Scenes/Reusable/Tasks/MailboxCheck.tscn"
const SOCIAL_SCENE_PATH := "res://Scenes/Reusable/Tasks/Social.tscn"

var _panel: Control = null
const SLEEP_AVAILABLE_MIN := 19 * 60
const KEY_STUDY_MODE := "__study_mode"
const KEY_SUBJECT_PICK := "__study_subject_pick"

func _ready() -> void:
	GameState.location = "Home"
	if home_button:
		home_button.pressed.connect(_on_home_btn_pressed)

func _on_home_btn_pressed() -> void:
	show_home_menu()

# ---------------- Menus ----------------

func show_home_menu() -> void:
	var opts := [
		{"id":"activities","text":"Activities"},
		{"id":"city","text":"City"},
	]
	if GameState.time >= SLEEP_AVAILABLE_MIN and not GameState.is_time_frozen():
		opts.append({"id":"sleep","text":"Sleep"})
	else:
		opts.append({"id":"sleep_locked","text":"Sleep (Locked)"})
	opts.append({"id":"back","text":"Back"})
	_show_choices(opts, Callable(self,"_on_home_choice"))

func _on_home_choice(id: String) -> void:
	match id:
		"activities":
			_show_activities_menu()
		"city":
			_change_scene(CITY_SCENE_PATH)
		"sleep":
			_do_sleep()
		"sleep_locked":
			show_home_menu()
		"back":
			_clear_panel()

func _show_activities_menu() -> void:
	var opts := [
		{"id":"study","text":"Study"},
		{"id":"schoolwork","text":"Schoolwork"},
		{"id":"mailbox","text":"Check Mailbox"},
		{"id":"social","text":"Social Media"},
		{"id":"back","text":"Back"}
	]
	_show_choices(opts, Callable(self,"_on_activities_choice"))

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
	var s1 := GameState.subject1 if GameState.subject1.strip_edges() != "" else "[Subject 1]"
	var s2 := GameState.subject2 if GameState.subject2.strip_edges() != "" else "[Subject 2]"
	var opts := [
		{"id":"s1","text":"Study " + s1},
		{"id":"s2","text":"Study " + s2},
		{"id":"back","text":"Back"}
	]
	_show_choices(opts, Callable(self,"_on_study_choice"))

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
	var opts := []

	# unlocked after meeting secretary
	if GameState.has_flag("secretary_met"):
		opts.append({"id":"cv","text":"Write CV"})
		opts.append({"id":"motivation","text":"Write Motivation Letter"})

	# project gated
	if _is_project_available_now():
		opts.append({"id":"project","text":"Write Project"})

	opts.append({"id":"back","text":"Back"})
	_show_choices(opts, Callable(self,"_on_schoolwork_choice"))

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

# --------------- helpers ----------------

func _show_choices(opts: Array, cb: Callable) -> void:
	_clear_panel()
	var ps := load(CCB_SCENE_PATH) as PackedScene
	if ps == null:
		push_error("CharacterChoiceButtons not found: " + CCB_SCENE_PATH)
		return
	_panel = ps.instantiate()
	add_child(_panel)
	_panel.call("show_options", opts, cb)

func _clear_panel() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null

func _change_scene(path: String) -> void:
	if GameState.is_time_frozen():
		print("⏸️ Finish the conversation first.")
		return
	_clear_panel()
	if path != "" and ResourceLoader.exists(path):
		get_tree().change_scene_to_file(path)

func _do_sleep() -> void:
	if GameState.is_time_frozen():
		print("⏸️ Finish the conversation first.")
		return
	if GameState.time < SLEEP_AVAILABLE_MIN:
		show_home_menu()
		return
	GameState.sleep_now()
	_clear_panel()

# ——— availability logic ———
func _is_project_available_now() -> bool:
	# Optional: allow when professor granted second chance (if you still use this flag)
	if GameState.has_flag("project_second_chance"):
		return true

	# Otherwise it’s available only if:
	# - not already submitted
	# - not already written (until printed & submitted)
	# - not bought from janitor (bought skips writing)
	# - professor has accepted the assignment
	if GameState.has_flag("project_submitted"):
		return false
	if GameState.has_flag("project_written"):
		return false
	if GameState.has_flag("have_old_project") or GameState.has_flag("bought_project"):
		return false
	return GameState.has_flag("project_accepted")
