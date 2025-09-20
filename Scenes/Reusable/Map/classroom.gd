extends Control

# ------------------------ Node Paths ------------------------
@export var background_texrect_path: NodePath = ^"background"
@export var teacher_button_path: NodePath     = ^"background/Teacher"
@export var janitor_button_path: NodePath     = ^"background/Janitor"
@export var back_button_path: NodePath        = ^"background/Back"

@onready var _choice_panel_scene: PackedScene = preload("res://Scenes/Reusable/CharacterChoiceButtons.tscn")

# ------------------------ Backgrounds ------------------------
@export var bg_teacher_morning: Texture2D
@export var bg_empty: Texture2D
@export var bg_janitor_cleaning: Texture2D
@export var bg_janitor_papers: Texture2D

# ------------------------ JSON paths ------------------------
const J_EMPTY_CLASSROOM                    := "res://Data/Classroom/Classroom_Afternoon_Empty.json"

const J_D2_MORNING_ON_TIME                 := "res://Data/Classroom/Classroom_Morning_OnTime.json"
const J_D2_MORNING_LATE                    := "res://Data/Classroom/Classroom_Morning_Late.json"
const J_D2_NOON_ANNOUNCEMENT               := "res://Data/Classroom/Classroom_D2_Noon_Event.json"

const J_CATCHUP_FIRST_SKIP                 := "res://Data/Classroom/Classroom_Catchup_FirstSkip.json"
const J_CATCHUP_REPEAT_SKIP                := "res://Data/Classroom/Classroom_Catchup_RepeatSkip.json"

const J_TEACHER_TRANSCRIPT_TOO_EARLY       := "res://Data/Classroom/Transcript_TooEarly.json"
const J_DOC_REVIEW_BANNED                  := "res://Data/Classroom/DocReview_Banned.json"
const J_DOC_NEED_BOTH                      := "res://Data/Classroom/DocReview_NeedBoth.json"
const J_DOC_NEED_PRINT                     := "res://Data/Classroom/DocReview_NeedPrint.json"
const J_DOC_START_CV                       := "res://Data/Classroom/DocReview_StartCV.json"
const J_DOC_SUSPICION_PROMPT               := "res://Data/Classroom/DocReview_Suspicion_Prompt.json"
const J_DOC_LIE_CAUGHT                     := "res://Data/Classroom/DocReview_Lie_Caught.json"
const J_DOC_LIE_PASSED                     := "res://Data/Classroom/DocReview_Lie_Passed.json"
const J_DOC_ADMIT_REWRITE                  := "res://Data/Classroom/DocReview_Admit_Rewrite.json"
const J_DOC_RESUBMIT_ACCEPTED              := "res://Data/Classroom/DocReview_Resubmit_Accepted.json"

# Janitor JSON (Classroom)
const J_JANITOR_TIPPED_INTRO  := "res://Data/Janitor/Classroom/Janitor_Tipped_Intro.json"
const J_JANITOR_LOWREP_INTRO  := "res://Data/Janitor/Classroom/Janitor_LowRep_Intro.json"
const J_JANITOR_NO_MONEY      := "res://Data/Janitor/Classroom/Janitor_NotEnough.json"
const J_JANITOR_DECLINED      := "res://Data/Janitor/Classroom/Janitor_Decline.json"
const J_JANITOR_CONFIRM       := "res://Data/Janitor/Classroom/Janitor_Confirm.json"
const J_JANITOR_D4_FALLBACK   := "res://Data/Janitor/Classroom/Janitor_D4_Fallback.json"

# ------------------------ Time Gates ------------------------
const T_07_00 := 7 * 60
const T_08_00 := 8 * 60
const T_08_15 := 8 * 60 + 15
const T_08_30 := 8 * 60 + 30
const T_12_30 := 12 * 60 + 30
const T_14_30 := 14 * 60 + 30
const T_15_00 := 15 * 60
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
var _next_cb: String = ""
var _doc_suspicious_this_review: bool = false

# Track which subject was just purchased (for clarity; step calc derives from flags)
var _last_bought_flag: String = ""

