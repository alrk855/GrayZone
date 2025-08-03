extends Node

const TASK_MANAGER_SCENE := preload("res://Scenes/TaskManager.tscn")

var task_instance: Control

func _ready():
	set_process(true)

func _process(_delta):
	if Input.is_action_just_pressed("ui_task"):
		if _can_open_task_manager():
			_toggle_task_scene()

func _can_open_task_manager() -> bool:
	if GameState.location == "Unknown":
		return false

	var root = get_tree().current_scene
	if root and root.find_child("Dialogue", true, false):
		return false

	return true

func _toggle_task_scene():
	if task_instance and is_instance_valid(task_instance):
		task_instance.queue_free()
		task_instance = null
	else:
		task_instance = TASK_MANAGER_SCENE.instantiate()
		get_tree().current_scene.add_child(task_instance)
		if task_instance.has_method("refresh_tasks"):
			task_instance.call("refresh_tasks")
