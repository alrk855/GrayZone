extends Control

# ===== Background (day/night) =====
@export var background_texrect_path: NodePath
@export var bg_day: Texture2D
@export var bg_night: Texture2D

# Click to open city menu
@export var city_button_path: NodePath
@onready var city_button: Button = get_node_or_null(city_button_path) as Button

@onready var choice_panel_scene: PackedScene = preload("res://Scenes/Reusable/CharacterChoiceButtons.tscn")
var _panel: Control = null
var _awaiting := ""   # "city_menu" | "activity_menu"

# ===== Scene paths =====
const HOME_SCENE_PATH            := "res://Scenes/Reusable/Map/Home.tscn"
const SCHOOL_SCENE_PATH          := "res://Scenes/Reusable/Map/School.tscn"
const MVR_SCENE_PATH             := "res://Scenes/Reusable/Map/MVR.tscn"
const YCO_SCENE_PATH             := "res://Scenes/Reusable/Map/YCO.tscn"
const HANGOUT_SCENE_PATH         := "res://Scenes/Reusable/Tasks/Hangout.tscn"
const TUTORING_SCENE_PATH        := "res://Scenes/Reusable/Tasks/Tutoring.tscn"
const MARKO_FIRST_EVENT_SCENE    := "res://Scenes/Reusable/Events/MarkoFirstEvent.tscn"
const MARKO_SECOND_EVENT_SCENE   := "res://Scenes/Reusable/Events/MarkoSecondEvent.tscn"

# ===== Flags =====
const MARKO_FIRST_EVENT_DONE     := "marko_first_event_done"
const YCO_INTERACTION_DONE       := "yco_interaction_done"
const MARKO_SECOND_EVENT_DONE    := "marko_second_event_done"

const EVENT2_DAY   := 3
const EVENT2_START := 17 * 60  # 17:00

# ===== Once-per-day keys =====
const K_HANGOUT_LAST_DAY := "__CITY_HANGOUT_LAST_DAY"
const K_TUTOR_LAST_DAY   := "__CITY_TUTOR_LAST_DAY"

# ===== School gating =====
const SCHOOL_OPEN  := 7 * 60 + 30
const SCHOOL_CLOSE := 18 * 60 + 30
const SCHOOL_CLOSED_JSON := "city/School_Closed.json"   # relative ID

# ===== MVR gating =====
const MVR_OPEN              := 13 * 60
const MVR_CLOSE_BASE        := 17 * 60
const MVR_CLOSE_EXT         := 18 * 60
const MVR_CLOSED_JSON       := "city/MVR_Closed.json"         # relative ID
const MVR_ALREADY_HAVE_JSON := "city/MVR_AlreadyHave.json"    # relative ID

# ===== YCO gating =====
const YCO_OPEN  := 9 * 60
const YCO_CLOSE := 15 * 60 + 30
const YCO_CLOSED_JSON := "city/YCO_Closed.json"               # relative ID

# ===== Activity JSONs (custom) =====
const HANGOUT_LOCKED_JSON      := "City/Hangout_Locked.json"           # keep original case
const HANGOUT_DAILY_JSON       := "City/Hangout_OnlyOncePerDay.json"
const TUTORING_LOCKED_JSON     := "City/Tutoring_Locked.json"
const TUTORING_DAILY_JSON      := "City/Tutoring_OnlyOncePerDay.json"

# ===== Day/Night thresholds =====
const NIGHT_START := 19 * 60
const DAY_START   := 7 * 60

var _bg: TextureRect
var _last_is_night = null

func _ready() -> void:
	_bg = get_node_or_null(background_texrect_path) as TextureRect
	_update_background(true)
	GameState.location = "CITY"

	if city_button and city_button.has_signal("pressed"):
		city_button.connect("pressed", Callable(self, "_on_city_button_pressed"))
	else:
		push_warning("City.gd: city_button_path is not set or not a Button. Set it in the Inspector.")

func _process(_dt: float) -> void:
	_update_background(false)

func _on_city_button_pressed() -> void:
	_show_city_menu()

# ========= MENUS =========
func _show_city_menu() -> void:
	_awaiting = "city_menu"
	_spawn_options_panel(_build_city_options(), Callable(self, "_on_city_choice"))

func _show_activity_menu() -> void:
	_awaiting = "activity_menu"
	_spawn_options_panel(_build_activity_options(), Callable(self, "_on_activity_choice"))

func _build_city_options() -> Array:
	var options: Array = [
		{ "text": tr("Home"),   "id": "home" },
		{ "text": tr("School"), "id": "school" },
		{ "text": tr("MVR"),    "id": "mvr" }
	]
	if _is_yco_available():
		options.append({ "text": tr("Volunteering Centre"), "id": "yco" })
	options.append({ "text": tr("Activity"), "id": "activity" })
	options.append({ "text": tr("Back"), "id": "back" })
	return options