# ------------------------ Flags ------------------------
const F_ATTENDED_PREFIX           := "attended_morning_day_"
const F_LATE_PENALIZED_PREFIX     := "late_penalized_day_"
const F_SKIP_PENALIZED_PREFIX     := "skip_penalized_day_"
const F_NOON_DAY2_DONE            := "noon_day2_announcement_done"
const F_CATCHUP_SHOWN_PREFIX      := "catchup_shown_day_"
const F_MISSED_CNT                := "missed_morning_count"

const F_MARKO_TIP                 := "marko_tip"
const F_ANS_SUBJ1                 := "bought_answers_s1"
const F_ANS_SUBJ2                 := "bought_answers_s2"
const F_JANITOR_REJECTED_D3       := "janitor_offer_declined_d3"

const F_DOC_REVIEW_BANNED         := "doc_review_banned"
const F_PRINTED_CV                := "printed_cv"
const F_PRINTED_MOTIVATION        := "printed_motivation"
const F_MLETTER_AI                := "motivation_ai_generated"
const F_MLETTER_REWRITE_REQ       := "motivation_rewrite_required"
const F_MLETTER_SECOND_CHANCE     := "motivation_second_chance"

# Tasks / navigation
const TASK_TRANSCRIPT             := "transcript"
const SCHOOL_SCENE                := "res://Scenes/Reusable/Map/School.tscn"

# Classroom Answers task
const TASK_CLASSROOM_ANS          := "Classroom Answers Lead"
const K_CLASSROOM_CHECK_DONE      := "__CLASSROOM_ANS_CHECK_DONE"

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

	if GameState.day == 4:
		_janitor_papers_mode = true

	_update_presence_and_background()
	_handle_entry_flow()

	# Keep UI + tasks in sync as the clock ticks
	if not GameState.time_changed.is_connected(Callable(self, "_on_time_changed")):
		GameState.time_changed.connect(_on_time_changed)

func _exit_tree() -> void:
	if GameState.time_changed.is_connected(Callable(self, "_on_time_changed")):
		GameState.time_changed.disconnect(_on_time_changed)

func _on_time_changed(_t: int, _d: int) -> void:
	_update_presence_and_background()
	_maybe_mark_classroom_answers_check()

# ------------------------ Presence / Background ------------------------
func _update_presence_and_background() -> void:
	var d := GameState.day
	var t := GameState.time

	var show_teacher_btn := false
	var show_janitor_btn := false
	var show_back := true
	var tex: Texture2D = bg_empty

	if d == 1:
		tex = bg_empty
		_apply_vis(tex, false, false, true)
		return

	if d >= 2 and d <= 4:
		if t < T_12_30:
			tex = (bg_teacher_morning if bg_teacher_morning else bg_empty)
			show_teacher_btn = false
			show_janitor_btn = false
			show_back = false
		elif t < T_14_30:
			tex = (bg_teacher_morning if bg_teacher_morning else bg_empty)
			show_teacher_btn = true
			show_janitor_btn = false
			show_back = true
		elif (d == 3 or d == 4) and t >= T_17_00 and t < T_17_45:
			if _janitor_papers_mode and bg_janitor_papers:
				tex = bg_janitor_papers
			elif bg_janitor_cleaning:
				tex = bg_janitor_cleaning
			else:
				tex = bg_empty
			show_janitor_btn = not (d == 4 and GameState.has_flag(F_JANITOR_REJECTED_D3))
			show_teacher_btn = false
			show_back = true
		else:
			tex = bg_empty
			show_teacher_btn = false
			show_janitor_btn = false
			show_back = true
	else:
		tex = bg_empty
		show_teacher_btn = false
		show_janitor_btn = false
		show_back = true

	_apply_vis(tex, show_teacher_btn, show_janitor_btn, show_back)

func _apply_vis(tex: Texture2D, teacher_btn: bool, janitor_btn: bool, back_btn: bool) -> void:
	if _bg: _bg.texture = tex
	if _btn_teacher: _btn_teacher.visible = teacher_btn
	if _btn_janitor: _btn_janitor.visible = janitor_btn
	if _btn_back: _btn_back.visible = back_btn

