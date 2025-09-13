extends Control

const TIME_MIN: int = 90
const REP_DELTA: int = -5

const KEY_RETURN_SCENE: String   = "__study_return_scene"
const KEY_HANGOUT_CONTEXT: String = "__hangout_context"   # "event" | ""
const RETURN_FALLBACK: String    = "res://Scenes/Reusable/Events/MarkoFirstEvent.tscn"

func _ready() -> void:
	# Run even if Dialogue paused the tree
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.location = "MarkoHangout"

	# Was this launched from an event? (then: no REP penalty)
	var from_event := String(GameState.features_unlocked.get(KEY_HANGOUT_CONTEXT, "")) == "event"
	# Clear the context so it doesn't leak
	if GameState.features_unlocked.has(KEY_HANGOUT_CONTEXT):
		GameState.features_unlocked.erase(KEY_HANGOUT_CONTEXT)

	if not from_event:
		GameState.adjust_reputation(REP_DELTA)
	GameState.adjust_time(TIME_MIN)

	var ret: String = String(GameState.features_unlocked.get(KEY_RETURN_SCENE, RETURN_FALLBACK)).strip_edges()
	if ret == "":
		ret = RETURN_FALLBACK

	# Unpause if needed and hop back next frame to avoid gray flash
	if get_tree().paused:
		get_tree().paused = false
	call_deferred("_return_to", ret)

func _return_to(path: String) -> void:
	if ResourceLoader.exists(path):
		get_tree().change_scene_to_file(path)
	else:
		push_warning("Hangout: invalid return path: " + path)
