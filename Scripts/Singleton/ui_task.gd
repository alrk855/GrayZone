extends Control

@onready var task_grid: GridContainer = $"CanvasLayer/Task Overview/ScrollContainer/GridContainer"
@onready var detail_panel: Control = $"CanvasLayer/Task Detailed"
@onready var title_label: Label = detail_panel.get_node("Title")
@onready var meta_label: Label = detail_panel.get_node("MetaLabel")
@onready var step_container: VBoxContainer = detail_panel.get_node("Scroll/LabelContainer")
@onready var back_button: Button = detail_panel.get_node("goback")

# For switching between panels (camera scroll method)
@onready var canvas_layer := $CanvasLayer
const SWITCH_DISTANCE := 1080

func _ready():
	_populate_tasks()
	back_button.pressed.connect(_on_back_pressed)

func _populate_tasks():
	var current_tasks: Array = GameState.tasks
	print("📋 Populating TaskManager with:", current_tasks)

	var i := 0
	for button in task_grid.get_children():
		if button is Button:
			if i < current_tasks.size():
				button.text = current_tasks[i]
				button.visible = true
				if button.is_connected("pressed", Callable(self, "_on_task_button_pressed")):
					button.disconnect("pressed", Callable(self, "_on_task_button_pressed"))
				button.pressed.connect(_on_task_button_pressed.bind(button))
				i += 1
			else:
				button.visible = false

func _on_task_button_pressed(button: Button):
	var task_name = button.text
	var task_path = "res://Tasks/" + task_name.to_snake_case() + ".json"

	if not FileAccess.file_exists(task_path):
		print("❌ Missing task file:", task_path)
		return

	var file = FileAccess.open(task_path, FileAccess.READ)
	var task_data = JSON.parse_string(file.get_as_text())

	if typeof(task_data) != TYPE_DICTIONARY:
		print("❌ Invalid task file format:", task_path)
		return

	# Populate title and metadata
	title_label.text = task_data.get("title", task_name)
	meta_label.text = "Given by: %s | Location: %s" % [
		task_data.get("giver", "Unknown"),
		task_data.get("location", "Unknown")
	]

	# Clear previous steps
	for child in step_container.get_children():
		child.queue_free()

	# Add new steps
	var steps = task_data.get("steps", [])
	for step in steps:
		var step_label = Label.new()
		step_label.text = "- " + step
		step_container.add_child(step_label)

	# Scroll view to show the detail panel (camera style)
	_switch_to_detail_view()

func _switch_to_detail_view():
	canvas_layer.position.y = -SWITCH_DISTANCE

func _on_back_pressed():
	canvas_layer.position.y = 0
