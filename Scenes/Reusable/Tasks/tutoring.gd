# res://Scripts/Scenes/TutoringScene.gd
extends Control

signal selection_made(id: String)  # "1h" | "3h"

# ---- BG (you fill these in Inspector) ----
@export var bg_rect_path: NodePath
@export var bg_male: Texture2D
@export var bg_female: Texture2D

# ---- JSONs ----
@export_file("*.json") var INTRO_JSON: String = "res://Data/Activities/Tutoring/Tutoring_Intro.json"
@export_file("*.json") var JSON_1H: String   = "res://Data/Activities/Tutoring/Tutoring_1h.json"
@export_file("*.json") var JSON_3H: String   = "res://Data/Activities/Tutoring/Tutoring_3h.json"

# ---- Choice panel ----
@export_file("*.tscn") var CHOICES_SCN: String = "res://Scenes/Reusable/CharacterChoiceButtons.tscn"

# ---- Return scene ----
@export_file("*.tscn") var RETURN_SCENE: String = "res://Scenes/Reusable/Map/City.tscn"

# ---- Rewards ----
const MONEY_1H: int = 200
const TIME_1H: int  = 60
const MONEY_3H: int = 600
const TIME_3H: int  = 180

# ---- Flags / Task IDs ----
const TUTORING_TASK_ID := "Tutoring Task"
const TUTORING_FLAG_PREFIX := "tutored_day_"   # + 1..4

func _ready() -> void:
	GameState.location = "Tutoring"
	_apply_bg()

	# 1) Intro
	var ui := DialogueManager.start_dialogue(_jp(INTRO_JSON), self)
	if ui and ui.has_signal("dialogue_finished"):
		await ui.dialogue_finished

	# 2) Choice (1h vs 3h)
	var pick: String = await _ask_choice()

	# 3) Narration + rewards
	if pick == "3h":
		var ui3 := DialogueManager.start_dialogue(_jp(JSON_3H), self)
		if ui3 and ui3.has_signal("dialogue_finished"):
			await ui3.dialogue_finished
		GameState.add_money(MONEY_3H)
		GameState.adjust_time(TIME_3H)
	else:
		var ui1 := DialogueManager.start_dialogue(_jp(JSON_1H), self)
		if ui1 and ui1.has_signal("dialogue_finished"):
			await ui1.dialogue_finished
		GameState.add_money(MONEY_1H)
		GameState.adjust_time(TIME_1H)

	# 4) Mark today as tutored (once per in-game day), and make sure the task is visible
	_mark_tutored_today()
	GameState.ensure_task(TUTORING_TASK_ID)

	# 5) Fade out and leave
	await fade.fade_out()
	get_tree().change_scene_to_file(RETURN_SCENE)
	await fade.fade_in()

func _apply_bg() -> void:
	if bg_rect_path == NodePath():
		return
	var node := get_node_or_null(bg_rect_path)
	if node == null or not (node is TextureRect):
		push_error("TutoringScene: bg_rect_path is invalid or not a TextureRect.")
		return
	var rect := node as TextureRect
	var g: String = String(GameState.player_gender).to_lower()
	rect.texture = bg_female if g == "female" else bg_male

func _ask_choice() -> String:
	var ps := load(CHOICES_SCN)
	if ps == null:
		push_error("TutoringScene: CharacterChoiceButtons.tscn not found.")
		return "1h"

	var panel = ps.instantiate()
	add_child(panel)
	panel.call("show_options", [
		{"id":"1h", "text": tr("1 hour") + " (%d %s)" % [MONEY_1H, tr("ден")]},
		{"id":"3h", "text": tr("3 hours") + " (%d %s)" % [MONEY_3H, tr("ден")]}
	], Callable(self, "_on_choice"))

	var pick: String = await selection_made
	if is_instance_valid(panel):
		panel.queue_free()
	return pick

func _on_choice(option_id) -> void:
	emit_signal("selection_made", String(option_id))

func _mark_tutored_today() -> void:
	var day_index: int = GameState.day
	# Only track the 4-day arc (1..4). Safe, idempotent flag set.
	if day_index >= 1 and day_index <= 4:
		var key := TUTORING_FLAG_PREFIX + str(day_index)
		if not GameState.has_flag(key):
			GameState.set_flag(key, true)

# ---- Locale-aware JSON resolver (non-breaking) ----
func _jp(p: String) -> String:
	# If GameState exposes a locale path resolver, use it; else, fall back to given path.
	if GameState.has_method("localized_json_path"):
		return String(GameState.localized_json_path(p))
	if GameState.has_method("get_localized_json_path"):
		return String(GameState.get_localized_json_path(p))
	return p
