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

# --------------------- Task/flags ---------------------
const TASK_MLETTER := "motivation"
const FLAG_MLETTER_WRITTEN := "motivation_written"

# --------------------- Optional JSON templates ---------------------
@export_file("*.json") var TEMPLATES_JSON: String = ""   # expects {"templates": ["Dear ...", "...", ...]}

# Fallback in-code templates (used if JSON missing/invalid)
@onready var text_library : Array[String] = [
	"Dear Committee, I come from a modest background, but I've worked hard to maintain my grades. I believe this scholarship can help me continue my education and give back to the community. Thank you for the opportunity. Sincerely, Me",
	"Dear Committee, I'm the first in my family to attend college. This scholarship would let me keep my grades up and continue mentoring local kids. Thank you. Sincerely, Me",
	"Dear Committee, Hard work lifted my GPA to 3.9 despite tight finances. Your support keeps me in school and giving back. Thanks. Best, Me",
	"Dear Esteemed Committee, My journey began at a kitchen table where bills often outnumbered paychecks. From that table, I learned that perseverance is a currency more reliable than cash. It bought me top grades, leadership roles in two campus clubs, and the chance every Saturday to serve meals at the youth shelter.",
	"Dear Committee, I juggle jobs and classes to stay on the Dean's List. Help me finish my degree and keep tutoring teens. Thank you."
]

# --------------------- Runtime state ---------------------
var _templates: Array[String] = []
var current: int = 0
var words: PackedStringArray = []
var current_word: int = 0
var correct: int = 0
var wrong: int = 0
var freed: bool = false

# completion guards
var _completed := false
var _task_bumped := false

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
	finishbutt.modulate.a = 0

	# Make sure buttons always fire
	if not nevermind.pressed.is_connected(Callable(self, "exit")):
		nevermind.pressed.connect(Callable(self, "exit"))
	if not finishbutt.pressed.is_connected(Callable(self, "exit")):
		finishbutt.pressed.connect(Callable(self, "exit"))

	# Make sure LineEdit submit is connected even if the scene isn’t wired
	if not edit.text_submitted.is_connected(Callable(self, "_on_line_edit_text_submitted")):
		edit.text_submitted.connect(Callable(self, "_on_line_edit_text_submitted"))

	# Load templates (JSON if provided; otherwise fallback to text_library)
	_load_templates()

	$SceneAnimation.play("LetterIntro")
	current = randi() % max(_templates.size(), 1)
	words = _templates[current].split(" ", false)
	current_word = 0
	correct = 0
	wrong = 0
	freed = false
	header.text = words[current_word]
	await $SceneAnimation.animation_finished

func _load_templates() -> void:
	_templates.clear()

	# Try JSON first
	if TEMPLATES_JSON.strip_edges() != "" and FileAccess.file_exists(TEMPLATES_JSON):
		var raw := FileAccess.get_file_as_string(TEMPLATES_JSON)
		var parsed = JSON.parse_string(raw)
		if typeof(parsed) == TYPE_DICTIONARY:
			var dict: Dictionary = parsed
			var arr: Variant = dict.get("templates", [])
			if arr is Array:
				for t in (arr as Array):
					var s := String(t).strip_edges()
					if s != "":
						_templates.append(s)

	# Fallback to in-code strings
	if _templates.is_empty():
		for s in text_library:
			var ss := String(s).strip_edges()
			if ss != "":
				_templates.append(ss)

	# Absolute last resort (should not happen)
	if _templates.is_empty():
		_templates.append("Dear Committee, Thank you for your time. Sincerely, Me")

func _on_line_edit_text_submitted(new_text: String) -> void:
	# Manual typing path
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

func _process(_delta: float) -> void:
	# Tiny debug HUD
	debLabel.text = "Correct: %d\nErrors: %d\nStatus:" % [correct, wrong]

	# Auto-accept when the currently typed word equals header.text (keeps your old QoL)
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
		outro()  # → marks complete & bumps task exactly once

func _on_button_pressed() -> void:
	# Start the typing game version
	gamebox.modulate.a = 0
	create_tween().tween_property(gamebox, "modulate:a", 1, 2)
	box.visible = false
	gamebox.visible = true
	msg.play("mesg")

func _on_button_2_pressed() -> void:
	# GPT version (auto-generate)
	box.visible = false
	$outroGPT.visible = true
	gptanim.play("GPT")
	await gptanim.animation_finished
	$outroGPT.visible = false
	outro()  # → shares same completion path as manual typing

func outro() -> void:
	_mark_completed_once()   # task bump + flag set

	# Your existing outro UI/FX
	zvuk_end.play()
	debLabel.visible_ratio = 0
	status.visible = false
	outrobox.visible = true

	var tween : Tween = create_tween()
	if wrong == 0:
		status.text = "Perfect"
	elif wrong > 0 and wrong < 4:
		status.text = "Almost Perfect"
	elif wrong > 3 and wrong < 7:
		status.text = "Mid"
	else:
		status.text = "Bad"
	tween.tween_property(debLabel, "visible_ratio", 1, 1)
	await tween.finished
	status.visible = true
	create_tween().tween_property(status, "modulate:a", 1, 5)
	create_tween().tween_property(finishbutt, "modulate:a", 1, 5)

func _mark_completed_once() -> void:
	if _completed:
		return
	_completed = true

	# Task bump (both GPT and manual funnel through here)
	if not _task_bumped:
		GameState.ensure_task(TASK_MLETTER)
		GameState.update_task_step(TASK_MLETTER)   # fires TaskManager notification
		_task_bumped = true

	# Flag for teacher/doc-review gating
	GameState.set_flag(FLAG_MLETTER_WRITTEN, true)

func SFX_play() -> void:
	var sound := AudioStreamPlayer2D.new()
	add_child(sound)
	sound.stream = zvuci[randi() % zvuci.size()]
	sound.play()
	await sound.finished
	sound.queue_free()

func exit() -> void:
	# No task/flag logic here; completion is handled in outro()
	var tween : Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0, 1).set_trans(Tween.TRANS_CUBIC)
	await tween.finished
	get_tree().change_scene_to_file("res://Scenes/Reusable/Map/Home.tscn")
