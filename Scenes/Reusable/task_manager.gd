extends Control

# ---------------- Scene nodes ----------------
@onready var task_grid: GridContainer = $"Task Overview/ScrollContainer/GridContainer"
@onready var task_detail: Control = $"Task Detailed"
@onready var title_label: Label = task_detail.get_node("Title") as Label
@onready var meta_label: Label = task_detail.get_node("MetaLabel") as Label
@onready var step_container: Control = task_detail.get_node("Scroll/LabelContainer") as Control
@onready var go_back_button: Button = task_detail.get_node("goback") as Button
@onready var camera: Camera2D = $Camera2D as Camera2D

# ---------------- Constants / IDs ----------------
const TASK_REQ := "Gather Scholarship Requirements"

# Day-by-day tasks with bespoke rendering
const TASK_ATTENDANCE := "Attend Morning Classes"
const TASK_STUDY_S1 := "study_subject1"
const TASK_STUDY_S2 := "study_subject2"
const TASK_TUTORING := "Tutoring Task"

# if you keep a “visit secretary” wrapper task, list candidate ids here
const TASK_VISIT_SECRETARY_CANDIDATES := [
	"Visit the Secretary", "Meet the Secretary", "Secretary Visit"
]

# Requirement step ids that we DO NOT auto-add (they are created elsewhere)
const REQ_EXCLUDE_AUTO_ADD := {
	"volunteer": true,
	"Volunteer for Community Work": true,
	"Attend Morning Classes": true
}

# ---------------- Fonts (only for details panel; grid mini label theme untouched) ----------------
const OVERVIEW_FONT_PATH := "res://Fonts/Russo_One.ttf"          # grid buttons
const BODY_FONT_PATH     := "res://Fonts/dehinted-DarumadropOne.ttf" # title/meta/steps

var FONT_OVERVIEW: Font = preload(OVERVIEW_FONT_PATH)
var FONT_BODY: Font     = preload(BODY_FONT_PATH)

const OVERVIEW_FONT_SIZE: int = 22
const STEP_FONT_SIZE: int = 26
const PREVIEW_COUNTER_FONT_SIZE: int = 16   # (we won't override theme, just FYI)

# ---------------- Sorting state ----------------
var _last_opened: Dictionary = {}            # task_id -> unix time (session only)
var _task_cache: Dictionary = {}             # (task_id|locale) -> parsed JSON

# Track last seen day to detect daily rollover
var _last_seen_day: int = 0

# ---------------- Step state enum ----------------
enum StepState { ONGOING, DONE, FAILED }

func _ready() -> void:
	# Signals to stay in sync
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