# ------------------------ Entry Flow (ordered precedence) ------------------------
func _handle_entry_flow() -> void:
	var d := GameState.day
	var t := GameState.time

	# Retro-skip marking for yesterday
	if d >= 3 and d <= 4:
		var prev := d - 1
		if prev >= 2:
			if not GameState.has_flag(F_ATTENDED_PREFIX + str(prev)) and not GameState.has_flag(F_SKIP_PENALIZED_PREFIX + str(prev)):
				GameState.adjust_reputation(-10)
				GameState.set_flag(F_SKIP_PENALIZED_PREFIX + str(prev), true)
				GameState.set_int(F_MISSED_CNT, GameState.get_int(F_MISSED_CNT, 0) + 1)

	# Morning block (07:00–12:30)
	if d >= 2 and d <= 4:
		if t >= T_07_00 and t < T_08_00:
			if T_08_00 - t > 0: GameState.adjust_time(T_08_00 - t)
			GameState.adjust_reputation(+5)
			GameState.set_flag(F_ATTENDED_PREFIX + str(d), true)
			_start_and_chain(J_D2_MORNING_ON_TIME, "_after_morning_dialogue")
			return
		if t >= T_08_00 and t < T_12_30:
			var attended := F_ATTENDED_PREFIX + str(d)
			if not GameState.has_flag(attended):
				if t < T_08_15:
					GameState.adjust_reputation(+5)
					GameState.set_flag(attended, true)
					_start_and_chain(J_D2_MORNING_ON_TIME, "_after_morning_dialogue")
					return
				elif t < T_08_30:
					var late_key := F_LATE_PENALIZED_PREFIX + str(d)
					if not GameState.has_flag(late_key):
						GameState.adjust_reputation(-5)
						GameState.set_flag(late_key, true)
					GameState.set_flag(attended, true)
					_start_and_chain(J_D2_MORNING_LATE, "_after_morning_dialogue")
					return

	# Catch-up only 07:00–15:00, once/day
	if d >= 2 and d <= 4:
		var shown_key := F_CATCHUP_SHOWN_PREFIX + str(d)
		if not GameState.has_flag(shown_key):
			var skips := GameState.get_int(F_MISSED_CNT, 0)
			if skips >= 1 and t >= T_07_00 and t < T_15_00:
				GameState.set_flag(shown_key, true)
				_apply_vis((bg_teacher_morning if bg_teacher_morning else bg_empty), false, false, true)
				if skips == 1:
					_start_and_chain(J_CATCHUP_FIRST_SKIP, "_after_catchup")
				else:
					_start_and_chain(J_CATCHUP_REPEAT_SKIP, "_after_catchup")
				return

	# Day 2 noon announcement
	if GameState.day == 2 and not GameState.has_flag(F_NOON_DAY2_DONE) and t >= T_12_30 and t < T_14_30:
		await fade.fade_out(1.0)
		await fade.fade_in(1.0)
		_start_and_chain(J_D2_NOON_ANNOUNCEMENT, "_after_day2_noon")
		return

	# If nobody is present now → show empty classroom JSON, then kick back to School
	if _is_room_empty_now(d, t):
		_start_and_chain(J_EMPTY_CLASSROOM, "_go_school")
		return

func _is_room_empty_now(d: int, t: int) -> bool:
	var teacher_here := (d >= 2 and d <= 4 and t >= T_12_30 and t < T_14_30)
	var janitor_here := ((d == 3 or d == 4) and t >= T_17_00 and t < T_17_45)
	if d == 4 and GameState.has_flag(F_JANITOR_REJECTED_D3):
		janitor_here = false
	return not teacher_here and not janitor_here

func _after_morning_dialogue() -> void:
	if GameState.time < T_12_30:
		GameState.adjust_time(T_12_30 - GameState.time)
	if GameState.day == 2 and not GameState.has_flag(F_NOON_DAY2_DONE):
		await fade.fade_out(1.0)
		await fade.fade_in(1.0)
		_start_and_chain(J_D2_NOON_ANNOUNCEMENT, "_after_day2_noon")
		return
	_update_presence_and_background()
	_go_school()

