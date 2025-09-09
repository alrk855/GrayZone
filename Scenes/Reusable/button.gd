extends Button

@export var main_menu_scene_path: String = "res://Scenes/main_menu.tscn"

func _ready() -> void:
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	var tree := get_tree()

	# Read context
	var from_menu := false
	if tree.has_meta("tutorial_from_menu"):
		from_menu = bool(tree.get_meta("tutorial_from_menu"))

	var prev_path := ""
	if tree.has_meta("tutorial_prev_scene_path"):
		prev_path = String(tree.get_meta("tutorial_prev_scene_path"))

	# Restore location (if we locked it to Unknown)
	if Engine.has_singleton("GameState"):
		var GS := Engine.get_singleton("GameState")
		if GS and GS.has("location"):
			var had_prev_loc := tree.has_meta("tutorial_prev_location")
			if had_prev_loc:
				var prev_loc := String(tree.get_meta("tutorial_prev_location"))
				GS.location = prev_loc
			tree.set_meta("tutorial_prev_location", "")

	# Unfreeze gameplay time
	var unfroze := false
	if Engine.has_singleton("GameState"):
		var GS2 := Engine.get_singleton("GameState")
		if GS2 and GS2.has_method("pop_freeze"):
			GS2.pop_freeze("tutorial")
			unfroze = true
		elif GS2 and GS2.has_method("freeze_time"):
			GS2.freeze_time(false)
			unfroze = true

	# If we paused the tree as fallback, unpause it now
	if not unfroze:
		if tree.has_meta("paused_by_tutorial"):
			tree.paused = false
			tree.set_meta("paused_by_tutorial", false)

	# Restore HUD visibility
	_set_hud_visible(true)

	# Clear context
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

# ----------- HUD helpers -----------

func _get_hud_node() -> CanvasItem:
	var root := get_tree().get_root()

	# Try common names first
	var hud := root.find_child("HUD", true, false)
	if hud and hud is CanvasItem:
		return hud as CanvasItem

	var top_hud := root.find_child("TopHUD", true, false)
	if top_hud and top_hud is CanvasItem:
		return top_hud as CanvasItem

	# Or anything in "hud" group
	var group_nodes := get_tree().get_nodes_in_group("hud")
	for n in group_nodes:
		if n is CanvasItem:
			return n as CanvasItem

	return null

func _set_hud_visible(v: bool) -> void:
	var hud := _get_hud_node()
	if hud:
		hud.visible = v
