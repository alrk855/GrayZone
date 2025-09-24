extends Control 

@export var home_button: Button
const CCB_SCENE_PATH := "res://Scenes/Reusable/CharacterChoiceButtons.tscn"

const CITY_SCENE_PATH := "res://Scenes/Reusable/Map/City.tscn"
const STUDY_SCENE_PATH := "res://Scenes/Reusable/Tasks/Study.tscn"
const WRITE_CV_SCENE_PATH := "res://Scenes/Reusable/Tasks/WRITE_A_CV.tscn"
const WRITE_MOTIVATION_PATH := "res://Scenes/Reusable/Tasks/WRITE_A_MLETTER.tscn"
const WRITE_PROJECT_PATH := "res://Scenes/Reusable/Tasks/WRITE_A_PROJECT.tscn"
const MAILBOX_SCENE_PATH := "res://Scenes/Reusable/Tasks/Mailbox.tscn"
const SOCIAL_SCENE_PATH := "res://Scenes/Reusable/Tasks/Social.tscn"

const WAKEUP_JSON := "res://Data/Home/WakeUp_Reminder.json"
const OUTRO_SCENE_PATH := "res://Scenes/Reusable/Outro.tscn"

const SLEEP_AVAILABLE_MIN := 19 * 60  # 19:00

var _panel: Control = null
var _ui_was_visible: bool = false

# Keys used by Study scene
const KEY_STUDY_MODE: String    = "__study_mode"
const KEY_SUBJECT_PICK: String  = "__study_subject_pick"
const KEY_RETURN_SCENE: String  = "__study_return_scene"
const KEY_STUDY_SESSION: String = "__study_session_index"

func _ready() -> void:
	GameState.location = "Home"

	# Gate CV/Motivation initial step behind meeting the secretary
	if GameState.has_flag("secretary_met"):
		GameState.ensure_task("cv")
		GameState.ensure_task("motivation")
		if GameState.get_task_progress("cv") == 0:
			GameState.update_task_step("cv")
		if GameState.get_task_progress("motivation") == 0:
			GameState.update_task_step("motivation")

	if home_button:
		home_button.pressed.connect(_on_home_btn_pressed)

func _on_home_btn_pressed() -> void:
	show_home_menu()

func _is_midnight_window() -> bool:
	return GameState.time <= 60

# ---------------- Menus ----------------
func show_home_menu() -> void:
	var opts: Array = []
	var in_midnight: bool = _is_midnight_window()

	opts.append({"id":"activities","text": tr("Activities")})

	if not in_midnight:
		opts.append({"id":"city","text": tr("City")})

	if not in_midnight:
		if GameState.time >= SLEEP_AVAILABLE_MIN and not GameState.is_time_frozen():
			opts.append({"id":"sleep","text": tr("Sleep")})
		else:
			opts.append({"id":"sleep_locked","text": tr("Sleep (Locked)")})

	opts.append({"id":"back","text": tr("Back")})
	_show_choices(opts, Callable(self,"_on_home_choice"))

func _on_home_choice(id: String) -> void:
	match id:
		"activities":
			_show_activities_menu()
		"city":
			await _change_scene(CITY_SCENE_PATH)
		"sleep":
			await _do_sleep(false)
		"sleep_locked":
			show_home_menu()
		"back":
			_clear_panel()

func _show_activities_menu() -> void:
	var opts: Array = []
	var in_midnight: bool = _is_midnight_window()

	if in_midnight:
		opts.append({"id":"sleep_force","text": tr("Sleep")})
		opts.append({"id":"back","text": tr("Back")})
		_show_choices(opts, Callable(self,"_on_activities_choice"))
		return

	opts.append({"id":"study","text": tr("Study")})
	opts.append({"id":"schoolwork","text": tr("Schoolwork")})
	opts.append({"id":"mailbox","text": tr("Check Mailbox")})
	opts.append({"id":"social","text": tr("Social Media")})
	opts.append({"id":"back","text": tr("Back")})
	_show_choices(opts, Callable(self,"_on_activities_choice"))