# ---------------- Font helpers (details panel only) ----------------
func _apply_title_meta_fonts() -> void:
	title_label.add_theme_font_override("font", FONT_BODY)
	var tsize := title_label.get_theme_font_size("font_size")
	if tsize <= 0:
		tsize = 24
	title_label.add_theme_font_size_override("font_size", tsize + 4)

	meta_label.add_theme_font_override("font", FONT_BODY)
	var msize := meta_label.get_theme_font_size("font_size")
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

				button.text = title
				button.tooltip_text = title
				button.visible = true
				button.set_meta("task_id", task_id)

				# Button font for the main caption (your theme still applies)
				button.add_theme_font_override("font", FONT_OVERVIEW)
				button.add_theme_font_size_override("font_size", OVERVIEW_FONT_SIZE)

				# Color rule (fail/red, complete/green, blocked/red) – day-by-day tasks gated below
				_apply_overview_color(button, task_id)

				# ---- Small “x/y” counter label on the button (child named "Label") ----
				var lbl: Label = button.get_node_or_null("Label") as Label
				if lbl:
					var pv := 0
					var tv := _get_steps_count(task_id)

					# dynamic preview for day-by-day tasks
					if task_id == TASK_STUDY_S1 or task_id == TASK_STUDY_S2:
						var studied := _count_study_done(task_id)
						var missed := _count_study_missed(task_id)
						pv = studied + missed
						tv = 4
					elif task_id == TASK_ATTENDANCE:
						var att := _count_attended()
						var miss := _attendance_missed()
						pv = att + miss
						tv = 4
					elif task_id == TASK_TUTORING:
						var tut := _count_tutored()
						var miss2 := _count_tutor_missed()
						pv = tut + miss2
						tv = 4
					elif task_id == TASK_REQ:
						var td := _load_task_data(TASK_REQ)
						var stps = td.get("steps", [])
						var req_total := 0
						var req_resolved := 0
						if stps is Array:
							for s in stps:
								if typeof(s) != TYPE_DICTIONARY:
									continue
								if bool(s.get("optional", false)):
									# optional doesn't count towards total
									continue
								req_total += 1
								var st := _req_step_state_from_id(s)
								if st == StepState.DONE or st == StepState.FAILED:
									req_resolved += 1
						pv = req_resolved
						tv = max(1, req_total)  # avoid 0/0 visual
					else:
						# generic tasks: use linear progress
						pv = GameState.get_task_progress(task_id)

					lbl.text = "%d/%d" % [pv, tv]  # do NOT touch label theme/colors
				# ---------------------------------------------------------------

				# Hook up click
				var cb := Callable(self, "_on_task_button_pressed_internal").bind(button)
				if not button.pressed.is_connected(cb):
					button.pressed.connect(cb)

				i += 1
			else:
				button.visible = false

# Color decisions for each button
func _apply_overview_color(button: Button, task_id: String) -> void:
	# Explicit fail?
	if _has_failed_task(task_id):
		button.add_theme_color_override("font_color", Color(0.9, 0.25, 0.25)) # red
		return

	# Completed → green (generic rule; day-by-day will only go green when fully complete)
	var steps_total := _get_steps_count(task_id)
	var prog := GameState.get_task_progress(task_id)
	if steps_total > 0 and prog >= steps_total:
		button.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))   # green
		return

	# Blocked → red
	if _is_task_blocked(task_id):
		button.add_theme_color_override("font_color", Color(0.9, 0.25, 0.25)) # red
		return

	# Default
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

	var loc_txt := String(task_data.get("location", tr("Unknown")))
	var giver_txt := String(task_data.get("giver", tr("???")))
	var raw_meta: String = "📍 " + loc_txt + " | 🎓 " + tr("Given by:") + " " + giver_txt
	meta_label.text = _format_placeholders(raw_meta)

	_clear_task_details()

	var steps: Array = []
	var steps_variant: Variant = task_data.get("steps", [])
	if steps_variant is Array:
		for s in steps_variant:
			if typeof(s) == TYPE_DICTIONARY:
				steps.append(s)

	# Bespoke renderers
	if task_id == TASK_STUDY_S1 or task_id == TASK_STUDY_S2:
		_render_study_steps(task_id, steps)
		return
	if task_id == TASK_ATTENDANCE:
		_render_attendance_steps(steps)
		return
	if task_id == TASK_TUTORING:
		_render_tutoring_steps(steps)
		return

	# Requirements task: special live status per step
	if task_id == TASK_REQ:
		_maybe_auto_add_requirement_subtasks(steps)
		_render_requirements_task(steps)
		_maybe_finish_requirements_and_bump_secretary(steps)
		return

	# Generic fallback: show steps up to progress
	var progress: int = GameState.get_task_progress(task_id)
	for i in range(steps.size()):
		if i > progress:
			break
		var step: Dictionary = steps[i]
		var raw_txt: String = String(step.get("text", tr("Unnamed Step")))
		var txt: String = _format_placeholders(raw_txt)
		var label := Label.new()
		label.add_theme_font_override("font", FONT_BODY)
		label.add_theme_font_size_override("font_size", STEP_FONT_SIZE)
		if i < progress:
			label.add_theme_color_override("font_color", Color.DIM_GRAY)
			label.text = "✔ " + txt
		else:
			label.text = "• " + txt
		step_container.add_child(label)

