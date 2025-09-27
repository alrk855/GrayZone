# res://Scripts/Scenes/MarkoHangout.gd
extends Control

# ---- Config (RELATIVE under Data/, locale-aware via GameState.get_data_path) ----
const HANGOUT_JSON_ID: String = "Marko/Marko_Hangout_Free.json"

# ---- BG (set these in Inspector) ----
@export var bg_rect_path: NodePath
@export var bg_male: Texture2D
@export var bg_female: Texture2D

# ---- Effects ----
const TIME_MIN: int = 90
const REP_DELTA: int = -5

# ---- Keys / Fallbacks ----
# NEW: use a unique return key to avoid collisions with Study/MarkoStudy
const KEY_RETURN_SCENE: String    = "__hangout_return_scene"
const KEY_HANGOUT_CONTEXT: String = "__hangout_context"      # "event" | ""
const RETURN_FALLBACK: String     = "res://Scenes/Reusable/Map/City.tscn"

var _returning: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.location = "MarkoHangout"

	_apply_bg_by_gender()

	# Context: if launched from the event, skip REP penalty
	var from_event := String(GameState.features_unlocked.get(KEY_HANGOUT_CONTEXT, "")) == "event"
	if GameState.features_unlocked.has(KEY_HANGOUT_CONTEXT):
		GameState.features_unlocked.erase(KEY_HANGOUT_CONTEXT)

	if not from_event:
		GameState.adjust_reputation(REP_DELTA)
	GameState.adjust_time(TIME_MIN)

	# Decide where to return (read new key first; fall back to old if present),
	# then consume the marker so it doesn't leak
	var ret := String(GameState.features_unlocked.get(KEY_RETURN_SCENE, ""))

	# Backward-compat: if some launcher still sets the old study key, use it once
	if ret.strip_edges() == "":
		ret = String(GameState.features_unlocked.get("__study_return_scene", ""))

	# If still empty, default to current scene, else fallback to City
	if ret.strip_edges() == "" and get_tree() and get_tree().current_scene:
		ret = get_tree().current_scene.get_scene_file_path()
	if ret.strip_edges() == "":
		ret = RETURN_FALLBACK


	# Resolve JSON via GameState.get_data_path(relative)
	var json_path := _dp(HANGOUT_JSON_ID)

	# Play JSON then return
	if json_path != "" and FileAccess.file_exists(json_path):
		var ui: Control = DialogueManager.start_dialogue(json_path, self)
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

	# Unpause just in case
	if get_tree().paused:
		get_tree().paused = false

	# Validate target; if missing, use fallback (still via fade singleton)
	var target := path
	if not ResourceLoader.exists(target):
		push_warning("Hangout: invalid return path: " + target + " → using fallback")
		target = RETURN_FALLBACK
		if not ResourceLoader.exists(target):
			push_error("Hangout: fallback path also invalid: " + target)
			_returning = false
			return

	# 🔒 Use ONLY the global fade singleton
	await fade.fade_to_scene(target)

	_returning = false

# ===================== Golden path resolver =====================
func _dp(relative: String) -> String:
	var rel := String(relative).strip_edges().trim_prefix("/")
	if GameState.has_method("get_data_path"):
		return String(GameState.get_data_path(rel))
	return "res://Data/" + rel