func _on_activities_choice(id: String) -> void:
	match id:
		"sleep_force":
			await _do_sleep(true)
		"study":
			_show_study_menu()
		"schoolwork":
			_show_schoolwork_menu()
		"mailbox":
			await _change_scene(MAILBOX_SCENE_PATH)
		"social":
			await _change_scene(SOCIAL_SCENE_PATH)
		"back":
			show_home_menu()

# ---- Study menus ----
func _show_study_menu() -> void:
	var s1: String = GameState.subject1
	if s1.strip_edges() == "":
		s1 = tr("Subject 1")
	var s2: String = GameState.subject2
	if s2.strip_edges() == "":
		s2 = tr("Subject 2")

	var opts: Array = []
	opts.append({"id":"s1","text": tr("Study") + " " + s1})
	opts.append({"id":"s2","text": tr("Study") + " " + s2})
	opts.append({"id":"back","text": tr("Back")})
	_show_choices(opts, Callable(self,"_on_study_choice"))

func _on_study_choice(id: String) -> void:
	match id:
		"s1":
			_show_subject_sessions_menu("subject1")
		"s2":
			_show_subject_sessions_menu("subject2")
		"back":
			_show_activities_menu()

func _show_subject_sessions_menu(which_subject: String) -> void:
	var subject_raw: String = ""
	if which_subject == "subject2":
		subject_raw = GameState.subject2
	else:
		subject_raw = GameState.subject1

	var subj_label: String = subject_raw
	if subj_label.strip_edges() == "":
		subj_label = tr("Subject 2") if which_subject == "subject2" else tr("Subject 1")

	var opts: Array = []
	var days_to_show: Array = _get_available_days_for_subject(subject_raw)
	for d in days_to_show:
		var studied: bool = _is_day_studied(subject_raw, d)
		var label: String = "%s %s" % [subj_label, tr("Notes #%d") % d]
		if studied:
			label += " (" + tr("Done") + ")"
			opts.append({"id": "sess_" + str(d), "text": label, "dim": true})
		else:
			opts.append({"id": "sess_" + str(d), "text": label})

	opts.append({"id":"back","text": tr("Back")})
	_show_choices(opts, Callable(self,"_on_subject_session_choice").bind(which_subject, subject_raw))

func _on_subject_session_choice(id: String, which_subject: String, subject_raw: String) -> void:
	if id == "back":
		_show_study_menu()
		return

	if id.begins_with("sess_"):
		var day_index: int = int(id.substr(5, id.length() - 5))

		GameState.features_unlocked[KEY_STUDY_MODE] = "regular"
		GameState.features_unlocked[KEY_SUBJECT_PICK] = which_subject

		var ret: String = ""
		if get_tree() and get_tree().current_scene:
			ret = String(get_tree().current_scene.get_scene_file_path())
		else:
			ret = "res://Scenes/Reusable/Map/Home.tscn"
		GameState.features_unlocked[KEY_RETURN_SCENE] = ret

		GameState.features_unlocked[KEY_STUDY_SESSION] = day_index
		await _change_scene(STUDY_SCENE_PATH)
	else:
		_show_subject_sessions_menu(which_subject)

# ---- helpers to compute available sets ----
func _count_studied_days_for_subject(subject_raw: String) -> int:
	var subj_key: String = GameState._get_subject_key_from_choice(subject_raw)
	if subj_key.strip_edges() == "":
		return 0
	var count: int = 0
	for d in range(1, 5): # 1..4
		var k: String = subj_key + "|" + str(d)
		if GameState.study_guard.has(k):
			count += 1
	return count

func _is_day_studied(subject_raw: String, day_index: int) -> bool:
	var subj_key: String = GameState._get_subject_key_from_choice(subject_raw)
	var k: String = subj_key + "|" + str(day_index)
	return GameState.study_guard.has(k)

