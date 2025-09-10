extends Button

@export var target_scene: PackedScene  # e.g., res://Scenes/Reusable/Tutorial.tscn

func _ready() -> void:
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	if target_scene == null:
		return

	var tree := get_tree()

	# Mark context: came from main menu
	tree.set_meta("tutorial_from_menu", true)

	# Remember previous scene path (optional)
	var prev_path := ""
	if tree.current_scene != null:
		prev_path = tree.current_scene.scene_file_path
	tree.set_meta("tutorial_prev_scene_path", prev_path)

	# Do NOT touch GameState.location here (main menu has no in-world location)
	# Do NOT freeze time; just load the tutorial
	tree.paused = false

	tree.change_scene_to_packed(target_scene)
