# res://Scenes/Reusable/Tasks/WriteCV.gd
extends Control

const HOME_SCENE_PATH := "res://Scenes/Reusable/Map/Home.tscn"
const CV_TASK_ID := "cv"

# Required sections (case-insensitive). Logic stays in English.
const REQUIRED_TAGS_EN := [
	"education:",
	"skills:",
	"name",
	"experience"
]
const REQUIRED_TAGS_MK := [
	"образование:",
	"вештини:",
	"име",
	"искуство"
]
var tekst_za_pisuvanje: String = ""

@onready var animIntro : AnimationPlayer = $SceneAnimation
@onready var edit : TextEdit = $TextEdit
@onready var peek : Button = $"PeekButton"
@onready var box : Control = $CVBOX
@onready var write : Button = $WriteButton
@onready var _edit_base_modulate: Color = Color(1, 1, 1, 1)

@export var back_button_path: NodePath

func _ready() -> void:
	_edit_base_modulate = edit.modulate
	animIntro.play("CV_anim")

	# Default player name safeguard (logic only)
	if GameState.player_name == "":
		GameState.player_name = "Aco"

	# Localized template for the *output text only*
	tekst_za_pisuvanje = _make_localized_template()

	GameState.location = "Unknown"

	_wire_back_button()

func _make_localized_template() -> String:
	# Only the visible strings are localized; the logic keys remain English.
	# Add these keys to your .translation files:
	# "Name:", "Date of Birth:", "Education:", "High School",
	# "Skills:", "Typing, Teamwork, Basic Research",
	# "Experience:", "None yet - willing to learn"
	var lines := [
		tr("Name:") + " " + GameState.player_name,
		tr("Date of Birth:") + " 28/11/2005",
		tr("Education:") + " " + tr("High School"),
		tr("Skills:") + " " + tr("Typing, Teamwork, Basic Research"),
		tr("Experience:") + " " + tr("None yet - willing to learn")
	]
	return String("\n").join(lines)

func _wire_back_button() -> void:
	if back_button_path == NodePath():
		return
	var n := get_node_or_null(back_button_path)
	if n and n is Button:
		var btn := n as Button
		if not btn.is_connected("pressed", Callable(self, "_on_back_pressed")):
			btn.pressed.connect(_on_back_pressed)

func _on_back_pressed() -> void:
	await _go_home()

func _on_button_pressed() -> void: # Peek
	create_tween().tween_property(edit, "position", Vector2(2100, 278), 1)
	create_tween().tween_property(box, "position", Vector2(517, 255), 1)
	create_tween().tween_property(peek, "position", Vector2(1602, -120), 1)
	create_tween().tween_property(write, "position", Vector2(0.0, 0), 1)

func _on_scene_animation_animation_finished(anim_name: StringName) -> void:
	create_tween().tween_property(edit, "position", Vector2(580.5, 278.5), 1)
	create_tween().tween_property(peek, "position", Vector2(1602, 1), 1)

func _on_write_button_pressed() -> void:
	create_tween().tween_property(write, "position", Vector2(0.0, -120), 1)
	create_tween().tween_property(peek, "position", Vector2(1602, 0), 1)
	create_tween().tween_property(edit, "position", Vector2(580.5, 278.5), 1)
	create_tween().tween_property(box, "position", Vector2(-1000, 255), 1)

func _on_finish_button_pressed() -> void:
	# Trim trailing whitespace safely
	edit.text = _trim_trailing_ws(edit.text)

	# Accept if exact (localized) template OR if it contains required English tags
	if edit.text == tekst_za_pisuvanje or _contains_required_tags(edit.text):
		_finish_success()
	else:
		await _flash_edit_error()

# ---------------- Helpers ----------------

func _contains_required_tags(s: String) -> bool:
	var low := s.to_lower()

	# Check if all EN tags exist
	var en_ok := true
	for tag in REQUIRED_TAGS_EN:
		if low.find(tag) == -1:
			en_ok = false
			break

	# Check if all MK tags exist
	var mk_ok := true
	for tag in REQUIRED_TAGS_MK:
		if low.find(tag) == -1:
			mk_ok = false
			break

	return en_ok or mk_ok
func _trim_trailing_ws(s: String) -> String:
	while s.length() > 0:
		var ch := s[s.length() - 1]
		if ch == " " or ch == "\n" or ch == "\t" or ch == "\r":
			s = s.substr(0, s.length() - 1)
		else:
			break
	return s

func _finish_success() -> void:
	_ensure_cv_progress_at_least(2)
	await _go_home()

func _ensure_cv_progress_at_least(step: int) -> void:
	if GameState.has_method("ensure_task"):
		GameState.ensure_task(CV_TASK_ID)

	if GameState.has_method("ensure_task_progress_at_least"):
		GameState.ensure_task_progress_at_least(CV_TASK_ID, step)
		return

	var p := 0
	if GameState.has_method("get_task_progress"):
		p = GameState.get_task_progress(CV_TASK_ID)
	while p < step and GameState.has_method("update_task_step"):
		GameState.update_task_step(CV_TASK_ID)
		p += 1

func _get_fader() -> Node:
	var paths := ["/root/Fade", "/root/fade", "/root/FADE"]
	for p in paths:
		if has_node(p):
			return get_node(p)
	return null

func _go_home() -> void:
	var fader := _get_fader()
	if fader and fader.has_method("fade_to_scene"):
		await fader.fade_to_scene(HOME_SCENE_PATH)
	else:
		get_tree().change_scene_to_file(HOME_SCENE_PATH)

func _flash_edit_error() -> void:
	var tw := create_tween()
	tw.tween_property(edit, "modulate", Color(1, 0.25, 0.25, 1), 0.12)
	tw.tween_interval(0.20)
	tw.tween_property(edit, "modulate", _edit_base_modulate, 0.22)
	await tw.finished

func finish_game():
	_finish_success()
