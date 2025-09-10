extends Control

@onready var task_grid: GridContainer = $"Task Overview/ScrollContainer/GridContainer"
@onready var task_detail: Control = $"Task Detailed"
@onready var title_label: Label = task_detail.get_node("Title") as Label
@onready var meta_label: Label = task_detail.get_node("MetaLabel") as Label
@onready var step_container: Control = task_detail.get_node("Scroll/LabelContainer") as Control
@onready var go_back_button: Button = task_detail.get_node("goback") as Button
@onready var camera: Camera2D = $Camera2D as Camera2D

const MAIN_REQUIREMENTS_TASK_ID := "Gather Scholarship Requirements"

# ---------------- Fonts ----------------
const OVERVIEW_FONT_PATH := "res://Fonts/Russo_One.ttf"          # buttons font
const BODY_FONT_PATH     := "res://Fonts/Chalkboard-Regular.ttf" # title/meta/steps

var FONT_OVERVIEW: Font = preload(OVERVIEW_FONT_PATH)
var FONT_BODY: Font     = preload(BODY_FONT_PATH)

# fixed size (no incremental growth)
const OVERVIEW_FONT_SIZE: int = 22
const BASE_STEP_FONT_SIZE: int = 22
const STEP_FONT_SIZE: int = BASE_STEP_FONT_SIZE + 4

# ---------------- Sorting helpers ----------------
var _last_opened: Dictionary = {}   # task_id -> unix time (session only)
var _task_cache: Dictionary = {}    # task_id -> parsed JSON

# Track last seen day to detect rollover
var _last_seen_day: int = 0

func _ready() -> void:
	if not GameState.task_added.is_connected(Callable(self, "_on_task_added")):
		GameState.task_added.connect(Callable(self, "_on_task_added"))
	if not GameState.task_updated.is_connected(Callable(self, "_on_task_updated")):
		GameState.task_updated.connect(Callable(self, "_on_task_updated"))
	if not GameState.flag_changed.is_connected(Callable(self, "_on_flag_changed")):
		GameState.flag_changed.connect(Callable(self, "_on_flag_changed"))
	if not GameState.time_changed.is_connected(Callable(self, "_on_time_changed")):
		GameState.time_changed.connect(Callable(self, "_on_time_changed"))

	_last_seen_day = GameState.day

	_apply_title_meta_fonts()
	_populate_tasks()
	await get_tree().process_frame
	camera.position = $"Task Overview".global_position + get_viewport().get_visible_rect().size * 0.5
	go_back_button.pressed.connect(_on_back_pressed)

# ---------------- Font application ----------------
func _apply_title_meta_fonts() -> void:
	title_label.add_theme_font_override("font", FONT_BODY)
	var tsize: int = title_label.get_theme_font_size("font_size")
	if tsize <= 0:
		tsize = 24
	title_label.add_theme_font_size_override("font_size", tsize + 4)

	meta_label.add_theme_font_override("font", FONT_BODY)
	var msize: int = meta_label.get_theme_font_size("font_size")
	if msize <= 0:
		msize = 14
	meta_label.add_theme_font_size_override("font_size", msize + 4)

# ---------------- Signals ----------------
func _on_task_added(_id: String) -> void:
	_populate_tasks()

func _on_task_updated(_id: String, _idx: int) -> void:
	_populate_tasks()

func _on_flag_changed(_flag: String, _val: bool) -> void:
	_populate_tasks()

func _on_time_changed(_new_time: int, new_day: int) -> void:
	# Detect day rollover and mark missed study days for the day that just ended
	if new_day != _last_seen_day:
		var prev_day: int = _last_seen_day
		_handle_study_day_rollover(prev_day)
		_last_seen_day = new_day
		_populate_tasks()

# ---------------- Overview population ----------------
func _populate_tasks() -> void:
	# 1) Collect task ids
	var ids: Array = []
	for t in GameState.tasks:
		ids.append(String(t))

	# 2) Sort by % complete desc, last opened desc, title asc
	var sorted: Array = _get_sorted_tasks(ids)

	# 3) Render into grid buttons
	var i := 0
	for child in task_grid.get_children():
		if child is Button:
			var button := child as Button
			if i < sorted.size():
				var task_id: String = String(sorted[i])
				var title: String = TaskCatalog.get_title(task_id)

				# Text + tooltip
				button.text = title
				button.tooltip_text = title
				button.visible = true
				button.set_meta("task_id", task_id)

				# Font (fixed size; no incremental growth)
				button.add_theme_font_override("font", FONT_OVERVIEW)
				button.add_theme_font_size_override("font_size", OVERVIEW_FONT_SIZE)

				_apply_overview_color(button, task_id)

				var cb := Callable(self, "_on_task_button_pressed_internal").bind(button)
				if not button.pressed.is_connected(cb):
					button.pressed.connect(cb)

				i += 1
			else:
				button.visible = false