# ---------------- Requirements logic ----------------
func _maybe_auto_add_requirement_subtasks(steps: Array) -> void:
	for s in steps:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var sub_id := String(s.get("id", s.get("links_to_task",""))).strip_edges()
		if sub_id == "" or REQ_EXCLUDE_AUTO_ADD.has(sub_id):
			continue
		GameState.ensure_task(sub_id)

func _render_requirements_task(steps: Array) -> void:
	var required_total := 0
	var resolved_required := 0

	for s in steps:
		if typeof(s) != TYPE_DICTIONARY:
			continue

		var txt := _format_placeholders(String(s.get("text", tr("Unnamed Step"))))
		var optional := bool(s.get("optional", false))
		if not optional:
			required_total += 1

		var st := _req_step_state_from_id(s)

		var label := Label.new()
		label.add_theme_font_override("font", FONT_BODY)
		label.add_theme_font_size_override("font_size", STEP_FONT_SIZE)

		match st:
			StepState.DONE:
				label.add_theme_color_override("font_color", Color.DIM_GRAY)
				label.text = "✔ " + txt
				if not optional:
					resolved_required += 1
			StepState.FAILED:
				label.add_theme_color_override("font_color", Color(0.9, 0.25, 0.25))
				label.text = "✘ " + txt
				if not optional:
					resolved_required += 1
			_:
				label.text = "• " + txt

		step_container.add_child(label)

	# update preview counter (x/y for required items)
	_update_preview_counter_for_task(TASK_REQ, resolved_required, max(1, required_total))

func _req_step_state_from_id(step: Dictionary) -> int:
	var id := String(step.get("id","")).strip_edges()
	var link := String(step.get("links_to_task","")).strip_edges()
	if id == "" and link != "":
		id = link
	var norm := id.to_lower()

	# --- Birth certificate ---
	if norm == "birth" or norm == "birth certificate":
		if _any_flag(["have_birth_certificate", "HAVE_BIRTH_CERTIFICATE"]):
			return StepState.DONE
		return StepState.ONGOING

	# --- Transcript ---
	if norm == "transcript":
		# Fail ONLY if classroom explicitly marked failure
		if GameState.has_flag("transcripts_failed"):
			return StepState.FAILED

		# Consider DONE if task itself is finished or you keep any of these legacy flags
		if _any_flag(["transcript_accepted", "transcript_delivered", "have_transcript"]):
			return StepState.DONE
		if GameState.get_task_progress("transcript") >= 2:
			return StepState.DONE

		# Otherwise still ongoing (no red until the flag is set)
		return StepState.ONGOING

	# --- CV ---
	if norm == "cv" or norm == "submit a cv":
		if GameState.has_flag("printed_cv"):
			return StepState.DONE
		return StepState.ONGOING

	# --- Motivation letter ---
	if norm == "motivation" or norm == "motivation letter":
		if GameState.has_flag("printed_motivation"):
			return StepState.DONE
		if GameState.has_flag("doc_review_banned"):
			return StepState.FAILED
		return StepState.ONGOING

	# --- Project ---
	if norm == "project":
		return _project_req_state()

	# --- Language certificate ---
	if norm == "language" or norm == "language certificate":
		if _any_flag(["have_language_certificate", "HAVE_LANGUAGE_CERTIFICATE", "lang_cert_picked"]):
			return StepState.DONE
		return StepState.ONGOING

	# --- Volunteer (optional) ---
	if norm == "volunteer" or norm == "volunteer for community work":
		if GameState.get_task_progress("Volunteer for Community Work") >= _get_steps_count("Volunteer for Community Work"):
			return StepState.DONE
		if _any_flag(["volunteer_done", "community_work_done"]):
			return StepState.DONE
		return StepState.ONGOING

	# --- Attend Morning Classes (formerly “discipline”) ---
	if id == "Attend Morning Classes":
		var finished := (GameState.day >= 5) or (_attendance_days_counted() >= 4)
		if not finished:
			return StepState.ONGOING
		return StepState.DONE if _attendance_missed() <= 1 else StepState.FAILED

	# Generic fallback: link-to-task or flag
	var link_task := String(step.get("links_to_task","")).strip_edges()
	if link_task != "":
		var total := _get_steps_count(link_task)
		var prog := GameState.get_task_progress(link_task)
		# If the linked task has zero steps, treat “any progress” as ongoing to avoid false green.
		if total > 0 and prog >= total:
			return StepState.DONE
		return StepState.ONGOING

	var f := String(step.get("flag_key","")).strip_edges()
	if f != "":
		return StepState.DONE if GameState.has_flag(f) else StepState.ONGOING

	return StepState.ONGOING

