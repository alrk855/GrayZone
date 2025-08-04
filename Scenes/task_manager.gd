extends Control

@onready var task_grid: GridContainer = $"CanvasLayer/Task Overview/ScrollContainer/GridContainer"
@onready var layer: CanvasLayer = $"CanvasLayer"
@onready var info: Label = get_node("/root/main/TASK_INFO")

func _ready():
	layer.visible = false

func _populate_tasks():
	var current_tasks: Array = GameState.tasks
	print("📋 Populating TaskManager with:", current_tasks)
	showInfo()
	var i := 0
	for button in task_grid.get_children():
		if button is Button:
			if i < current_tasks.size():
				button.text = current_tasks[i]
				button.visible = true
				i += 1
			else:
				button.visible = false

func _process(_delta: float) -> void:
	if(Input.is_action_just_pressed("ui_task")):
		if(layer.visible == true):
			layer.visible = false
		else:
			layer.visible = true
			_populate_tasks()

func showInfo():
	create_tween().tween_property(info, "position", Vector2(50, 30), 1)
	info.text = "TEST"
