extends Control

# ---------- Scene Paths ----------
@export var background_path: NodePath = ^"background"
@export var talk_button_path: NodePath = ^"background/Talk"
@export var choice_panel_scene: PackedScene = preload("res://Scenes/Reusable/CharacterChoiceButtons.tscn")

# Optional: where to send the player if we kick them out after-hours
@export var city_scene_path: String = "res://Scenes/Reusable/Map/City.tscn"

# ---------- JSON paths ----------
const D := "res://Data/MVR/files/"

const J_OPEN_ARRIVAL              := D + "MVR_Open_Arrival.json"
const J_REQUEST_CLERK             := D + "MVR_Request_Clerk.json"

const J_PAY_STANDARD              := D + "MVR_Payment_Standard.json"
const J_PAY_EXPEDITED             := D + "MVR_Payment_Expedited.json"
const J_PAY_BRIBE_OFFER           := D + "MVR_Payment_Bribery_Offer.json"

const J_BRIBE_WAIT                := D + "MVR_Bribery_Wait.json"
const J_BRIBE_COME_LATER          := D + "MVR_Bribery_ComeLater.json"

const J_FOLLOW_STANDARD           := D + "MVR_Standard_Followup.json"
const J_FOLLOW_EXPEDITED          := D + "MVR_Expedited_Followup.json"
const J_FOLLOW_BRIBERY            := D + "MVR_Bribery_Followup.json"

const J_PICKUP_LEGAL              := D + "MVR_Pickup_Legal.json"
const J_PICKUP_BRIBERY            := D + "MVR_Pickup_Bribery.json"

# ---------- Costs / Gates ----------
const COST_STANDARD := 150
const COST_EXPEDITED := 500
const COST_BRIBE := 1000

const T_COST_STANDARD := 35
const T_COST_EXPEDITED := 30
const T_COST_PICKUP := 20

const INTEGRITY_BRIBE_GATE    := 40
const INTEGRITY_BRIBE_PAYMENT := -15
const INTEGRITY_BRIBE_PICKUP  := -5

# ---------- Time ----------
const T_BRIBE_PICK := 16 * 60
const T_AFTER_HOURS_LIMIT := 16 * 60 + 30

const END_DAY := 5
func _can_standard_today() -> bool: return GameState.day <= 2
func _can_expedite_today() -> bool: return GameState.day <= 4

# ---------- Nodes ----------
var _bg: TextureRect
var _btn_talk: Button
var _panel: Control = null
var _fade_layer: ColorRect

var _arrival_shown: bool = false
var _last_is_night = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.location = "MVR"

	_bg = get_node_or_null(background_path) as TextureRect
	_btn_talk = get_node_or_null(talk_button_path) as Button

	if _btn_talk and not _btn_talk.pressed.is_connected(Callable(self, "_on_talk")):
		_btn_talk.pressed.connect(_on_talk)

	_make_fade_layer()

func _process(_dt: float) -> void:
	if GameState.time >= T_AFTER_HOURS_LIMIT:
		if not _method_bribery() or GameState.has_flag(GameFlags.HAVE_BIRTH_CERTIFICATE):
			_go_city()

# ---------- Helpers ----------
func _clear_panel() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null

func _play_json(path: String) -> Control:
	if path == "":
		return null
	if ResourceLoader.exists(path):
		return DialogueManager.start_dialogue(path, self)
	return null

func _pay(amount: int) -> bool:
	if GameState.money < amount:
		return false
	GameState.add_money(-amount)
	if not GameState.has_flag(GameFlags.SPENT_MONEY_ONCE):
		GameState.set_flag(GameFlags.SPENT_MONEY_ONCE, true)
	return true

func _ready_day() -> int:
	return GameState.get_int(GameFlags.MVR_BCERT_READY_DAY, 0)

func _days_remaining() -> int:
	var rd := _ready_day()
	if rd <= 0:
		return 0
	var rem := rd - GameState.day
	if rem < 0:
		rem = 0
	return rem