# --- helper: fetch letter grade using ProfessorOffice if available (fallback to local map) ---
func _project_grade_letter() -> String:
	var score: int = GameState.get_int("project_score", 0)
	return _grade_from_score_local(score)


func _grade_from_score_local(score: int) -> String:
	if score >= 5: return "A"
	if score == 4: return "B"
	if score == 3: return "C"
	if score == 2: return "D"
	return "F"


# --- drop-in replacement: requirement state for the Final Project line ---
func _project_req_state() -> int:
	var submitted := GameState.has_flag("project_submitted")
	var second_chance := GameState.has_flag("project_second_chance")

	# If not submitted yet → still ongoing
	if not submitted:
		return StepState.ONGOING

	# Use professor's grading (or fallback) to decide
	var letter := _project_grade_letter().to_upper()

	# No grade yet (waiting / being reviewed) → ongoing
	if letter == "":
		return StepState.ONGOING

	# F logic:
	# - First F typically triggers a reset & second chance → don't show red while that chance is active
	# - If second chance is already consumed (flag not set) and it's F again → FAILED (red)
	if letter == "F":
		return StepState.ONGOING if second_chance else StepState.FAILED

	# Any non-F grade counts as done
	return StepState.DONE

func _any_flag(names: Array) -> bool:
	for n in names:
		if GameState.has_flag(String(n)):
			return true
	return false

func _attendance_days_counted() -> int:
	var total := 0
	for i in range(1,5):
		if GameState.has_flag("attended_morning_day_%d" % i) or GameState.has_flag("skip_penalized_day_%d" % i):
			total += 1
	return total

func _attendance_missed() -> int:
	var missed := 0
	for i in range(1,5):
		var att := GameState.has_flag("attended_morning_day_%d" % i)
		if not att and i <= 4 and i < GameState.day:
			missed += 1
	return missed

func _maybe_finish_requirements_and_bump_secretary(steps: Array) -> void:
	var required_total := 0
	var resolved_required := 0

	for s in steps:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var optional := bool(s.get("optional", false))
		if not optional:
			required_total += 1

		var st := _req_step_state_from_id(s)
		if st == StepState.DONE or st == StepState.FAILED:
			resolved_required += 1

	# If all required subtasks are resolved, bump "Visit the Secretary" by +1
	if required_total > 0 and resolved_required >= required_total:
		if not GameState.has_flag("requirements_all_done"):
			GameState.set_flag("requirements_all_done", true)
			var sec_task := "Visit the Secretary"
			if GameState.tasks.has(sec_task):
				GameState.update_task_step(sec_task)  # only +1

func _update_preview_counter_for_task(task_id: String, progress_val: int, total_val: int) -> void:
	for child in task_grid.get_children():
		if child is Button:
			var b := child as Button
			if String(b.get_meta("task_id", "")) == task_id:
				var lbl := b.get_node_or_null("Label") as Label
				if lbl:
					lbl.text = "%d/%d" % [progress_val, total_val]
				return

