extends Control

@export var professor_path: NodePath = "background/Professor"
@export var janitor_path: NodePath   = "background/Janitor"
@export var back_button_path: NodePath = "background/Back"

@onready var professor_btn: Node = get_node_or_null(professor_path)
@onready var janitor_btn: Node   = get_node_or_null(janitor_path)
@onready var back_btn: Button    = get_node_or_null(back_button_path)

@onready var choice_panel_scene: PackedScene = preload("res://Scenes/Reusable/CharacterChoiceButtons.tscn")

const D_PROF := "res://Data/Dialogue/Professor/"

const JSON_PROF_INITIAL      := D_PROF + "Prof_Office_Initial.json"
const JSON_PROF_NOT_HERE     := D_PROF + "Prof_NotHere.json"
const JSON_PROF_FOLLOWUP_NR  := D_PROF + "Prof_Followup_NotReady.json"
const JSON_PROF_FOLLOWUP_OK  := D_PROF + "Prof_Followup_Accepted.json"
const JSON_PROF_ASK          := D_PROF + "Prof_Initial_AskDeadline.json"
const JSON_PROF_TOMORROW     := D_PROF + "Prof_Initial_BringTomorrow.json"
const JSON_PROF_DECLINE      := D_PROF + "Prof_Initial_Decline.json"

# Grades
const JSON_GRADE_A      := D_PROF + "Prof_Grade_A.json"
const JSON_GRADE_B      := D_PROF + "Prof_Grade_B.json"
const JSON_GRADE_C      := D_PROF + "Prof_Grade_C.json"
const JSON_GRADE_D      := D_PROF + "Prof_Grade_D.json"
const JSON_GRADE_F      := D_PROF + "Prof_Grade_F.json"
const JSON_GRADE_F_PLAG := D_PROF + "Prof_Grade_F_Plagiarized.json"

# Extra flows
const JSON_FAIL_SECOND_CHANCE := D_PROF + "Prof_Fail_SecondChance.json"
const JSON_PRAISE_INIT        := D_PROF + "Prof_Praise_Initiative.json"
const JSON_SCOLD_MISSED       := D_PROF + "Prof_Scold_MissedPromise.json"
const JSON_POST_SUBMIT        := D_PROF + "Prof_PostSubmit.json"

# Janitor
const JSON_JANITOR_TIPPED_INTRO   := D_PROF + "Janitor_Office_Tipped_Intro.json"
const JSON_JANITOR_NOTIP_INTRO    := D_PROF + "Janitor_Office_NoTip_Intro.json"
const JSON_JANITOR_HIGHREP        := D_PROF + "Janitor_Office_NoAccess_HighRep.json"
const JSON_JANITOR_ANYTHING_ELSE  := D_PROF + "Janitor_Office_AnythingElse.json"
const JSON_JANITOR_DEAL_300       := D_PROF + "Janitor_Deal_300.json"
const JSON_JANITOR_DEAL_500       := D_PROF + "Janitor_Deal_500.json"
const JSON_JANITOR_PASS           := D_PROF + "Janitor_Pass.json"
const JSON_JANITOR_NOMONEY        := D_PROF + "Janitor_NotEnoughMoney.json"

const T_13_00 := 13 * 60
const T_15_00 := 15 * 60
const T_17_00 := 17 * 60
const T_17_45 := 17 * 60 + 45

const TASK_PROJECT := "project"
const PLAGIARISM_CATCH_CHANCE := 0.5

var _panel: Control = null
var _intro_panel_shown: bool = false
var _janitor_panel_shown: bool = false

func _ready() -> void:
	GameState.location = "ProfessorOffice"

	if professor_btn and professor_btn.has_signal("pressed"):
		professor_btn.connect("pressed", Callable(self, "_on_professor_pressed"))
	if janitor_btn and janitor_btn.has_signal("pressed"):
		janitor_btn.connect("pressed", Callable(self, "_on_janitor_pressed"))
	if back_btn:
		back_btn.pressed.connect(_on_back_pressed)

	_update_presence()
	_maybe_show_not_here_on_enter()

func _process(_delta: float) -> void:
	_update_presence()

