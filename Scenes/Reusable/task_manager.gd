extends Control

@onready var task_grid := $"Task Overview/ScrollContainer/GridContainer"
@onready var task_detail := $"Task Detailed"
@onready var title_label := task_detail.get_node("Title")
@onready var meta_label := task_detail.get_node("MetaLabel")
@onready var step_container := task_detail.get_node("Scroll/LabelContainer")
@onready var go_back_button := task_detail.get_node("goback")
@onready var camera := $Camera2D

const MAIN_REQUIREMENTS_TASK_ID := "Gather Scholarship Requirements"
const BASE_STEP_FONT_SIZE := 22
const STEP_FONT_SIZE := BASE_STEP_FONT_SIZE + 4   # +4 as requested

var overview_y := 0.0
var CUSTOM_FONT: Font = preload("res://Fonts/Chalkboard-Regular.ttf")

func _ready():
	# connect wrappers
	if not GameState.task_added.is_connected(Callable(self, "_on_task_added")):
		GameState.task_added.connect(Callable(self, "_on_task_added"))
	if not GameState.task_updated.is_connected(Callable(self, "_on_task_updated")):
		GameState.task_updated.connect(Callable(self, "_on_task_updated"))
	if not GameState.flag_changed.is_connected(Callable(self, "_on_flag_changed")):
		GameState.flag_changed.connect(Callable(self, "_on_flag_changed"))

	# apply custom font to static labels (buttons untouched)
	_apply_title_meta_fonts()

	refresh_tasks()
	await get_tree().process_frame
	overview_y = camera.position.y
	camera.position = $"Task Overview".global_position + get_viewport().get_visible_rect().size * 0.5
	go_back_button.pressed.connect(_on_back_pressed)

func _apply_title_meta_fonts() -> void:
	# Title
	title_label.add_theme_font_override("font", CUSTOM_FONT)
	var tsize: int = title_label.get_theme_font_size("font_size")
	if tsize <= 0: tsize = 24
	title_label.add_theme_font_size_override("font_size", tsize + 4)

	# Meta
	meta_label.add_theme_font_override("font", CUSTOM_FONT)
	var msize: int = meta_label.get_theme_font_size("font_size")
	if msize <= 0: msize = 14
	meta_label.add_theme_font_size_override("font_size", msize + 4)

func _on_task_added(_id: String) -> void: refresh_tasks()
func _on_task_updated(_id: String, _idx: int) -> void: refresh_tasks()
func _on_flag_changed(_flag: String, _val: bool) -> void: refresh_tasks()

# Public API
func refresh_tasks():
	for button in task_grid.get_children():
		if button is Button:
			if button.pressed.is_connected(Callable(self, "_on_task_button_pressed_internal")):
				button.pressed.disconnect(Callable(self, "_on_task_button_pressed_internal"))
	_populate_tasks()

func _populate_tasks():
	var current_tasks: Array = GameState.tasks
	var i := 0
	for button in task_grid.get_children():
		if button is Button:
			if i < current_tasks.size():
				var task_id: String = str(current_tasks[i])
				var title := _get_task_title(task_id)
				button.text = title
				button.visible = true
				button.set_meta("task_id", task_id)
				if not button.pressed.is_connected(Callable(self, "_on_task_button_pressed_internal")):
					button.pressed.connect(Callable(self, "_on_task_button_pressed_internal").bind(button))
				i += 1
			else:
				button.visible = false

func _on_task_button_pressed_internal(button: Button):
	var task_id := String(button.get_meta("task_id"))
	_on_task_button_pressed(task_id)

func _get_task_title(task_id: String) -> String:
	var data := _load_task_data(task_id)
	if data.is_empty():
		return _prettify_task_name(task_id)
	var raw_title := String(data.get("title", "Untitled Task"))
	return GameState.format_placeholders(raw_title)

func _prettify_task_name(task_id: String) -> String:
	return task_id.capitalize().replace("_", " ")

func _on_task_button_pressed(task_id: String):
	_show_task_details(task_id)
	_move_camera_down()

func _show_task_details(task_id: String):
	var task_data: Dictionary = _load_task_data(task_id)
	if task_data.is_empty():
		return

	var raw_title := String(task_data.get("title", "Untitled Task"))
	title_label.text = GameState.format_placeholders(raw_title)
	var raw_meta := "📍 " + String(task_data.get("location", "Unknown")) + " | 🎓 Given by: " + String(task_data.get("giver", "???"))
	meta_label.text = GameState.format_placeholders(raw_meta)

	_clear_task_details()

	var steps: Array = task_data.get("steps", [])
	var progress: int = GameState.get_task_progress(task_id)
	var show_all_steps := (task_id == MAIN_REQUIREMENTS_TASK_ID)

	for i in range(steps.size()):
		if not show_all_steps and i > progress:
			break
		var step := steps[i] as Dictionary
		var raw_txt := String(step.get("text", "Unnamed Step"))
		var txt := GameState.format_placeholders(raw_txt)

		if step.has("counter_key") and step.has("counter_goal"):
			var key := String(step.get("counter_key"))
			var goal := int(step.get("counter_goal"))
			var count := GameState.get_task_counter(task_id, key, 0)
			txt += " (%d/%d)" % [count, goal]

		var label := Label.new()
		# custom font + bigger size (+4)
		label.add_theme_font_override("font", CUSTOM_FONT)
		label.add_theme_font_size_override("font_size", STEP_FONT_SIZE)

		if i < progress:
			label.add_theme_color_override("font_color", Color.DIM_GRAY)
			label.text = "✔ " + txt
		else:
			label.text = "• " + txt

		step_container.add_child(label)

	if task_id == MAIN_REQUIREMENTS_TASK_ID and not GameState.has_flag("req_subtasks_added"):
		_add_requirement_subtasks(steps)
		GameState.set_flag("req_subtasks_added", true)
		refresh_tasks()

func _add_requirement_subtasks(steps: Array):
	for step in steps:
		if typeof(step) == TYPE_DICTIONARY:
			var d := step as Dictionary
			var sub_id: String = String(d.get("id", "")).strip_edges()
			if sub_id != "":
				GameState.ensure_task(sub_id)

func _on_back_pressed():
	_clear_task_details()
	_move_camera_up()

func _clear_task_details():
	for child in step_container.get_children():
		child.queue_free()

func _move_camera_down(): camera.position += Vector2(0, 1080)
func _move_camera_up(): camera.position -= Vector2(0, 1080)

func _load_task_data(task_id: String) -> Dictionary:
	var file_path := "res://Data/Tasks/%s.json" % task_id
	if not FileAccess.file_exists(file_path):
		push_error("❌ Task file not found: " + file_path)
		return {}
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("❌ Could not open file: " + file_path)
		return {}
	var content := file.get_as_text()
	var parsed: Variant = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("❌ Malformed JSON in file: " + file_path)
		return {}
	return parsed as Dictionary