# ---------------- Study rendering ----------------
func _render_study_steps(task_id: String, steps: Array) -> void:
	var subject_raw: String = GameState.subject2 if task_id == TASK_STUDY_S2 else GameState.subject1
	var subj_key: String = GameState._get_subject_key_from_choice(subject_raw)
	var max_steps: int = min(4, steps.size())

	for i in range(max_steps):
		var day_idx: int = i + 1
		var raw_txt: String = String(steps[i].get("text", tr("Unnamed Step")))
		var txt: String = _format_placeholders(raw_txt)

		var studied := false
		var missed := false
		if subj_key.strip_edges() != "":
			var guard_key: String = subj_key + "|" + str(day_idx)
			if GameState.study_guard.has(guard_key):
				studied = true
			else:
				if day_idx < GameState.day:
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

# ---------------- Attendance rendering ----------------
func _render_attendance_steps(steps: Array) -> void:
	var max_steps = min(4, steps.size())
	for i in range(max_steps):
		var day_idx := i + 1
		var raw_txt: String = String(steps[i].get("text", tr("Unnamed Step")))
		var txt: String = _format_placeholders(raw_txt)

		var attended := GameState.has_flag("attended_morning_day_%d" % day_idx)
		var missed := (not attended) and (day_idx < GameState.day)

		var label := Label.new()
		label.add_theme_font_override("font", FONT_BODY)
		label.add_theme_font_size_override("font_size", STEP_FONT_SIZE)

		if attended:
			label.add_theme_color_override("font_color", Color.DIM_GRAY)
			label.text = "✔ " + txt
		elif missed:
			label.add_theme_color_override("font_color", Color(0.9, 0.25, 0.25))
			label.text = "✘ " + txt
		else:
			label.text = "• " + txt

		step_container.add_child(label)

# ---------------- Tutoring rendering ----------------
func _render_tutoring_steps(steps: Array) -> void:
	var max_steps = min(4, steps.size())
	for i in range(max_steps):
		var day_idx := i + 1
		var raw_txt: String = String(steps[i].get("text", tr("Unnamed Step")))
		var txt: String = _format_placeholders(raw_txt)

		var tutored := GameState.has_flag("tutored_day_%d" % day_idx)
		var missed := (not tutored) and (day_idx < GameState.day)

		var label := Label.new()
		label.add_theme_font_override("font", FONT_BODY)
		label.add_theme_font_size_override("font_size", STEP_FONT_SIZE)

		if tutored:
			label.add_theme_color_override("font_color", Color.DIM_GRAY)
			label.text = "✔ " + txt
		elif missed:
			label.add_theme_color_override("font_color", Color(0.9, 0.25, 0.25))
			label.text = "✘ " + txt
		else:
			label.text = "• " + txt

		step_container.add_child(label)

# ---------------- Day rollover (study auto-advance) ----------------
func _handle_study_day_rollover(prev_day: int) -> void:
	# If day that just ended was 1..4, advance study tasks even if missed.
	if prev_day < 1 or prev_day > 4:
		return

	_mark_missed_if_needed_for_subject(prev_day, TASK_STUDY_S1, GameState.subject1)
	_mark_missed_if_needed_for_subject(prev_day, TASK_STUDY_S2, GameState.subject2)

func _mark_missed_if_needed_for_subject(day_index: int, task_id: String, subject_raw: String) -> void:
	if subject_raw.strip_edges() == "":
		return
	var subj_key: String = GameState._get_subject_key_from_choice(subject_raw)
	var guard_key: String = subj_key + "|" + str(day_index)
	var studied_today: bool = GameState.study_guard.has(guard_key)

	GameState.ensure_task(task_id)
	var current_prog: int = GameState.get_task_progress(task_id)
	if not studied_today and current_prog < day_index:
		GameState.update_task_step(task_id)

