# res://Scripts/Scenes/WriteMotivation.gd
extends Control

# --------------------- UI refs ---------------------
@onready var lab : Label = $"a"
@onready var header : Label = $"gamebox/Header"
@onready var edit : LineEdit = $"gamebox/LineEdit"
@onready var debLabel : Label = $"outrobox/DebugLabel"
@onready var gamebox : Control = $"gamebox"
@onready var outrobox : Control = $"outrobox"
@onready var box : Control = $"box"
@onready var msg : AnimationPlayer = $"message/AnimationPlayer"
@onready var status : Label = $"outrobox/status"
@onready var gptanim : AnimationPlayer = $"outroGPT/AnimationPlayer"
@onready var finishbutt : Button = $"outrobox/finish"
@onready var nevermind : Button = $"box/button3"
@onready var zvuk_end : AudioStreamPlayer2D = $"end"
@onready var zvuk_wrong : AudioStreamPlayer2D = $"wrong"
@onready var AILABEL : Label = $"outroGPT/textfull"
@onready var scene_anim : AnimationPlayer = $SceneAnimation

# ---- GPT button ----
@export var gpt_button_path: NodePath = ^"box/button2"
@export var hide_gpt_by_default: bool = false
var _gpt_button: Button = null

# --------------------- Task/flags ---------------------
const TASK_MLETTER := "motivation"
const FLAG_MLETTER_WRITTEN := "motivation_written"

# Shared flags
const F_PRINTED_MOTIVATION  := "printed_motivation"
const F_MLETTER_AI          := "motivation_ai_generated"
const F_MLETTER_REWRITE_REQ := "motivation_rewrite_required"

# --------------------- JSON locations (RELATIVE) ---------------------
# Relative IDs under Data/. Resolve with GameState.get_data_path(<id>).
const HUMAN_DIR_ID := "MotivationTemplates/Human"                   # directory containing many Motivation_Human_XX.json
const AI_JSON_ID   := "MotivationTemplates/AI/Motivation_AI_01.json"

# --------------------- Runtime state ---------------------
var _templates: Array[String] = []   # holds exactly 1 manual template after load
var current: int = 0
var words: PackedStringArray = []
var current_word: int = 0
var correct: int = 0
var wrong: int = 0
var freed: bool = false

# completion guards
var _completed := false
var _task_bumped := false
var _used_gpt := false

# --------------------- SFX pool ---------------------
var zvuci : Array[AudioStream] = [
	preload("res://Audio/MotivLetterSounds/b1.mp3"),
	preload("res://Audio/MotivLetterSounds/b2.mp3"),
	preload("res://Audio/MotivLetterSounds/b3.mp3"),
	preload("res://Audio/MotivLetterSounds/b4.mp3"),
	preload("res://Audio/MotivLetterSounds/b5.mp3")
]

func _ready() -> void:
	randomize()
	GameState.location = "Unknown"
	finishbutt.modulate.a = 0.0

	# Buttons
	if not nevermind.pressed.is_connected(Callable(self, "exit")):
		nevermind.pressed.connect(Callable(self, "exit"))
	if not finishbutt.pressed.is_connected(Callable(self, "exit")):
		finishbutt.pressed.connect(Callable(self, "exit"))

	# GPT button setup: hide/disable if rewrite is required (manual-only)
	_gpt_button = get_node_or_null(gpt_button_path) as Button
	var lock_manual: bool = GameState.has_flag(F_MLETTER_REWRITE_REQ)
	var hide_now: bool = hide_gpt_by_default or lock_manual
	if _gpt_button:
		_gpt_button.visible = not hide_now
		_gpt_button.disabled = hide_now
		if not hide_now and not _gpt_button.pressed.is_connected(Callable(self, "_on_button_2_pressed")):
			_gpt_button.pressed.connect(Callable(self, "_on_button_2_pressed"))

	# LineEdit submit
	if not edit.text_submitted.is_connected(Callable(self, "_on_line_edit_text_submitted")):
		edit.text_submitted.connect(Callable(self, "_on_line_edit_text_submitted"))

	# Load the single AI JSON and show it in the AI panel now (no randomness)
	_load_ai_text_into_label()

	# Load exactly ONE manual template from JSONs (random pick among Human/*.json)
	_load_one_manual_template()

	# Start intro and typing content
	if scene_anim:
		scene_anim.play("LetterIntro")
	current = 0
	words = _templates[current].split(" ", false)
	current_word = 0
	correct = 0
	wrong = 0
	freed = false
	header.text = words[current_word]
	if scene_anim:
		await scene_anim.animation_finished

# --------------------- Manual typing ---------------------
func _on_button_pressed() -> void:
	gamebox.modulate.a = 0.0
	create_tween().tween_property(gamebox, "modulate:a", 1.0, 2.0)
	box.visible = false
	gamebox.visible = true
	msg.play("mesg")

func _on_line_edit_text_submitted(new_text: String) -> void:
	if new_text == header.text:
		current_word += 1
		correct += 1
		edit.text = ""
		SFX_play()
	else:
		wrong += 1
		current_word += 1
		edit.text = ""
		edit.grab_focus()
		if not zvuk_wrong.playing:
			zvuk_wrong.play()

# --------------------- GPT path (uses AILABEL content) ---------------------
func _on_button_2_pressed() -> void:
	# Hard block if rewrite required → manual-only
	if GameState.has_flag(F_MLETTER_REWRITE_REQ):
		return
	_used_gpt = true

	box.visible = false
	$outroGPT.visible = true
	gptanim.play("GPT")
	await gptanim.animation_finished
	$outroGPT.visible = false
	outro()

