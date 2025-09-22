# res://Scenes/Reusable/Tasks/WriteCV.gd
extends Control

const HOME_SCENE_PATH := "res://Scenes/Reusable/Map/Home.tscn"
const CV_TASK_ID := "cv"

# Required sections (case-insensitive). Add more if you want to enforce them.
const REQUIRED_TAGS := [
	"education:",
	"skills:",
	"name",
	"expirience"
]

var tekst_za_pisuvanje : String = "Name: Aco
Date of Birth: 28/11/2005
Education: High School
Skills: Typing, Teamwork, Basic Research
Experience: None yet - willing to learn"

@onready var animIntro : AnimationPlayer = $SceneAnimation
@onready var edit : TextEdit = $TextEdit
@onready var peek : Button = $"PeekButton"
@onready var box : Control = $CVBOX
@onready var write : Button = $WriteButton
@onready var _edit_base_modulate: Color = Color(1, 1, 1, 1)

func _ready() -> void:
	# Cache the base modulate so we can restore after error flash
	_edit_base_modulate = edit.modulate

	# Animation
	animIntro.play("CV_anim")

	# Default player name safeguard
	if GameState.player_name == "":
		GameState.player_name = "Aco"

	# Template text
	tekst_za_pisuvanje = "Name: " + GameState.player_name + "\nDate of Birth: 28/11/2005 \nEducation: High School \nSkills: Typing, Teamwork, Basic Research \nExperience: None yet - willing to learn"

	GameState.location = "Unknown" # Location Unknown

func _on_button_pressed() -> void: # Peek
	create_tween().tween_property(edit, "position", Vector2(2100, 278), 1) # edit
	create_tween().tween_property(box, "position", Vector2(517, 255), 1)   # CV text
	create_tween().tween_property(peek, "position", Vector2(1602, -120), 1)# peek
	create_tween().tween_property(write, "position", Vector2(0.0, 0), 1)   # write

func _on_scene_animation_animation_finished(anim_name: StringName) -> void:
	create_tween().tween_property(edit, "position", Vector2(580.5, 278.5), 1)
	create_tween().tween_property(peek, "position", Vector2(1602, 1), 1)

func _on_write_button_pressed() -> void:
	create_tween().tween_property(write, "position", Vector2(0.0, -120), 1)
	create_tween().tween_property(peek, "position", Vector2(1602, 0), 1)
	create_tween().tween_property(edit, "position", Vector2(580.5, 278.5), 1) # edit
	create_tween().tween_property(box, "position", Vector2(-1000, 255), 1)   # CV text

func _on_finish_button_pressed() -> void:
	# Trim trailing whitespace safely (original code crashed on empty string)
	edit.text = _trim_trailing_ws(edit.text)

	# Accept if exact template OR if it contains the required section tags (case-insensitive)
	if edit.text == tekst_za_pisuvanje or _contains_required_tags(edit.text):
		_finish_success()
	else:
		await _flash_edit_error()

# ---------------- Helpers ----------------

func _contains_required_tags(s: String) -> bool:
	var low := s.to_lower()
	for tag in REQUIRED_TAGS:
		if low.find(String(tag)) == -1:
			return false
	return true

func _trim_trailing_ws(s: String) -> String:
	while s.length() > 0:
		var ch := s[s.length() - 1]
		if ch == " " or ch == "\n" or ch == "\t" or ch == "\r":
			s = s.substr(0, s.length() - 1)
		else:
			break
	return s

func _finish_success() -> void:
	# 1) Advance CV task so printing unlocks (requires >= 2)
	_ensure_cv_progress_at_least(2)

	# 2) Go home (Fade singleton if available, else direct change)
	await _go_home()

func _ensure_cv_progress_at_least(step: int) -> void:
	# Make sure the task exists
	if GameState.has_method("ensure_task"):
		GameState.ensure_task(CV_TASK_ID)

	# Prefer helper if your GameState has it
	if GameState.has_method("ensure_task_progress_at_least"):
		GameState.ensure_task_progress_at_least(CV_TASK_ID, step)
		return

	# Fallback: increment until we reach the desired step
	var p := 0
	if GameState.has_method("get_task_progress"):
		p = GameState.get_task_progress(CV_TASK_ID)
	while p < step and GameState.has_method("update_task_step"):
		GameState.update_task_step(CV_TASK_ID)
		p += 1

func _get_fader() -> Node:
	# Try common autoload names/paths
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
	# Brief red flash, then restore
	var tw := create_tween()
	tw.tween_property(edit, "modulate", Color(1, 0.25, 0.25, 1), 0.12)
	tw.tween_interval(0.20)
	tw.tween_property(edit, "modulate", _edit_base_modulate, 0.22)
	await tw.finished

# Keep your original finish hook if something else calls it
func finish_game():
	_finish_success()
