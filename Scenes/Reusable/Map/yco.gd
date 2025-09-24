extends Control

# ---------- Inspector ----------
@export var background_texrect_path: NodePath = ^"background"
@export var daniel_button_path: NodePath      = ^"background/Daniel"
@export var back_button_path: NodePath        = ^"background/Back"

# Volunteer background images (gender-specific)
@export var volunteer_bg_male: Texture2D
@export var volunteer_bg_female: Texture2D

@export var city_scene_path: String           = "res://Scenes/Reusable/Map/City.tscn"
@export var choice_panel_scene: PackedScene   = preload("res://Scenes/Reusable/CharacterChoiceButtons.tscn")

# ---------- JSON paths ----------
const D: String = "res://Data/YCO/"
const J_INTRO: String             = D + "Daniel_Intro.json"
const J_INTRO_FALLBACK: String    = D + "Daniel_Intro_Only.json"

const J_OPT1_ACCEPT: String       = D + "Daniel_Option1_Accept.json"
const J_OPT2_INFO: String         = D + "Daniel_Option2_Info.json"
const J_OPT3_BRIBE_OFFER: String  = D + "Daniel_Option3_BribeOffer.json" # generic offer line

const J_TALK_0: String            = D + "Daniel_Talk_0of3.json"
const J_TALK_1: String            = D + "Daniel_Talk_1of3.json"
const J_TALK_2: String            = D + "Daniel_Talk_2of3.json"
const J_TALK_3_GRANT: String      = D + "Daniel_Talk_3of3_GrantLetter.json"
const J_TALK_POST: String         = D + "Daniel_Talk_PostLetter.json"

const J_VOL_FLYERS: String        = D + "Volunteer_Flyers.json"
const J_VOL_FILING: String        = D + "Volunteer_Filing.json"
const J_VOL_SURVEY: String        = D + "Volunteer_Survey.json"
const J_VOL_DONE_TODAY: String    = D + "Volunteer_DoneToday.json"

# Bribe JSONs
const J_BRIBE_DECLINED: String            = D + "Daniel_Bribe_Declined.json"
const J_BRIBE_NOMONEY: String             = D + "Daniel_Bribe_NoMoney.json"
const J_BRIBE_GRANTED: String             = D + "Daniel_Bribe_Granted.json"

# ---------- Task / Flags / Ints ----------
const TASK_ID: String = "volunteer"

const F_REC_LETTER: String = "rec_letter_yco"
const F_ACCEPTED: String   = "yco_volunteer_accepted"
const F_BRIBED: String     = "yco_letter_bribed"

const I_COUNT: String    = "yco_volunteer_count"
const I_LAST_DAY: String = "yco_last_shift_day"

# ---------- Bribe pricing (base 1000; -200 per shift; floor 200) ----------
const BRIBE_BASE_PRICE: int = 1000
const BRIBE_DISCOUNT_PER_SHIFT: int = 200
const BRIBE_MIN_PRICE: int = 200
const BRIBE_INTEGRITY_PENALTY: int = 15
const BRIBE_DECLINE_INTEGRITY_BONUS: int = 5

# ---------- Nodes / state ----------
var _bg_rect: TextureRect
var _btn_talk: Button
var _btn_back: Button

var _panel: Control = null
var _dialogue_playing: bool = false
var _intro_shown_this_visit: bool = false

var _bg_original_tex: Texture2D

# ========================= GameState helpers =========================
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

func _adjust_reputation(delta: int) -> void:
	if GameState.has_method("adjust_reputation"):
		GameState.adjust_reputation(delta)
	else:
		GameState.reputation = GameState.reputation + delta

func _pay_money(amount: int) -> bool:
	if GameState.money < amount:
		return false
	if GameState.has_method("add_money"):
		GameState.add_money(-amount)
	else:
		GameState.money -= amount
	return true

# Price formula based on volunteer count
func _current_bribe_price() -> int:
	var price := BRIBE_BASE_PRICE - BRIBE_DISCOUNT_PER_SHIFT * _count()
	return max(BRIBE_MIN_PRICE, price)

