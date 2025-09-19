extends Button

@export var main_menu_scene_path: String = "res://Scenes/main_menu.tscn"

func _ready() -> void:
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	var tree := get_tree()

	# Read context
	var from_menu := tree.has_meta("tutorial_from_menu") and bool(tree.get_meta("tutorial_from_menu"))

	var prev_path := ""
	if tree.has_meta("tutorial_prev_scene_path"):
		prev_path = String(tree.get_meta("tutorial_prev_scene_path"))

	var prev_loc := ""
	if tree.has_meta("tutorial_prev_location"):
		prev_loc = String(tree.get_meta("tutorial_prev_location"))

	# Clear context metas so nothing leaks into next opens
	tree.set_meta("tutorial_from_menu", false)
	tree.set_meta("tutorial_prev_scene_path", "")
	tree.set_meta("tutorial_prev_location", "")

	# Is there a valid previous scene to return to?
	var go_prev := prev_path != "" and ResourceLoader.exists(prev_path)

	# Ensure unpaused
	tree.paused = false

	if go_prev and not from_menu:
		# Returning to the game world → restore UI/time/location
		if typeof(GameUi) != TYPE_NIL:
			GameUi.visible = true
		if typeof(GameState) != TYPE_NIL:
			GameState.pop_time_freeze("tutorial")
			if prev_loc != "":
				GameState.location = prev_loc
		tree.change_scene_to_file(prev_path)
	else:
		# From main menu (or no valid prev) → go to main menu, UI hidden
		if typeof(GameUi) != TYPE_NIL:
			GameUi.visible = false
		tree.change_scene_to_file(main_menu_scene_path)
