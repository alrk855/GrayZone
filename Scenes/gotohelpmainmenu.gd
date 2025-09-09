extends Button

@export var target_scene: PackedScene  # res://Scenes/Reusable/Tutorial.tscn

func _ready() -> void:
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	if target_scene == null:
		return

	var tree := get_tree()

	# Mark context: we're coming from the main menu.
	tree.set_meta("tutorial_from_menu", true)

	# Remember previous scene path (for completeness)
	var prev_path := ""
	if tree.current_scene != null:
		prev_path = tree.current_scene.scene_file_path
	tree.set_meta("tutorial_prev_scene_path", prev_path)

	# Ensure not paused when coming from menu
	tree.paused = false

	tree.change_scene_to_packed(target_scene)
