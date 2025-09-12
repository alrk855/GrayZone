extends Control

# ------------------------ Scene Paths ------------------------
@export var background_texrect_path: NodePath = ^"background"
@export var teacher_button_path: NodePath     = ^"background/Teacher"
@export var janitor_button_path: NodePath     = ^"background/Janitor"
@export var back_button_path: NodePath        = ^"background/Back"
@export var choice_panel_scene: PackedScene = preload("res://Scenes/Reusable/CharacterChoiceButtons.tscn")

# ------------------------ Backgrounds ------------------------
@export var bg_teacher_morning: Texture2D
@export var bg_empty: Texture2D
@export var bg_janitor_cleaning: Texture2D
@export var bg_janitor_papers: Texture2D

# ------------------------ JSON paths ------------------------
const J_DAY1_AFTERCLASS                 := "res://Data/Classroom/Classroom_Afternoon_Empty.json"

const J_D2_MORNING_ON_TIME              := "res://Data/Classroom/Classroom_Morning_OnTime.json"
const J_D2_MORNING_LATE                 := "res://Data/Classroom/Classroom_Morning_Late.json"
const J_D2_NOON_ANNOUNCEMENT            := "res://Data/Classroom/Classroom_D2_Noon_Event.json"

const J_CATCHUP_WARNING                 := "res://Data/Classroom/Classroom_Catchup.json"
const J_SKIPPED_PENALTY                 := "res://Data/Classroom/Classroom_Skipped_Penalty.json"

const J_TEACHER_TRANSCRIPT_TOO_EARLY    := "res://Data/Classroom/Transcript_TooEarly.json"
const J_TEACHER_DOC_REVIEW              := "res://Data/Classroom/DocReview_Start.json"

const J_JANITOR_TIPPED_INTRO            := "res://Data/Classroom/Janitor_Tipped_Intro.json"
const J_JANITOR_LOWREP_INTRO            := "res://Data/Classroom/Janitor_LowRep_Intro.json"
const J_JANITOR_NO_MONEY                := "res://Data/Classroom/Janitor_NotEnough.json"
const J_JANITOR_DECLINED                := "res://Data/Classroom/Janitor_Decline.json"
const J_JANITOR_CONFIRM                 := "res://Data/Classroom/Janitor_Confirm.json"
const J_JANITOR_D4_FALLBACK             := "res://Data/Classroom/Janitor_D4_Fallback.json"

# ------------------------ Time Gates (minutes) ------------------------
const T_08_00 := 8 * 60
const T_08_15 := 8 * 60 + 15
const T_08_30 := 8 * 60 + 30
const T_12_30 := 12 * 60 + 30
const T_14_30 := 14 * 60 + 30
const T_17_00 := 17 * 60
const T_17_45 := 17 * 60 + 45

# ------------------------ Internals ------------------------
var _bg: TextureRect
var _btn_teacher: Button
var _btn_janitor: Button
var _btn_back: Button
var _panel: Control = null
var _nav_pending: bool = false
var _janitor_papers_mode: bool = false

# per-day flags (in GameState.flags)
const F_ATTENDED_PREFIX           := "attended_morning_day_"
const F_LATE_PENALIZED_PREFIX     := "late_penalized_day_"
const F_SKIP_PENALIZED_PREFIX     := "skip_penalized_day_"
const F_NOON_DAY2_DONE            := "noon_day2_announcement_done"
const F_CATCHUP_SHOWN_PREFIX      := "catchup_shown_day_"
const F_TRANSCRIPT_STEP1_DONE     := "transcript_step1_done"
const F_DISCIPLINE_WARNED         := "discipline_warned"
const F_DISCIPLINE_FAILED         := "discipline_failed"
const F_MISSED_CNT                := "missed_morning_count"

# janitor flags
const F_MARKO_TIP                 := "marko_tip"
const F_ANS_SUBJ1                 := "answers_bought_subject1"
const F_ANS_SUBJ2                 := "answers_bought_subject2"
const F_JANITOR_REJECTED_D3       := "class_janitor_rejected_day3"

# tasks / navigation
const TASK_VOLUNTEER              := "Volunteer for Community Work"
const TASK_TRANSCRIPT             := "transcript"
const SCHOOL_SCENE                := "res://Scenes/Reusable/Map/School.tscn"

