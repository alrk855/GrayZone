extends Control

const TIME_MIN: int = 90
const REP_DELTA: int = -5

const KEY_RETURN_SCENE: String = "__study_return_scene"
const RETURN_FALLBACK: String = "res://Scenes/Reusable/Events/MarkoFirstEvent.tscn"

func _ready() -> void:
	GameState.location = "MarkoHangout"

	# Apply effects
	GameState.adjust_reputation(REP_DELTA)
	GameState.adjust_time(TIME_MIN)

	# Return to whoever set the return path (MarkoFirstEvent)
	var ret: String = String(GameState.features_unlocked.get(KEY_RETURN_SCENE, RETURN_FALLBACK))
	if ret.strip_edges() == "":
		ret = RETURN_FALLBACK

	get_tree().change_scene_to_file(ret)
