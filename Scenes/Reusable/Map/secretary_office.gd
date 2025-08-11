extends Control

@onready var secretary: Node = $background/Secretary
@onready var choice_panel_scene: PackedScene = preload("res://Scenes/Reusable/CharacterChoiceButtons.tscn")

const GSR_ID := "Gather Scholarship Requirements"
const VISIT_SEC_ID := "Visit the Secretary"
const CORE_REQUIREMENTS := ["birth","transcript","cv","motivation","project","language"]

var _active_panel: Control = null
var _pending_close_to_school: bool = false
var _task_steps_cache: Dictionary = {}   # { task_id: step_count }

func _ready() -> void:
	GameState.location = "SecretaryOffice"

	# Cross visit step on first entry (any day)
	if GameState.tasks.has(VISIT_SEC_ID) and GameState.get_task_progress(VISIT_SEC_ID) == 0:
		GameState.update_task_step(VISIT_SEC_ID)

	# React to subtask progress (auto-cross requirements step)
	if not GameState.task_updated.is_connected(Callable(self, "_on_any_task_updated")):
		GameState.task_updated.connect(Callable(self, "_on_any_task_updated"))

	# Day 1 intro window
	if GameState.day == 1 and GameState.time >= 13 * 60 and GameState.time < 16 * 60:
		if not GameState.has_flag("secretary_met"):
			GameState.set_flag("secretary_met", true)
			GameState.ensure_task(GSR_ID)
			var ui: Control = DialogueManager.start_dialogue("res://Data/Dialogue/Secretary/Secretary_Initial.json", self)
			if ui and ui.has_signal("dialogue_finished"):
				ui.connect("dialogue_finished", Callable(self, "_on_intro_done"))

	_try_mark_requirements_step()

func _process(_delta: float) -> void:
	# Close office at 16:00; don’t interrupt dialogue
	if GameState.time >= 16 * 60:
		if GameState.is_time_frozen():
			_pending_close_to_school = true
		else:
			_close_to_school()

func _on_intro_done(_dlg_id: String = "", _payload: Variant = null) -> void:
	# Kept for potential future gating; no “leave-room back” anymore
	GameState.set_flag("secretary_first_exit_done", true)

func _close_to_school() -> void:
	print("🔒 The secretary has left for the day. Returning to school.")
	get_tree().change_scene_to_file("res://Scenes/Reusable/Map/School.tscn")

func _clear_panel() -> void:
	if _active_panel and is_instance_valid(_active_panel):
		_active_panel.queue_free()
	_active_panel = null

# Called by the Secretary button in the scene
func start_interaction() -> void:
	if _pending_close_to_school and not GameState.is_time_frozen():
		_pending_close_to_school = false
		_close_to_school()
		return

	_clear_panel()

	var options: Array = []
	options.append({ "text": "Ask about scholarship", "id": "talk" })
	if _should_offer_notary_info():
		options.append({ "text": "Where can I notarize my certificate?", "id": "notary_info" })
	if _has_any_printables():
		options.append({ "text": "Print a document", "id": "print" })
	if GameState.day >= 5:
		options.append({ "text": "Submit documents", "id": "submit" })

	# Persistent Back: just closes the choice panel (stays in the office)
	options.append({ "text": "Back", "id": "back_dialogue" })

	_active_panel = choice_panel_scene.instantiate() as Control
	add_child(_active_panel)
	_active_panel.call("show_options", options, Callable(self, "_on_choice_selected"))

func _on_choice_selected(choice_id: String) -> void:
	match choice_id:
		"talk":
			DialogueManager.start_dialogue("res://Data/Dialogue/Secretary/Secretary_Talk.json", self)
		"notary_info":
			print("📝 Notary: near City Hall (09:00–16:00).")
			_clear_panel()
		"print":
			_show_printable_options()
		"submit":
			if GameState.day >= 5:
				_try_mark_requirements_step()
				DialogueManager.start_dialogue("res://Data/Dialogue/Secretary/Secretary_Submit.json", self)
				# Mark visit task progression to submit (step 2 then 3)
				if GameState.get_task_progress(VISIT_SEC_ID) < 3:
					if GameState.get_task_progress(VISIT_SEC_ID) == 1 and _requirements_complete():
						GameState.update_task_step(VISIT_SEC_ID) # -> 2
					GameState.update_task_step(VISIT_SEC_ID)     # -> 3
			else:
				print("⏳ Submissions open on Day 5.")
			_clear_panel()
		"back_dialogue":
			_clear_panel()

