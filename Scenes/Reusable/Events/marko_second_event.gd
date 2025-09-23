extends Control

# ---------- Exports ----------
@export var bg_rect_path: NodePath
@export var bg_party_male: Texture2D
@export var bg_party_female: Texture2D
@export var study_scene_path: String = "res://Scenes/Reusable/Tasks/Study.tscn"
@export var home_scene_path: String  = "res://Scenes/Reusable/Map/Home.tscn"

# Choice panel scene
const CCB_SCENE_PATH := "res://Scenes/Reusable/CharacterChoiceButtons.tscn"

# JSONs (dialogue-only)
const JSON_INTRO_STUDY := "res://Data/Marko/SecondEvent/MarkoSecond_Intro_Study.json"
const JSON_INTRO_PARTY := "res://Data/Marko/SecondEvent/MarkoSecond_Intro_Party.json"
const JSON_PARTY_NIGHT := "res://Data/Marko/SecondEvent/MarkoSecond_Party_Night.json"

# ---------- Internals ----------
var _bg_node: Node = null
var _panel: Control = null
var _ui: Control = null
var _came_from_study_intro: bool = false

func _ready() -> void:
	GameState.location = "MarkoSecondEvent"

	_bg_node = null
	if bg_rect_path != NodePath():
		_bg_node = get_node_or_null(bg_rect_path)

	# Branch by reputation for the intro
	var rep = GameState.reputation
	if rep >= 50:
		_came_from_study_intro = true
		await _play_json(JSON_INTRO_STUDY)
		_show_choices_study_intro()
	else:
		_came_from_study_intro = false
		await _play_json(JSON_INTRO_PARTY)
		_show_choices_party_intro()

# -------------------- Choice sets --------------------
func _show_choices_study_intro() -> void:
	_clear_panel()
	var opts: Array = [
		{ "id": "study_with_marko", "text": "Yeah, let’s study." },
		{ "id": "party",            "text": "Nah, I’m done for tonight — let’s party!" }
	]
	_panel = preload(CCB_SCENE_PATH).instantiate()
	add_child(_panel)
	_panel.call("show_options", opts, Callable(self, "_on_choice"))

func _show_choices_party_intro() -> void:
	_clear_panel()
	var opts: Array = [
		{ "id": "party",       "text": "Let’s go." },
		{ "id": "solo_study",  "text": "I need to study." }
	]
	_panel = preload(CCB_SCENE_PATH).instantiate()
	add_child(_panel)
	_panel.call("show_options", opts, Callable(self, "_on_choice"))

# -------------------- Choice handler --------------------
func _on_choice(id: String) -> void:
	match id:
		"study_with_marko":
			_clear_panel()
			# Study with Marko: no time/stat change here; Study scene handles time.
			await _fade_to(study_scene_path)
			_mark_done(false)  # no party flag
		"solo_study":
			_clear_panel()
			# Solo study: +5 integrity, +60 minutes, then go home
			GameState.adjust_integrity(+5)
			GameState.adjust_time(60)
			await _fade_to(home_scene_path)
			_mark_done(false)
		"party":
			_clear_panel()
			await _handle_party_branch()
		_:
			_clear_panel()

# -------------------- Party branch --------------------
func _handle_party_branch() -> void:
	# Rep -5
	GameState.adjust_reputation(-5)

	# BG swaps ONLY for party; choose by gender
	_apply_party_bg_by_gender()

	# Set time to 21:00 while party is "playing"
	GameState.time = 21 * 60
	if GameState.has_method("_emit_time_changed"):
		GameState._emit_time_changed()

	# Play party JSON
	await _play_json(JSON_PARTY_NIGHT)

	# After party, set to 23:00 and send home
	GameState.time = 23 * 60
	if GameState.has_method("_emit_time_changed"):
		GameState._emit_time_changed()

	await _fade_to(home_scene_path)
	_mark_done(true)

# -------------------- Helpers --------------------
func _apply_party_bg_by_gender() -> void:
	if _bg_node == null:
		return
	var g = String(GameState.player_gender).to_lower()
	var tex: Texture2D = null
	if g == "female":
		tex = bg_party_female
	else:
		tex = bg_party_male

	if tex == null:
		return

	if _bg_node is TextureRect:
		(_bg_node as TextureRect).texture = tex
	elif _bg_node is Sprite2D:
		(_bg_node as Sprite2D).texture = tex
	elif _bg_node.has_method("set_texture"):
		_bg_node.call("set_texture", tex)

func _play_json(path: String) -> void:
	if path == "" or not FileAccess.file_exists(path):
		return
	_ui = DialogueManager.start_dialogue(path, self)
	if _ui and _ui.has_signal("dialogue_finished"):
		await _ui.dialogue_finished
	await get_tree().process_frame

func _fade_to(scene_path: String) -> void:
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		push_warning("Invalid scene path: " + scene_path)
		return
	await fade.fade_to_scene(scene_path, 0.4, 0.35)

func _mark_done(went_party: bool) -> void:
	GameState.set_flag("marko_second_event_done", true)
	if went_party:
		GameState.set_flag("marko_second_event_chose_party", true)

func _clear_panel() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null
