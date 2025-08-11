extends Button

@export var target_scene: String = "res://Scenes/Reusable/Map/School.tscn"

func _ready() -> void:
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	# Don’t allow leaving mid-dialogue/time-freeze
	if GameState.is_time_frozen():
		print("⏸️ Finish the conversation first.")
		return
	get_tree().change_scene_to_file("res://Scenes/Reusable/Map/School.tscn")
