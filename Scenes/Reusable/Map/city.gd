extends Control

# ===== Background (day/night) =====
@export var background_texrect_path: NodePath
@export var bg_day: Texture2D
@export var bg_night: Texture2D

# Click this button to open the city menu (set its path in the Inspector)
@export var city_button_path: NodePath
@onready var city_button: Button = get_node_or_null(city_button_path) as Button

# Choice panel (spawned, used, freed)
@onready var choice_panel_scene: PackedScene = preload("res://Scenes/Reusable/CharacterChoiceButtons.tscn")
var _panel: Control = null
var _awaiting := ""   # "city_menu" | "activity_menu"

# Scene paths
const HOME_SCENE_PATH            := "res://Scenes/Reusable/Map/Home.tscn"
const SCHOOL_SCENE_PATH          := "res://Scenes/Reusable/Map/School.tscn"
const MVR_SCENE_PATH             := "res://Scenes/Reusable/Map/MVR.tscn"
const YCO_SCENE_PATH             := "res://Scenes/Reusable/Map/YCO.tscn"
const MARKO_FIRST_EVENT_SCENE    := "res://Scenes/Reusable/Events/MarkoFirstEvent.tscn"

# Flags
const MARKO_FIRST_EVENT_DONE     := "marko_first_event_done"
const YCO_INTERACTION_DONE       := "yco_interaction_done"

# ===== MVR gating (handled here, not in MVR scene) =====
const MVR_OPEN  := 13 * 60  # 13:00
const MVR_CLOSE := 15 * 60  # 15:00
const MVR_LOCKED_JSON := "res://Data/MVR/MVR_Locked.json"

# ===== Day/Night thresholds =====
const NIGHT_START := 19 * 60  # 19:00 (inclusive → night)
const DAY_START   := 7 * 60   # 07:00 (exclusive before → night)

var _bg: TextureRect
var _last_is_night = null

func _ready() -> void:
	# Background ref
	_bg = get_node_or_null(background_texrect_path) as TextureRect
	_update_background(true)

	# Wire the button that should pop the city menu
	if city_button and city_button.has_signal("pressed"):
		city_button.connect("pressed", Callable(self, "_on_city_button_pressed"))
	else:
		push_warning("City.gd: city_button_path is not set or not a Button. Set it in the Inspector.")

func _process(_dt: float) -> void:
	# If time changes while idling in City, update bg automatically
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
		{ "text": "Home",   "id": "home" },
		{ "text": "School", "id": "school" },
		{ "text": "MVR",    "id": "mvr" }
	]
	if _is_yco_available():
		options.append({ "text": "YCO", "id": "yco" })
	options.append({ "text": "Activity", "id": "activity" })
	options.append({ "text": "Back", "id": "back" })
	return options

func _build_activity_options() -> Array:
	var options: Array = []
	if _is_marko_unlocked():
		options.append({ "text": "Hang Out with Marko", "id": "hangout_marko" })
	else:
		options.append({ "text": "Hang Out with Marko (Locked)", "id": "hangout_locked" })
	if _is_tutoring_unlocked():
		options.append({ "text": "Tutoring", "id": "tutoring" })
	else:
		options.append({ "text": "Tutoring (Locked)", "id": "tutoring_locked" })
	options.append({ "text": "Back", "id": "back" })
	return options

# ========= CHOICE HANDLERS =========
func _on_city_choice(id: String) -> void:
	match id:
		"home":
			_go_home()
		"school":
			_go_to(SCHOOL_SCENE_PATH, "School")
		"mvr":
			_try_enter_mvr() # gated here by time; MVR scene assumes you’re allowed in
		"yco":
			if _is_yco_available():
				_go_to(YCO_SCENE_PATH, "YCO")
			else:
				print("YCO locked: Day ≥ 2 + interaction needed.")
				_show_city_menu()
		"activity":
			_show_activity_menu()
		"back":
			_clear_panel()

func _on_activity_choice(id: String) -> void:
	match id:
		"hangout_marko":
			if _is_marko_unlocked():
				_start_scene("res://Scenes/Reusable/Tasks/Hangout.tscn")
			else:
				print("Hangout locked until MarkoFirstEvent is done.")
				_show_activity_menu()
		"tutoring":
			if _is_tutoring_unlocked():
				_start_scene("res://Scenes/Reusable/Tasks/Tutoring.tscn")
			else:
				print("Tutoring locked until you spend money once.")
				_show_activity_menu()
		"hangout_locked":
			print("Locked: finish MarkoFirstEvent first.")
			_show_activity_menu()
		"tutoring_locked":
			print("Locked: spend money at least once.")
			_show_activity_menu()
		"back":
			_show_city_menu()

# ========= ACTIONS =========
func _go_home() -> void:
	GameState.location = "Home"
	# Day 1 first time going Home -> start Marko First Event
	if GameState.day == 1 and not GameState.has_flag(MARKO_FIRST_EVENT_DONE):
		GameState.set_flag(MARKO_FIRST_EVENT_DONE, true)
		print("Auto-starting MarkoFirstEvent (Day 1, first Home).")
		_start_scene(MARKO_FIRST_EVENT_SCENE)
		_clear_panel()
		return
	_start_scene(HOME_SCENE_PATH)
	_clear_panel()

func _go_to(scene_path: String, loc_name: String) -> void:
	GameState.location = loc_name
	_start_scene(scene_path)
	_clear_panel()

func _start_scene(path: String) -> void:
	if path != "" and ResourceLoader.exists(path):
		get_tree().change_scene_to_file(path)
	else:
		push_warning("City.gd: Scene missing or path invalid: " + path)

# ========= MVR GATING (CITY-LEVEL) =========
func _try_enter_mvr() -> void:
	var now := GameState.time
	if now >= MVR_OPEN and now < MVR_CLOSE:
		_go_to(MVR_SCENE_PATH, "MVR")
		return

	# Outside hours → narrative “no use in going” JSON; fallback to console if missing
	if FileAccess.file_exists(MVR_LOCKED_JSON):
		DialogueManager.start_dialogue(MVR_LOCKED_JSON, self)
	else:
		var os := _minutes_to_time_str(MVR_OPEN)
		var cs := _minutes_to_time_str(MVR_CLOSE)
		print("No use in going there — it's locked from %s to %s." % [os, cs])
	_show_city_menu()

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
		if night:
			if bg_night:
				_bg.texture = bg_night
		else:
			if bg_day:
				_bg.texture = bg_day

# ========= HELPERS =========
func _spawn_options_panel(options: Array, cb: Callable) -> void:
	_clear_panel()
	var panel := choice_panel_scene.instantiate()
	_panel = panel
	add_child(panel)
	panel.call("show_options", options, cb)

func _clear_panel() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null

func _minutes_to_time_str(minutes: int) -> String:
	var hours := int(minutes / 60)
	var mins := int(minutes % 60)
	return "%02d:%02d" % [hours, mins]