func _update_presence() -> void:
	var d: int = GameState.day
	var t: int = GameState.time

	if professor_btn:
		professor_btn.visible = _in(t, T_13_00, T_15_00)

	if janitor_btn:
		var bought: bool = GameState.has_flag("bought_project")
		var show: bool = false
		if _in(t, T_17_00, T_17_45):
			if d == 1:
				show = true
			elif d == 2 and not bought:
				show = true
		janitor_btn.visible = show

func _in(now: int, start_incl: int, end_excl: int) -> bool:
	return now >= start_incl and now < end_excl

func _maybe_show_not_here_on_enter() -> void:
	if GameState.day == 1 and _in(GameState.time, T_15_00, T_17_00):
		DialogueManager.start_dialogue(JSON_PROF_NOT_HERE, self)

# ---------- Professor ----------
func _on_professor_pressed() -> void:
	_clear_panel()
	_intro_panel_shown = false

	var d: int = GameState.day
	var t: int = GameState.time
	if not _in(t, T_13_00, T_15_00):
		if d == 1 and _in(GameState.time, T_15_00, T_17_00):
			DialogueManager.start_dialogue(JSON_PROF_NOT_HERE, self)
		return

	var options: Array = []
	var accepted: bool = GameState.has_flag("project_accepted")

	if d == 1 and not accepted:
		options.append({ "text": "Talk to Professor", "id": "talk_initial" })
	else:
		if _project_ready_for_submit():
			options.append({ "text": "Submit Final Project", "id": "submit" })
		options.append({ "text": "Talk", "id": "talk_followup" })

	options.append({ "text": "Back", "id": "back" })

	_panel = choice_panel_scene.instantiate()
	add_child(_panel)
	_panel.call("show_options", options, Callable(self, "_on_prof_menu_choice"))

func _on_prof_menu_choice(id: String) -> void:
	match id:
		"talk_initial":
			DialogueManager.start_dialogue(JSON_PROF_INITIAL, self)
			_clear_panel()
		"talk_followup":
			if GameState.has_flag("project_submitted"):
				DialogueManager.start_dialogue(JSON_POST_SUBMIT, self)
			elif GameState.has_flag("project_accepted"):
				DialogueManager.start_dialogue(JSON_PROF_FOLLOWUP_NR, self)
			else:
				DialogueManager.start_dialogue(JSON_PROF_INITIAL, self)
			_clear_panel()
		"submit":
			await _handle_project_submission()
		"back":
			_clear_panel()

func _handle_project_submission() -> void:
	var score: int = int(GameState.flags.get("project_score", 0))
	var is_bought: bool = GameState.has_flag("bought_project")

	# 1) Promise effects first (rep/integrity) and remember if we should show a side dialogue.
	var side: String = _promise_reward_or_penalty(is_bought)
	_clear_promise_flags()

	# If it was bought, persist plagiarism flag (used by endings)
	if is_bought:
		GameState.set_flag("project_plagiarized", true)

	# Plagiarism catch roll (only if bought)
	var caught_plag: bool = false
	if is_bought:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		caught_plag = rng.randf() < PLAGIARISM_CATCH_CHANCE
		if caught_plag:
			GameState.adjust_integrity(-5)
			print("[Integrity] Plagiarism detected at submission. -5 integrity.")

	# --- Ordering fix: show praise/scold FIRST, then continue branch ---
	if side == "praise":
		DialogueManager.start_dialogue(JSON_PRAISE_INIT, self)
		await get_tree().create_timer(0.2).timeout
	elif side == "scold":
		DialogueManager.start_dialogue(JSON_SCOLD_MISSED, self)
		await get_tree().create_timer(0.2).timeout

	# Caught plag → final F (plag), no second chance, mark submitted
	if caught_plag:
		DialogueManager.start_dialogue(JSON_GRADE_F_PLAG, self)
		_mark_submitted_no_task_increment()
		return

	# Not caught but bought → treat as A dialogue (flag persists for ending)
	if is_bought and not caught_plag:
		DialogueManager.start_dialogue(JSON_GRADE_A, self)
		_valid_submit_increment_task()
		return

	# Normal grading (not bought)
	var grade_id: String = _grade_from_score(score)
	if grade_id == "F":
		# Day < 5 → second chance. We already showed praise/scold above.
		if GameState.day < 5:
			_reset_project_to_step1()
			DialogueManager.start_dialogue(JSON_FAIL_SECOND_CHANCE, self)
			return
		# Friday+ → final fail; mark submitted (no increment)
		DialogueManager.start_dialogue(JSON_GRADE_F, self)
		_mark_submitted_no_task_increment()
		return

	# D/C/B/A → increment task
	match grade_id:
		"A": DialogueManager.start_dialogue(JSON_GRADE_A, self)
		"B": DialogueManager.start_dialogue(JSON_GRADE_B, self)
		"C": DialogueManager.start_dialogue(JSON_GRADE_C, self)
		"D": DialogueManager.start_dialogue(JSON_GRADE_D, self)
	_valid_submit_increment_task()