func _ready() -> void:
	GameState.location = "Classroom"

	_bg = get_node_or_null(background_texrect_path) as TextureRect
	_btn_teacher = get_node_or_null(teacher_button_path) as Button
	_btn_janitor = get_node_or_null(janitor_button_path) as Button
	_btn_back = get_node_or_null(back_button_path) as Button

	if _btn_teacher and not _btn_teacher.pressed.is_connected(Callable(self, "_on_teacher_pressed")):
		_btn_teacher.pressed.connect(_on_teacher_pressed)
	if _btn_janitor and not _btn_janitor.pressed.is_connected(Callable(self, "_on_janitor_pressed")):
		_btn_janitor.pressed.connect(_on_janitor_pressed)
	if _btn_back and not _btn_back.pressed.is_connected(Callable(self, "_on_back_pressed")):
		_btn_back.pressed.connect(_on_back_pressed)

	# Day 4: janitor always showing "papers in hand"
	if GameState.day == 4:
		_janitor_papers_mode = true

	_update_presence_and_background()
	await _handle_morning_entry_or_noon_chain()

# ------------------------ Presence / Background ------------------------
func _update_presence_and_background() -> void:
	var d: int = GameState.day
	var t: int = GameState.time

	var show_teacher_btn := false
	var show_janitor_btn := false
	var show_back := true
	var tex: Texture2D = bg_empty

	# Day 1: after 12:30 show empty classroom
	if d == 1:
		tex = bg_empty
		show_teacher_btn = false
		show_janitor_btn = false
		show_back = true
		_apply_vis(tex, show_teacher_btn, show_janitor_btn, show_back)
		return

	if d >= 2 and d <= 4:
		if t >= T_08_00 and t < T_12_30:
			tex = bg_teacher_morning if bg_teacher_morning else bg_empty
			show_teacher_btn = false
			show_janitor_btn = false
			show_back = false
		else:
			if t >= T_12_30 and t < T_14_30:
				tex = bg_empty
				show_teacher_btn = true
				show_back = true
			else:
				if (d == 3 or d == 4) and t >= T_17_00 and t < T_17_45:
					# Choose janitor art based on mode
					if _janitor_papers_mode and bg_janitor_papers:
						tex = bg_janitor_papers
					elif bg_janitor_cleaning:
						tex = bg_janitor_cleaning
					else:
						tex = bg_empty
					if d == 4 and GameState.has_flag(F_JANITOR_REJECTED_D3):
						show_janitor_btn = false
					else:
						show_janitor_btn = true
					show_teacher_btn = false
					show_back = true
				else:
					tex = bg_empty
					show_teacher_btn = false
					show_janitor_btn = false
					show_back = true
	else:
		tex = bg_empty
		show_teacher_btn = true
		show_janitor_btn = false
		show_back = true

	_apply_vis(tex, show_teacher_btn, show_janitor_btn, show_back)

func _apply_vis(tex: Texture2D, teacher_btn: bool, janitor_btn: bool, back_btn: bool) -> void:
	if _bg:
		_bg.texture = tex
	if _btn_teacher:
		_btn_teacher.visible = teacher_btn
	if _btn_janitor:
		_btn_janitor.visible = janitor_btn
	if _btn_back:
		_btn_back.visible = back_btn