# ========================= Lifecycle =========================
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.location = "YCO"

	_bg_rect = get_node_or_null(background_texrect_path) as TextureRect
	if _bg_rect:
		_bg_original_tex = _bg_rect.texture

	_btn_talk = get_node_or_null(daniel_button_path)
	_btn_back = get_node_or_null(back_button_path)

	if _btn_talk and not _btn_talk.pressed.is_connected(Callable(self, "_on_talk")):
		_btn_talk.pressed.connect(_on_talk)
	if _btn_back and not _btn_back.pressed.is_connected(Callable(self, "_on_back")):
		_btn_back.pressed.connect(_on_back)

	_ensure_task()
	if GameState.get_task_progress(TASK_ID) == 0:
		GameState.update_task_step(TASK_ID)

	_sync_task_from_flags()

# ========================= Dialogue utils =========================
func _set_talk_enabled(v: bool) -> void:
	if _btn_talk:
		_btn_talk.visible = v
		_btn_talk.disabled = not v

func _play_and_wait(path: String) -> void:
	_dialogue_playing = true
	_set_talk_enabled(false)
	if not ResourceLoader.exists(path):
		await _play_inline_notice("Missing dialogue: " + path.get_file())
	else:
		var ui = DialogueManager.start_dialogue(path, self)
		if ui and ui.has_signal("dialogue_finished"):
			await Signal(ui, "dialogue_finished")
	_dialogue_playing = false
	_set_talk_enabled(true)

func _play_inline_notice(text: String) -> void:
	var temp_path := "user://__yco_notice__.json"
	var obj := {"meta": {"id": "yco_notice"}, "lines": [{"speaker":"Daniel","text": text}]}
	var f = FileAccess.open(temp_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(obj))
		f.close()
	var ui = DialogueManager.start_dialogue(temp_path, self)
	if ui and ui.has_signal("dialogue_finished"):
		await Signal(ui, "dialogue_finished")

# Replace {price} inside a JSON by writing a temp file (no dependency on placeholder system)
func _play_with_price(path: String, price: int) -> void:
	if not ResourceLoader.exists(path):
		await _play_inline_notice("Missing dialogue: " + path.get_file())
		return
	var txt := FileAccess.get_file_as_string(path)
	txt = txt.replace("{price}", str(price))
	var temp := "user://__yco_price__.json"
	var f = FileAccess.open(temp, FileAccess.WRITE)
	f.store_string(txt)
	f.close()
	var ui = DialogueManager.start_dialogue(temp, self)
	if ui and ui.has_signal("dialogue_finished"):
		await Signal(ui, "dialogue_finished")

# ========================= Panel helpers =========================
func _clear_panel() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null

func _show_menu(opts: Array, cb: Callable) -> void:
	_clear_panel()
	_panel = choice_panel_scene.instantiate()
	add_child(_panel)
	_panel.call("show_options", opts, cb)

# ========================= Talk entry =========================
func _on_talk() -> void:
	_clear_panel()

	# Step 2 on first talk
	if GameState.get_task_progress(TASK_ID) == 1:
		GameState.update_task_step(TASK_ID)

	# Already have letter → limited menu
	if _has_flag(F_REC_LETTER):
		_show_post_letter_menu()
		return

	# Not accepted/not bribed → intro once per visit, then first menu
	if not _has_flag(F_ACCEPTED) and not _has_flag(F_BRIBED):
		if not _intro_shown_this_visit:
			_intro_shown_this_visit = true
			var intro_path := J_INTRO if ResourceLoader.exists(J_INTRO) else J_INTRO_FALLBACK
			await _play_and_wait(intro_path)
		_show_first_menu()
		return

	# Accepted (or bribed pre-letter) → full menu
	_show_main_menu()