func _grade_from_score(score: int) -> String:
	if score >= 5: return "A"
	if score == 4: return "B"
	if score == 3: return "C"
	if score == 2: return "D"
	return "F"

func _mark_submitted_no_task_increment() -> void:
	GameState.set_flag("project_submitted", true)
	GameState.adjust_time(15)
	_clear_panel()

func _valid_submit_increment_task() -> void:
	GameState.set_flag("project_submitted", true)
	GameState.update_task_step(TASK_PROJECT)
	GameState.adjust_time(15)
	_clear_panel()

func _reset_project_to_step1() -> void:
	GameState.ensure_task(TASK_PROJECT)
	GameState.task_step_index[TASK_PROJECT] = 1
	print("[Task] Project reset to step 1 for second chance.")

func _promise_reward_or_penalty(is_plag: bool) -> String:
	# Returns "praise", "scold", or ""
	var promised: bool = GameState.has_flag("project_tomorrow_promise")
	var prom_day: int = int(GameState.flags.get("project_promise_day", 0))
	if not promised or prom_day <= 0:
		return ""
	# No reward if plag (even if not caught). Still scold if late.
	if GameState.day == prom_day + 1 and not is_plag:
		GameState.adjust_reputation(+5)
		GameState.adjust_integrity(+5)
		return "praise"
	elif GameState.day > prom_day + 1:
		GameState.adjust_reputation(-10)
		GameState.adjust_integrity(-10)
		return "scold"
	return ""

func _clear_promise_flags() -> void:
	GameState.clear_flag("project_tomorrow_promise")
	if GameState.flags.has("project_promise_day"):
		GameState.flags.erase("project_promise_day")

func on_dialogue_action(line: Dictionary) -> void:
	var act: String = String(line.get("action", ""))
	if act == "show_prof_intro_choices":
		if GameState.has_flag("project_accepted"):
			DialogueManager.end_active_dialogue()
			DialogueManager.start_dialogue(JSON_PROF_FOLLOWUP_NR, self)
			return
		if not _intro_panel_shown:
			_intro_panel_shown = true
			_show_prof_intro_options()
		return
	if act == "show_janitor_office_options":
		await get_tree().create_timer(0.20).timeout
		_show_janitor_office_options()
		return
	GameState.apply_action(line)

func _show_prof_intro_options() -> void:
	_clear_panel()
	var options: Array = [
		{ "text": "When do I need to bring it?", "id": "prof_ask_deadline" },
		{ "text": "I'll bring it tomorrow.",     "id": "prof_bring_tomorrow" },
		{ "text": "Never mind.",                 "id": "prof_nevermind" }
	]
	_panel = choice_panel_scene.instantiate()
	add_child(_panel)
	_panel.call("show_options", options, Callable(self, "_on_prof_intro_option"))

func _on_prof_intro_option(id: String) -> void:
	_clear_panel()
	match id:
		"prof_ask_deadline":
			GameState.set_flag("project_accepted", true)
			DialogueManager.start_dialogue(JSON_PROF_ASK, self)
		"prof_bring_tomorrow":
			GameState.set_flag("project_accepted", true)
			GameState.set_flag("project_tomorrow_promise", true)
			GameState.flags["project_promise_day"] = GameState.day
			DialogueManager.start_dialogue(JSON_PROF_TOMORROW, self)
		"prof_nevermind":
			DialogueManager.start_dialogue(JSON_PROF_DECLINE, self)
			await get_tree().create_timer(0.2).timeout
			_show_prof_intro_options()
		_:
			DialogueManager.end_active_dialogue()

func _project_ready_for_submit() -> bool:
	if not GameState.tasks.has(TASK_PROJECT):
		return false
	var prog: int = GameState.get_task_progress(TASK_PROJECT)
	return prog >= 2 and not GameState.has_flag("project_submitted")