func _build_activity_options() -> Array:
	var options: Array = []
	if _is_marko_unlocked():
		options.append({ "text": tr("Hang Out with Marko"), "id": "hangout_marko" })
	else:
		options.append({ "text": tr("Hang Out with Marko (Locked)"), "id": "hangout_locked" })

	if _is_tutoring_unlocked():
		options.append({ "text": tr("Tutoring"), "id": "tutoring" })
	else:
		options.append({ "text": tr("Tutoring (Locked)"), "id": "tutoring_locked" })

	options.append({ "text": tr("Back"), "id": "back" })
	return options

# ========= CHOICE HANDLERS =========
func _on_city_choice(id: String) -> void:
	match id:
		"home":
			await _go_home()
		"school":
			await _try_enter_school()
		"mvr":
			await _try_enter_mvr()
		"yco":
			await _try_enter_yco()
		"activity":
			_show_activity_menu()
		"back":
			_clear_panel()

func _on_activity_choice(id: String) -> void:
	match id:
		"hangout_marko":
			if not _is_marko_unlocked():
				await _play_city_json_or_fallback(HANGOUT_LOCKED_JSON, tr("You can't hang out with Marko yet."))
				_show_activity_menu()
				return
			if not _once_per_day_allowed(K_HANGOUT_LAST_DAY):
				await _play_city_json_or_fallback(HANGOUT_DAILY_JSON, tr("You already hung out with Marko today."))
				_show_activity_menu()
				return
			_mark_once_per_day(K_HANGOUT_LAST_DAY)
			await _go_to(HANGOUT_SCENE_PATH, "Hangout")

		"tutoring":
			if not _is_tutoring_unlocked():
				await _play_city_json_or_fallback(TUTORING_LOCKED_JSON, tr("Tutoring isn't available yet."))
				_show_activity_menu()
				return
			if not _once_per_day_allowed(K_TUTOR_LAST_DAY):
				await _play_city_json_or_fallback(TUTORING_DAILY_JSON, tr("You've already done tutoring today."))
				_show_activity_menu()
				return
			_mark_once_per_day(K_TUTOR_LAST_DAY)
			await _go_to(TUTORING_SCENE_PATH, "Tutoring")

		"hangout_locked":
			await _play_city_json_or_fallback(HANGOUT_LOCKED_JSON, tr("You can't hang out with Marko yet."))
			_show_activity_menu()

		"tutoring_locked":
			await _play_city_json_or_fallback(TUTORING_LOCKED_JSON, tr("Tutoring isn't available yet."))
			_show_activity_menu()

		"back":
			_show_city_menu()

# ========= ONCE-PER-DAY HELPERS =========
func _once_per_day_allowed(key: String) -> bool:
	return GameState.get_int(key, 0) < GameState.day

func _mark_once_per_day(key: String) -> void:
	GameState.set_int(key, GameState.day)

# ========= ACTIONS =========
func _go_home() -> void:
	_clear_panel()

	# Day 1 first event
	if GameState.day == 1 and not GameState.has_flag(MARKO_FIRST_EVENT_DONE):
		GameState.set_flag(MARKO_FIRST_EVENT_DONE, true)
		GameState.location = "MarkoFirstEvent"
		await fade.fade_to_scene(MARKO_FIRST_EVENT_SCENE)
		return

	# Day 3 second event trigger after 17:00, only once
	if GameState.day == EVENT2_DAY and GameState.time >= EVENT2_START and not GameState.has_flag(MARKO_SECOND_EVENT_DONE):
		GameState.location = "MarkoSecondEvent"
		await fade.fade_to_scene(MARKO_SECOND_EVENT_SCENE)
		return

	# Normal go home
	GameState.location = "Home"
	await _change_scene(HOME_SCENE_PATH, true)

func _go_to(scene_path: String, loc_name: String) -> void:
	_clear_panel()
	GameState.location = loc_name
	await _change_scene(scene_path, true)

# ======== CENTRALIZED SCENE CHANGE (fade singleton only) ========
func _change_scene(path: String, use_fade: bool = true) -> void:
	if path == "" or not ResourceLoader.exists(path):
		push_warning("City.gd: Scene missing or path invalid: " + path)
		return

	_disable_self_inputs_temporarily()

	if use_fade:
		await fade.fade_to_scene(path)
	else:
		get_tree().change_scene_to_file(path)
	# do not access local nodes after awaiting fade_to_scene

func _disable_self_inputs_temporarily() -> void:
	if city_button:
		city_button.disabled = true
		call_deferred("_reenable_city_button")

