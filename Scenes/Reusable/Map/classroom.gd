extends Control

# ------------------------ Node Paths ------------------------
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

# Catch-up (skip-only, two variants)
const J_CATCHUP_FIRST_SKIP              := "res://Data/Classroom/Classroom_Catchup_FirstSkip.json"
const J_CATCHUP_REPEAT_SKIP             := "res://Data/Classroom/Classroom_Catchup_RepeatSkip.json"

# Teacher: transcripts + doc review set
const J_TEACHER_TRANSCRIPT_TOO_EARLY    := "res://Data/Classroom/Transcript_TooEarly.json"

const J_DOC_REVIEW_BANNED               := "res://Data/Classroom/DocReview_Banned.json"             # optional
const J_DOC_NEED_BOTH                   := "res://Data/Classroom/DocReview_NeedBoth.json"
const J_DOC_NEED_PRINT                  := "res://Data/Classroom/DocReview_NeedPrint.json"
const J_DOC_START_CV                    := "res://Data/Classroom/DocReview_StartCV.json"
const J_DOC_SUSPICION_PROMPT            := "res://Data/Classroom/DocReview_Suspicion_Prompt.json"
const J_DOC_LIE_CAUGHT                  := "res://Data/Classroom/DocReview_Lie_Caught.json"
const J_DOC_LIE_PASSED                  := "res://Data/Classroom/DocReview_Lie_Passed.json"
const J_DOC_ADMIT_REWRITE               := "res://Data/Classroom/DocReview_Admit_Rewrite.json"
const J_DOC_RESUBMIT_ACCEPTED           := "res://Data/Classroom/DocReview_Resubmit_Accepted.json"

# Janitor
const J_JANITOR_TIPPED_INTRO            := "res://Data/Classroom/Janitor_Tipped_Intro.json"
const J_JANITOR_LOWREP_INTRO            := "res://Data/Classroom/Janitor_LowRep_Intro.json"
const J_JANITOR_NO_MONEY                := "res://Data/Classroom/Janitor_NotEnough.json"
const J_JANITOR_DECLINED                := "res://Data/Classroom/Janitor_Decline.json"
const J_JANITOR_CONFIRM                 := "res://Data/Classroom/Janitor_Confirm.json"
const J_JANITOR_D4_FALLBACK             := "res://Data/Classroom/Janitor_D4_Fallback.json"

# ------------------------ Time Gates ------------------------
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

# Fade overlay
var _fade_layer: CanvasLayer = null
var _fade_rect: ColorRect = null

# chain state for dialogue
var _next_cb: String = ""

# doc review temp state
var _doc_suspicious_this_review: bool = false

# ------------------------ Flags (string keys) ------------------------
# per-day flags
const F_ATTENDED_PREFIX           := "attended_morning_day_"
const F_LATE_PENALIZED_PREFIX     := "late_penalized_day_"          # late is flavor-only now
const F_SKIP_PENALIZED_PREFIX     := "skip_penalized_day_"
const F_NOON_DAY2_DONE            := "noon_day2_announcement_done"
const F_CATCHUP_SHOWN_PREFIX      := "catchup_shown_day_"

# counters
const F_MISSED_CNT                := "missed_morning_count"         # ndays-skips source of truth

# janitor flags
const F_MARKO_TIP                 := "marko_tip"
const F_ANS_SUBJ1                 := "bought_answers_s1"
const F_ANS_SUBJ2                 := "bought_answers_s2"
const F_JANITOR_REJECTED_D3       := "janitor_offer_declined_d3"

# doc review / printing
const F_DOC_REVIEW_BANNED         := "doc_review_banned"
const F_PRINTED_CV                := "printed_cv"
const F_PRINTED_MOTIVATION        := "printed_motivation"
const F_MLETTER_AI                := "motivation_ai_generated"
const F_MLETTER_REWRITE_REQ       := "motivation_rewrite_required"
const F_MLETTER_SECOND_CHANCE     := "motivation_second_chance"

# tasks / navigation
const TASK_VOLUNTEER              := "Volunteer for Community Work" # not auto-bumped here
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

	if GameState.day == 4:
		_janitor_papers_mode = true

	_update_presence_and_background()
	_handle_entry_flow()

