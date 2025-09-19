extends Control

# -------- Inspector --------
@export var background_texrect_path: NodePath = ^"background"
@export var daniel_button_path: NodePath      = ^"background/Daniel"
@export var back_button_path: NodePath        = ^"background/Back"

# Separate volunteering scene (emits: signal finished(duty_key: String))
@export var volunteer_scene_path: String      = "res://Scenes/YCO/VolunteerSession.tscn"
@export var city_scene_path: String           = "res://Scenes/Reusable/Map/City.tscn"

@onready var choice_panel_scene: PackedScene  = preload("res://Scenes/Reusable/CharacterChoiceButtons.tscn")

# -------- JSON paths --------
const D: String = "res://Data/YCO/"
const J_INTRO: String             = D + "Daniel_Intro.json"          # preferred intro (line only is OK)
const J_INTRO_FALLBACK: String    = D + "Daniel_Intro_Only.json"

const J_OPT1_ACCEPT: String       = D + "Daniel_Option1_Accept.json"
const J_OPT2_INFO: String         = D + "Daniel_Option2_Info.json"
const J_OPT3_REPGATE: String      = D + "Daniel_Option3_RepGate.json"
const J_OPT3_BRIBE_OFFER: String  = D + "Daniel_Option3_BribeOffer.json"

const J_TALK_0: String            = D + "Daniel_Talk_0of3.json"
const J_TALK_1: String            = D + "Daniel_Talk_1of3.json"
const J_TALK_2: String            = D + "Daniel_Talk_2of3.json"
const J_TALK_3_GRANT: String      = D + "Daniel_Talk_3of3_GrantLetter.json"
const J_TALK_POST: String         = D + "Daniel_Talk_PostLetter.json"

const J_VOL_FLYERS: String        = D + "Volunteer_Flyers.json"
const J_VOL_FILING: String        = D + "Volunteer_Filing.json"
const J_VOL_SURVEY: String        = D + "Volunteer_Survey.json"
const J_VOL_TWICE: String         = D + "Volunteer_TwiceOneDay.json"
const J_VOL_LOCKED: String        = D + "Volunteer_Locked_PreAccept.json"

# -------- Task / Flags / Ints --------
const TASK_ID: String = "volunteer"

const F_REC_LETTER: String = "rec_letter_yco"
const F_ACCEPTED: String   = "yco_volunteer_accepted"
const F_BRIBED: String     = "yco_letter_bribed"

const I_COUNT: String    = "yco_volunteer_count"
const I_LAST_DAY: String = "yco_last_shift_day"

const REP_GATE_THRESHOLD: int = 10

# -------- Nodes --------
@onready var background: CanvasItem = get_node_or_null(background_texrect_path)
@onready var btn_daniel: Button     = get_node_or_null(daniel_button_path)
@onready var btn_back: Button       = get_node_or_null(back_button_path)

# -------- Menu state --------
var _active_menu: Control = null
var _menu_handler: Callable = Callable()

var _intro_played: bool = false                        # once per scene load
var _pending_menu_after_id: String = ""
var _pending_menu_choices: Array[Dictionary] = []
var _pending_menu_handler: Callable = Callable()

# optional Fade autoload instance
var _fade: Node = null

# =========================================================
# Helpers (declared early so no "not found" compile errors)
# =========================================================

func _ensure_task() -> void:
	GameState.ensure_task(TASK_ID)

func _sync_task_from_flags() -> void:
	_ensure_task()
	if _has_flag(F_REC_LETTER):
		while GameState.get_task_progress(TASK_ID) < 7:
			GameState.update_task_step(TASK_ID)

func _has_flag(k: String) -> bool:
	return GameState.has_flag(k)

func _set_flag(k: String, v: bool) -> void:
	GameState.set_flag(k, v)

func _count() -> int:
	return GameState.get_int(I_COUNT, 0)

func _set_count(v: int) -> void:
	GameState.set_int(I_COUNT, v)

func _last_day() -> int:
	return GameState.get_int(I_LAST_DAY, -999)

func _set_last_day(v: int) -> void:
	GameState.set_int(I_LAST_DAY, v)

func _day() -> int:
	return GameState.day

func _rep() -> int:
	return GameState.reputation

# =========================================================
# Lifecycle
# =========================================================
func _ready() -> void:
	_connect_btns()

	# Find Fade autoload safely (works whether or not you registered it)
	if has_node("/root/Fade"):
		_fade = get_node("/root/Fade")

	# React after dialogues to show menus as needed
	if not DialogueManager.is_connected("dialogue_finished", Callable(self, "_on_dialogue_finished")):
		DialogueManager.connect("dialogue_finished", Callable(self, "_on_dialogue_finished"))

	_ensure_task()
	if GameState.get_task_progress(TASK_ID) == 0:
		GameState.update_task_step(TASK_ID)

	_sync_task_from_flags()