func _should_offer_notary_info() -> bool:
	if GameState.has_flag("mvr_visited"):
		return true
	var birth_progress: int = GameState.get_task_progress("birth")
	return birth_progress >= 3 and not GameState.has_flag("notarized_birth")

func _has_any_printables() -> bool:
	if GameState.has_feature("transcript") and not GameState.has_flag("printed_transcript"): return true
	if GameState.has_feature("final_project") and not GameState.has_flag("printed_project"): return true
	if GameState.has_feature("cv") and not GameState.has_flag("printed_cv"): return true
	return false

func _show_printable_options() -> void:
	_clear_panel()
	var options: Array = []
	var price: int = int(GameState.PRICES.get("print", 10))
	if GameState.has_feature("transcript") and not GameState.has_flag("printed_transcript"):
		options.append({ "text": "Print transcript (%d$)" % price, "id": "transcript" })
	if GameState.has_feature("final_project") and not GameState.has_flag("printed_project"):
		options.append({ "text": "Print final project (%d$)" % price, "id": "project" })
	if GameState.has_feature("cv") and not GameState.has_flag("printed_cv"):
		options.append({ "text": "Print CV (%d$)" % price, "id": "cv" })
	if options.is_empty():
		print("ℹ️ Nothing to print.")
		return
	_active_panel = choice_panel_scene.instantiate() as Control
	add_child(_active_panel)
	_active_panel.call("show_options", options, Callable(self, "_on_print_selected"))

func _on_print_selected(id: String) -> void:
	var price: int = int(GameState.PRICES.get("print", 10))
	if GameState.money < price:
		print("❌ Not enough money to print.")
		return
	GameState.money -= price
	GameState.emit_signal("money_changed", GameState.money)
	match id:
		"transcript":
			GameState.set_flag("printed_transcript", true)
			GameState.update_task_step(GSR_ID)
		"project":
			GameState.set_flag("printed_project", true)
			GameState.update_task_step(GSR_ID)
		"cv":
			GameState.set_flag("printed_cv", true)
			GameState.update_task_step(GSR_ID)
	print("📄 Document printed successfully!")
	_clear_panel()
	_try_mark_requirements_step()

func _on_any_task_updated(_id: String, _idx: int) -> void:
	_try_mark_requirements_step()

func _try_mark_requirements_step() -> void:
	# Steps: 0 visit, 1 requirements, 2 submit, 3 done
	if GameState.get_task_progress(VISIT_SEC_ID) == 0: return
	if GameState.get_task_progress(VISIT_SEC_ID) >= 2: return
	if _requirements_complete():
		if GameState.get_task_progress(VISIT_SEC_ID) == 1: return
		GameState.update_task_step(VISIT_SEC_ID) # -> 1

func _requirements_complete() -> bool:
	for t in CORE_REQUIREMENTS:
		if not _is_task_complete(String(t)):
			return false
	return true

func _is_task_complete(task_id: String) -> bool:
	var total: int = _get_task_steps_count(task_id)
	if total <= 0:
		return false
	return GameState.get_task_progress(task_id) >= total

func _get_task_steps_count(task_id: String) -> int:
	if _task_steps_cache.has(task_id):
		return int(_task_steps_cache[task_id])
	var file_path: String = "res://Data/Tasks/%s.json" % task_id
	if not FileAccess.file_exists(file_path):
		_task_steps_cache[task_id] = 0
		return 0
	var f: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if not f:
		_task_steps_cache[task_id] = 0
		return 0
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		_task_steps_cache[task_id] = 0
		return 0
	var steps: Array = (parsed as Dictionary).get("steps", [])
	var n: int = steps.size()
	_task_steps_cache[task_id] = n
	return n

func on_dialogue_action(line: Dictionary) -> void:
	GameState.apply_action(line)
