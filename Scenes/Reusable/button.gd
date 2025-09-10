extends Button

@export var main_menu_scene_path: String = "res://Scenes/main_menu.tscn"

func _ready() -> void:
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	var tree := get_tree()

	# Where did we come from?
	var from_menu := false
	if tree.has_meta("tutorial_from_menu"):
		from_menu = bool(tree.get_meta("tutorial_from_menu"))

	var prev_path := ""
	if tree.has_meta("tutorial_prev_scene_path"):
		prev_path = String(tree.get_meta("tutorial_prev_scene_path"))

	# Restore the in-game UI and time
	GameUi.visible = true
	GameState.pop_time_freeze("tutorial")

	# Restore previous location (only set when opened from in-game)
	if tree.has_meta("tutorial_prev_location"):
		var prev_loc := String(tree.get_meta("tutorial_prev_location"))
		if prev_loc != "":
			GameState.location = prev_loc
		tree.set_meta("tutorial_prev_location", "")

	# Clear context flags
	tree.set_meta("tutorial_from_menu", false)
	tree.set_meta("tutorial_prev_scene_path", "")

	# Route back
	var go_prev := false
	if prev_path != "":
		if FileAccess.file_exists(prev_path):
			go_prev = true

	if (not from_menu) and go_prev:
		tree.change_scene_to_file(prev_path)
	else:
		tree.change_scene_to_file(main_menu_scene_path)
