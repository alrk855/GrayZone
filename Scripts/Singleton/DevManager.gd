extends Node
# DevManager: hotkey → spawn DevTools panel

const DEVTOOLS_SCENE_PATH := "res://Scenes/devtools.tscn"

@export var allow_open_during_dialogue := false

var _panel: Control = null
var _devtools_packed: PackedScene = null

func _ready() -> void:
	if ResourceLoader.exists(DEVTOOLS_SCENE_PATH):
		_devtools_packed = load(DEVTOOLS_SCENE_PATH)
	else:
		push_warning("DevManager: DevTools scene not found at %s" % DEVTOOLS_SCENE_PATH)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("dev"):
		call_deferred("_on_dev_hotkey")

func _on_dev_hotkey() -> void:
	# Toggle if already open
	if _panel and is_instance_valid(_panel):
		close_panel()
		return

	if not allow_open_during_dialogue and _is_dialogue_active():
		print("[DevManager] Dialogue active; devtools suppressed.")
		return

	open_panel()

func open_panel() -> void:
	if _devtools_packed == null:
		push_error("DevManager: DevTools scene not loaded.")
		return

	_panel = _devtools_packed.instantiate() as Control
	if not _panel:
		push_error("DevManager: Failed to instantiate devtools scene.")
		return

	get_tree().root.add_child(_panel)
	_panel.z_index = 4096
	_panel.top_level = true

	# Auto-clear reference when panel is closed
	_panel.tree_exited.connect(func():
		_panel = null
	)

func close_panel() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null

func _is_dialogue_active() -> bool:
	var dm := get_node_or_null("/root/DialogueManager")
	if dm:
		if dm.has_method("is_busy") and dm.call("is_busy"): return true
		if dm.has_method("is_playing") and dm.call("is_playing"): return true
		if dm.has_method("is_running") and dm.call("is_running"): return true
		if dm.has_method("has_active_dialogue") and dm.call("has_active_dialogue"): return true
	return false
