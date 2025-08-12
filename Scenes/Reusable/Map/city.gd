# City.gd
extends Control

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
const FLAG_MARKO_EVENT_DONE      := "marko_first_event_done"
const FLAG_MARKO_EVENT_SEEN      := "marko_first_event_seen"
const FLAG_YCO_INTERACTION_DONE  := "yco_interaction_done"

func _ready() -> void:
	# Wire the button that should pop the city menu
	if city_button and city_button.has_signal("pressed"):
		city_button.connect("pressed", Callable(self, "_on_city_button_pressed"))
	else:
		push_warning("City.gd: city_button_path is not set or not a Button. Set it in the Inspector.")

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
			_go_to(MVR_SCENE_PATH, "MVR")
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
	if GameState.day == 1 and not GameState.has_flag(FLAG_MARKO_EVENT_SEEN):
		GameState.set_flag(FLAG_MARKO_EVENT_SEEN, true)
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

# ========= UNLOCK CHECKS =========
func _is_yco_available() -> bool:
	return GameState.day >= 2 and GameState.has_flag(FLAG_YCO_INTERACTION_DONE)

func _is_marko_unlocked() -> bool:
	return GameState.has_flag(FLAG_MARKO_EVENT_DONE)

func _is_tutoring_unlocked() -> bool:
	return GameState.has_flag("spent_money_once")

# ========= PANEL HELPERS =========
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