func _get_available_days_for_subject(subject_raw: String) -> Array[int]:
	var out: Array[int] = []
	var subj_key: String = GameState._get_subject_key_from_choice(subject_raw)
	if subj_key.strip_edges() == "":
		return out

	var today_index: int = GameState.day
	if today_index > 4:
		today_index = 4
	if today_index < 1:
		today_index = 1

	for d in range(1, today_index):
		var k: String = subj_key + "|" + str(d)
		if GameState.study_guard.has(k):
			out.append(d)

	out.append(today_index)
	return out

# ---- Schoolwork ----
func _show_schoolwork_menu() -> void:
	var opts: Array = []
	if _is_midnight_window():
		opts.append({"id":"back","text": tr("Back")})
		_show_choices(opts, Callable(self,"_on_schoolwork_choice"))
		return

	if _can_write_cv():
		opts.append({"id":"cv","text": tr("Write CV")})
	if _can_write_mletter():
		opts.append({"id":"motivation","text": tr("Write Motivation Letter")})
	if _is_project_available_now():
		opts.append({"id":"project","text": tr("Write Project")})

	opts.append({"id":"back","text": tr("Back")})
	_show_choices(opts, Callable(self,"_on_schoolwork_choice"))

func _on_schoolwork_choice(id: String) -> void:
	match id:
		"cv":
			await _change_scene(WRITE_CV_SCENE_PATH)
		"motivation":
			await _change_scene(WRITE_MOTIVATION_PATH)
		"project":
			await _change_scene(WRITE_PROJECT_PATH)
		"back":
			_show_activities_menu()

# --------------- shared helpers ----------------
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
	if _is_midnight_window():
		return
	_clear_panel()
	if path == "" or not ResourceLoader.exists(path):
		return
	await fade.fade_to_scene(path, 0.4, 0.35)

# --------------- Sleep with Fade singleton + Day5 Outro ---------------
func _block_ui(lock: bool) -> void:
	_ui_was_visible = _panel != null and _panel.visible
	if lock:
		if _panel: _panel.visible = false
		if home_button: home_button.disabled = true
	else:
		if home_button: home_button.disabled = false
		if _panel and _ui_was_visible: _panel.visible = true
		_ui_was_visible = false

func _do_sleep(force: bool) -> void:
	if not force:
		if GameState.is_time_frozen():
			return
		if GameState.time < SLEEP_AVAILABLE_MIN:
			return

	_block_ui(true)

	await fade.fade_out(3.35)
	GameState.sleep_now()

	if GameState.day >= 5:
		if ResourceLoader.exists(OUTRO_SCENE_PATH):
			await fade.fade_to_scene(OUTRO_SCENE_PATH, 0.0, 3.6)
		else:
			push_warning("Outro scene not found at: " + OUTRO_SCENE_PATH)
			await fade.fade_in(3.6)
		_block_ui(false)
		return

	await fade.fade_in(3.6)
	_block_ui(false)

	# Locale-aware wake-up JSON
	var wake_path := WAKEUP_JSON
	if GameState.has_method("localized_json_path"):
		wake_path = GameState.localized_json_path(WAKEUP_JSON)

	if FileAccess.file_exists(wake_path):
		var dm := get_node_or_null("/root/DialogueManager")
		if dm and dm.has_method("start_dialogue"):
			dm.start_dialogue(wake_path, self)

func _is_project_available_now() -> bool:
	if GameState.has_flag("project_submitted"): return false
	if GameState.has_flag("project_written"): return false
	if GameState.has_flag("bought_project"): return false
	return GameState.has_flag("project_accepted")

# ---- helpers to gate writing once done/printed ----
func _can_write_cv() -> bool:
	if not GameState.has_flag("secretary_met"):
		return false
	if GameState.has_flag("printed_cv"):
		return false
	return GameState.get_task_progress("cv") < 2

func _can_write_mletter() -> bool:
	if not GameState.has_flag("secretary_met"):
		return false
	if GameState.has_flag("printed_motivation"):
		return false
	return GameState.get_task_progress("motivation") < 2
