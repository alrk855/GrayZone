extends Control

@onready var teacher_sprite: TextureRect = $background/Control/Control/teacher2
@onready var principal_sprite: TextureRect = $background/Control/Control/principal
@onready var screen_fader: ColorRect = $ColorRect

func _ready():
	GameState.location = "Classroom"
	principal_sprite.visible = false
	DialogueManager.start_dialogue("res://Data/StartEvent.json", self)

func on_scene_transition(name: String):
	match name:
		"principal_enters":
			await fade_out()
			_swap_to_principal()
			await fade_in()

func _swap_to_principal():
	teacher_sprite.visible = false
	principal_sprite.visible = true

func fade_out():
	screen_fader.visible = true
	screen_fader.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(screen_fader, "modulate:a", 1.0, 0.5)
	await tween.finished

func fade_in():
	var tween = create_tween()
	tween.tween_property(screen_fader, "modulate:a", 0.0, 0.5)
	await tween.finished
	screen_fader.visible = false

func on_dialogue_action(line: Dictionary):
	match line["action"]:
		"add_task":
			print("🧩 Task marker received:", line["tasks"])
		"adjust_time":
			GameState.adjust_time(line["value"])
		"unlock_feature":
			GameState.unlock_game_feature(line["feature"])
		_:
			print("⚠ Unknown action:", line["action"])

func on_choices_selected(selected: Array):
	if selected.size() >= 2:
		GameState.subject1 = selected[0]
		GameState.subject2 = selected[1]
		print("📘 Subjects chosen:", GameState.subject1, GameState.subject2)
