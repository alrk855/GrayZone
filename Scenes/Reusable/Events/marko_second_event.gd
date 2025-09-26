extends Control

# ---------- Exports ----------
@export var bg_rect_path: NodePath
@export var bg_party_male: Texture2D
@export var bg_party_female: Texture2D
@export var study_scene_path: String = "res://Scenes/Reusable/Tasks/Study.tscn"
@export var home_scene_path: String  = "res://Scenes/Reusable/Map/Home.tscn"

# Choice panel scene
const CCB_SCENE_PATH := "res://Scenes/Reusable/CharacterChoiceButtons.tscn"

# JSON IDs (relative under Data/)
const JSON_INTRO_STUDY_ID: String = "Marko/SecondEvent/MarkoSecond_Intro_Study.json"
const JSON_INTRO_PARTY_ID: String = "Marko/SecondEvent/MarkoSecond_Intro_Party.json"
const JSON_PARTY_NIGHT_ID: String = "Marko/SecondEvent/MarkoSecond_Party_Night.json"

# ---------- Local party music ----------
const PARTY_TRACK_PATH := "res://Audio/ACO!.mp3"
var _party_player: AudioStreamPlayer = null

# ---------- Internals ----------
var _bg_node: Node = null
var _panel: Control = null
var _ui: Control = null
var _came_from_study_intro: bool = false

func _ready() -> void:
	GameState.location = "Unknown"

	_bg_node = null
	if bg_rect_path != NodePath():
		_bg_node = get_node_or_null(bg_rect_path)

	# Branch by reputation for the intro
	var rep = GameState.reputation
	if rep >= 50:
		_came_from_study_intro = true
		await _play_json(JSON_INTRO_STUDY_ID)
		_show_choices_study_intro()
	else:
		_came_from_study_intro = false
		await _play_json(JSON_INTRO_PARTY_ID)
		_show_choices_party_intro()

# -------------------- Choice sets --------------------
func _show_choices_study_intro() -> void:
	_clear_panel()
	var opts: Array = [
		{ "id": "study_with_marko", "text": tr("Yeah, let’s study.") },
		{ "id": "party",            "text": tr("Nah, I’m done for tonight — let’s party!") }
	]
	_panel = preload(CCB_SCENE_PATH).instantiate()
	add_child(_panel)
	_panel.call("show_options", opts, Callable(self, "_on_choice"))

func _show_choices_party_intro() -> void:
	_clear_panel()
	var opts: Array = [
		{ "id": "party",       "text": tr("Let’s go.") },
		{ "id": "solo_study",  "text": tr("I need to study.") }
	]
	_panel = preload(CCB_SCENE_PATH).instantiate()
	add_child(_panel)
	_panel.call("show_options", opts, Callable(self, "_on_choice"))

# -------------------- Choice handler --------------------
func _on_choice(id: String) -> void:
	match id:
		"study_with_marko":
			_clear_panel()
			await _fade_to(study_scene_path)
			_mark_done(false)
		"solo_study":
			_clear_panel()
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
	GameState.adjust_reputation(-5)
	_apply_party_bg_by_gender()

	# stop global BG and start the local party loop
	GameState.stop_bg_music()
	_start_party_music()

	# advance to party time
	GameState.time = 21 * 60
	if GameState.has_method("_emit_time_changed"):
		GameState._emit_time_changed()

	await _play_json(JSON_PARTY_NIGHT_ID)

	# night passes
	GameState.time = 23 * 60
	if GameState.has_method("_emit_time_changed"):
		GameState._emit_time_changed()

	# stop party loop and restore global BG before leaving
	_stop_party_music()
	GameState.start_bg_music()

	await _fade_to(home_scene_path)
	_mark_done(true)

# -------------------- Local party music helpers --------------------
func _start_party_music() -> void:
	if _party_player == null:
		_party_player = AudioStreamPlayer.new()
		_party_player.bus = "Music"  # adjust if you use a different bus
		add_child(_party_player)

	var s := load(PARTY_TRACK_PATH)
	if s is AudioStream:
		s.loop = true
		_party_player.stream = s
		_party_player.play()
	else:
		push_warning("Party track missing: " + PARTY_TRACK_PATH)

func _stop_party_music() -> void:
	if _party_player:
		_party_player.stop()

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

func _play_json(relative_id: String) -> void:
	var p := _dp(relative_id)
	if p == "" or not FileAccess.file_exists(p):
		push_warning("MarkoSecondEvent: missing JSON → " + relative_id + " (resolved: " + p + ")")
		return
	_ui = DialogueManager.start_dialogue(p, self)
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

# -------- Golden data-path resolver (JSON) --------
func _dp(relative: String) -> String:
	var rel := String(relative).strip_edges().trim_prefix("/")
	if GameState.has_method("get_data_path"):
		return String(GameState.get_data_path(rel))
	return "res://Data/" + rel