func _reenable_city_button() -> void:
	if city_button:
		city_button.disabled = false

# ========= SCHOOL GATING =========
func _try_enter_school() -> void:
	var now := GameState.time
	if now >= SCHOOL_OPEN and now < SCHOOL_CLOSE:
		await _go_to(SCHOOL_SCENE_PATH, "School")
		return

	var hours_text := _fmt_time(SCHOOL_OPEN) + "–" + _fmt_time(SCHOOL_CLOSE)
	await _play_city_json_or_fallback(SCHOOL_CLOSED_JSON, tr("School is closed right now. Open %s.") % hours_text)
	_show_city_menu()

# ========= MVR GATING =========
func _mvr_is_same_day_bribe_active() -> bool:
	var method := GameState.get_int("MVR_METHOD", 0)              # 3 = Bribery
	var ready  := GameState.get_int("MVR_BCERT_READY_DAY", 0)
	if method != 3:
		return false
	if GameState.day != ready:
		return false
	if GameState.has_flag(GameFlags.HAVE_BIRTH_CERTIFICATE):
		return false
	return true

func _mvr_close_time() -> int:
	return MVR_CLOSE_EXT if _mvr_is_same_day_bribe_active() else MVR_CLOSE_BASE

func _try_enter_mvr() -> void:
	if GameState.has_flag(GameFlags.HAVE_BIRTH_CERTIFICATE):
		await _play_city_json_or_fallback(MVR_ALREADY_HAVE_JSON, tr("You already have the certificate. No need to go back."))
		_show_city_menu()
		return

	var now := GameState.time
	var close_time := _mvr_close_time()
	if now >= MVR_OPEN and now < close_time:
		await _go_to(MVR_SCENE_PATH, "MVR")
		return

	await _play_city_json_or_fallback(MVR_CLOSED_JSON, tr("It's closed right now."))
	_show_city_menu()

# ========= YCO GATING =========
func _try_enter_yco() -> void:
	if not _is_yco_available():
		_show_city_menu()
		return

	var now := GameState.time
	if now >= YCO_OPEN and now < YCO_CLOSE:
		await _go_to(YCO_SCENE_PATH, "YCO")
		return

	await _play_city_json_or_fallback(
		YCO_CLOSED_JSON,
		tr("Not the best idea to go there now. The Youth Civil Office is closed between 09:00 and 15:30.")
	)
	_show_city_menu()

# ========= JSON RUNNER (relative ID → resolve with GameState.get_data_path) =========
func _play_city_json_or_fallback(relative_id: String, fallback_msg: String) -> void:
	var dm := get_node_or_null("/root/DialogueManager")
	var path := _dp(relative_id)
	if path != "" and FileAccess.file_exists(path) and dm and dm.has_method("start_dialogue"):
		var ui = dm.start_dialogue(path, self)
		if ui and ui.has_signal("dialogue_finished"):
			await ui.dialogue_finished
	else:
		print(fallback_msg)

# ========= UNLOCK CHECKS =========
func _is_yco_available() -> bool:
	return GameState.day >= 2 and GameState.has_flag(YCO_INTERACTION_DONE)

func _is_marko_unlocked() -> bool:
	return GameState.has_flag(MARKO_FIRST_EVENT_DONE)

func _is_tutoring_unlocked() -> bool:
	return GameState.has_flag("spent_money_once")

# ========= BACKGROUND UTILS =========
func _is_night_time() -> bool:
	var t := GameState.time
	return (t >= NIGHT_START) or (t < DAY_START)

func _update_background(force := false) -> void:
	if not _bg:
		_bg = get_node_or_null(background_texrect_path) as TextureRect
		if not _bg:
			return
	var night := _is_night_time()
	if force or _last_is_night == null or _last_is_night != night:
		_last_is_night = night
		if night and bg_night:
			_bg.texture = bg_night
		elif not night and bg_day:
			_bg.texture = bg_day

# ========= HELPERS =========
func _spawn_options_panel(options: Array, cb: Callable) -> void:
	_clear_panel()
	var panel = choice_panel_scene.instantiate()
	_panel = panel
	add_child(panel)
	panel.call("show_options", options, cb)

func _clear_panel() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null

func _fmt_time(m: int) -> String:
	var h := int(m / 60) % 24
	var mm := int(m % 60)
	return "%02d:%02d" % [h, mm]

# -------- Locale-aware data-path resolver (Golden Standard) --------
func _dp(relative: String) -> String:
	var rel := String(relative).strip_edges().trim_prefix("/")
	if GameState.has_method("get_data_path"):
		return String(GameState.get_data_path(rel))
	return "res://Data/" + rel