# ---------- Janitor ----------
func _on_janitor_pressed() -> void:
	_clear_panel()
	_janitor_panel_shown = false

	var has_tip: bool = GameState.has_flag("janitor_tip") or GameState.has_flag("tipped_by_marko") or GameState.has_flag("marko_tip")
	var rep: int = GameState.reputation

	if has_tip:
		DialogueManager.start_dialogue(JSON_JANITOR_TIPPED_INTRO, self)
	elif rep >= 30 and FileAccess.file_exists(JSON_JANITOR_HIGHREP):
		DialogueManager.start_dialogue(JSON_JANITOR_HIGHREP, self)
	else:
		DialogueManager.start_dialogue(JSON_JANITOR_NOTIP_INTRO, self)

func _show_janitor_office_options() -> void:
	if GameState.has_flag("bought_project"):
		DialogueManager.end_active_dialogue()
		return
	if _janitor_panel_shown:
		return
	_janitor_panel_shown = true

	var options: Array = []
	var has_tip: bool = GameState.has_flag("janitor_tip") or GameState.has_flag("tipped_by_marko") or GameState.has_flag("marko_tip")

	if has_tip:
		options.append({ "text": "Deal (300 денари)", "id": "janitor_buy_300" })
	else:
		options.append({ "text": "Buy it (500 денари)", "id": "janitor_buy_500" })

	options.append({ "text": "That’s still shady.",     "id": "janitor_pass" })
	options.append({ "text": "Anything else for sale?", "id": "janitor_anything_else" })
	options.append({ "text": "Back",                    "id": "back" })

	_clear_panel()
	_panel = choice_panel_scene.instantiate()
	add_child(_panel)
	_panel.call("show_options", options, Callable(self, "_on_janitor_option"))

func _on_janitor_option(id: String) -> void:
	match id:
		"janitor_buy_300":
			if GameState.money < 300:
				DialogueManager.start_dialogue(JSON_JANITOR_NOMONEY, self)
				return
			GameState.add_money(-300)
			_handle_janitor_purchase(true)
		"janitor_buy_500":
			if GameState.money < 500:
				DialogueManager.start_dialogue(JSON_JANITOR_NOMONEY, self)
				return
			GameState.add_money(-500)
			_handle_janitor_purchase(false)
		"janitor_anything_else":
			if not GameState.tasks.has("Visit the Classroom"):
				GameState.add_task("Visit the Classroom")
			DialogueManager.start_dialogue(JSON_JANITOR_ANYTHING_ELSE, self)
		"janitor_pass":
			DialogueManager.start_dialogue(JSON_JANITOR_PASS, self)
		"back":
			DialogueManager.end_active_dialogue()
			_clear_panel()
		_:
			DialogueManager.end_active_dialogue()
			_clear_panel()

func _handle_janitor_purchase(tipped: bool) -> void:
	GameState.set_flag("bought_project", true)
	GameState.set_flag("project_plagiarized", true)
	GameState.set_flag("have_old_project", true)
	GameState.adjust_integrity(-5)
	print("[Integrity] Bought project from janitor. -5 integrity.")
	GameState.ensure_task_progress_at_least(TASK_PROJECT, 2)
	if not GameState.tasks.has("Visit the Classroom"):
		GameState.add_task("Visit the Classroom")
	GameState.adjust_time(15)

	if tipped:
		DialogueManager.start_dialogue(JSON_JANITOR_DEAL_300, self)
	else:
		DialogueManager.start_dialogue(JSON_JANITOR_DEAL_500, self)

	_clear_panel()

# ---------- Back ----------
func _on_back_pressed() -> void:
	var tree := get_tree()
	if tree == null:
		return
	if GameState.is_time_frozen():
		print("⏸️ Finish the conversation first.")
		return
	tree.change_scene_to_file("res://Scenes/Reusable/Map/School.tscn")

# ---------- Utils ----------
func _ensure_task_progress_at_least(task_id: String, target_step: int) -> void:
	if not GameState.tasks.has(task_id):
		GameState.add_task(task_id)
	var prog: int = GameState.get_task_progress(task_id)
	while prog < target_step:
		GameState.update_task_step(task_id)
		prog += 1

func _clear_panel() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null
