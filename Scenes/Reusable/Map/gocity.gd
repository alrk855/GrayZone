# res://Scripts/Reusable/go_to_scene_button.gd
extends Button

@export_file("*.tscn") var target_scene: String
@export var use_fade: bool = true
@export var fallback_fade_duration: float = 0.35  # only used if fade autoload isn't found

func _ready() -> void:
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	if GameState.is_time_frozen():
		print("⏸️ Finish the conversation first.")
		return
	if target_scene == "" or target_scene == null:
		push_error("GoToSceneButton: target_scene not set.")
		return

	disabled = true
	await _go_with_fade_or_fallback(target_scene)
	disabled = false

func _go_with_fade_or_fallback(scene_path: String) -> void:
	if use_fade:
		var fader := _get_fader()
		if fader:
			# Your autoload is named 'fade' and exposes fade_to_scene()
			if fader.has_method("fade_to_scene"):
				await fader.fade_to_scene(scene_path)
				return
			# If you ever change API names, add branches here.

	# Fallback local fade
	await _local_fade_and_change_scene(scene_path)

func _get_fader() -> Node:
	# Autoload is lowercase 'fade'
	var path := "/root/fade"
	return get_tree().get_node_or_null(path)

func _local_fade_and_change_scene(scene_path: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 999
	add_child(layer)

	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 1)
	black.modulate.a = 0.0
	black.mouse_filter = Control.MOUSE_FILTER_STOP
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(black)

	var tw := create_tween()
	tw.tween_property(black, "modulate:a", 1.0, fallback_fade_duration)
	await tw.finished

	get_tree().change_scene_to_file(scene_path)