# ------------------------ Morning flow ------------------------
func _handle_morning_entry_or_noon_chain() -> void:
	var d := GameState.day
	var t := GameState.time

	# Day 1: show empty message after 12:30
	if d == 1:
		if t >= T_12_30:
			await _play_json_and_wait(J_DAY1_AFTERCLASS)
		return

	# Retroactive skip from previous day (if they never opened Classroom)
	if d >= 3 and d <= 4:
		var prev := d - 1
		if prev >= 2:
			var prev_attended := GameState.has_flag(F_ATTENDED_PREFIX + str(prev))
			var prev_pen := GameState.has_flag(F_SKIP_PENALIZED_PREFIX + str(prev))
			if not prev_attended and not prev_pen:
				GameState.adjust_reputation(-10)
				GameState.set_flag(F_SKIP_PENALIZED_PREFIX + str(prev), true)
				GameState.set_int(F_MISSED_CNT, GameState.get_int(F_MISSED_CNT, 0) + 1)
				await _play_json_and_wait(J_SKIPPED_PENALTY)

	# Days 2–4
	if d >= 2 and d <= 4:
		# Early entry before 08:00 counts as on-time
		if t < T_08_00:
			var delta := T_08_00 - t
			if delta > 0:
				GameState.adjust_time(delta)
			await _play_json_and_wait(J_D2_MORNING_ON_TIME)
			GameState.adjust_reputation(+5)
			GameState.set_flag(F_ATTENDED_PREFIX + str(d), true)
			await _skip_to_1230_then_noon_chain()
			return

		# Within morning block
		if t >= T_08_00 and t < T_12_30:
			var attended_key := F_ATTENDED_PREFIX + str(d)
			if GameState.has_flag(attended_key):
				return

			if t < T_08_15:
				await _play_json_and_wait(J_D2_MORNING_ON_TIME)
				GameState.adjust_reputation(+5)
				GameState.set_flag(attended_key, true)
				await _skip_to_1230_then_noon_chain()
				return

			if t >= T_08_15 and t < T_08_30:
				var late_key := F_LATE_PENALIZED_PREFIX + str(d)
				if not GameState.has_flag(late_key):
					await _play_json_and_wait(J_D2_MORNING_LATE)
					GameState.adjust_reputation(-5)
					GameState.set_flag(late_key, true)
				GameState.set_flag(attended_key, true)
				await _skip_to_1230_then_noon_chain()
				return

			# 08:30–12:30 → School scene prevents entry (no JSON here)
			return

		# After 12:30 and didn’t attend (penalty was applied live or retro)
		var attended_key2 := F_ATTENDED_PREFIX + str(d)
		var skip_pen_key := F_SKIP_PENALIZED_PREFIX + str(d)
		if t >= T_12_30 and not GameState.has_flag(attended_key2) and not GameState.has_flag(skip_pen_key):
			GameState.adjust_reputation(-10)
			GameState.set_flag(skip_pen_key, true)
			GameState.set_int(F_MISSED_CNT, GameState.get_int(F_MISSED_CNT, 0) + 1)
			await _play_json_and_wait(J_SKIPPED_PENALTY)

	_update_presence_and_background()

func _skip_to_1230_then_noon_chain() -> void:
	var delta := T_12_30 - GameState.time
	if delta > 0:
		GameState.adjust_time(delta)

	# Day 2 noon announcement → unlocks doc review + yco
	if GameState.day == 2 and not GameState.has_flag(F_NOON_DAY2_DONE):
		await _after_morning_block()
	else:
		# Catch-up talk on D3/D4 if they’ve missed before
		var d := GameState.day
		if d >= 3 and d <= 4:
			var total_missed := GameState.get_int(F_MISSED_CNT, 0)
			if total_missed >= 1:
				var shown_key := F_CATCHUP_SHOWN_PREFIX + str(d)
				if not GameState.has_flag(shown_key):
					await _play_json_and_wait(J_CATCHUP_WARNING)
					GameState.set_flag(shown_key, true)
					if not GameState.has_flag(F_DISCIPLINE_WARNED):
						GameState.set_flag(F_DISCIPLINE_WARNED, true)
					else:
						GameState.set_flag(F_DISCIPLINE_FAILED, true)

	_update_presence_and_background()
	_go_school()

func _after_morning_block() -> void:
	GameState.set_flag(F_NOON_DAY2_DONE, true)
	await _play_json_and_wait(J_D2_NOON_ANNOUNCEMENT)
	GameState.ensure_task(TASK_VOLUNTEER)
	GameState.set_flag("doc_review_unlocked", true)
	GameState.set_flag("yco_interaction_done", true)
	GameState.adjust_time(+10)
	_update_presence_and_background()
	_go_school()

# ------------------------ Teacher interaction ------------------------
func _on_teacher_pressed() -> void:
	_clear_panel()
	var opts: Array = []
	if GameState.has_flag("doc_review_unlocked"):
		opts.append({"id":"doc_review","text":"Ask for document review"})
	else:
		opts.append({"id":"doc_locked","text":"Ask for document review (Locked)"})
	opts.append({"id":"transcript","text":"Ask about transcript"})
	opts.append({"id":"back","text":"Back"})

	_panel = choice_panel_scene.instantiate()
	add_child(_panel)
	_panel.call("show_options", opts, Callable(self, "_on_teacher_choice"))

