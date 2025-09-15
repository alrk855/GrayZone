extends Control

# -------- Inspector --------
@export var background_texrect_path: NodePath = ^"background"
@export var daniel_button_path: NodePath      = ^"background/Daniel"
@export var back_button_path: NodePath        = ^"background/Back"

# Separate volunteering scene (emits: signal finished(duty_key: String))
@export var volunteer_scene_path: String      = "res://Scenes/YCO/VolunteerSession.tscn"
@export var city_scene_path: String           = "res://Scenes/Reusable/Map/City.tscn"

@onready var choice_panel_scene: PackedScene  = preload("res://Scenes/Reusable/CharacterChoiceButtons.tscn")

# -------- JSON paths (unchanged) --------
const D := "res://Data/YCO/"
const J_OPT1_ACCEPT          := D + "Daniel_Option1_Accept.json"
const J_OPT2_INFO            := D + "Daniel_Option2_Info.json"
const J_OPT3_REPGATE         := D + "Daniel_Option3_RepGate.json"
const J_OPT3_BRIBE_OFFER     := D + "Daniel_Option3_BribeOffer.json"

const J_TALK_0               := D + "Daniel_Talk_0of3.json"
const J_TALK_1               := D + "Daniel_Talk_1of3.json"
const J_TALK_2               := D + "Daniel_Talk_2of3.json"
const J_TALK_3_GRANT         := D + "Daniel_Talk_3of3_GrantLetter.json"
const J_TALK_POST            := D + "Daniel_Talk_PostLetter.json"

const J_VOL_FLYERS           := D + "Volunteer_Flyers.json"
const J_VOL_FILING           := D + "Volunteer_Filing.json"
const J_VOL_SURVEY           := D + "Volunteer_Survey.json"
const J_VOL_TWICE            := D + "Volunteer_TwiceOneDay.json"
const J_VOL_LOCKED           := D + "Volunteer_Locked_PreAccept.json"

# -------- Task / Flags / Ints --------
const TASK_ID := "volunteer"

const F_REC_LETTER := "rec_letter_yco"
const F_ACCEPTED   := "yco_volunteer_accepted"
const F_BRIBED     := "yco_letter_bribed"

const I_COUNT      := "yco_volunteer_count"
const I_LAST_DAY   := "yco_last_shift_day"

const REP_GATE_THRESHOLD := 10

# -------- Nodes / FX --------
@onready var background: CanvasItem = get_node_or_null(background_texrect_path)
@onready var btn_daniel: Button     = get_node_or_null(daniel_button_path)
@onready var btn_back: Button       = get_node_or_null(back_button_path)

var _fader: ColorRect
var _tw: Tween

# menu state (to avoid inline lambdas)
var _active_menu: Node = null
var _menu_handler: Callable
var _menu_choices: Array = []

func _ready() -> void:
	_setup_fade()
	_connect_btns()
	_fade_in()

	# Add task if missing and mark "visit_office" once (step 1)
	_ensure_task()
	if GameState.get_task_progress(TASK_ID) == 0:
		GameState.update_task_step(TASK_ID)

	# If letter already owned (e.g., bribe elsewhere), fast-forward to final step
	_sync_task_from_flags()

func _connect_btns() -> void:
	if btn_daniel:
		btn_daniel.pressed.connect(_on_daniel)
	if btn_back:
		btn_back.pressed.connect(_on_back)

# -------- Fade --------
func _setup_fade() -> void:
	_fader = ColorRect.new()
	_fader.color = Color.BLACK
	_fader.size = get_viewport_rect().size
	_fader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fader)
	_fader.move_to_front()
	_fader.modulate.a = 1.0

func _fade_in() -> void:
	if _tw:
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(_fader, "modulate:a", 0.0, 0.35)

func _fade_out(cb: Callable) -> void:
	if _tw:
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(_fader, "modulate:a", 1.0, 0.25)
	_tw.finished.connect(cb)

func _go_back() -> void:
	if city_scene_path != "":
		get_tree().change_scene_to_file(city_scene_path)

# -------- Menu helper (no inline funcs) --------
func _show_menu(choices: Array, handler: Callable) -> void:
	_close_menu_if_any()

	var panel := choice_panel_scene.instantiate()
	_active_menu = panel
	_menu_handler = handler
	_menu_choices = choices.duplicate(true)

	add_child(panel)
	panel.z_index = 9999

	if not panel.has_method("set_choices"):
		push_warning("CharacterChoiceButtons missing set_choices(). Adapt if needed.")
		_close_menu_if_any()
		return
	panel.set_choices(choices)

	var wired: bool = false
	if panel.has_signal("choice_made"):
		panel.choice_made.connect(_on_menu_choice_made)
		wired = true
	elif panel.has_signal("choice_selected"):
		panel.choice_selected.connect(_on_menu_choice_selected)
		wired = true

	if not wired:
		push_warning("CharacterChoiceButtons: unknown signal; wire it here.")
		_close_menu_if_any()

