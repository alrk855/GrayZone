# res://Scripts/Scenes/MarkoHangout.gd
extends Control

# ---- Config (RELATIVE under Data/, locale-aware via GameState.get_data_path) ----
const HANGOUT_JSON_ID: String = "Marko/Marko_Hangout_Free.json"

# ---- SCENE PATHS ----
const HOME_SCENE: String = "res://Scenes/Reusable/Map/Home.tscn"
# TODO: set this to your actual First Event scene path:
const FIRST_EVENT_SCENE: String = "res://Scenes/Reusable/Events/MarkoFirstEvent.tscn"

# ---- BG (set these in Inspector) ----
@export var bg_rect_path: NodePath
@export var bg_male: Texture2D
@export var bg_female: Texture2D

# ---- Effects ----
const TIME_MIN: int = 90
const REP_DELTA: int = -5

var _returning := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.location = "MarkoHangout"

	_apply_bg_by_gender()

	# Decide whether this hangout is part of Day1 first-event flow.
	var returning_to_first_event := _should_return_to_first_event()

	# Preserve prior logic: if we came from the First Event flow (Day1, not done),
	# skip REP penalty; otherwise apply it.
	if not returning_to_first_event:
		GameState.adjust_reputation(REP_DELTA)
	GameState.adjust_time(TIME_MIN)

	# Resolve JSON and play it; on finish, route accordingly.
	var json_path := _dp(HANGOUT_JSON_ID)
	if json_path != "" and FileAccess.file_exists(json_path):
		var ui: Control = DialogueManager.start_dialogue(json_path, self)
		if ui and ui.has_signal("dialogue_finished"):
			if not ui.is_connected("dialogue_finished", Callable(self, "_on_json_done").bind(returning_to_first_event)):
				ui.connect("dialogue_finished", Callable(self, "_on_json_done").bind(returning_to_first_event))
		else:
			await get_tree().process_frame
			await _route_after_hangout(returning_to_first_event)
	else:
		await _route_after_hangout(returning_to_first_event)

func _apply_bg_by_gender() -> void:
	if bg_rect_path == NodePath():
		return
	var node := get_node_or_null(bg_rect_path)
	if node == null or not (node is TextureRect):
		push_error("MarkoHangout: bg_rect_path is invalid or not a TextureRect.")
		return
	var rect := node as TextureRect
	var g := String(GameState.player_gender).to_lower()
	rect.texture = bg_female if g == "female" else bg_male

func _on_json_done(returning_to_first_event: bool) -> void:
	await _route_after_hangout(returning_to_first_event)

func _route_after_hangout(returning_to_first_event: bool) -> void:
	if _returning:
		return
	_returning = true

	# Unpause just in case
	if get_tree().paused:
		get_tree().paused = false

	var target := HOME_SCENE
	if returning_to_first_event:
		# Mark that we should show only the end segment once First Event loads.
		GameState.set_flag("marko_hangout_recent", true)
		target = FIRST_EVENT_SCENE

	if not ResourceLoader.exists(target):
		push_warning("Hangout: invalid route path: " + target + " → falling back to Home")
		target = HOME_SCENE
		if not ResourceLoader.exists(target):
			push_error("Hangout: Home fallback missing: " + HOME_SCENE)
			_returning = false
			return

	await fade.fade_to_scene(target)
	_returning = false

# ===================== Helpers =====================
func _is_day1() -> bool:
	# Robust day check: prefer GameState.get_day_index() if provided, else commonly used fields.
	if GameState.has_method("get_day_index"):
		return int(GameState.get_day_index()) == 1
	if "day_index" in GameState:
		return int(GameState.day_index) == 1
	if "day" in GameState:
		return int(GameState.day) == 1
	return false

func _should_return_to_first_event() -> bool:
	# Day 1 and the event is not marked done yet → return to First Event to play only the end.
	return _is_day1() and (not GameState.has_flag("marko_first_event_done"))

# Golden path resolver
func _dp(relative: String) -> String:
	var rel := String(relative).strip_edges().trim_prefix("/")
	if GameState.has_method("get_data_path"):
		return String(GameState.get_data_path(rel))
	return "res://Data/" + rel
