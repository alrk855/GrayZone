# res://Scenes/Map/Reusable/Tasks/Mailbox/Mailbox.gd
extends Control

const GF = preload("res://Scripts/Singleton/GameFlags.gd")

# -------- Scene nodes / assets --------
@export var background_path: NodePath = ^"background"
@export var texture_empty: Texture2D
@export var texture_full: Texture2D
@export var home_scene_path: String = "res://Scenes/Reusable/Map/Home.tscn"

# -------- JSONs (in Data/Home) --------
const D_HOME := "res://Data/Home/"
const J_MAIL_NOT_ARRIVED := D_HOME + "Mail_LangCert_Not_Arrived.json"
const J_MAIL_ARRIVED     := D_HOME + "Mail_LangCert_Arrived.json"

# -------- Task id used for progress --------
const TASK_LANG_CERT := "language_certificate"

@onready var _bg: TextureRect = get_node_or_null(background_path) as TextureRect
var _returned := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.location = "Mailbox"
	GameState.push_time_freeze("mailbox_scene")

	# Initialize arrival day once (1..4) and persist in GameState
	if GameState.lang_cert_ready_day <= 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		GameState.lang_cert_ready_day = rng.randi_range(1, 4)
		print("[Mailbox] lang_cert_ready_day = Day %d" % GameState.lang_cert_ready_day)

	var arrived: bool = false
	if GameState.day >= GameState.lang_cert_ready_day or GameState.day > 4:
		arrived = true

	_set_bg(arrived)

	var json_path := ""
	if arrived:
		json_path = J_MAIL_ARRIVED
	else:
		json_path = J_MAIL_NOT_ARRIVED

	# On first arrival, set flag + ensure/advance task
	if arrived and not GameState.has_flag(GF.HAVE_LANGUAGE_CERTIFICATE):
		GameState.set_flag(GF.HAVE_LANGUAGE_CERTIFICATE, true)
		if not GameState.tasks.has(TASK_LANG_CERT):
			GameState.add_task(TASK_LANG_CERT)
		GameState.ensure_task_progress_at_least(TASK_LANG_CERT, 1)

	await _play_dialogue_and_return(json_path)

func _set_bg(arrived: bool) -> void:
	if _bg:
		if arrived:
			_bg.texture = texture_full
		else:
			_bg.texture = texture_empty

func _play_dialogue_and_return(json_path: String) -> void:
	# Start dialogue via your DialogueManager (simple narrator-only JSONs)
	if FileAccess.file_exists(json_path):
		DialogueManager.start_dialogue(json_path, self)
	else:
		push_error("[Mailbox] Missing dialogue JSON: " + json_path)

	# Wait for dialogue to end (common signals) or fallback timer.
	if DialogueManager and DialogueManager.has_signal("dialogue_finished"):
		await DialogueManager.dialogue_finished
	elif DialogueManager and DialogueManager.has_signal("dialogue_closed"):
		await DialogueManager.dialogue_closed
	else:
		var sec := _estimate_dialogue_duration(json_path)
		await get_tree().create_timer(sec).timeout

	_go_home()

func _estimate_dialogue_duration(json_path: String) -> float:
	var sec: float = 1.5
	if FileAccess.file_exists(json_path):
		var txt := FileAccess.get_file_as_string(json_path)
		var parsed = JSON.parse_string(txt)
		if typeof(parsed) == TYPE_DICTIONARY:
			var lines: Array = (parsed as Dictionary).get("lines", []) as Array
			var calc := float(lines.size()) * 2.2
			if calc > 1.5:
				sec = calc
	return sec

func _go_home() -> void:
	if _returned:
		return
	_returned = true
	GameState.pop_time_freeze("mailbox_scene")
	if home_scene_path != "" and ResourceLoader.exists(home_scene_path):
		get_tree().change_scene_to_file(home_scene_path)