func _after_day2_noon() -> void:
	GameState.set_flag(F_NOON_DAY2_DONE, true)
	GameState.set_flag("doc_review_unlocked", true)
	GameState.set_flag("yco_interaction_done", true)
	GameState.adjust_time(+10)
	_update_presence_and_background()
	_go_school()

func _after_catchup() -> void:
	_update_presence_and_background()
	_go_school()

# ------------------------ Teacher ------------------------
func _on_teacher_pressed() -> void:
	_clear_panel()
	var opts: Array = []
	if GameState.has_flag("doc_review_unlocked"):
		opts.append({"id":"doc_review","text":"Ask for document review"})
	else:
		opts.append({"id":"doc_locked","text":"Ask for document review (Locked)"})
	opts.append({"id":"transcript","text":"Ask about transcript"})
	opts.append({"id":"back","text":"Back"})
	_spawn_options_panel(opts, Callable(self, "_on_teacher_choice"))

func _on_teacher_choice(id: String) -> void:
	if id == "doc_review":
		_try_doc_review(); _clear_panel(); return
	if id == "doc_locked":
		_start_and_chain(J_D2_NOON_ANNOUNCEMENT, ""); _clear_panel(); return
	if id == "transcript":
		_start_and_chain(J_TEACHER_TRANSCRIPT_TOO_EARLY, "")
		if not GameState.has_flag("transcript_step1_done"):
			GameState.ensure_task(TASK_TRANSCRIPT)
			GameState.update_task_step(TASK_TRANSCRIPT)
			GameState.set_flag("transcript_step1_done", true)
		_clear_panel(); return
	if id == "back":
		_clear_panel(); return

func _try_doc_review() -> void:
	if GameState.has_flag(F_DOC_REVIEW_BANNED):
		_start_and_chain(J_DOC_REVIEW_BANNED, ""); return
	var has_both := false
	if GameState.has_flag("secretary_met"):
		var cvp := GameState.get_task_progress("cv")
		var mlp := GameState.get_task_progress("motivation")
		if cvp > 0 and mlp > 0: has_both = true
	if not has_both:
		_start_and_chain(J_DOC_NEED_BOTH, ""); return
	var printed_cv := GameState.has_flag(F_PRINTED_CV)
	var printed_ml := GameState.has_flag(F_PRINTED_MOTIVATION)
	if not printed_cv or not printed_ml:
		_start_and_chain(J_DOC_NEED_PRINT, ""); return
	if GameState.has_flag(F_MLETTER_REWRITE_REQ) and printed_ml and GameState.has_flag(F_MLETTER_SECOND_CHANCE):
		_start_and_chain(J_DOC_RESUBMIT_ACCEPTED, "_after_resubmit_accept"); return
	_start_and_chain(J_DOC_START_CV, "_after_cv_review")

func _after_cv_review() -> void:
	var rng := RandomNumberGenerator.new(); rng.randomize()
	_doc_suspicious_this_review = rng.randi() % 100 < 50
	_start_and_chain(J_DOC_SUSPICION_PROMPT, "_show_doc_suspicion_choices")

func _show_doc_suspicion_choices() -> void:
	_clear_panel()
	_spawn_options_panel(
		[
			{"id":"lie","text":"(Lie) Yes, I wrote it myself."},
			{"id":"admit","text":"(Admit) I used help online."}
		],
		Callable(self, "_on_doc_suspicion_choice")
	)

