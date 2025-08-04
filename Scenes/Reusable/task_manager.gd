extends Control

@onready var task_grid := $"Task Overview/ScrollContainer/GridContainer"
@onready var task_detail := $"Task Detailed"
@onready var title_label := task_detail.get_node("Title")
@onready var meta_label := task_detail.get_node("MetaLabel")
@onready var step_container := task_detail.get_node("Scroll/LabelContainer")
@onready var go_back_button := task_detail.get_node("goback")
@onready var camera := $Camera2D

var overview_y := 0.0

func _ready():
	_populate_tasks()
	await get_tree().process_frame
	# Save current position (overview)
	overview_y = camera.position.y
	camera.position = $"Task Overview".global_position + get_viewport().get_visible_rect().size * 0.5
	go_back_button.pressed.connect(_on_back_pressed)

func _populate_tasks():
	var current_tasks: Array = GameState.tasks
	print("📋 Populating TaskManager with:", current_tasks)

	var i := 0
	for button in task_grid.get_children():
		if button is Button:
			if i < current_tasks.size():
				var task_id = current_tasks[i]
				button.text = _prettify_task_name(task_id)
				button.visible = true
				button.pressed.connect(_on_task_button_pressed.bind(task_id))
				i += 1
			else:
				button.visible = false

func _prettify_task_name(task_id: String) -> String:
	return task_id.capitalize().replace("_", " ")

func _on_task_button_pressed(task_id: String):
	print("📖 Viewing Task:", task_id)
	_show_task_details(task_id)
	_move_camera_down()

func _show_task_details(task_id: String):
	var task_data = _load_task_data(task_id)
	if not task_data:
		print("❌ Task JSON not found or invalid for:", task_id)
		return

	title_label.text = task_data.get("title", "Untitled Task")
	meta_label.text = "📍 " + task_data.get("location", "Unknown") + " | 🎓 Given by: " + task_data.get("giver", "???")

	for child in step_container.get_children():
		child.queue_free()

	var steps = task_data.get("steps", [])
	for step in steps:
		var step_id = step.get("id", "")
		var label = Label.new()
		label.text = "• " + step.get("text", "Unnamed Step")

		if GameState.is_step_complete(task_id, step_id):
			label.add_theme_color_override("font_color", Color.DIM_GRAY)
			label.text = "[x] " + label.text
		step_container.add_child(label)

func _on_back_pressed():
	_clear_task_details()
	_move_camera_up()

func _clear_task_details():
	for child in step_container.get_children():
		child.queue_free()

func _move_camera_down():
	var new_pos = camera.position + Vector2(0, 1080)
	camera.position = new_pos

func _move_camera_up():
	var new_pos = camera.position - Vector2(0, 1080)
	camera.position = new_pos

func _load_task_data(task_id: String) -> Dictionary:
	var file_path = "res://Data/Tasks/%s.json" % task_id
	if not FileAccess.file_exists(file_path):
		push_error("❌ Task file not found: " + file_path)
		return {}

	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("❌ Could not open file: " + file_path)
		return {}

	var content = file.get_as_text()
	var parsed = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("❌ Malformed JSON in file: " + file_path)
		return {}

	return parsed