# ------------------------ Presence / Background ------------------------
func _update_presence_and_background() -> void:
	var d := GameState.day
	var t := GameState.time

	var show_teacher_btn := false
	var show_janitor_btn := false
	var show_back := true
	var tex: Texture2D = bg_empty

	# Day 1: after 12:30 empty classroom
	if d == 1:
		tex = bg_empty
		show_teacher_btn = false
		show_janitor_btn = false
		show_back = true
		_apply_vis(tex, show_teacher_btn, show_janitor_btn, show_back)
		return

	if d >= 2 and d <= 4:
		# before 12:30 show teacher bg (also before 08:00)
		if t < T_12_30:
			if bg_teacher_morning:
				tex = bg_teacher_morning
			else:
				tex = bg_empty
			show_teacher_btn = false
			show_janitor_btn = false
			show_back = false
		else:
			# 12:30–14:30 → teacher present during free time (CHANGED)
			if t >= T_12_30 and t < T_14_30:
				tex = bg_teacher_morning if bg_teacher_morning else bg_empty
				show_teacher_btn = true
				show_janitor_btn = false
				show_back = true
			else:
				# 17:00–17:45 on D3/D4 → janitor
				if (d == 3 or d == 4) and t >= T_17_00 and t < T_17_45:
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

# ------------------------ Entry Flow (chains via DM signal) ------------------------
func _handle_entry_flow() -> void:
	var d := GameState.day
	var t := GameState.time

	# Day 1: after 12:30
	if d == 1:
		if t >= T_12_30:
			_start_and_chain(J_DAY1_AFTERCLASS, "")
		return

	# Retro skip for previous day (if they never opened Classroom)
	if d >= 3 and d <= 4:
		var prev := d - 1
		if prev >= 2:
			if not GameState.has_flag(F_ATTENDED_PREFIX + str(prev)) and not GameState.has_flag(F_SKIP_PENALIZED_PREFIX + str(prev)):
				GameState.adjust_reputation(-10)
				GameState.set_flag(F_SKIP_PENALIZED_PREFIX + str(prev), true)
				GameState.set_int(F_MISSED_CNT, GameState.get_int(F_MISSED_CNT, 0) + 1)
				# No immediate catch-up JSON here; it will show in today's branch below

	# Days 2–4 morning logic
	if d >= 2 and d <= 4:
		if t < T_08_00:
			# Early entry counts as on-time
			var delta := T_08_00 - t
			if delta > 0:
				GameState.adjust_time(delta)
			GameState.adjust_reputation(+5)
			GameState.set_flag(F_ATTENDED_PREFIX + str(d), true)
			_start_and_chain(J_D2_MORNING_ON_TIME, "_after_morning_dialogue")
			return

		if t >= T_08_00 and t < T_12_30:
			var attended_key := F_ATTENDED_PREFIX + str(d)
			if GameState.has_flag(attended_key):
				return

			if t < T_08_15:
				GameState.adjust_reputation(+5)
				GameState.set_flag(attended_key, true)
				_start_and_chain(J_D2_MORNING_ON_TIME, "_after_morning_dialogue")
				return

			if t >= T_08_15 and t < T_08_30:
				# Late is flavor-only; keep light rep effect but don't affect catch-up logic
				var late_key := F_LATE_PENALIZED_PREFIX + str(d)
				if not GameState.has_flag(late_key):
					GameState.adjust_reputation(-5)
					GameState.set_flag(late_key, true)
				GameState.set_flag(attended_key, true)
				_start_and_chain(J_D2_MORNING_LATE, "_after_morning_dialogue")
				return

			# 08:30–12:30 locked by School scene
			return

		# After 12:30 and didn’t attend → one-time skip penalty for TODAY
		if t >= T_12_30:
			var attended_key2 := F_ATTENDED_PREFIX + str(d)
			var skip_pen_key := F_SKIP_PENALIZED_PREFIX + str(d)
			if not GameState.has_flag(attended_key2) and not GameState.has_flag(skip_pen_key):
				GameState.adjust_reputation(-10)
				GameState.set_flag(skip_pen_key, true)
				GameState.set_int(F_MISSED_CNT, GameState.get_int(F_MISSED_CNT, 0) + 1)
				# fall through to catch-up JSON below

	# Catch-up branch (skip-only): show once per day if you've missed at least one
	# This keeps original "after morning" placement behavior.
	if d >= 2 and d <= 4:
		var shown_key := F_CATCHUP_SHOWN_PREFIX + str(d)
		if not GameState.has_flag(shown_key):
			var total_skips := GameState.get_int(F_MISSED_CNT, 0)
			if total_skips >= 1:
				GameState.set_flag(shown_key, true)
				if total_skips == 1:
					_start_and_chain(J_CATCHUP_FIRST_SKIP, "_after_catchup")
					return
				else:
					_start_and_chain(J_CATCHUP_REPEAT_SKIP, "_after_catchup")
					return

