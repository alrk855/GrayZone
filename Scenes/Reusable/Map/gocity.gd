# res://Scripts/Reusable/go_to_scene_button.gd
extends Button

@export_file("*.tscn") var target_scene: String
@export var fade_out_duration: float = -1.0   # -1 => use fade singleton default
@export var fade_in_duration: float = -1.0    # -1 => use fade singleton default

func _ready() -> void:
	if not pressed.is_connected(Callable(self, "_on_pressed")):
		pressed.connect(_on_pressed)

func _on_pressed() -> void:
	# Respect frozen time (e.g., during dialogue)
	if GameState.has_method("is_time_frozen") and GameState.is_time_frozen():
		print("⏸️ Finish the conversation first.")
		return

	# Validate target
	if target_scene == "" or target_scene == null or not ResourceLoader.exists(target_scene):
		push_error("GoToSceneButton: invalid or missing target_scene: " + String(target_scene))
		return

	# Simple re-entry guard
	disabled = true

	# Use the global fade singleton directly (autoload named 'fade')
	await fade.fade_to_scene(target_scene, fade_out_duration, fade_in_duration)

	# If we’re somehow still in the same scene (e.g., editor preview), re-enable
	if is_inside_tree():
		disabled = false
