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

# Normal sleep availability outside midnight window
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

# ---- Midnight window helper (00:00–01:00 inclusive of 01:00) ----
func _is_midnight_window() -> bool:
	return GameState.time <= 60

# ---------------- Menus ----------------
func show_home_menu() -> void:
	var opts: Array = []
	var in_midnight: bool = _is_midnight_window()

	opts.append({"id":"activities","text":"Activities"})

	# Hide / block City during midnight window
	if not in_midnight:
		opts.append({"id":"city","text":"City"})

	# During midnight window, Sleep should only appear under Activities.
	if not in_midnight:
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
			await _do_sleep(false) # normal gating when not midnight window
		"sleep_locked":
			show_home_menu()
		"back":
			_clear_panel()

func _show_activities_menu() -> void:
	var opts: Array = []
	var in_midnight: bool = _is_midnight_window()

	if in_midnight:
		# Between 00:00–01:00 (incl. 01:00 after warp): ONLY Sleep here
		opts.append({"id":"sleep_force","text":"Sleep"})
		opts.append({"id":"back","text":"Back"})
		_show_choices(opts, Callable(self,"_on_activities_choice"))
		return

	opts.append({"id":"study","text":"Study"})
	opts.append({"id":"schoolwork","text":"Schoolwork"})
	opts.append({"id":"mailbox","text":"Check Mailbox"})
	opts.append({"id":"social","text":"Social Media"})
	opts.append({"id":"back","text":"Back"})
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
			_change_scene(MAILBOX_SCENE_PATH)
		"social":
			_change_scene(SOCIAL_SCENE_PATH)
		"back":
			show_home_menu()

# ---- Study menus ----
func _show_study_menu() -> void:
	var s1: String = GameState.subject1
	if s1.strip_edges() == "":
		s1 = "Subject 1"
	var s2: String = GameState.subject2
	if s2.strip_edges() == "":
		s2 = "Subject 2"

	# Top-level: no counts, just the two subjects
	var opts: Array = []
	opts.append({"id":"s1","text":"Study " + s1})
	opts.append({"id":"s2","text":"Study " + s2})
	opts.append({"id":"back","text":"Back"})
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
	# FIX: avoid C-style ternary
	var subject_raw: String = ""
	if which_subject == "subject2":
		subject_raw = GameState.subject2
	else:
		subject_raw = GameState.subject1

	var subj_label: String = subject_raw
	if subj_label.strip_edges() == "":
		if which_subject == "subject2":
			subj_label = "Subject 2"
		else:
			subj_label = "Subject 1"

	var opts: Array = []
	var days_to_show: Array = _get_available_days_for_subject(subject_raw)
	for d in days_to_show:
		var studied: bool = _is_day_studied(subject_raw, d)
		var label: String = "%s Notes #%d" % [subj_label, d]
		if studied:
			label += " (Done)"
			opts.append({"id": "sess_" + str(d), "text": label, "dim": true}) # 'dim' is optional hint
		else:
			opts.append({"id": "sess_" + str(d), "text": label})

	opts.append({"id":"back","text":"Back"})
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
		_change_scene(STUDY_SCENE_PATH)
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

	# Past days: only include ones actually studied (missed days remain hidden)
	for d in range(1, today_index):
		var k: String = subj_key + "|" + str(d)
		if GameState.study_guard.has(k):
			out.append(d)

	# Always include today’s slot
	out.append(today_index)
	return out

# ---- Schoolwork ----
func _show_schoolwork_menu() -> void:
	var opts: Array = []
	if _is_midnight_window():
		opts.append({"id":"back","text":"Back"})
		_show_choices(opts, Callable(self,"_on_schoolwork_choice"))
		return

	# Gate CV / Motivation to “not done/printed”
	if _can_write_cv():
		opts.append({"id":"cv","text":"Write CV"})
	if _can_write_mletter():
		opts.append({"id":"motivation","text":"Write Motivation Letter"})
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
	if path != "" and ResourceLoader.exists(path):
		get_tree().change_scene_to_file(path)

# --------------- Sleep with Fade singleton ---------------
func _fade_out(dur: float) -> void:
	var f := get_node_or_null("/root/Fade")
	if f:
		if f.has_method("out"):
			await f.out(dur); return
		if f.has_method("fade_out"):
			await f.fade_out(dur); return

func _fade_in(dur: float) -> void:
	var f := get_node_or_null("/root/Fade")
	if f:
		if f.has_method("in"):
			await f.in(dur); return
		if f.has_method("fade_in"):
			await f.fade_in(dur); return

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
	await _fade_out(0.35)
	GameState.sleep_now()
	await _fade_in(0.6)
	_block_ui(false)

	# Optional wake-up nudge (non-blocking preferred)
	if FileAccess.file_exists(WAKEUP_JSON):
		var dm := get_node_or_null("/root/DialogueManager")
		if dm and dm.has_method("start_dialogue"):
			dm.start_dialogue(WAKEUP_JSON, self)

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
	return GameState.get_task_progress("cv") < 2  # 2 = finished (your print unlock step)

func _can_write_mletter() -> bool:
	if not GameState.has_flag("secretary_met"):
		return false
	if GameState.has_flag("printed_motivation"):
		return false
	return GameState.get_task_progress("motivation") < 2
