extends Control

# ---- Config ----
const HANGOUT_JSON: String = "res://Data/Marko/Marko_Hangout_Free.json"

# ---- BG (set these in Inspector) ----
@export var bg_rect_path: NodePath
@export var bg_male: Texture2D
@export var bg_female: Texture2D

# ---- Effects ----
const TIME_MIN: int = 90
const REP_DELTA: int = -5

# ---- Keys / Fallbacks ----
const KEY_RETURN_SCENE: String    = "__study_return_scene"   # set by launcher
const KEY_HANGOUT_CONTEXT: String = "__hangout_context"      # "event" | ""
const RETURN_FALLBACK: String     = "res://Scenes/Reusable/Map/City.tscn"

var _returning := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.location = "MarkoHangout"

	# Set BG immediately based on player gender
	_apply_bg_by_gender()

	# Context: if launched from the event, skip REP penalty
	var from_event := String(GameState.features_unlocked.get(KEY_HANGOUT_CONTEXT, "")) == "event"
	if GameState.features_unlocked.has(KEY_HANGOUT_CONTEXT):
		GameState.features_unlocked.erase(KEY_HANGOUT_CONTEXT)

	if not from_event:
		GameState.adjust_reputation(REP_DELTA)
	GameState.adjust_time(TIME_MIN)

	# Decide where to return; then consume the marker so it doesn't leak
	var ret := String(GameState.features_unlocked.get(KEY_RETURN_SCENE, RETURN_FALLBACK)).strip_edges()
	if ret == "":
		ret = RETURN_FALLBACK
	if GameState.features_unlocked.has(KEY_RETURN_SCENE):
		GameState.features_unlocked.erase(KEY_RETURN_SCENE)

	# Play JSON then return
	if HANGOUT_JSON != "" and ResourceLoader.exists(HANGOUT_JSON):
		var ui: Control = DialogueManager.start_dialogue(HANGOUT_JSON, self)
		if ui and ui.has_signal("dialogue_finished"):
			if not ui.is_connected("dialogue_finished", Callable(self, "_on_json_done").bind(ret)):
				ui.connect("dialogue_finished", Callable(self, "_on_json_done").bind(ret))
		else:
			await get_tree().process_frame
			await _return_to(ret)
	else:
		await _return_to(ret)

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

func _on_json_done(ret: String) -> void:
	await _return_to(ret)

func _return_to(path: String) -> void:
	if _returning:
		return
	_returning = true
	if get_tree().paused:
		get_tree().paused = false
	if ResourceLoader.exists(path):
		var f = get_tree().get_node_or_null("/root/fade")
		if f and f.has_method("fade_to_scene"):
			await f.fade_to_scene(path)
		else:
			get_tree().change_scene_to_file(path)
	else:
		push_warning("Hangout: invalid return path: " + path)
	_returning = false
