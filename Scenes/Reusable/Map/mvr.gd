extends Control

# ---------- Scene Paths ----------
@export var background_path = ^"background"
@export var talk_button_path = ^"background/Talk"
@export var choice_panel_scene = preload("res://Scenes/Reusable/CharacterChoiceButtons.tscn")
@export var city_scene_path = "res://Scenes/Reusable/Map/City.tscn"

# ---------- JSON paths ----------
const D = "res://Data/MVR/files/"
const J_OPEN_ARRIVAL     = D + "MVR_Open_Arrival.json"
const J_REQUEST_CLERK    = D + "MVR_Request_Clerk.json"
const J_PAY_STANDARD     = D + "MVR_Payment_Standard.json"
const J_PAY_EXPEDITED    = D + "MVR_Payment_Expedited.json"
const J_PAY_BRIBE_OFFER  = D + "MVR_Payment_Bribery_Offer.json"
const J_BRIBE_WAIT       = D + "MVR_Bribery_Wait.json"
const J_BRIBE_COME_LATER = D + "MVR_Bribery_ComeLater.json"
const J_FOLLOW_STANDARD  = D + "MVR_Standard_Followup.json"
const J_FOLLOW_EXPEDITED = D + "MVR_Expedited_Followup.json"
const J_FOLLOW_BRIBERY   = D + "MVR_Bribery_Followup.json"
const J_PICKUP_LEGAL     = D + "MVR_Pickup_Legal.json"
const J_PICKUP_BRIBERY   = D + "MVR_Pickup_Bribery.json"
const J_BRIBERY_EXPIRED  = D + "MVR_Bribery_Expired.json"

# ---------- Costs / Gates ----------
const COST_STANDARD = 150
const COST_EXPEDITED = 500
const COST_BRIBE = 1000
const INTEGRITY_BRIBE_GATE = 40
const INTEGRITY_BRIBE_PAYMENT = -15
const INTEGRITY_BRIBE_PICKUP = -5

# ---------- Time ----------
const T_COST_STANDARD = 35
const T_COST_EXPEDITED = 30
const T_COST_PICKUP = 20
const T_BRIBE_PICK = 17 * 60
const T_AFTER_HOURS_LIMIT = 16 * 60 + 30
const T_AFTER_HOURS_EXTENDED = 18 * 60

# ---------- Method enum ----------
const METHOD_NONE = 0
const METHOD_STANDARD = 1
const METHOD_EXPEDITED = 2
const METHOD_BRIBERY = 3

# ---------- Keys ----------
const K_METHOD = "MVR_METHOD"
const K_READY_DAY = "MVR_BCERT_READY_DAY"
const K_BRIBE_PERMA_LOCK = "MVR_BRIBE_PERMA_LOCK"

# ---------- Nodes / state ----------
var _bg
var _btn_talk
var _panel = null
var _arrival_shown = false
var _dialogue_playing = false

var _fade_layer_canvas
var _fade_layer

# Kick control: only kick after UI (dialogue/panel) is done
var _pending_after_hours_kick := false

# ---------- Day gates ----------
func _can_standard_today() -> bool:
	return GameState.day <= 2

func _can_expedite_today() -> bool:
	return GameState.day <= 4

# ---------- Ready / Method helpers ----------
func _method() -> int:
	return GameState.get_int(K_METHOD, METHOD_NONE)

func _set_method(m):
	GameState.set_int(K_METHOD, m)

func _ready_day() -> int:
	return GameState.get_int(K_READY_DAY, 0)

func _days_remaining() -> int:
	var rd = _ready_day()
	if rd <= 0:
		return 0
	var rem = rd - GameState.day
	if rem > 0:
		return rem
	return 0

func _effective_after_hours_limit() -> int:
	# Extend to 18:00 ONLY for bribery on its ready day (pre-pickup).
	if _method() == METHOD_BRIBERY and GameState.day == _ready_day():
		return T_AFTER_HOURS_EXTENDED
	return T_AFTER_HOURS_LIMIT

# ========================= Lifecycle =========================
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.location = "MVR"

	_bg = get_node_or_null(background_path)
	_btn_talk = get_node_or_null(talk_button_path)
	if _btn_talk and not _btn_talk.pressed.is_connected(Callable(self, "_on_talk")):
		_btn_talk.pressed.connect(_on_talk)

	_make_fade_layer()
	await get_tree().process_frame
	await _fade_out_only(0.6)

func _process(_dt) -> void:
	# If we are past closing, prepare to kick.
	if GameState.time >= _effective_after_hours_limit():
		# If any UI is active, defer; otherwise, kick immediately.
		if _dialogue_playing or _panel != null:
			_pending_after_hours_kick = true
		else:
			_go_city()
	else:
		# If we're back under the limit (e.g., scene time manipulation), clear pending.
		_pending_after_hours_kick = false

# ========================= Fade =========================
func _make_fade_layer() -> void:
	_fade_layer_canvas = CanvasLayer.new()
	_fade_layer_canvas.layer = 100
	add_child(_fade_layer_canvas)

	_fade_layer = ColorRect.new()
	_fade_layer.color = Color(0, 0, 0, 1)
	_fade_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_fade_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_layer.visible = true
	_fade_layer.z_index = 999
	_fade_layer_canvas.add_child(_fade_layer)