# ---------------- Fail-state computation (gated) ----------------
func _has_failed_task(task_id: String) -> bool:
	# Study/Attendance/Tutoring shouldn’t color early
	if task_id == TASK_STUDY_S1 or task_id == TASK_STUDY_S2:
		var finished := (GameState.day >= 5) or (_count_study_done(task_id) + _count_study_missed(task_id) >= 4)
		return finished and _is_study_failed(task_id)
	if task_id == TASK_ATTENDANCE:
		var finished := (GameState.day >= 5) or (_count_attended() + _attendance_missed() >= 4)
		return finished and (_attendance_missed() > _count_attended())
	if task_id == TASK_TUTORING:
		var finished := (GameState.day >= 5) or (_count_tutored() + _count_tutor_missed() >= 4)
		return finished and (_count_tutor_missed() > _count_tutored())

	# Requirements: fail if any sub-step explicitly FAILED
	if task_id == TASK_REQ:
		var d := _load_task_data(TASK_REQ)
		var stps = d.get("steps", [])
		if stps is Array:
			for s in stps:
				if typeof(s) == TYPE_DICTIONARY:
					if _req_step_state_from_id(s) == StepState.FAILED:
						return true
		return false

	return false

func _is_study_failed(task_id: String) -> bool:
	var subject_raw: String = GameState.subject2 if task_id == TASK_STUDY_S2 else GameState.subject1
	var subj_key := GameState._get_subject_key_from_choice(subject_raw)
	if subj_key.strip_edges() == "":
		return false
	var studied := 0
	var missed := 0
	for day_idx in range(1, 5):
		var guard_key := subj_key + "|" + str(day_idx)
		var did := GameState.study_guard.has(guard_key)
		if did:
			studied += 1
		else:
			if day_idx < GameState.day:
				missed += 1
	return missed > studied

# ---------------- Counters for dynamic x/y ----------------
func _count_study_done(task_id: String) -> int:
	var subject_raw := GameState.subject2 if task_id == TASK_STUDY_S2 else GameState.subject1
	var subj_key := GameState._get_subject_key_from_choice(subject_raw)
	if subj_key == "":
		return 0
	var c := 0
	for i in range(1,5):
		if GameState.study_guard.has(subj_key + "|" + str(i)):
			c += 1
	return c

func _count_study_missed(task_id: String) -> int:
	var subject_raw := GameState.subject2 if task_id == TASK_STUDY_S2 else GameState.subject1
	var subj_key := GameState._get_subject_key_from_choice(subject_raw)
	if subj_key == "":
		return 0
	var c := 0
	for i in range(1,5):
		if not GameState.study_guard.has(subj_key + "|" + str(i)) and i < GameState.day:
			c += 1
	return c

func _count_attended() -> int:
	var c := 0
	for i in range(1,5):
		if GameState.has_flag("attended_morning_day_%d" % i):
			c += 1
	return c

func _count_tutored() -> int:
	var c := 0
	for i in range(1,5):
		if GameState.has_flag("tutored_day_%d" % i):
			c += 1
	return c

func _count_tutor_missed() -> int:
	var c := 0
	for i in range(1,5):
		if not GameState.has_flag("tutored_day_%d" % i) and i < GameState.day:
			c += 1
	return c

# ---------------- Data access + helpers ----------------
func _load_task_data(task_id: String) -> Dictionary:
	var k := _cache_key(task_id)
	if _task_cache.has(k):
		return _task_cache[k]

	# Locale-aware path (no ID changes)
	var file_path: String = GameState.get_data_path("Tasks/%s.json" % task_id)
	if not FileAccess.file_exists(file_path):
		_task_cache[k] = {}
		return {}

	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		_task_cache[k] = {}
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	var d: Dictionary = {}
	if typeof(parsed) == TYPE_DICTIONARY:
		d = parsed

	_task_cache[k] = d
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
	# Delegate to the centralized, locale-aware version in GameState
	return GameState.format_placeholders(text)


# ---- locale-aware cache key ----
func _cache_key(task_id: String) -> String:
	var loc := "en"
	if Engine.is_editor_hint():
		loc = "en"
	elif Engine.has_singleton("GameState"):
		loc = String(GameState.current_locale)
		if loc == "":
			loc = "en"
	return "%s|%s" % [task_id, loc]

# ---------------- Nav ----------------
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
