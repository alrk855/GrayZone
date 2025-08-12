# res://Scripts/Reusable/go_to_scene_button.gd
extends Button

@export_file("*.tscn") var target_scene: String

func _ready() -> void:
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	if GameState.is_time_frozen():
		print("⏸️ Finish the conversation first.")
		return
	if target_scene == "" or target_scene == null:
		push_error("GoToSceneButton: target_scene not set.")
		return
	get_tree().change_scene_to_file(target_scene)
