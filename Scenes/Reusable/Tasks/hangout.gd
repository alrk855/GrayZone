extends Control

# ---- Config ----
const HANGOUT_JSON: String = "res://Data/Marko/Marko_Hangout_Free.json"

# ---- Effects ----
const TIME_MIN: int = 90
const REP_DELTA: int = -5

# ---- Keys / Fallbacks ----
const KEY_RETURN_SCENE: String    = "__study_return_scene"
const KEY_HANGOUT_CONTEXT: String = "__hangout_context"   # "event" | ""
const RETURN_FALLBACK: String     = "res://Scenes/Reusable/Events/MarkoFirstEvent.tscn"

var _returning := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.location = "MarkoHangout"

	# Context: if launched with KEY_HANGOUT_CONTEXT="event", skip REP penalty
	var from_event := String(GameState.features_unlocked.get(KEY_HANGOUT_CONTEXT, "")) == "event"
	if GameState.features_unlocked.has(KEY_HANGOUT_CONTEXT):
		GameState.features_unlocked.erase(KEY_HANGOUT_CONTEXT)

	# Apply effects
	if not from_event:
		GameState.adjust_reputation(REP_DELTA)
	GameState.adjust_time(TIME_MIN)

	# Where to return
	var ret := String(GameState.features_unlocked.get(KEY_RETURN_SCENE, RETURN_FALLBACK)).strip_edges()
	if ret == "":
		ret = RETURN_FALLBACK

	# Play micro JSON if present; otherwise brief hold then return
	if HANGOUT_JSON != "" and ResourceLoader.exists(HANGOUT_JSON):
		var ui: Control = DialogueManager.start_dialogue(HANGOUT_JSON, self)
		if ui and ui.has_signal("dialogue_finished"):
			if not ui.is_connected("dialogue_finished", Callable(self, "_on_json_done").bind(ret)):
				ui.connect("dialogue_finished", Callable(self, "_on_json_done").bind(ret))
	else:
		_return_to(ret)

func _on_json_done(ret: String) -> void:
	_return_to(ret)

func _return_to(path: String) -> void:
	if _returning:
		return
	_returning = true
	if get_tree().paused:
		get_tree().paused = false
	if ResourceLoader.exists(path):
		get_tree().change_scene_to_file(path)
	else:
		push_warning("Hangout: invalid return path: " + path)
	_returning = false
