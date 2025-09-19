extends Control

# ---------- Background (full-scene) ----------
# Point this to your TextureRect or Sprite2D that renders the whole classroom background.
@export var background_node_path: NodePath = "background"
@onready var _bg_node: Node = get_node_or_null(background_node_path)

# Assign these in the Inspector (full backgrounds):
@export var bg_teacher: Texture2D
@export var bg_principal: Texture2D

# ---------- Fade ----------
@onready var screen_fader: ColorRect = $ColorRect

func _ready():
	GameUi.visible = true
	GameState.location = "Classroom"

	# Start with the teacher background
	_set_bg(bg_teacher)

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

# Called by DialogueManager via action: {"action":"principal_enters"}
func on_scene_transition(namee: String):
	match namee:
		"principal_enters":
			await fade_out()
			_set_bg(bg_principal)
			await fade_in()

# ---------- BG setter ----------
func _set_bg(tex: Texture2D) -> void:
	if _bg_node == null or tex == null:
		return
	if _bg_node is TextureRect:
		(_bg_node as TextureRect).texture = tex
	elif _bg_node is Sprite2D:
		(_bg_node as Sprite2D).texture = tex
	elif _bg_node.has_method("set_texture"):
		_bg_node.call("set_texture", tex)

# ---------- Fade helpers ----------
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
