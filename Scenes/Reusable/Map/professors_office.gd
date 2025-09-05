extends Control

# ---------- Scene Nodes ----------
@export var professor_path: NodePath   = "background/Professor"
@export var janitor_path: NodePath     = "background/Janitor"
@export var back_button_path: NodePath = "background/Back"

@onready var professor_btn: Node = get_node_or_null(professor_path)
@onready var janitor_btn: Node   = get_node_or_null(janitor_path)
@onready var back_btn: Button    = get_node_or_null(back_button_path)

@onready var choice_panel_scene: PackedScene = preload("res://Scenes/Reusable/CharacterChoiceButtons.tscn")

# ---------- JSON paths ----------
const D_PROF: String = "res://Data/Dialogue/Professor/"

const JSON_PROF_INITIAL: String      = D_PROF + "Prof_Office_Initial.json"
const JSON_PROF_NOT_HERE: String     = D_PROF + "Prof_NotHere.json"
const JSON_PROF_FOLLOWUP_NR: String  = D_PROF + "Prof_Followup_NotReady.json"
const JSON_PROF_FOLLOWUP_OK: String  = D_PROF + "Prof_Followup_Accepted.json"
const JSON_PROF_ASK: String          = D_PROF + "Prof_Initial_AskDeadline.json"
const JSON_PROF_TOMORROW: String     = D_PROF + "Prof_Initial_BringTomorrow.json"
const JSON_PROF_DECLINE: String      = D_PROF + "Prof_Initial_Decline.json"

const JSON_GRADE_A: String           = D_PROF + "Prof_Grade_A.json"
const JSON_GRADE_B: String           = D_PROF + "Prof_Grade_B.json"
const JSON_GRADE_C: String           = D_PROF + "Prof_Grade_C.json"
const JSON_GRADE_D: String           = D_PROF + "Prof_Grade_D.json"
const JSON_GRADE_F: String           = D_PROF + "Prof_Grade_F.json"
const JSON_GRADE_F_PLAG: String      = D_PROF + "Prof_Grade_F_Plagiarized.json"

const JSON_FAIL_SECOND_CHANCE: String = D_PROF + "Prof_Fail_SecondChance.json"
const JSON_PRAISE_INIT: String        = D_PROF + "Prof_Praise_Initiative.json"
const JSON_SCOLD_MISSED: String       = D_PROF + "Prof_Scold_MissedPromise.json"
const JSON_POST_SUBMIT: String        = D_PROF + "Prof_PostSubmit.json"

# Janitor
const JSON_JANITOR_TIPPED_INTRO: String  = D_PROF + "Janitor_Office_Tipped_Intro.json"
const JSON_JANITOR_NOTIP_INTRO: String   = D_PROF + "Janitor_Office_NoTip_Intro.json"
const JSON_JANITOR_HIGHREP: String       = D_PROF + "Janitor_Office_NoAccess_HighRep.json"
const JSON_JANITOR_ANYTHING_ELSE: String = D_PROF + "Janitor_Office_AnythingElse.json"
const JSON_JANITOR_DEAL_300: String      = D_PROF + "Janitor_Deal_300.json"
const JSON_JANITOR_DEAL_500: String      = D_PROF + "Janitor_Deal_500.json"
const JSON_JANITOR_PASS: String          = D_PROF + "Janitor_Pass.json"
const JSON_JANITOR_NOMONEY: String       = D_PROF + "Janitor_NotEnoughMoney.json"

# ---------- Time gates ----------
const T_13_00: int = 13 * 60
const T_15_00: int = 15 * 60
const T_17_00: int = 17 * 60
const T_17_45: int = 17 * 60 + 45

# ---------- Gameplay ----------
const TASK_PROJECT: String = "project"
const PLAGIARISM_CATCH_CHANCE: float = 0.5

# ---------- Internals ----------
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

	# Professor 13:00–15:00
	if professor_btn:
		professor_btn.visible = _in(t, T_13_00, T_15_00)

	# Janitor 17:00–17:45 (D1 always; D2 if not bought)
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

	var options: Array[Dictionary] = []
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

func _project_ready_for_submit() -> bool:
	# Must not have submitted already
	if GameState.has_flag("project_submitted"):
		return false
	# Bought project bypasses print requirement
	if GameState.has_flag("bought_project"):
		return true
	# Self-written path requires the printed copy
	if GameState.has_flag("project_written") and GameState.has_flag("printed_project"):
		return true
	return false