# after the morning (on-time/late) JSON finishes
func _after_morning_dialogue() -> void:
	# jump to 12:30
	if GameState.time < T_12_30:
		GameState.adjust_time(T_12_30 - GameState.time)

	# Day 2 → noon announcement (only once)
	if GameState.day == 2 and not GameState.has_flag(F_NOON_DAY2_DONE):
		# fade between dialogues
		await _fade_flash(1.0, 1.0)
		_start_and_chain(J_D2_NOON_ANNOUNCEMENT, "_after_day2_noon")
		return

	# D3/D4: catch-up handled by central branch in _handle_entry_flow after penalties
	_update_presence_and_background()
	_go_school()

func _after_day2_noon() -> void:
	GameState.set_flag(F_NOON_DAY2_DONE, true)
	# No auto-ensures/bump for volunteering here; handled by Day2 noon JSON/actions or your TaskManager later.
	GameState.set_flag("doc_review_unlocked", true)
	GameState.set_flag("yco_interaction_done", true)
	GameState.adjust_time(+10)
	_update_presence_and_background()
	_go_school()

func _after_catchup() -> void:
	# No discipline flags; no task increments here by design.
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
	_panel = choice_panel_scene.instantiate()
	add_child(_panel)
	_panel.call("show_options", opts, Callable(self, "_on_teacher_choice"))

func _on_teacher_choice(id: String) -> void:
	if id == "doc_review":
		_try_doc_review()
		_clear_panel()
		return
	if id == "doc_locked":
		_start_and_chain(J_D2_NOON_ANNOUNCEMENT, "")
		_clear_panel()
		return
	if id == "transcript":
		_start_and_chain(J_TEACHER_TRANSCRIPT_TOO_EARLY, "")
		if not GameState.has_flag("transcript_step1_done"):
			GameState.ensure_task(TASK_TRANSCRIPT)
			GameState.update_task_step(TASK_TRANSCRIPT)
			GameState.set_flag("transcript_step1_done", true)
		_clear_panel()
		return
	if id == "back":
		_clear_panel()
		return

# ----- Doc Review flow -----
func _try_doc_review() -> void:
	# banned?
	if GameState.has_flag(F_DOC_REVIEW_BANNED):
		_start_and_chain(J_DOC_REVIEW_BANNED, "")
		return

	# Need both tasks started (secretary met + some progress)
	var has_both_started := false
	var sec_met := GameState.has_flag("secretary_met")
	if sec_met:
		var cv_prog := GameState.get_task_progress("cv")
		var ml_prog := GameState.get_task_progress("motivation")
		if cv_prog > 0 and ml_prog > 0:
			has_both_started = true
	if not has_both_started:
		_start_and_chain(J_DOC_NEED_BOTH, "")
		return

	# Need both printed
	var printed_cv := GameState.has_flag(F_PRINTED_CV)
	var printed_ml := GameState.has_flag(F_PRINTED_MOTIVATION)
	if not printed_cv or not printed_ml:
		_start_and_chain(J_DOC_NEED_PRINT, "")
		return

	# Resubmit path (second chance, rewritten + reprinted)
	if GameState.has_flag(F_MLETTER_REWRITE_REQ) and printed_ml and GameState.has_flag(F_MLETTER_SECOND_CHANCE):
		_start_and_chain(J_DOC_RESUBMIT_ACCEPTED, "_after_resubmit_accept")
		return

	# Normal review: CV quick pass, then ML suspicion prompt
	_start_and_chain(J_DOC_START_CV, "_after_cv_review")

func _after_cv_review() -> void:
	# roll 50% suspicion
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_doc_suspicious_this_review = rng.randi() % 100 < 50

	_start_and_chain(J_DOC_SUSPICION_PROMPT, "_show_doc_suspicion_choices")

func _show_doc_suspicion_choices() -> void:
	_clear_panel()
	var opts: Array = []
	opts.append({"id":"lie","text":"(Lie) Yes, I wrote it myself."})
	opts.append({"id":"admit","text":"(Admit) I used help online."})
	_panel = choice_panel_scene.instantiate()
	add_child(_panel)
	_panel.call("show_options", opts, Callable(self, "_on_doc_suspicion_choice"))