func _method_standard() -> bool: return GameState.has_flag(GameFlags.MVR_BCERT_STANDARD)
func _method_expedited() -> bool: return GameState.has_flag(GameFlags.MVR_BCERT_EXPEDITED)
func _method_bribery() -> bool: return GameState.has_flag(GameFlags.MVR_BCERT_BRIBERY)
func _has_started() -> bool: return GameState.has_flag(GameFlags.MVR_BCERT_STARTED)

# ---------- Fade utility ----------
func _make_fade_layer() -> void:
	_fade_layer = ColorRect.new()
	_fade_layer.color = Color(0,0,0,0)
	_fade_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fade_layer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_fade_layer)
	_fade_layer.set_anchors_preset(Control.PRESET_FULL_RECT)

func _fade_in_out(dur := 0.35) -> void:
	var tw1 := create_tween()
	tw1.tween_property(_fade_layer, "color", Color(0,0,0,1), dur)
	await tw1.finished
	var tw2 := create_tween()
	tw2.tween_property(_fade_layer, "color", Color(0,0,0,0), dur)
	await tw2.finished

# ---------- Main Talk entry ----------
func _on_talk() -> void:
	_clear_panel()

	if _has_started():
		_handle_followups_or_pickup()
		return

	if not _arrival_shown:
		_arrival_shown = true
		_play_json(J_OPEN_ARRIVAL)

	_show_greeting_menu()

# ---------- Greeting -> Ask flow ----------
func _show_greeting_menu() -> void:
	var opts: Array = [
		{"id":"ask","text":"I need a birth certificate."},
		{"id":"bye","text":"Never mind."}
	]
	_panel = choice_panel_scene.instantiate()
	add_child(_panel)
	_panel.call("show_options", opts, Callable(self, "_on_greeting_choice"))

func _play_and_then_show_methods(path: String) -> void:
	var ui: Control = DialogueManager.start_dialogue(path, self)
	if ui and ui.has_signal("dialogue_finished"):
		var sig := Signal(ui, "dialogue_finished")
		await sig
	_show_method_menu()

func _on_greeting_choice(id: String) -> void:
	match id:
		"ask":
			GameState.ensure_task("birth")
			GameState.update_task_step("birth")
			await _play_and_then_show_methods(J_REQUEST_CLERK)
		"bye":
			_clear_panel()
		_:
			pass

# ---------- Method selection ----------
func _show_method_menu() -> void:
	var opts: Array = []
	if _can_standard_today():
		opts.append({"id":"standard","text":"Standard (150 ден) – Ready in 3 days"})
	if _can_expedite_today():
		opts.append({"id":"expedited","text":"Expedited (500 ден) – Ready tomorrow"})
	if GameState.integrity < INTEGRITY_BRIBE_GATE:
		opts.append({"id":"bribe","text":"Same-day (1,000 ден) – After 16:00"})
	opts.append({"id":"think","text":"Let me think on it."})

	_panel = choice_panel_scene.instantiate()
	add_child(_panel)
	_panel.call("show_options", opts, Callable(self, "_on_method_choice"))

func _on_method_choice(id: String) -> void:
	match id:
		"standard":
			_choose_standard()
		"expedited":
			_choose_expedited()
		"bribe":
			_choose_bribery()
		"think":
			_clear_panel()
		_:
			pass

# ---------- Choosing methods ----------
func _choose_standard() -> void:
	_clear_panel()
	if not _can_standard_today() or not _pay(COST_STANDARD):
		return

	GameState.adjust_time(T_COST_STANDARD)
	GameState.set_flag(GameFlags.MVR_BCERT_STARTED, true)
	GameState.set_flag(GameFlags.MVR_BCERT_STANDARD, true)
	GameState.set_int(GameFlags.MVR_BCERT_READY_DAY, GameState.day + 3)
	GameState.ensure_task("birth")
	GameState.update_task_step("birth")
	_play_json(J_PAY_STANDARD)