func _on_doc_suspicion_choice(id: String) -> void:
	_clear_panel()
	if id == "admit":
		GameState.adjust_integrity(+3)
		GameState.set_flag(F_MLETTER_REWRITE_REQ, true)
		GameState.set_flag(F_MLETTER_SECOND_CHANCE, true)
		if GameState.has_flag(F_PRINTED_MOTIVATION):
			GameState.clear_flag(F_PRINTED_MOTIVATION)
		if GameState.has_method("reset_task_progress"):
			GameState.reset_task_progress("motivation")
		elif GameState.has_method("reset_task"):
			GameState.reset_task("motivation")
		elif GameState.has_method("set_task_progress"):
			GameState.set_task_progress("motivation", 0)
		_start_and_chain(J_DOC_ADMIT_REWRITE, ""); return
	if id == "lie":
		GameState.adjust_integrity(-5)
		if _doc_suspicious_this_review:
			GameState.adjust_reputation(-10)
			GameState.set_flag(F_DOC_REVIEW_BANNED, true)
			GameState.set_flag(F_MLETTER_AI, true)
			_start_and_chain(J_DOC_LIE_CAUGHT, ""); return
		else:
			_start_and_chain(J_DOC_LIE_PASSED, ""); return

func _after_resubmit_accept() -> void:
	if GameState.has_flag(F_MLETTER_REWRITE_REQ): GameState.clear_flag(F_MLETTER_REWRITE_REQ)
	if GameState.has_flag(F_MLETTER_SECOND_CHANCE): GameState.clear_flag(F_MLETTER_SECOND_CHANCE)
	if GameState.has_flag(F_MLETTER_AI): GameState.clear_flag(F_MLETTER_AI)

# ------------------------ Janitor ------------------------
func _on_janitor_pressed() -> void:
	_clear_panel()
	var d := GameState.day
	var t := GameState.time

	# Only open in the selling window
	if not ((d == 3 or d == 4) and t >= T_17_00 and t < T_17_45):
		return

	if d == 4 and GameState.has_flag(F_JANITOR_REJECTED_D3):
		_start_and_chain(J_JANITOR_D4_FALLBACK, ""); return

	var has_tip := GameState.has_flag(F_MARKO_TIP)
	var can_deal := has_tip or (GameState.reputation < 30)
	if not can_deal:
		_start_and_chain(J_JANITOR_LOWREP_INTRO, ""); return

	# Switch papers art for selling stage
	_janitor_papers_mode = true
	_update_presence_and_background()

	# Start intro JSON. The JSON should call { "action": "show_janitor_sale_menu" } when ready.
	DialogueManager.start_dialogue(has_tip ? J_JANITOR_TIPPED_INTRO : J_JANITOR_LOWREP_INTRO, self)

func _show_janitor_sale_menu() -> void:
	var s1 := GameState.subject1
	var s2 := GameState.subject2
	var choices: Array = []

	if s1.strip_edges() != "" and not GameState.has_flag(F_ANS_SUBJ1):
		choices.append({ "id": "buy_s1", "text": "Buy answers for " + s1.capitalize() })
	if s2.strip_edges() != "" and not GameState.has_flag(F_ANS_SUBJ2):
		choices.append({ "id": "buy_s2", "text": "Buy answers for " + s2.capitalize() })

	if choices.is_empty():
		# Nothing left to sell
		_start_and_chain(J_JANITOR_DECLINED, "")
		return

	choices.append({ "id": "pass", "text": "I’ll pass" })
	_spawn_options_panel(choices, Callable(self, "_on_janitor_choice"))

func _on_janitor_choice(id: String) -> void:
	_clear_panel()

	if id == "pass":
		_start_and_chain(J_JANITOR_DECLINED, "")
		if GameState.day == 3:
			GameState.set_flag(F_JANITOR_REJECTED_D3, true)
		return

	var price := GameState.has_flag(F_MARKO_TIP) ? 400 : 600

	var bought_flag := ""
	if id == "buy_s1":
		bought_flag = F_ANS_SUBJ1
	elif id == "buy_s2":
		bought_flag = F_ANS_SUBJ2

	if bought_flag == "":
		return

	if GameState.money < price:
		_start_and_chain(J_JANITOR_NO_MONEY, "")
		return

	GameState.add_money(-price)
	GameState.adjust_integrity(-10)
	GameState.set_flag(bought_flag, true)
	_last_bought_flag = bought_flag

	# Confirm JSON — AFTER that, update tasks & time
	_start_and_chain(J_JANITOR_CONFIRM, "_after_janitor_confirm")
	_update_presence_and_background()