# ========================= Menus =========================
func _show_post_letter_menu() -> void:
	var opts = [
		{"id":"talk","text": tr("Talk")},
		{"id":"back","text": tr("Never mind")}
	]
	_show_menu(opts, Callable(self, "_on_post_letter_choice"))

func _on_post_letter_choice(id: String) -> void:
	if id == "talk":
		await _play_and_wait(J_TALK_POST)
	elif id == "back":
		_clear_panel()

func _show_first_menu() -> void:
	var price := _current_bribe_price()
	var opts = [
		{"id":"opt1","text": tr("I’m here to volunteer.")},
		{"id":"opt2","text": tr("Depends. What would I be doing?")},
		{"id":"bribe","text": tr("Offer a bribe for a recommendation (%d ден)") % price},
		{"id":"back","text": tr("I’ll come back later.")}
	]
	_show_menu(opts, Callable(self, "_on_first_choice"))

func _on_first_choice(id: String) -> void:
	match id:
		"opt1":
			GameState.adjust_integrity(5)
			_adjust_reputation(10)
			_set_flag(F_ACCEPTED, true)
			_ensure_task()
			while GameState.get_task_progress(TASK_ID) < 3:
				GameState.update_task_step(TASK_ID)
			await _play_and_wait(J_OPT1_ACCEPT)
			_clear_panel()
		"opt2":
			await _play_and_wait(J_OPT2_INFO)
			_show_first_menu()
		"bribe":
			var price := _current_bribe_price()
			await _play_with_price(J_OPT3_BRIBE_OFFER, price)
			_show_bribe_confirm_menu(price)
		"back":
			_clear_panel()

func _show_main_menu() -> void:
	var price := _current_bribe_price()
	var opts = [
		{"id":"talk","text": tr("Talk")},
		{"id":"vol","text": tr("Volunteer (once per day)")},
		{"id":"bribe","text": tr("Offer a bribe for a recommendation (%d ден)") % price},
		{"id":"back","text": tr("Never mind")}
	]
	_show_menu(opts, Callable(self, "_on_main_choice"))

func _on_main_choice(id: String) -> void:
	match id:
		"talk":
			await _do_talk()
		"vol":
			await _do_volunteer()
		"bribe":
			var price := _current_bribe_price()
			await _play_with_price(J_OPT3_BRIBE_OFFER, price)
			_show_bribe_confirm_menu(price)
		"back":
			_clear_panel()

# ========================= Bribe confirm =========================
func _show_bribe_confirm_menu(price: int) -> void:
	var opts = [
		{"id":"bribe_yes","text": tr("Pay (%d ден)") % price},
		{"id":"bribe_no","text": tr("Never mind")}
	]
	_show_menu(opts, Callable(self, "_on_bribe_confirm").bind(price))

func _on_bribe_confirm(id: String, price: int) -> void:
	match id:
		"bribe_yes":
			if not _pay_money(price):
				await _play_with_price(J_BRIBE_NOMONEY, price)
				_show_first_menu()
				return
			GameState.adjust_integrity(-BRIBE_INTEGRITY_PENALTY)
			_set_flag(F_BRIBED, true)
			_set_flag(F_REC_LETTER, true)
			_ensure_task()
			while GameState.get_task_progress(TASK_ID) < 7:
				GameState.update_task_step(TASK_ID)
			await _play_and_wait(J_BRIBE_GRANTED)
			_clear_panel()
		"bribe_no":
			GameState.adjust_integrity(BRIBE_DECLINE_INTEGRITY_BONUS)
			await _play_and_wait(J_BRIBE_DECLINED)
			_show_first_menu()

# ========================= Talk flow =========================
func _do_talk() -> void:
	_sync_task_from_flags()

	if _has_flag(F_REC_LETTER):
		await _play_and_wait(J_TALK_POST)
		return

	var c := _count()
	match c:
		0:
			await _play_and_wait(J_TALK_0)
		1:
			await _play_and_wait(J_TALK_1)
		2:
			await _play_and_wait(J_TALK_2)
		3:
			_set_flag(F_REC_LETTER, true)
			await _play_and_wait(J_TALK_3_GRANT)
			_ensure_task()
			if GameState.get_task_progress(TASK_ID) == 6:
				GameState.update_task_step(TASK_ID)

	if _has_flag(F_REC_LETTER):
		_show_post_letter_menu()
	else:
		_show_main_menu()