func _on_teacher_choice(id: String) -> void:
	if id == "doc_review":
		await _play_json_and_wait(J_TEACHER_DOC_REVIEW)
		_clear_panel()
		return
	if id == "doc_locked":
		await _play_json_and_wait(J_D2_NOON_ANNOUNCEMENT)
		_clear_panel()
		return
	if id == "transcript":
		await _play_json_and_wait(J_TEACHER_TRANSCRIPT_TOO_EARLY)
		if not GameState.has_flag(F_TRANSCRIPT_STEP1_DONE):
			GameState.ensure_task(TASK_TRANSCRIPT)
			GameState.update_task_step(TASK_TRANSCRIPT)
			GameState.set_flag(F_TRANSCRIPT_STEP1_DONE, true)
		_clear_panel()
		return
	if id == "back":
		_clear_panel()
		return

# ------------------------ Janitor interaction ------------------------
func _on_janitor_pressed() -> void:
	_clear_panel()

	var d := GameState.day
	if d == 4 and GameState.has_flag(F_JANITOR_REJECTED_D3):
		await _play_json_and_wait(J_JANITOR_D4_FALLBACK)
		return

	var has_tip := GameState.has_flag(F_MARKO_TIP)
	var can_deal := has_tip or (GameState.reputation < 30)

	if not can_deal:
		await _play_json_and_wait(J_JANITOR_LOWREP_INTRO)
		_clear_panel()
		return

	if has_tip:
		await _play_json_and_wait(J_JANITOR_TIPPED_INTRO)
	else:
		await _play_json_and_wait(J_JANITOR_LOWREP_INTRO)

	# Swap to papers artwork when we reach the selling stage (Day 3)
	_janitor_papers_mode = true
	_update_presence_and_background()

	var s1 := GameState.subject1
	var s2 := GameState.subject2

	var choices: Array = []
	if s1.strip_edges() != "" and not GameState.has_flag(F_ANS_SUBJ1):
		choices.append({"id":"buy_s1","text":"Buy answers for " + s1.capitalize()})
	if s2.strip_edges() != "" and not GameState.has_flag(F_ANS_SUBJ2):
		choices.append({"id":"buy_s2","text":"Buy answers for " + s2.capitalize()})
	choices.append({"id":"pass","text":"I’ll pass"})

	_panel = choice_panel_scene.instantiate()
	add_child(_panel)
	_panel.call("show_options", choices, Callable(self, "_on_janitor_choice"))

func _on_janitor_choice(id: String) -> void:
	_clear_panel()
	if id == "pass":
		await _play_json_and_wait(J_JANITOR_DECLINED)
		if GameState.day == 3:
			GameState.set_flag(F_JANITOR_REJECTED_D3, true)
		return

	var price := GameState.has_flag(F_MARKO_TIP) ? 400 : 600

	var bought_flag := ""
	if id == "buy_s1":
		bought_flag = F_ANS_SUBJ1
	elif id == "buy_s2":
		bought_flag = F_ANS_SUBJ2
	else:
		return

	if GameState.money < price:
		await _play_json_and_wait(J_JANITOR_NO_MONEY)
		return

	GameState.add_money(-price)
	GameState.adjust_integrity(-10)
	GameState.set_flag(bought_flag, true)

	await _play_json_and_wait(J_JANITOR_CONFIRM)

	if GameState.time < T_17_45:
		var to_1745 := T_17_45 - GameState.time
		if to_1745 > 0:
			GameState.adjust_time(to_1745)

	_update_presence_and_background()

# ------------------------ Back / Navigation ------------------------
func _on_back_pressed() -> void:
	_go_school()

func _go_school() -> void:
	if _nav_pending:
		return
	_nav_pending = true
	if _btn_back:
		_btn_back.visible = false
	_clear_panel()
	await get_tree().process_frame
	call_deferred("_deferred_change_scene", SCHOOL_SCENE)

func _deferred_change_scene(path: String) -> void:
	_nav_pending = false
	var tree := get_tree()
	if tree and path != "" and ResourceLoader.exists(path):
		tree.change_scene_to_file(path)

# ------------------------ Helpers ------------------------
func _clear_panel() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null

func _json_exists(p: String) -> bool:
	return p != "" and FileAccess.file_exists(p)

func _play_json_and_wait(path: String) -> void:
	if not _json_exists(path):
		return
	var ui: Control = DialogueManager.start_dialogue(path, self)
	if ui and ui.has_signal("dialogue_finished"):
		var sig := Signal(ui, "dialogue_finished")
		await sig