func _fade_out_only(dur := 0.6) -> void:
	_fade_layer.visible = true
	_fade_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var t = create_tween()
	t.tween_property(_fade_layer, "color", Color(0, 0, 0, 0), dur)
	await t.finished
	_fade_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.visible = false

func _fade_in_out(dur := 0.35) -> void:
	_fade_layer.visible = true
	_fade_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_fade_layer.color = Color(0, 0, 0, 0)
	var t1 = create_tween()
	t1.tween_property(_fade_layer, "color", Color(0, 0, 0, 1), dur)
	await t1.finished
	var t2 = create_tween()
	t2.tween_property(_fade_layer, "color", Color(0, 0, 0, 0), dur)
	await t2.finished
	_fade_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.visible = false

# ========================= Dialogue utils =========================
func _set_talk_enabled(v: bool) -> void:
	if _btn_talk:
		_btn_talk.visible = v
		_btn_talk.disabled = not v

func _play_and_wait(path: String) -> void:
	_dialogue_playing = true
	_set_talk_enabled(false)
	var ui = DialogueManager.start_dialogue(path, self)
	if ui and ui.has_signal("dialogue_finished"):
		await Signal(ui, "dialogue_finished")
	_dialogue_playing = false
	_set_talk_enabled(true)
	# Do NOT kick here; let _process() handle it on the next frame
	# so any post-dialogue flow (e.g., pickups) can finish neatly.

# ========================= Panel helpers =========================
func _clear_panel() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null
	# Do NOT kick here; _process() will kick on the next frame if needed.

func _show_menu(opts, cb: Callable) -> void:
	_clear_panel()
	_panel = choice_panel_scene.instantiate()
	add_child(_panel)
	_panel.call("show_options", opts, cb)

# ========================= Talk entry =========================
func _on_talk() -> void:
	_clear_panel()

	# Bribery expired check (came back after ready day without pickup)
	if _method() == METHOD_BRIBERY and GameState.day > _ready_day() and not GameState.has_flag(GameFlags.HAVE_BIRTH_CERTIFICATE):
		if ResourceLoader.exists(J_BRIBERY_EXPIRED):
			await _play_and_wait(J_BRIBERY_EXPIRED)
		GameState.set_flag(K_BRIBE_PERMA_LOCK, true)
		_set_method(METHOD_NONE)
		GameState.set_int(K_READY_DAY, 0)
		_show_method_menu()
		return

	# If there's an active method, handle followups/pickup
	if _method() != METHOD_NONE:
		await _handle_followups_or_pickup()
		return

	if not _arrival_shown:
		_arrival_shown = true
		await _play_and_wait(J_OPEN_ARRIVAL)

	_show_greeting_menu()

# ========================= Greeting =========================
func _show_greeting_menu() -> void:
	var opts = []
	opts.append({"id":"ask","text":"I need a birth certificate."})
	opts.append({"id":"bye","text":"Never mind."})
	_show_menu(opts, Callable(self, "_on_greeting_choice"))

func _on_greeting_choice(id: String) -> void:
	if id == "ask":
		GameState.ensure_task("birth")
		GameState.update_task_step("birth")
		await _play_and_wait(J_REQUEST_CLERK)
		_show_method_menu()
	elif id == "bye":
		_clear_panel()

# ========================= Method selection =========================
func _show_method_menu() -> void:
	var opts = []
	if _can_standard_today():
		opts.append({"id":"standard","text":"Standard (150 ден) – Ready in 3 days"})
	if _can_expedite_today():
		opts.append({"id":"expedited","text":"Expedited (500 ден) – Ready tomorrow"})
	if GameState.integrity < INTEGRITY_BRIBE_GATE and not GameState.has_flag(K_BRIBE_PERMA_LOCK):
		opts.append({"id":"bribe","text":"Same-day (1,000 ден) – After 17:00"})
	opts.append({"id":"think","text":"Let me think on it."})
	_show_menu(opts, Callable(self, "_on_method_choice"))

func _on_method_choice(id: String) -> void:
	if id == "standard":
		await _choose_standard()
	elif id == "expedited":
		await _choose_expedited()
	elif id == "bribe":
		await _choose_bribery()
	elif id == "think":
		_clear_panel()

# ========================= Payment helpers =========================
func _pay(amount: int) -> bool:
	if GameState.money < amount:
		return false
	GameState.add_money(-amount)
	if not GameState.has_flag(GameFlags.SPENT_MONEY_ONCE):
		GameState.set_flag(GameFlags.SPENT_MONEY_ONCE, true)
	return true

# ========================= Choose flows =========================
func _choose_standard() -> void:
	_clear_panel()
	if not _can_standard_today():
		return
	if not _pay(COST_STANDARD):
		return
	GameState.adjust_time(T_COST_STANDARD)
	_set_method(METHOD_STANDARD)
	GameState.set_int(K_READY_DAY, GameState.day + 3)
	GameState.ensure_task("birth")
	GameState.update_task_step("birth")
	await _play_and_wait(J_PAY_STANDARD)