func _connect_btns() -> void:
	if btn_daniel:
		btn_daniel.pressed.connect(_on_daniel)
	if btn_back:
		btn_back.pressed.connect(_on_back)

# =========================================================
# CCB menu helper
# =========================================================
func _show_menu(choices: Array[Dictionary], handler: Callable) -> void:
	_close_menu_if_any()

	var panel: Control = choice_panel_scene.instantiate() as Control
	_active_menu = panel
	_menu_handler = handler
	add_child(panel)
	panel.top_level = true
	panel.z_index = 4095

	if not panel.has_method("show_options"):
		push_error("CharacterChoiceButtons is missing show_options(options, callback).")
		_close_menu_if_any()
		return

	panel.call("show_options", choices, Callable(self, "_on_menu_choice_from_ccb"))

func _on_menu_choice_from_ccb(option_id: Variant) -> void:
	_close_menu_if_any()
	if _menu_handler.is_valid():
		_menu_handler.call(String(option_id))

func _close_menu_if_any() -> void:
	if _active_menu and is_instance_valid(_active_menu):
		_active_menu.queue_free()
	_active_menu = null
	_menu_handler = Callable()

# =========================================================
# Daniel entry
# =========================================================
func _on_daniel() -> void:
	_sync_task_from_flags()

	# Step 2 on first talk
	if GameState.get_task_progress(TASK_ID) == 1:
		GameState.update_task_step(TASK_ID)

	# Post-letter state: Talk only
	if _has_flag(F_REC_LETTER):
		_show_menu(
			[
				{"text":"Talk","id":"talk"},
				{"text":"Never mind","id":"back"}
			],
			Callable(self, "_idle_choice")
		)
		return

	# Not accepted & not bribed ⇒ show intro once, then menu
	if not _has_flag(F_ACCEPTED) and not _has_flag(F_BRIBED):
		if not _intro_played:
			_intro_played = true
			var intro_path: String = J_INTRO if ResourceLoader.exists(J_INTRO) else J_INTRO_FALLBACK
			var intro_id: String = _get_dialogue_id(intro_path)
			_set_pending_menu_after(
				intro_id,
				[
					{"text":"I’m here to volunteer.","id":"opt1"},
					{"text":"Depends. What would I be doing?","id":"opt2"},
					{"text":"Actually, I need a recommendation...","id":"opt3"},
					{"text":"I’ll come back later.","id":"back"}
				],
				Callable(self, "_first_choice")
			)
			_play_json(intro_path)
			return

		_show_menu(
			[
				{"text":"I’m here to volunteer.","id":"opt1"},
				{"text":"Depends. What would I be doing?","id":"opt2"},
				{"text":"Actually, I need a recommendation...","id":"opt3"},
				{"text":"I’ll come back later.","id":"back"}
			],
			Callable(self, "_first_choice")
		)
		return

	# Accepted or bribed (pre-letter): full menu
	_show_menu(
		[
			{"text":"Talk","id":"talk"},
			{"text":"Volunteer (once per day)","id":"vol"},
			{"text":"Never mind","id":"back"}
		],
		Callable(self, "_idle_choice")
	)

# Show menu after the given dialogue id finishes
func _set_pending_menu_after(dlg_id: String, choices: Array[Dictionary], handler: Callable) -> void:
	_pending_menu_after_id = dlg_id
	_pending_menu_choices = choices
	_pending_menu_handler = handler

func _on_dialogue_finished(dlg_id: String) -> void:
	if dlg_id == _pending_menu_after_id and _pending_menu_handler.is_valid():
		var choices_copy: Array[Dictionary] = _pending_menu_choices.duplicate(true)
		var handler_copy: Callable = _pending_menu_handler
		_pending_menu_after_id = ""
		_pending_menu_choices.clear()
		_pending_menu_handler = Callable()
		_show_menu(choices_copy, handler_copy)

func _get_dialogue_id(path: String) -> String:
	if not ResourceLoader.exists(path):
		return path.get_file().get_basename()
	var txt: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) == TYPE_DICTIONARY:
		var meta: Variant = (parsed as Dictionary).get("meta", {})
		if typeof(meta) == TYPE_DICTIONARY and (meta as Dictionary).has("id"):
			return String((meta as Dictionary).get("id"))
	return path.get_file().get_basename()

# =========================================================
# Choice handlers
# =========================================================
func _first_choice(id: String) -> void:
	match id:
		"opt1":
			_set_flag(F_ACCEPTED, true)
			_ensure_task()
			while GameState.get_task_progress(TASK_ID) < 3:
				GameState.update_task_step(TASK_ID)
			_play_json(J_OPT1_ACCEPT)
		"opt2":
			_play_json(J_OPT2_INFO)
		"opt3":
			if _rep() >= REP_GATE_THRESHOLD:
				_play_json(J_OPT3_REPGATE)
			else:
				_play_json(J_OPT3_BRIBE_OFFER)
		"back":
			pass