func _close_menu_if_any() -> void:
	if _active_menu and is_instance_valid(_active_menu):
		_active_menu.queue_free()
	_active_menu = null
	_menu_handler = Callable() # reset invalid
	_menu_choices = []

func _on_menu_choice_made(choice_id: String) -> void:
	_close_menu_if_any()
	if _menu_handler.is_valid():
		_menu_handler.call(choice_id)

func _on_menu_choice_selected(idx: int, _text: String) -> void:
	var cid := String(_menu_choices[idx].get("id", str(idx)))
	_close_menu_if_any()
	if _menu_handler.is_valid():
		_menu_handler.call(cid)

# -------- Daniel entry --------
func _on_daniel() -> void:
	_sync_task_from_flags()

	# First time talking to Daniel completes "talk_daniel" (step 2)
	if GameState.get_task_progress(TASK_ID) == 1:
		GameState.update_task_step(TASK_ID)

	if _has_flag(F_REC_LETTER):
		_show_menu(
			[
				{"text":"Talk","id":"talk"},
				{"text":"Never mind","id":"back"}
			],
			_idle_choice
		)
		return

	if not _has_flag(F_ACCEPTED) and not _has_flag(F_BRIBED):
		_show_menu(
			[
				{"text":"I’m here to volunteer.","id":"opt1"},
				{"text":"Depends. What would I be doing?","id":"opt2"},
				{"text":"Actually, I need a recommendation...","id":"opt3"},
				{"text":"I’ll come back later.","id":"back"}
			],
			_first_choice
		)
		return

	_show_menu(
		[
			{"text":"Talk","id":"talk"},
			{"text":"Volunteer (once per day)","id":"vol"},
			{"text":"Never mind","id":"back"}
		],
		_idle_choice
	)

func _first_choice(id: String) -> void:
	match id:
		"opt1":
			# Accept → step 3
			_play_json(J_OPT1_ACCEPT)
			_set_flag(F_ACCEPTED, true)
			_ensure_task()
			while GameState.get_task_progress(TASK_ID) < 3:
				GameState.update_task_step(TASK_ID)
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

# -------- Talk (progress-aware) --------
func _do_talk() -> void:
	_sync_task_from_flags()
	if _has_flag(F_REC_LETTER):
		_play_json(J_TALK_POST)
		return

	var c := _count()
	match c:
		0:
			_play_json(J_TALK_0)
		1:
			_play_json(J_TALK_1)
		2:
			_play_json(J_TALK_2)
		3:
			# Grant letter via script; then advance final step
			_set_flag(F_REC_LETTER, true)
			_play_json(J_TALK_3_GRANT)
			_ensure_task()
			# we expect current progress == 6 (after 3 sessions). Advance once to step 7 ("letter")
			if GameState.get_task_progress(TASK_ID) == 6:
				GameState.update_task_step(TASK_ID)

# -------- Volunteer (once/day) --------
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
		_on_volunteer_choice
	)

func _on_volunteer_choice(choice_id: String) -> void:
	if choice_id == "back":
		return
	_start_session(choice_id)

func _start_session(duty_key: String) -> void:
	var p := load(volunteer_scene_path)
	if p == null:
		push_error("Volunteer scene missing: %s" % volunteer_scene_path)
		return

	var s = p.instantiate()
	add_child(s)
	s.z_index = 5000

	if s.has_method("set_duty"):
		s.set_duty(duty_key)

	if s.has_signal("finished"):
		s.finished.connect(_on_session_finished)
	else:
		# No signal? Treat as instant finish.
		_on_session_finished(duty_key)

func _on_session_finished(duty_key: String) -> void:
	# Clean up session node if still present
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

	var c := _count() + 1
	_set_count(c)
	_set_last_day(_day())

	_ensure_task()
	# shift completions → steps 4,5,6 (one bump per session)
	var prog := GameState.get_task_progress(TASK_ID)
	if prog >= 3 and prog < 6:
		GameState.update_task_step(TASK_ID)

# -------- Back --------
func _on_back() -> void:
	_fade_out(Callable(self, "_go_back"))

# -------- Sync & helpers --------
func _sync_task_from_flags() -> void:
	_ensure_task()
	if _has_flag(F_REC_LETTER):
		# fast-forward to final step (7) using single-arg increments
		while GameState.get_task_progress(TASK_ID) < 7:
			GameState.update_task_step(TASK_ID)

func _ensure_task() -> void:
	GameState.ensure_task(TASK_ID)

# -------- GameState shims --------
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

# -------- Dialogue launcher --------
func _play_json(path: String) -> void:
	var dlg := get_tree().root.get_node_or_null("/root/Dialogue")
	if dlg and dlg.has_method("start"):
		dlg.start(path)
		return
	var dm := get_tree().root.get_node_or_null("/root/DialogueManager")
	if dm and dm.has_method("start"):
		dm.start(path)
		return
