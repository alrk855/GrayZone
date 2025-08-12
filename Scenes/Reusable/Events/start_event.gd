extends Control

@onready var teacher_sprite: TextureRect = $background/Control/Control/teacher2
@onready var principal_sprite: TextureRect = $background/Control/Control/principal
@onready var screen_fader: ColorRect = $ColorRect

func _ready():
	GameState.location = "Classroom"
	principal_sprite.visible = false

	# Start dialogue (pass self so callbacks still work)
	var dialogue_ui = DialogueManager.start_dialogue("res://Data/StartEvent.json", self)

	# Connect to "dialogue_finished" if possible
	if dialogue_ui and dialogue_ui.has_signal("dialogue_finished"):
		dialogue_ui.connect("dialogue_finished", Callable(self, "_on_start_event_finished"))

func _on_start_event_finished(_dlg_id: String = "", _payload: Variant = null):
	# Start the global game clock AFTER the intro (keeps any JSON time adjustments)
	GameState.begin_game(GameState.day, GameState.time)

	print("🎬 StartEvent completed. Moving to School.")
	await fade_out()
	get_tree().change_scene_to_file("res://Scenes/Reusable/Map/School.tscn")

func on_scene_transition(namee: String):
	match namee:
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

# Route line actions through GameState helper
func on_dialogue_action(line: Dictionary):
	GameState.apply_action(line)

func on_choices_selected(selected: Array):
	if selected.size() >= 2:
		GameState.subject1 = selected[0]
		GameState.subject2 = selected[1]
		print("📘 Subjects chosen:", GameState.subject1, GameState.subject2)
