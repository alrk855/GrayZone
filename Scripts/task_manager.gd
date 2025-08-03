extends Control

@onready var task_grid: GridContainer = $"CanvasLayer/Task Overview/ScrollContainer/GridContainer"
var task_buttons: Array = []

func _ready():
	await get_tree().process_frame  # Make sure all children exist
	task_buttons = task_grid.get_children().filter(func(child): return child is Button)

	for btn in task_buttons:
		btn.visible = false

	# Delay populate again to ensure GameState.tasks is filled
	await get_tree().create_timer(0.1).timeout
	_populate_tasks()

func _populate_tasks():
	var tasks = GameState.tasks
	print("🧩 Populating Tasks:", tasks)

	if tasks.size() == 0:
		print("⚠ No tasks to display.")
		return

	for i in range(task_buttons.size()):
		if i < tasks.size():
			task_buttons[i].text = tasks[i]
			task_buttons[i].visible = true
		else:
			task_buttons[i].visible = false