func _on_doc_suspicion_choice(id: String) -> void:
	_clear_panel()
	if id == "admit":
		GameState.adjust_integrity(+3)
		# require rewrite + reprint, give second chance
		GameState.set_flag(F_MLETTER_REWRITE_REQ, true)
		GameState.set_flag(F_MLETTER_SECOND_CHANCE, true)
		# clear printed flag so they must print again
		if GameState.has_flag(F_PRINTED_MOTIVATION):
			GameState.clear_flag(F_PRINTED_MOTIVATION)
		# Try to reset motivation task progress if API available
		if GameState.has_method("reset_task_progress"):
			GameState.reset_task_progress("motivation")
		elif GameState.has_method("reset_task"):
			GameState.reset_task("motivation")
		elif GameState.has_method("set_task_progress"):
			GameState.set_task_progress("motivation", 0)
		_start_and_chain(J_DOC_ADMIT_REWRITE, "")
		return

	if id == "lie":
		GameState.adjust_integrity(-5)
		if _doc_suspicious_this_review:
			# Caught lying → banned + extra rep hit, locked into AI route
			GameState.adjust_reputation(-10)
			GameState.set_flag(F_DOC_REVIEW_BANNED, true)
			GameState.set_flag(F_MLETTER_AI, true)
			_start_and_chain(J_DOC_LIE_CAUGHT, "")
			return
		else:
			# Not suspected → passes as "excellent"
			_start_and_chain(J_DOC_LIE_PASSED, "")
			return

# resubmit accepted → consume second chance, clear rewrite requirement, mark not-AI
func _after_resubmit_accept() -> void:
	if GameState.has_flag(F_MLETTER_REWRITE_REQ):
		GameState.clear_flag(F_MLETTER_REWRITE_REQ)
	if GameState.has_flag(F_MLETTER_SECOND_CHANCE):
		GameState.clear_flag(F_MLETTER_SECOND_CHANCE)
	# ensure AI flag is not forced if player rewrote genuinely
	if GameState.has_flag(F_MLETTER_AI):
		GameState.clear_flag(F_MLETTER_AI)

# ------------------------ Janitor ------------------------
func _on_janitor_pressed() -> void:
	_clear_panel()

	var d := GameState.day
	if d == 4 and GameState.has_flag(F_JANITOR_REJECTED_D3):
		_start_and_chain(J_JANITOR_D4_FALLBACK, "")
		return

	var has_tip := GameState.has_flag(F_MARKO_TIP)
	var can_deal := false
	if has_tip:
		can_deal = true
	else:
		if GameState.reputation < 30:
			can_deal = true

	if not can_deal:
		_start_and_chain(J_JANITOR_LOWREP_INTRO, "")
		return

	if has_tip:
		_start_and_chain(J_JANITOR_TIPPED_INTRO, "")
	else:
		_start_and_chain(J_JANITOR_LOWREP_INTRO, "")

	# switch to "papers" artwork for selling stage
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
		_start_and_chain(J_JANITOR_DECLINED, "")
		if GameState.day == 3:
			GameState.set_flag(F_JANITOR_REJECTED_D3, true)
		return

	var price := 600
	if GameState.has_flag(F_MARKO_TIP):
		price = 400

	var bought_flag := ""
	if id == "buy_s1":
		bought_flag = F_ANS_SUBJ1
	elif id == "buy_s2":
		bought_flag = F_ANS_SUBJ2
	else:
		bought_flag = ""

	if bought_flag == "":
		return

	if GameState.money < price:
		_start_and_chain(J_JANITOR_NO_MONEY, "")
		return

	GameState.add_money(-price)
	GameState.adjust_integrity(-10)
	GameState.set_flag(bought_flag, true)
	_start_and_chain(J_JANITOR_CONFIRM, "")

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
	# small fade-out before warp
	await _fade_to(1.0, 0.4)
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

# ------------------------ Fade helpers ------------------------
func _ensure_fader() -> void:
	if _fade_layer == null or not is_instance_valid(_fade_layer):
		_fade_layer = CanvasLayer.new()
		_fade_layer.layer = 100
		add_child(_fade_layer)
	if _fade_rect == null or not is_instance_valid(_fade_rect):
		_fade_rect = ColorRect.new()
		_fade_rect.color = Color(0, 0, 0, 1)     # black
		_fade_rect.modulate = Color(1, 1, 1, 0)  # start transparent
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fade_layer.add_child(_fade_rect)

func _fade_to(alpha: float, duration: float) -> void:
	_ensure_fader()
	var tw := create_tween()
	tw.tween_property(_fade_rect, "modulate:a", alpha, duration)
	await tw.finished

func _fade_flash(out_dur: float, in_dur: float) -> void:
	await _fade_to(1.0, out_dur)
	await _fade_to(0.0, in_dur)