func _apply_overview_color(button: Button, task_id: String) -> void:
	var steps_total := _get_steps_count(task_id)
	var prog := GameState.get_task_progress(task_id)

	if steps_total > 0 and prog >= steps_total:
		button.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))   # green
	elif _is_task_blocked(task_id):
		button.add_theme_color_override("font_color", Color(0.9, 0.25, 0.25)) # red
	else:
		if button.has_theme_color_override("font_color"):
			button.remove_theme_color_override("font_color")

# ---------------- Sorting ----------------
func _get_sorted_tasks(ids: Array) -> Array:
	var items: Array = []
	for idv in ids:
		var id: String = String(idv)
		var steps_total := _get_steps_count(id)
		var prog := GameState.get_task_progress(id)
		var pct: float = 0.0
		if steps_total > 0:
			pct = float(prog) / float(steps_total)
		var opened: int = int(_last_opened.get(id, 0))
		items.append({"id": id, "pct": pct, "opened": opened})
	items.sort_custom(Callable(self, "_cmp_task_items"))
	var out: Array = []
	for it in items:
		out.append(it["id"])
	return out

func _cmp_task_items(a: Dictionary, b: Dictionary) -> bool:
	if a["pct"] > b["pct"]:
		return true
	if a["pct"] < b["pct"]:
		return false
	if a["opened"] > b["opened"]:
		return true
	if a["opened"] < b["opened"]:
		return false
	var at: String = TaskCatalog.get_title(String(a["id"]))
	var bt: String = TaskCatalog.get_title(String(b["id"]))
	return at.naturalnocasecmp_to(bt) < 0

# ---------------- Details panel ----------------
func _on_task_button_pressed_internal(button: Button) -> void:
	var task_id: String = String(button.get_meta("task_id"))
	_last_opened[task_id] = Time.get_unix_time_from_system()
	_on_task_button_pressed(task_id)

func _on_task_button_pressed(task_id: String) -> void:
	_show_task_details(task_id)
	_move_camera_down()

func _show_task_details(task_id: String) -> void:
	var task_data: Dictionary = _load_task_data(task_id)
	if task_data.is_empty():
		return

	title_label.text = TaskCatalog.get_title(task_id)
	var raw_meta: String = "📍 " + String(task_data.get("location", "Unknown")) + " | 🎓 Given by: " + String(task_data.get("giver", "???"))
	meta_label.text = _format_placeholders(raw_meta)

	_clear_task_details()

	var steps: Array = []
	var steps_variant: Variant = task_data.get("steps", [])
	if steps_variant is Array:
		for s in steps_variant:
			if typeof(s) == TYPE_DICTIONARY:
				steps.append(s)

	var progress: int = GameState.get_task_progress(task_id)
	var show_all_steps: bool = (task_id == MAIN_REQUIREMENTS_TASK_ID)

	# Special rendering for study tasks: always show 4 steps with ✔ / ✘ / • per day
	if task_id == "study_subject1" or task_id == "study_subject2":
		_render_study_steps(task_id, steps)
	else:
		for i in range(steps.size()):
			if not show_all_steps and i > progress:
				break
			var step: Dictionary = steps[i]
			var raw_txt: String = String(step.get("text", "Unnamed Step"))
			var txt: String = _format_placeholders(raw_txt)

			if step.has("counter_key") and step.has("counter_goal"):
				var key: String = String(step.get("counter_key"))
				var goal: int = int(step.get("counter_goal"))
				var count: int = int(GameState.get_task_counter(task_id, key, 0))
				txt += " (%d/%d)" % [count, goal]

			var label := Label.new()
			label.add_theme_font_override("font", FONT_BODY)
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
		_populate_tasks()