# ========================= Volunteer flow (no separate scene; swap BG) =========================
func _do_volunteer() -> void:
	if not _has_flag(F_ACCEPTED):
		await _play_and_wait(J_OPT2_INFO)
		_show_first_menu()
		return
	if _has_flag(F_REC_LETTER):
		await _play_and_wait(J_TALK_POST)
		return
	if _last_day() == _day():
		await _play_and_wait(J_VOL_DONE_TODAY)
		return
	if _count() >= 3:
		await _do_talk()
		return

	var opts = [
		{"id":"flyers","text": tr("Outreach & Flyers")},
		{"id":"filing","text": tr("Archive & Filing")},
		{"id":"survey","text": tr("Survey Help")},
		{"id":"back","text": tr("Never mind")}
	]
	_show_menu(opts, Callable(self, "_on_volunteer_choice"))

func _on_volunteer_choice(choice_id: String) -> void:
	if choice_id == "back":
		_clear_panel()
		return
	await _run_volunteer(choice_id)

func _set_volunteer_bg(active: bool) -> void:
	if _bg_rect == null:
		return
	if active:
		var g := ("" + str(GameState.player_gender)).to_lower()
		if g == "f" or g == "female":
			if volunteer_bg_female: _bg_rect.texture = volunteer_bg_female
		else:
			if volunteer_bg_male: _bg_rect.texture = volunteer_bg_male
	else:
		_bg_rect.texture = _bg_original_tex

func _run_volunteer(duty_key: String) -> void:
	_clear_panel()
	_set_volunteer_bg(true)
	match duty_key:
		"flyers":
			await _play_and_wait(J_VOL_FLYERS)
		"filing":
			await _play_and_wait(J_VOL_FILING)
		"survey":
			await _play_and_wait(J_VOL_SURVEY)
		_:
			await _play_and_wait(J_VOL_FLYERS)
	_set_volunteer_bg(false)

	# Update attendance
	var c := _count() + 1
	_set_count(c)
	_set_last_day(_day())
	_set_flag("yco_vol_attend_day_%d" % _day(), true)

	_ensure_task()
	var prog := GameState.get_task_progress(TASK_ID)
	if prog >= 3 and prog < 6:
		GameState.update_task_step(TASK_ID)

	_show_main_menu()

# ========================= Back / Navigation =========================
func _on_back() -> void:
	if city_scene_path == "" or not ResourceLoader.exists(city_scene_path):
		return
	_clear_panel()
	if has_node("/root/fade"):
		var f := get_node("/root/fade")
		if f and f.has_method("fade_to_scene"):
			await f.call("fade_to_scene", city_scene_path)
			return
	get_tree().change_scene_to_file(city_scene_path)

# ========================= Minimal action bridge =========================
func on_dialogue_action(line: Dictionary) -> void:
	var a = line.get("action", null)
	if a == null:
		return
	if typeof(a) == TYPE_STRING and a == "end_dialogue":
		if DialogueManager.has_method("end_active_dialogue"):
			DialogueManager.end_active_dialogue()
	elif typeof(a) == TYPE_DICTIONARY:
		var t = a.get("type", "")
		if typeof(t) == TYPE_STRING and t == "end_dialogue" and DialogueManager.has_method("end_active_dialogue"):
			DialogueManager.end_active_dialogue()
	elif typeof(a) == TYPE_ARRAY:
		for item in a:
			if typeof(item) == TYPE_DICTIONARY:
				var t2 = item.get("type", "")
				if typeof(t2) == TYPE_STRING and t2 == "end_dialogue" and DialogueManager.has_method("end_active_dialogue"):
					DialogueManager.end_active_dialogue()