func _choose_expedited() -> void:
	_clear_panel()
	if not _can_expedite_today() or not _pay(COST_EXPEDITED):
		return

	GameState.adjust_time(T_COST_EXPEDITED)
	GameState.set_flag(GameFlags.MVR_BCERT_STARTED, true)
	GameState.set_flag(GameFlags.MVR_BCERT_EXPEDITED, true)
	GameState.set_int(GameFlags.MVR_BCERT_READY_DAY, GameState.day + 1)
	GameState.ensure_task("birth")
	GameState.update_task_step("birth")
	_play_json(J_PAY_EXPEDITED)

func _choose_bribery() -> void:
	_clear_panel()
	if GameState.integrity >= INTEGRITY_BRIBE_GATE or not _pay(COST_BRIBE):
		return

	GameState.adjust_integrity(INTEGRITY_BRIBE_PAYMENT)
	GameState.set_flag(GameFlags.MVR_BCERT_STARTED, true)
	GameState.set_flag(GameFlags.MVR_BCERT_BRIBERY, true)
	GameState.set_int(GameFlags.MVR_BCERT_READY_DAY, GameState.day)
	GameState.ensure_task("birth")
	GameState.update_task_step("birth")
	_play_json(J_PAY_BRIBE_OFFER)
	_show_bribe_wait_menu()

# ---------- Follow-ups & Pickup ----------
func _handle_followups_or_pickup() -> void:
	if _method_bribery():
		if GameState.time >= T_BRIBE_PICK:
			_do_pickup_bribery()
		else:
			_play_json(J_FOLLOW_BRIBERY)
			_show_bribe_wait_menu()
		return

	if _method_standard():
		if _days_remaining() == 0:
			_do_pickup_legal()
		else:
			_play_json(J_FOLLOW_STANDARD)
		return

	if _method_expedited():
		if _days_remaining() == 0:
			_do_pickup_legal()
		else:
			_play_json(J_FOLLOW_EXPEDITED)
		return

func _show_bribe_wait_menu() -> void:
	var opts: Array = []
	if GameState.time < T_BRIBE_PICK:
		opts.append({"id":"wait","text":"Wait here until 16:00"})
	opts.append({"id":"later","text":"I’ll come back later"})
	_panel = choice_panel_scene.instantiate()
	add_child(_panel)
	_panel.call("show_options", opts, Callable(self, "_on_bribe_wait_choice"))

func _on_bribe_wait_choice(id: String) -> void:
	_clear_panel()
	match id:
		"wait":
			if GameState.time < T_BRIBE_PICK:
				await _fade_in_out(0.35)
				var delta := T_BRIBE_PICK - GameState.time
				if delta > 0:
					GameState.adjust_time(delta)
			_play_json(J_BRIBE_WAIT)
		"later":
			_play_json(J_BRIBE_COME_LATER)

func _do_pickup_legal() -> void:
	GameState.adjust_time(T_COST_PICKUP)
	GameState.set_flag(GameFlags.HAVE_BIRTH_CERTIFICATE, true)
	_play_json(J_PICKUP_LEGAL)
	_go_city()

func _do_pickup_bribery() -> void:
	GameState.adjust_time(T_COST_PICKUP)
	GameState.adjust_integrity(INTEGRITY_BRIBE_PICKUP)
	GameState.set_flag(GameFlags.HAVE_BIRTH_CERTIFICATE, true)
	_play_json(J_PICKUP_BRIBERY)
	_go_city()

# ---------- Navigation ----------
func _go_city() -> void:
	if city_scene_path == "" or not ResourceLoader.exists(city_scene_path):
		return
	_clear_panel()
	call_deferred("_deferred_change_scene", city_scene_path)

func _deferred_change_scene(p: String) -> void:
	var tree := get_tree()
	if tree and ResourceLoader.exists(p):
		tree.change_scene_to_file(p)

# ---------- Dialogue action hook ----------
func on_dialogue_action(line: Dictionary) -> void:
	GameState.apply_action(line)