func _render_study_steps(task_id: String, steps: Array) -> void:
	# Determine which subject this task is for and render 4 daily steps.
	var subject_raw: String = ""
	if task_id == "study_subject2":
		subject_raw = GameState.subject2
	else:
		subject_raw = GameState.subject1

	var subj_key: String = GameState._get_subject_key_from_choice(subject_raw)
	var today_index: int = GameState.day
	if today_index < 1:
		today_index = 1
	if today_index > 4:
		today_index = 4

	# Always show up to min(4, steps.size()) lines
	var max_steps: int = steps.size()
	if max_steps > 4:
		max_steps = 4

	for i in range(max_steps):
		var day_idx: int = i + 1
		var raw_txt: String = String(steps[i].get("text", "Unnamed Step"))
		var txt: String = _format_placeholders(raw_txt)

		var studied: bool = false
		var missed: bool = false
		if subj_key.strip_edges() != "":
			var guard_key: String = subj_key + "|" + str(day_idx)
			if GameState.study_guard.has(guard_key):
				studied = true
			else:
				if day_idx < GameState.day:
					# prior day not present in guard => missed
					missed = true

		var label := Label.new()
		label.add_theme_font_override("font", FONT_BODY)
		label.add_theme_font_size_override("font_size", STEP_FONT_SIZE)

		if studied:
			label.add_theme_color_override("font_color", Color.DIM_GRAY)
			label.text = "✔ " + txt
		elif missed:
			label.add_theme_color_override("font_color", Color(0.9, 0.25, 0.25))
			label.text = "✘ " + txt
		else:
			label.text = "• " + txt

		step_container.add_child(label)

func _add_requirement_subtasks(steps: Array) -> void:
	for s in steps:
		var sub_id: String = String((s as Dictionary).get("id", "")).strip_edges()
		if sub_id != "":
			GameState.ensure_task(sub_id)

func _on_back_pressed() -> void:
	_clear_task_details()
	_move_camera_up()

func _clear_task_details() -> void:
	for child in step_container.get_children():
		child.queue_free()

func _move_camera_down() -> void:
	camera.position += Vector2(0, 1080)

func _move_camera_up() -> void:
	camera.position -= Vector2(0, 1080)

# ---------------- Day rollover logic ----------------
func _handle_study_day_rollover(prev_day: int) -> void:
	# If the day that just ended was 1..4, advance the study task step even if missed.
	if prev_day < 1:
		return
	if prev_day > 4:
		return

	# Subject 1
	_mark_missed_if_needed_for_subject(prev_day, "study_subject1", GameState.subject1)

	# Subject 2
	_mark_missed_if_needed_for_subject(prev_day, "study_subject2", GameState.subject2)

func _mark_missed_if_needed_for_subject(day_index: int, task_id: String, subject_raw: String) -> void:
	if subject_raw.strip_edges() == "":
		return

	var subj_key: String = GameState._get_subject_key_from_choice(subject_raw)
	var guard_key: String = subj_key + "|" + str(day_index)
	var studied_today: bool = GameState.study_guard.has(guard_key)

	GameState.ensure_task(task_id)
	var current_prog: int = GameState.get_task_progress(task_id)

	# Step numbers align with day index (1..4)
	# If the player did study, progress was already advanced by Study scene.
	# If they did not study and progress is still behind this day, advance to mark as missed.
	if not studied_today and current_prog < day_index:
		GameState.update_task_step(task_id)

# ---------------- Data access + helpers ----------------
func _load_task_data(task_id: String) -> Dictionary:
	if _task_cache.has(task_id):
		return _task_cache[task_id]

	var file_path: String = "res://Data/Tasks/%s.json" % task_id
	if not FileAccess.file_exists(file_path):
		push_error("❌ Task file not found: " + file_path)
		_task_cache[task_id] = {}
		return {}

	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("❌ Could not open file: " + file_path)
		_task_cache[task_id] = {}
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	var d: Dictionary = {}
	if typeof(parsed) == TYPE_DICTIONARY:
		d = parsed
	else:
		push_error("❌ Malformed JSON in file: " + file_path)

	_task_cache[task_id] = d
	return d

func _get_steps_count(task_id: String) -> int:
	var d: Dictionary = _load_task_data(task_id)
	var arr: Variant = d.get("steps", [])
	if arr is Array:
		return (arr as Array).size()
	return 0

func _is_task_blocked(task_id: String) -> bool:
	var d: Dictionary = _load_task_data(task_id)
	if bool(d.get("blocked", false)):
		return true
	var bf: String = String(d.get("blocked_flag", ""))
	if bf != "" and GameState.has_flag(bf):
		return true
	var bnf: String = String(d.get("blocked_if_not_flag", ""))
	if bnf != "" and not GameState.has_flag(bnf):
		return true
	return false

func _format_placeholders(text: String) -> String:
	var s := text
	if GameState.subject1 != "":
		s = s.replace("{subject1}", GameState.subject1.capitalize())
		s = s.replace("[Subject 1]", GameState.subject1.capitalize())
	if GameState.subject2 != "":
		s = s.replace("{subject2}", GameState.subject2.capitalize())
		s = s.replace("[Subject 2]", GameState.subject2.capitalize())
	return s
