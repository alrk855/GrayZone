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

# Scene paths
const HOME_SCENE_PATH            := "res://Scenes/Reusable/Map/Home.tscn"
const SCHOOL_SCENE_PATH          := "res://Scenes/Reusable/Map/School.tscn"
const MVR_SCENE_PATH             := "res://Scenes/Reusable/Map/MVR.tscn"
const YCO_SCENE_PATH             := "res://Scenes/Reusable/Map/YCO.tscn"
const MARKO_FIRST_EVENT_SCENE    := "res://Scenes/Reusable/Events/MarkoFirstEvent.tscn"

# Flags
const MARKO_FIRST_EVENT_DONE     := "marko_first_event_done"
const YCO_INTERACTION_DONE       := "yco_interaction_done"

# ===== MVR gating =====
const MVR_OPEN  := 13 * 60
const MVR_CLOSE := 15 * 60
const MVR_CLOSED_JSON        := "res://Data/MVR/MVR_Closed.json"
const MVR_ALREADY_HAVE_JSON  := "res://Data/MVR/MVR_AlreadyHave.json"

# ===== YCO gating =====
const YCO_OPEN  := 9 * 60
const YCO_CLOSE := 15 * 60 + 30
const YCO_CLOSED_JSON := "res://Data/YCO/YCO_Closed.json"

# ===== Day/Night thresholds =====
const NIGHT_START := 19 * 60
const DAY_START   := 7 * 60

var _bg: TextureRect
var _last_is_night = null

# ===== Fade overlay =====
var _fade_layer: CanvasLayer = null
var _fade_rect: ColorRect = null

func _ready() -> void:
	GameUi.visible = false
	_bg = get_node_or_null(background_texrect_path) as TextureRect
	_update_background(true)

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
			await _go_home()
		"school":
			await _go_to(SCHOOL_SCENE_PATH, "School")
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
			if _is_marko_unlocked():
				await _start_scene("res://Scenes/Reusable/Tasks/Hangout.tscn") # fades
			else:
				_show_activity_menu()
		"tutoring":
			if _is_tutoring_unlocked():
				await _start_scene("res://Scenes/Reusable/Tasks/Tutoring.tscn") # fades
			else:
				_show_activity_menu()
		"hangout_locked":
			_show_activity_menu()
		"tutoring_locked":
			_show_activity_menu()
		"back":
			_show_city_menu()

# ========= ACTIONS =========
func _go_home() -> void:
	GameState.location = "Home"
	if GameState.day == 1 and not GameState.has_flag(MARKO_FIRST_EVENT_DONE):
		GameState.set_flag(MARKO_FIRST_EVENT_DONE, true)
		# No fade for the event trigger
		await _start_scene(MARKO_FIRST_EVENT_SCENE, false)
	else:
		# No fade when going Home
		await _start_scene(HOME_SCENE_PATH, false)
	_clear_panel()

func _go_to(scene_path: String, loc_name: String) -> void:
	GameState.location = loc_name
	await _start_scene(scene_path, true) # keep fades everywhere else
	_clear_panel()

# use_fade controls whether we do the fade-out before scene change
func _start_scene(path: String, use_fade: bool = true) -> void:
	if path == "" or not ResourceLoader.exists(path):
		push_warning("City.gd: Scene missing or path invalid: " + path)
		return
	if use_fade:
		await _fade_to(1.0, 0.4)
	get_tree().change_scene_to_file(path)

# ========= MVR GATING =========
func _try_enter_mvr() -> void:
	if GameState.has_flag(GameFlags.HAVE_BIRTH_CERTIFICATE):
		await _play_city_json_or_fallback(MVR_ALREADY_HAVE_JSON, "You already have the certificate. No need to go back.")
		_show_city_menu()
		return

	var now = GameState.time
	if now >= MVR_OPEN and now < MVR_CLOSE:
		await _go_to(MVR_SCENE_PATH, "MVR") # fades
		return

	await _play_city_json_or_fallback(MVR_CLOSED_JSON, "It's closed right now.")
	_show_city_menu()

# ========= YCO GATING =========
func _try_enter_yco() -> void:
	if not _is_yco_available():
		_show_city_menu()
		return

	var now = GameState.time
	if now >= YCO_OPEN and now < YCO_CLOSE:
		await _go_to(YCO_SCENE_PATH, "YCO") # fades
		return

	await _play_city_json_or_fallback(YCO_CLOSED_JSON, "Not the best idea to go there now. The Youth Civil Office is closed between 09:00 and 15:30.")
	_show_city_menu()

func _play_city_json_or_fallback(path: String, fallback_msg: String) -> void:
	if FileAccess.file_exists(path):
		var ui := DialogueManager.start_dialogue(path, self)
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
	var t = GameState.time
	return (t >= NIGHT_START) or (t < DAY_START)

func _update_background(force := false) -> void:
	if not _bg:
		_bg = get_node_or_null(background_texrect_path) as TextureRect
		if not _bg:
			return
	var night = _is_night_time()
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

# ========= Fade helpers =========
func _ensure_fader() -> void:
	if _fade_layer == null or not is_instance_valid(_fade_layer):
		_fade_layer = CanvasLayer.new()
		_fade_layer.layer = 200
		add_child(_fade_layer)
	if _fade_rect == null or not is_instance_valid(_fade_rect):
		_fade_rect = ColorRect.new()
		_fade_rect.color = Color(0, 0, 0, 1)
		_fade_rect.modulate = Color(1, 1, 1, 0)
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fade_layer.add_child(_fade_rect)

func _fade_to(alpha: float, duration: float) -> void:
	_ensure_fader()
	var tw := create_tween()
	tw.tween_property(_fade_rect, "modulate:a", alpha, duration)
	await tw.finished