func _handle_project_submission() -> void:
	# 1) Promise side-effects FIRST (praise/scold), then grading
	var side: String = _promise_reward_or_penalty()
	_clear_promise_flags()

	if side == "praise":
		DialogueManager.start_dialogue(JSON_PRAISE_INIT, self)
		await get_tree().create_timer(0.2).timeout
	elif side == "scold":
		DialogueManager.start_dialogue(JSON_SCOLD_MISSED, self)
		await get_tree().create_timer(0.2).timeout

	# 2) Grading logic
	var score: int = GameState.get_int("project_score", 0)
	var is_bought: bool = GameState.has_flag("bought_project")
	var caught_plag: bool = false

	if is_bought:
		GameState.set_flag("project_plagiarized", true)
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		caught_plag = rng.randf() < PLAGIARISM_CATCH_CHANCE
		if caught_plag:
			GameState.adjust_integrity(-5)
			print("[Integrity] Plagiarism detected at submission. -5 integrity.")

	if caught_plag:
		DialogueManager.start_dialogue(JSON_GRADE_F_PLAG, self)
		_mark_submitted_no_task_increment()
		return

	if is_bought and not caught_plag:
		DialogueManager.start_dialogue(JSON_GRADE_A, self)
		_valid_submit_increment_task()
		return

	# Normal grading path (self-written)
	var grade_id: String = _grade_from_score(score)
	if grade_id == "F":
		if GameState.day < 5:
			_reset_project_for_second_chance()
			DialogueManager.start_dialogue(JSON_FAIL_SECOND_CHANCE, self)
			return
		DialogueManager.start_dialogue(JSON_GRADE_F, self)
		_mark_submitted_no_task_increment()
		return

	match grade_id:
		"A": DialogueManager.start_dialogue(JSON_GRADE_A, self)
		"B": DialogueManager.start_dialogue(JSON_GRADE_B, self)
		"C": DialogueManager.start_dialogue(JSON_GRADE_C, self)
		"D": DialogueManager.start_dialogue(JSON_GRADE_D, self)
		_:   DialogueManager.start_dialogue(JSON_GRADE_C, self) # fallback
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
	GameState.update_task_step(TASK_PROJECT) # +1 on valid submit
	GameState.adjust_time(15)
	_clear_panel()

func _reset_project_for_second_chance() -> void:
	# Reset task back to step 1
	GameState.ensure_task(TASK_PROJECT)
	GameState.task_step_index[TASK_PROJECT] = 1
	print("[Task] Project reset to step 1 for second chance.")

	# Clear states so player can choose either path again (write OR buy)
	GameState.clear_flag("project_written")
	GameState.clear_flag("printed_project")
	GameState.clear_flag("bought_project")
	GameState.clear_flag("have_old_project")
	GameState.clear_flag("project_plagiarized")

func _promise_reward_or_penalty() -> String:
	# Returns "praise", "scold", or ""
	var promised: bool = GameState.has_flag("project_promise_tomorrow")
	var prom_day: int = GameState.get_int("project_promise_day", 0)
	if not promised or prom_day <= 0:
		return ""

	if GameState.day == prom_day + 1:
		GameState.adjust_reputation(+5)
		GameState.adjust_integrity(+5)
		return "praise"

	if GameState.day > prom_day + 1:
		GameState.adjust_reputation(-10)
		GameState.adjust_integrity(-10)
		return "scold"

	return ""

func _clear_promise_flags() -> void:
	GameState.clear_flag("project_promise_tomorrow")
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
	var options: Array[Dictionary] = [
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
			GameState.set_flag("project_promise_tomorrow", true)
			GameState.set_int("project_promise_day", GameState.day)
			DialogueManager.start_dialogue(JSON_PROF_TOMORROW, self)
		"prof_nevermind":
			DialogueManager.start_dialogue(JSON_PROF_DECLINE, self) # flavor
			await get_tree().create_timer(0.2).timeout
			 # loop until accepted
		_:
			DialogueManager.end_active_dialogue()

# ---------- Janitor ----------
var has_tip = GameFlags.TIPPED
func _on_janitor_pressed() -> void:
	_clear_panel()
	_janitor_panel_shown = false

	var rep: int = GameState.reputation
	if rep >= 30 and FileAccess.file_exists(JSON_JANITOR_HIGHREP):
		DialogueManager.start_dialogue(JSON_JANITOR_HIGHREP, self)
	elif has_tip==true:
		DialogueManager.start_dialogue(JSON_JANITOR_TIPPED_INTRO, self)
	else:
		DialogueManager.start_dialogue(JSON_JANITOR_NOTIP_INTRO, self)
func _show_janitor_office_options() -> void:
	
	if GameState.has_flag("bought_project"):
		DialogueManager.end_active_dialogue()
		return
	if _janitor_panel_shown:
		return
	_janitor_panel_shown = true

	var options: Array[Dictionary] = []
	 # tip flow not implemented; default to 500

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
	GameState.set_flag("project_plagiarized", true) # persist for endings
	GameState.set_flag("have_old_project", true)    # legacy compatibility
	GameState.adjust_integrity(-5)                  # buying penalty
	print("[Integrity] Bought project from janitor. -5 integrity.")
	GameState.ensure_task_progress_at_least(TASK_PROJECT, 2)
	if not GameState.tasks.has("Visit the Classroom"):
		GameState.add_task("Visit the Classroom")
	GameState.adjust_time(15)

	# FIX: no ternary operator; use if/else to pick the dialogue
	var dlg_path: String = JSON_JANITOR_DEAL_500
	if tipped:
		dlg_path = JSON_JANITOR_DEAL_300
	DialogueManager.start_dialogue(dlg_path, self)

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
func _clear_panel() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null