func _choose_expedited() -> void:
	_clear_panel()
	if not _can_expedite_today():
		return
	if not _pay(COST_EXPEDITED):
		return
	GameState.adjust_time(T_COST_EXPEDITED)
	_set_method(METHOD_EXPEDITED)
	GameState.set_int(K_READY_DAY, GameState.day + 1)
	GameState.ensure_task("birth")
	GameState.update_task_step("birth")
	await _play_and_wait(J_PAY_EXPEDITED)

func _choose_bribery() -> void:
	_clear_panel()
	if GameState.integrity >= INTEGRITY_BRIBE_GATE:
		return
	if not _pay(COST_BRIBE):
		return
	GameState.adjust_integrity(INTEGRITY_BRIBE_PAYMENT)
	_set_method(METHOD_BRIBERY)
	GameState.set_int(K_READY_DAY, GameState.day)
	GameState.ensure_task("birth")
	GameState.update_task_step("birth")
	await _play_and_wait(J_PAY_BRIBE_OFFER)
	_show_bribe_wait_menu()

# ========================= Follow-ups / pickup =========================
func _handle_followups_or_pickup() -> void:
	var m = _method()

	if m == METHOD_BRIBERY:
		if GameState.day == _ready_day():
			if GameState.time >= T_BRIBE_PICK:
				await _fade_in_out(0.20)
				await _do_pickup_bribery()
			else:
				await _play_and_wait(J_FOLLOW_BRIBERY)
				_show_bribe_wait_menu()
		else:
			if ResourceLoader.exists(J_BRIBERY_EXPIRED):
				await _play_and_wait(J_BRIBERY_EXPIRED)
			GameState.set_flag(K_BRIBE_PERMA_LOCK, true)
			_set_method(METHOD_NONE)
			GameState.set_int(K_READY_DAY, 0)
			_show_method_menu()
		return

	if m == METHOD_STANDARD:
		if _days_remaining() == 0:
			await _do_pickup_legal()
		else:
			await _play_and_wait(J_FOLLOW_STANDARD)
		return

	if m == METHOD_EXPEDITED:
		if _days_remaining() == 0:
			await _do_pickup_legal()
		else:
			await _play_and_wait(J_FOLLOW_EXPEDITED)
		return

# ========================= Bribery wait (auto-jump into pickup) =========================
func _show_bribe_wait_menu() -> void:
	var opts = []
	if GameState.time < T_BRIBE_PICK:
		opts.append({"id":"wait","text":"Wait here until 17:00"})
	opts.append({"id":"later","text":"I’ll come back later"})
	_show_menu(opts, Callable(self, "_on_bribe_wait_choice"))

func _on_bribe_wait_choice(id: String) -> void:
	_clear_panel()
	if id == "wait":
		# Jump time to 17:00 and flow straight into the pickup without extra clicks
		await _fade_in_out(0.35)
		var delta = T_BRIBE_PICK - GameState.time
		if delta > 0:
			GameState.adjust_time(delta)
		await _play_and_wait(J_BRIBE_WAIT)     # “time passes” dialogue
		await _do_pickup_bribery()              # immediately proceed to pickup
		return
	if id == "later":
		await _play_and_wait(J_BRIBE_COME_LATER)
		return

# ========================= Pickups (each bumps task by +1) =========================
func _advance_birth_task_by_one() -> void:
	GameState.ensure_task("birth")
	GameState.update_task_step("birth")

func _do_pickup_legal() -> void:
	GameState.set_flag(GameFlags.HAVE_BIRTH_CERTIFICATE, true)
	_advance_birth_task_by_one()               # +1 on pickup (legal)
	await _play_and_wait(J_PICKUP_LEGAL)
	await _fade_in_out(0.20)
	_set_method(METHOD_NONE)
	GameState.set_int(K_READY_DAY, 0)
	_go_city()

func _do_pickup_bribery() -> void:
	GameState.adjust_integrity(INTEGRITY_BRIBE_PICKUP)
	GameState.set_flag(GameFlags.HAVE_BIRTH_CERTIFICATE, true)
	_advance_birth_task_by_one()               # +1 on pickup (bribery)
	await _play_and_wait(J_PICKUP_BRIBERY)
	await _fade_in_out(0.20)
	GameState.set_flag(K_BRIBE_PERMA_LOCK, true)
	_set_method(METHOD_NONE)
	GameState.set_int(K_READY_DAY, 0)
	_go_city()

# ========================= Navigation =========================
func _go_city() -> void:
	_pending_after_hours_kick = false
	if city_scene_path == "" or not ResourceLoader.exists(city_scene_path):
		return
	_clear_panel()
	call_deferred("_deferred_change_scene", city_scene_path)

func _deferred_change_scene(p: String) -> void:
	var tree = get_tree()
	if tree and ResourceLoader.exists(p):
		tree.change_scene_to_file(p)

# ========================= Dialogue action hook =========================
func on_dialogue_action(line: Dictionary) -> void:
	GameState.apply_action(line)