func _idle_choice(id: String) -> void:
	match id:
		"talk":
			_do_talk()
		"vol":
			_do_volunteer()
		"back":
			pass

# =========================================================
# Talk flow
# =========================================================
func _do_talk() -> void:
	_sync_task_from_flags()

	if _has_flag(F_REC_LETTER):
		_play_json(J_TALK_POST)
		return

	var c: int = _count()
	match c:
		0:
			_play_json(J_TALK_0)
		1:
			_play_json(J_TALK_1)
		2:
			_play_json(J_TALK_2)
		3:
			_set_flag(F_REC_LETTER, true)
			_play_json(J_TALK_3_GRANT)
			_ensure_task()
			if GameState.get_task_progress(TASK_ID) == 6:
				GameState.update_task_step(TASK_ID)

# =========================================================
# Volunteer flow
# =========================================================
func _do_volunteer() -> void:
	if not _has_flag(F_ACCEPTED):
		_play_json(J_VOL_LOCKED)
		return
	if _has_flag(F_REC_LETTER):
		_play_json(J_TALK_POST)
		return
	if _last_day() == _day():
		_play_json(J_VOL_TWICE)
		return
	if _count() >= 3:
		_do_talk()
		return

	_show_menu(
		[
			{"text":"Outreach & Flyers","id":"flyers"},
			{"text":"Archive & Filing","id":"filing"},
			{"text":"Survey Help","id":"survey"},
			{"text":"Never mind","id":"back"}
		],
		Callable(self, "_on_volunteer_choice")
	)

func _on_volunteer_choice(choice_id: String) -> void:
	if choice_id == "back":
		return
	_start_session(choice_id)

func _start_session(duty_key: String) -> void:
	var p: PackedScene = load(volunteer_scene_path) as PackedScene
	if p == null:
		push_error("Volunteer scene missing: %s" % volunteer_scene_path)
		return

	var s_node: Node = p.instantiate()
	add_child(s_node)

	if s_node is CanvasItem:
		var s_ci: CanvasItem = s_node as CanvasItem
		s_ci.top_level = true
		s_ci.z_index = 4095

	if s_node.has_method("set_duty"):
		s_node.call("set_duty", duty_key)

	if s_node.has_signal("finished"):
		s_node.connect("finished", Callable(self, "_on_session_finished"))
	else:
		_on_session_finished(duty_key)

func _on_session_finished(duty_key: String) -> void:
	# Clean up any child that exposes the "finished" signal (the volunteer overlay)
	for child in get_children():
		if child and child.has_signal("finished"):
			child.queue_free()

	match duty_key:
		"flyers":
			_play_json(J_VOL_FLYERS)
		"filing":
			_play_json(J_VOL_FILING)
		"survey":
			_play_json(J_VOL_SURVEY)
		_:
			_play_json(J_VOL_FLYERS)

	var c: int = _count() + 1
	_set_count(c)
	_set_last_day(_day())

	_ensure_task()
	var prog: int = GameState.get_task_progress(TASK_ID)
	if prog >= 3 and prog < 6:
		GameState.update_task_step(TASK_ID)

# =========================================================
# Back (Fade if present)
# =========================================================
func _on_back() -> void:
	if city_scene_path == "":
		return
	if _fade and _fade.has_method("fade_to_scene"):
		await _fade.call("fade_to_scene", city_scene_path)
	else:
		get_tree().change_scene_to_file(city_scene_path)

# =========================================================
# Dialogue hook (your manager)
# =========================================================
func _play_json(path: String) -> void:
	if not ResourceLoader.exists(path):
		push_error("Dialogue JSON missing: %s" % path)
		return
	DialogueManager.start_dialogue(path, self)

# Optional: handle JSON-driven actions (if any remain)
func on_dialogue_action(line: Dictionary) -> void:
	var act: String = String(line.get("action", ""))
	if act == "":
		return
	if act == "yco_accept":
		_set_flag(F_ACCEPTED, true)
		_ensure_task()
		while GameState.get_task_progress(TASK_ID) < 3:
			GameState.update_task_step(TASK_ID)
	elif act == "yco_grant_letter":
		_set_flag(F_REC_LETTER, true)
		_ensure_task()
		while GameState.get_task_progress(TASK_ID) < 7:
			GameState.update_task_step(TASK_ID)
	elif act == "yco_bribed":
		_set_flag(F_BRIBED, true)
		_set_flag(F_REC_LETTER, true)
		_ensure_task()
		while GameState.get_task_progress(TASK_ID) < 7:
			GameState.update_task_step(TASK_ID)
	else:
		# forward any time-related actions if you kept them in JSON
		GameState.apply_action(line)