func _after_janitor_confirm() -> void:
	# 1) Make sure “checks” is credited if we’re in the window
	_maybe_mark_classroom_answers_check()

	# 2) Derive task progress from actual purchase flags (idempotent)
	GameState.ensure_task(TASK_CLASSROOM_ANS)

	var base := GameState.has_flag(K_CLASSROOM_CHECK_DONE) ? 1 : 0
	var unique_buys := (GameState.has_flag(F_ANS_SUBJ1) ? 1 : 0) + (GameState.has_flag(F_ANS_SUBJ2) ? 1 : 0)
	var target := base + unique_buys

	var prog := GameState.get_task_progress(TASK_CLASSROOM_ANS)
	if target > prog:
		GameState.ensure_task_progress_at_least(TASK_CLASSROOM_ANS, target)

	# 3) Move time to 17:45 AFTER JSON (to end the selling window)
	if GameState.time < T_17_45:
		var delta := T_17_45 - GameState.time
		if delta > 0:
			GameState.adjust_time(delta)

	_update_presence_and_background()

# ------------------------ Back / Navigation ------------------------
func _on_back_pressed() -> void:
	_go_school()

func _go_school() -> void:
	if _nav_pending: return
	_nav_pending = true
	if _btn_back: _btn_back.visible = false
	_clear_panel()
	await get_tree().process_frame
	if ResourceLoader.exists(SCHOOL_SCENE):
		await fade.fade_to_scene(SCHOOL_SCENE, 0.4, 0.35)
	_nav_pending = false

# ------------------------ Dialogue actions ------------------------
func on_dialogue_action(line: Dictionary) -> void:
	var act := String(line.get("action",""))
	if act == "show_janitor_sale_menu":
		_show_janitor_sale_menu()
		return
	if act == "classroom_mark_checks":
		_maybe_mark_classroom_answers_check()
		return
	# Pass anything else to your global action handler if you use it
	if GameState.has_method("apply_action"):
		GameState.apply_action(line)

# ------------------------ Helpers ------------------------
func _clear_panel() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null

func _spawn_options_panel(options: Array, cb: Callable) -> void:
	_clear_panel()
	var scene := _choice_panel_scene
	if scene == null:
		scene = load("res://Scenes/Reusable/CharacterChoiceButtons.tscn")
		if scene == null:
			push_error("Choice panel scene missing.")
			return
	var panel := scene.instantiate()
	if panel == null:
		push_error("Failed to instantiate choice panel.")
		return
	_panel = panel
	add_child(panel)
	panel.call("show_options", options, cb)

func _start_and_chain(json_path: String, next_method: String) -> void:
	_next_cb = next_method
	if DialogueManager.is_connected("dialogue_finished", Callable(self, "_on_dm_finished")):
		DialogueManager.disconnect("dialogue_finished", Callable(self, "_on_dm_finished"))
	DialogueManager.connect("dialogue_finished", Callable(self, "_on_dm_finished"), Object.CONNECT_ONE_SHOT)
	DialogueManager.start_dialogue(json_path, self)

func _on_dm_finished(_id: String) -> void:
	var cb := _next_cb
	_next_cb = ""
	if cb != "":
		call_deferred(cb)

# ---------- Time-window auto marker for "Classroom Answers Lead" ----------
func _maybe_mark_classroom_answers_check() -> void:
	if GameState.has_flag(K_CLASSROOM_CHECK_DONE):
		return
	var d := GameState.day
	var t := GameState.time
	if (d == 3 or d == 4) and t >= T_17_00 and t < T_17_45:
		GameState.ensure_task(TASK_CLASSROOM_ANS)
		# Only push to step 1 if still at 0
		if GameState.get_task_progress(TASK_CLASSROOM_ANS) < 1:
			GameState.update_task_step(TASK_CLASSROOM_ANS)
		GameState.set_flag(K_CLASSROOM_CHECK_DONE, true)
