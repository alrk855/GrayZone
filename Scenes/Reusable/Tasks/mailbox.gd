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

# -------- Task id used for progress (matches file name language.json) --------
const TASK_LANG_CERT := "language"  # <— fixed id

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

	var arrived := (GameState.day >= GameState.lang_cert_ready_day) or (GameState.day > 4)
	_set_bg(arrived)

	var json_path := arrived ? J_MAIL_ARRIVED : J_MAIL_NOT_ARRIVED

	# If arrived: set flag (once) AND always ensure task exists + advance to final step
	if arrived:
		if not GameState.has_flag(GF.HAVE_LANGUAGE_CERTIFICATE):
			GameState.set_flag(GF.HAVE_LANGUAGE_CERTIFICATE, true)
		_ensure_task_and_finish(TASK_LANG_CERT)

	await _play_dialogue_and_return(json_path)

func _ensure_task_and_finish(task_id: String) -> void:
	# Ensure the task exists
	if GameState.has_method("ensure_task"):
		GameState.ensure_task(task_id)
	else:
		if not GameState.tasks.has(task_id):
			GameState.add_task(task_id)

	# Read the task JSON to determine the final step index (assumes 1-based steps)
	var final_idx := _get_task_final_step_index(task_id)
	if final_idx > 0:
		if GameState.has_method("ensure_task_progress_at_least"):
			GameState.ensure_task_progress_at_least(task_id, final_idx)
		else:
			# Fallback: bump step once if the helper is missing
			if GameState.has_method("update_task_step"):
				while GameState.get_task_progress(task_id) < final_idx:
					GameState.update_task_step(task_id)
	else:
		# If we couldn't read the JSON, still make sure the task is at least started
		if GameState.has_method("ensure_task_progress_at_least"):
			GameState.ensure_task_progress_at_least(task_id, 1)

func _get_task_final_step_index(task_id: String) -> int:
	var path := "res://Data/Tasks/%s.json" % task_id
	if not FileAccess.file_exists(path):
		var alt := "res://Data/Tasks/%s.json" % task_id.to_lower()
		if FileAccess.file_exists(alt):
			path = alt
		else:
			push_warning("[Mailbox] Task JSON not found for '%s' at %s" % [task_id, path])
			return 0

	var txt := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) == TYPE_DICTIONARY:
		var steps = (parsed as Dictionary).get("steps", [])
		if steps is Array and steps.size() > 0:
			# Convention in your project: step indices are 1..N
			return steps.size()
	return 0

func _set_bg(arrived: bool) -> void:
	if _bg:
		_bg.texture = texture_full if arrived else texture_empty

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
