extends Node
# Global toggler that calls show_settings()/hide_settings() on your Settings scene.

const SETTINGS_SCENE_PATH := "res://Scenes/Reusable/SettingsUI.tscn"  # <-- put your exact path

var _instance: Node = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_unhandled_input(true)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("settings_ui") and _can_show_here():
		_toggle()
		get_viewport().set_input_as_handled()

func _can_show_here() -> bool:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return true
	return String(gs.location) != "Unknown"

func _ensure() -> void:
	if _instance != null:
		return
	var packed := load(SETTINGS_SCENE_PATH) as PackedScene
	if packed == null:
		push_error("SettingsOverlay: bad SETTINGS_SCENE_PATH: %s" % SETTINGS_SCENE_PATH)
		return
	_instance = packed.instantiate()
	add_child(_instance)

	# If the root is a CanvasLayer, keep it on top
	if _instance is CanvasLayer and (_instance as CanvasLayer).layer < 100:
		(_instance as CanvasLayer).layer = 100

	# Start hidden
	if _instance.has_method("hide_settings"):
		_instance.hide_settings()
	elif _instance is CanvasLayer:
		(_instance as CanvasLayer).visible = false

func _is_open() -> bool:
	if _instance == null:
		return false
	if _instance.has_method("is_open"):
		return _instance.is_open()
	if _instance is CanvasLayer:
		return (_instance as CanvasLayer).visible
	return false

func _toggle() -> void:
	_ensure()
	if _instance == null:
		return
	if _is_open():
		if _instance.has_method("hide_settings"):
			_instance.hide_settings()
		elif _instance is CanvasLayer:
			(_instance as CanvasLayer).visible = false
	else:
		if _instance.has_method("show_settings"):
			_instance.show_settings()
		elif _instance is CanvasLayer:
			(_instance as CanvasLayer).visible = true

# Optional helpers if you ever need them:
func open() -> void:  _ensure(); if _instance and _instance.has_method("show_settings"): _instance.show_settings()
func close() -> void: _ensure(); if _instance and _instance.has_method("hide_settings"): _instance.hide_settings()
