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

var _panel: Control = null
const SLEEP_AVAILABLE_MIN := 19 * 60  # 19:00

# Keys used by Study scene
const KEY_STUDY_MODE: String    = "__study_mode"
const KEY_SUBJECT_PICK: String  = "__study_subject_pick"
const KEY_RETURN_SCENE: String  = "__study_return_scene"
const KEY_STUDY_SESSION: String = "__study_session_index"

# Fade overlay (temporary until Fade singleton wiring)
var _fade_rect: ColorRect = null
var _ui_was_visible: bool = false

# ---------- helpers for curfew / midnight lock ----------
func _night_lock_active() -> bool:
	# Lock if curfew flag is set (teleport at 01:00) OR during midnight hour [00:00–00:59]
	if GameState.has_flag("curfew_lock"):
		return true
	if GameState.time < 60:
		return true
	return false

func _ready() -> void:
	GameState.location = "Home"

	# Gate CV/Motivation initial step behind meeting the secretary
	if GameState.has_flag("secretary_met"):
		if GameState.get_task_progress("cv") == 0:
			GameState.update_task_step("cv")
		if GameState.get_task_progress("motivation") == 0:
			GameState.update_task_step("motivation")

	if home_button:
		home_button.pressed.connect(_on_home_btn_pressed)

func _on_home_btn_pressed() -> void:
	show_home_menu()

# ---------------- Menus ----------------

func show_home_menu() -> void:
	var opts: Array = []
	var night_lock := _night_lock_active()

	opts.append({"id":"activities","text":"Activities"})

	# City is hidden/blocked during midnight lock or curfew lock
	if not night_lock:
		opts.append({"id":"city","text":"City"})

	# Top-level Sleep appears only in normal hours, like before.
	# During lock window we keep Sleep ONLY inside Activities (per your request).
	if not night_lock:
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
			await _do_sleep(false) # normal gating
		"sleep_locked":
			show_home_menu()
		"back":
			_clear_panel()

func _show_activities_menu() -> void:
	var opts: Array = []
	var night_lock := _night_lock_active()

	if night_lock:
		# Lock window: ONLY sleep here
		opts.append({"id":"sleep_force","text":"Sleep"})
		opts.append({"id":"back","text":"Back"})
		_show_choices(opts, Callable(self,"_on_activities_choice"))
		return

	# Normal menu
	opts.append({"id":"study","text":"Study"})
	opts.append({"id":"schoolwork","text":"Schoolwork"})
	opts.append({"id":"mailbox","text":"Check Mailbox"})
	opts.append({"id":"social","text":"Social Media"})
	opts.append({"id":"back","text":"Back"})
	_show_choices(opts, Callable(self,"_on_activities_choice"))

func _on_activities_choice(id: String) -> void:
	match id:
		"sleep_force":
			# Force sleep regardless of time-of-day / frozen clock
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
		s1 = "[Subject 1]"
	var s2: String = GameState.subject2
	if s2.strip_edges() == "":
		s2 = "[Subject 2]"

	var n1: int = _count_studied_days_for_subject(GameState.subject1)
	var n2: int = _count_studied_days_for_subject(GameState.subject2)

	var opts: Array = []
	opts.append({"id":"s1","text":"Study " + s1 + " (" + str(n1) + "/4)"})
	opts.append({"id":"s2","text":"Study " + s2 + " (" + str(n2) + "/4)"})
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
	var subject_raw: String = ""
	if which_subject == "subject2":
		subject_raw = GameState.subject2
	else:
		subject_raw = GameState.subject1

	var subj_label: String = subject_raw
	if subj_label.strip_edges() == "":
		if which_subject == "subject2":
			subj_label = "[Subject 2]"
		else:
			subj_label = "[Subject 1]"

	var opts: Array = []
	var days_to_show: Array = _get_available_days_for_subject(subject_raw)
	for d in days_to_show:
		var tag: String = ""
		if _is_day_studied(subject_raw, d):
			tag = " (Done)"
		var label: String = "Study " + subj_label + " " + str(d) + "/4" + tag
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

	var d: int = 1
	while d < today_index:
		var k: String = subj_key + "|" + str(d)
		if GameState.study_guard.has(k):
			out.append(d)
		d += 1

	if today_index <= 4:
		out.append(today_index)

	return out

# ---- Schoolwork ----

func _show_schoolwork_menu() -> void:
	var opts: Array = []
	var night_lock := _night_lock_active()

	if night_lock:
		# During lock window, schoolwork is blocked entirely
		opts.append({"id":"back","text":"Back"})
		_show_choices(opts, Callable(self,"_on_schoolwork_choice"))
		return

	if GameState.has_flag("secretary_met"):
		opts.append({"id":"cv","text":"Write CV"})
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
	# Extra safety: during lock window, do not leave Home
	if _night_lock_active():
		return
	_clear_panel()
	if path != "" and ResourceLoader.exists(path):
		get_tree().change_scene_to_file(path)

# --------------- Fade + Sleep ----------------

func _ensure_fader() -> void:
	if _fade_rect:
		return
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 1)
	_fade_rect.modulate = Color(1, 1, 1, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.z_index = 100
	add_child(_fade_rect)

func _fade_to(alpha: float, duration: float) -> void:
	_ensure_fader()
	var tw := create_tween()
	tw.tween_property(_fade_rect, "modulate:a", alpha, duration)
	await tw.finished

func _block_ui(lock: bool) -> void:
	_ensure_fader()
	if lock:
		_ui_was_visible = _panel != null and _panel.visible
		if _panel:
			_panel.visible = false
		if home_button:
			home_button.disabled = true
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		if home_button:
			home_button.disabled = false
		if _panel and _ui_was_visible:
			_panel.visible = true
		_ui_was_visible = false
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _do_sleep(force: bool) -> void:
	# When force=true (midnight/curfew), bypass normal gating and frozen checks
	if not force:
		if GameState.is_time_frozen():
			return
		if GameState.time < SLEEP_AVAILABLE_MIN:
			return

	_block_ui(true)
	await _fade_to(1.0, 0.4)

	# Apply sleep (GameState handles post-23:00 penalty internally)
	GameState.sleep_now()

	# Clear curfew state so the new day runs normally
	if GameState.has_flag("curfew_lock"):
		GameState.clear_flag("curfew_lock")
	# Release the specific curfew freeze (if present)
	GameState.pop_time_freeze("__curfew__")
	# Reset the curfew guard so adjust_time works again today
	# (variable exists in the GameState I sent you)
	GameState._curfew_triggered = false

	await _fade_to(0.0, 0.6)
	_block_ui(false)

	# Optional wake-up nudge
	if FileAccess.file_exists(WAKEUP_JSON):
		if has_node("/root/DialogueManager"):
			var dm = get_node("/root/DialogueManager")
			if dm and dm.has_method("start_dialogue"):
				dm.start_dialogue(WAKEUP_JSON, self)

# ——— availability logic ———
func _is_project_available_now() -> bool:
	if GameState.has_flag("project_submitted"):
		return false
	if GameState.has_flag("project_written"):
		return false
	if GameState.has_flag("bought_project"):
		return false
	return GameState.has_flag("project_accepted")
