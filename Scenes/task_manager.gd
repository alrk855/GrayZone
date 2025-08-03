extends Control

@onready var task_grid: GridContainer = $"CanvasLayer/Task Overview/ScrollContainer/GridContainer"

func _ready():
	_populate_tasks()

func _populate_tasks():
	var current_tasks: Array = GameState.tasks
	print("📋 Populating TaskManager with:", current_tasks)

	var i := 0
	for button in task_grid.get_children():
		if button is Button:
			if i < current_tasks.size():
				button.text = current_tasks[i]
				button.visible = true
				i += 1
			else:
				button.visible = false