# --------------------- Flow ---------------------
func _process(_delta: float) -> void:
	debLabel.text = tr("Correct: %d") % correct + "\n" + tr("Errors: %d") % wrong + "\n" + tr("Status:")
	if current_word < words.size():
		header.text = words[current_word]
		if edit.text == header.text:
			current_word += 1
			correct += 1
			edit.text = ""
			SFX_play()
	elif not freed:
		freed = true
		gamebox.visible = false
		outro()

func outro() -> void:
	_mark_completed_once()

	zvuk_end.play()
	debLabel.visible_ratio = 0.0
	status.visible = false
	outrobox.visible = true

	var tween : Tween = create_tween()
	if wrong == 0:
		status.text = tr("Perfect")
	elif wrong < 4:
		status.text = tr("Almost Perfect")
	elif wrong < 7:
		status.text = tr("Mid")
	else:
		status.text = tr("Bad")
	tween.tween_property(debLabel, "visible_ratio", 1.0, 1.0)
	await tween.finished
	status.visible = true
	create_tween().tween_property(status, "modulate:a", 1.0, 5.0)
	create_tween().tween_property(finishbutt, "modulate:a", 1.0, 5.0)

func _mark_completed_once() -> void:
	if _completed:
		return
	_completed = true

	# Bump the task (Secretary meeting likely set it to 1; this moves it to 2)
	if not _task_bumped:
		GameState.ensure_task(TASK_MLETTER)
		GameState.update_task_step(TASK_MLETTER)
		_task_bumped = true

	# Mark written
	GameState.set_flag(FLAG_MLETTER_WRITTEN, true)

	# GPT vs Manual: if manual while rewrite_required, clear AI flag so review won't ping again
	if _used_gpt:
		GameState.set_flag(F_MLETTER_AI, true)
	else:
		if GameState.has_flag(F_MLETTER_REWRITE_REQ) and GameState.has_flag(F_MLETTER_AI):
			GameState.clear_flag(F_MLETTER_AI)

func SFX_play() -> void:
	var sound := AudioStreamPlayer2D.new()
	add_child(sound)
	sound.stream = zvuci[randi() % zvuci.size()]
	sound.play()
	await sound.finished
	sound.queue_free()

func exit() -> void:
	var tween : Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 1.0).set_trans(Tween.TRANS_CUBIC)
	await tween.finished
	get_tree().change_scene_to_file("res://Scenes/Reusable/Map/Home.tscn")

# ===================== JSON LOADERS (manual/AI) =====================

# Manual: pick one random JSON from HUMAN_DIR_ID and use it as the typing content
func _load_one_manual_template() -> void:
	_templates.clear()
	var dir_abs: String = String(GameState.get_data_path(HUMAN_DIR_ID))
	var picked_abs: String = _pick_random_json_from_abs_dir(dir_abs)
	var text: String = _read_text_from_json(picked_abs)
	if text.strip_edges() == "":
		push_warning("MLetter: fallback used (no Human JSON found or empty). Tried dir: " + dir_abs)
		text = tr("Dear Committee, Thank you for your time. Sincerely, {name}")
	text = _apply_placeholders(text)
	_templates.append(text)

# AI: load the single file you specified and assign to AILABEL (no randomness)
func _load_ai_text_into_label() -> void:
	var ai_abs: String = String(GameState.get_data_path(AI_JSON_ID))
	var text: String = _read_text_from_json(ai_abs)
	if text.strip_edges() == "":
		push_warning("MLetter: AI fallback used (missing/empty): " + ai_abs)
		text = tr("Esteemed Committee, I am enthusiastic about joining your program. With gratitude, {name}")
	text = _apply_placeholders(text)
	if AILABEL:
		AILABEL.text = text

# Pick a random .json from an *absolute* directory path
func _pick_random_json_from_abs_dir(dir_abs: String) -> String:
	var da := DirAccess.open(dir_abs)
	if da == null:
		push_warning("MLetter: directory not found → " + dir_abs)
		return ""
	var files: Array[String] = []
	da.list_dir_begin()
	while true:
		var fname: String = da.get_next()
		if fname == "":
			break
		if da.current_is_dir():
			continue
		if fname.to_lower().ends_with(".json"):
			files.append(dir_abs.rstrip("/") + "/" + fname)
	da.list_dir_end()
	if files.is_empty():
		push_warning("MLetter: no .json files in → " + dir_abs)
		return ""
	return files[randi() % files.size()]

func _read_text_from_json(abs_path: String) -> String:
	if abs_path.strip_edges() == "" or not FileAccess.file_exists(abs_path):
		return ""
	var raw: String = FileAccess.get_file_as_string(abs_path)
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) == TYPE_DICTIONARY:
		var dict: Dictionary = parsed
		return String(dict.get("text", ""))
	push_warning("MLetter: bad JSON format in → " + abs_path)
	return ""

# --- Placeholder helper: {name} and [Field] ---
func _apply_placeholders(s: String) -> String:
	var nm: String = String(GameState.player_name).strip_edges()
	if nm == "":
		nm = tr("Student")
	var field: String = String(GameState.subject1).strip_edges()
	if field == "":
		field = tr("your field")
	s = s.replace("{name}", nm)
	s = s.replace("[Field]", field).replace("[field]", field).replace("[FIELD]", field)
	return s
 	
