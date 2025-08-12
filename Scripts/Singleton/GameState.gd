extends Node

# -----------------------------
# Signals
# -----------------------------
signal task_added(task_id: String)
signal task_updated(task_id: String, step_index: int)
signal flag_changed(flag: String, value: bool)
signal money_changed(new_money: int)
signal clock_started
signal clock_stopped

# -----------------------------
# Basic Player / World
# -----------------------------
var player_name: String = ""
var player_gender: String = ""
var location: String = "Unknown"

# -----------------------------
# Time
# -----------------------------
var time: int = 12 * 60 + 45 # 12:45 in minutes
var day: int = 1
var time_speed: float = 2.0
var time_running: bool = false
var _freeze_stack: Array[String] = []

# -----------------------------
# Status
# -----------------------------
var money: int = 2000 # STARTING MONEY
var integrity: int = 0
var reputation: int = 0

# -----------------------------
# Gameplay
# -----------------------------
var inventory: Array = []
var features_unlocked: Dictionary = {}
var subject1: String = ""
var subject2: String = ""
var flags: Dictionary = {}

# -----------------------------
# Tasks
# -----------------------------
var tasks: Array = []
var task_step_index: Dictionary = {}
var _task_counters: Dictionary = {}

# -----------------------------
# Study/Exam (paths + caches)
# -----------------------------
var study_paths: Dictionary = {
	"science":    "res://Data/Study/Science.json",
	"geography":  "res://Data/Study/Geography.json",
	"math":       "res://Data/Study/Math.json",
	"macedonian": "res://Data/Study/Macedonian.json",
	"english":    "res://Data/Study/English.json",
}

var study_pool_cache: Dictionary = {}   # subject -> Array[Dictionary]
var exam_finals: Dictionary = {}        # subject -> Array[String] ids (picked 10)
var exam_revealed: Dictionary = {}      # subject -> Array[String] ids (revealed during study)
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# -------------------------------------------------
# Lifecycle
# -------------------------------------------------
func _ready() -> void:
	_rng.randomize()
	print("📂 GameState Ready — timer idle at %s (Day %d)" % [_format_time(), day])

func begin_game(day_start: int, time_start: int) -> void:
	day = day_start
	time = time_start
	_start_time_simulation()
	time_running = true
	emit_signal("clock_started")

# -------------------------------------------------
# Reputation / Integrity helpers
# -------------------------------------------------
func adjust_reputation(delta: int) -> void:
	reputation += delta
	print("📈 Reputation %+d → %d" % [delta, reputation])

func adjust_integrity(delta: int) -> void:
	integrity += delta
	print("📉 Integrity %+d → %d" % [delta, integrity])

# -------------------------------------------------
# Time system
# -------------------------------------------------
func _start_time_simulation() -> void:
	if has_node("TimeTick"):
		return
	var timer: Timer = Timer.new()
	timer.name = "TimeTick"
	timer.wait_time = time_speed
	timer.autostart = true
	timer.one_shot = false
	timer.timeout.connect(_on_minute_passed)
	add_child(timer)

func _on_minute_passed() -> void:
	if not time_running: return
	if is_time_frozen(): return
	time += 1
	if time >= 24 * 60:
		time = 0
		day += 1
	print("🕒 Time:%s" % _format_time())

func _format_time() -> String:
	var hours: int = time / 60
	var minutes: int = time % 60
	return "%02d:%02d" % [hours, minutes]

func adjust_time(value: int) -> void:
	time += value
	while time >= 24 * 60:
		time -= 24 * 60
		day += 1
	if time < 0:
		time = 0
	print("⏱️ Time adjusted by %d → %s (Day %d)" % [value, _format_time(), day])

func push_time_freeze(src: String) -> void:
	if not _freeze_stack.has(src):
		_freeze_stack.append(src)
	emit_signal("clock_stopped")
	print("⏸️ Freeze ON:%s stack:%s" % [src, str(_freeze_stack)])

func pop_time_freeze(src: String) -> void:
	if _freeze_stack.has(src):
		_freeze_stack.erase(src)
		if _freeze_stack.size() == 0:
			emit_signal("clock_started")
	print("▶️ Freeze OFF:%s stack:%s" % [src, str(_freeze_stack)])

func is_time_frozen() -> bool:
	return _freeze_stack.size() > 0

# Provide a canonical sleep for Home.gd
func sleep_now() -> void:
	var wake_base: int = 7 * 60 + 30 # 07:30
	var penalty: int = 0
	if time >= 23 * 60:
		var after_23: int = time - 23 * 60
		penalty = int(ceil(float(after_23) / 4.0))
	var wake: int = wake_base + penalty
	while wake >= 24 * 60:
		wake -= 24 * 60
	day += 1
	time = wake
	print("🛌 Slept. Wake at %s (Day %d), penalty +%d min" % [_format_time(), day, penalty])

# -------------------------------------------------
# Money / Stats
# -------------------------------------------------
func add_money(delta: int) -> void:
	var before: int = money
	money += delta

	# First spend detection
	if delta < 0 and not has_flag("spent_money_once"):
		set_flag("spent_money_once", true)
		print("[MoneyWatch] First spend detected — Tutoring unlocked.")
		add_task("Tutoring Task") # replace with your actual tutoring task ID

	emit_signal("money_changed", money)

# -------------------------------------------------
# Features
# -------------------------------------------------
func unlock_game_feature(feature_id: String, limit: Variant = null) -> void:
	if not features_unlocked.has(feature_id):
		features_unlocked[feature_id] = {}
	if limit != null:
		(features_unlocked[feature_id] as Dictionary)["limit"] = limit
	print("🔓 Feature unlocked:%s Limit:%s" % [feature_id, str(limit)])

func has_feature(feature_id: String) -> bool:
	return features_unlocked.has(feature_id)

# -------------------------------------------------
# Flags
# -------------------------------------------------
func has_flag(flag: String) -> bool:
	return bool(flags.get(flag, false))

func set_flag(flag: String, value: bool = true) -> void:
	var prev: bool = has_flag(flag)
	flags[flag] = value
	if prev != value:
		emit_signal("flag_changed", flag, value)

func clear_flag(flag: String) -> void:
	if flags.has(flag):
		flags.erase(flag)
		emit_signal("flag_changed", flag, false)

# -------------------------------------------------
# Tasks
# -------------------------------------------------
func ensure_task(task_id: String) -> void:
	if not tasks.has(task_id):
		add_task(task_id)

func add_task(task_id: String) -> void:
	if task_id == "": return
	if not tasks.has(task_id):
		tasks.append(task_id)
		task_step_index[task_id] = 0
		print("➕ Task added:%s" % task_id)
		emit_signal("task_added", task_id)

func update_task_step(task_id: String) -> void:
	if task_id == "": return
	var idx: int = int(task_step_index.get(task_id, 0))
	idx += 1
	task_step_index[task_id] = idx
	print("✅ Step advanced to %d in %s" % [idx, task_id])
	emit_signal("task_updated", task_id, idx)

func get_task_progress(task_id: String) -> int:
	return int(task_step_index.get(task_id, 0))

func get_task_counter(task_id: String, key: String, default_val: int = 0) -> int:
	var bucket: Dictionary = _task_counters.get(task_id, {})
	return int(bucket.get(key, default_val))

func inc_task_counter(task_id: String, key: String, delta: int = 1) -> int:
	var bucket: Dictionary = _task_counters.get(task_id, {})
	var cur: int = int(bucket.get(key, 0)) + delta
	bucket[key] = cur
	_task_counters[task_id] = bucket
	return cur

func ensure_task_progress_at_least(task_id: String, target_step: int) -> void:
	ensure_task(task_id)
	var prog: int = get_task_progress(task_id)
	while prog < target_step:
		update_task_step(task_id)
		prog += 1

# -------------------------------------------------
# Dialogue JSON action router
# -------------------------------------------------
func apply_action(line: Dictionary) -> void:
	var act: String = String(line.get("action", ""))
	match act:
		"add_task":
			var t: Variant = line.get("tasks", null)
			if t is Array:
				for x in (t as Array):
					add_task(String(x))
			elif t is String:
				add_task(String(t))
		"update_task_step":
			var task: String = String(line.get("task", ""))
			if task != "":
				update_task_step(task)
		"set_flags":
			var fs: Variant = line.get("flags", null)
			if fs is Array:
				for f in (fs as Array):
					set_flag(String(f), true)
			elif fs is String:
				set_flag(String(fs), true)
		"clear_flags":
			var cf: Variant = line.get("flags", null)
			if cf is Array:
				for f2 in (cf as Array):
					clear_flag(String(f2))
			elif cf is String:
				clear_flag(String(cf))
		"adjust_time":
			adjust_time(int(line.get("value", 0)))
		"unlock_feature":
			var feat: String = String(line.get("feature", ""))
			var lim: Variant = line.get("limit", null)
			if feat != "":
				unlock_game_feature(feat, lim)
		"add_money":
			add_money(int(line.get("value", 0)))
		"adjust_reputation":
			adjust_reputation(int(line.get("value", 0)))
		"adjust_integrity":
			adjust_integrity(int(line.get("value", 0)))
		_:
			# ignore unknown actions
			pass

# -------------------------------------------------
# Text helpers (used by Task Manager UI)
# -------------------------------------------------
func format_placeholders(text: String) -> String:
	var s: String = text
	var s1: String = subject1.capitalize()
	var s2: String = subject2.capitalize()
	s = s.replace("{subject1}", s1).replace("{subject2}", s2)
	s = s.replace("[Subject 1]", s1).replace("[Subject 2]", s2)
	return s

# -------------------------------------------------
# Study/Exam helpers
# -------------------------------------------------
func _get_subject_key_from_choice(which: String) -> String:
	var s: String = which.strip_edges().to_lower()
	match s:
		"science": return "science"
		"geography": return "geography"
		"math (algebra basics)", "math": return "math"
		"macedonian": return "macedonian"
		"english": return "english"
		_: return s

func _load_pool(subject: String) -> Array:
	if study_pool_cache.has(subject):
		return study_pool_cache[subject]
	var path: String = String(study_paths.get(subject, ""))
	if path == "" or not FileAccess.file_exists(path):
		push_error("Study pool missing for subject: " + subject + " @ " + path)
		return []
	var txt: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Malformed pool JSON: " + path)
		return []
	var dict: Dictionary = parsed
	var pool: Array = dict.get("pool", []) as Array
	study_pool_cache[subject] = pool
	return pool

func _ensure_finals(subject: String) -> void:
	if exam_finals.has(subject): return
	var pool: Array = _load_pool(subject)
	if pool.is_empty(): return
	var idxs: Array[int] = _pick_unique_indexes(pool.size(), 10)
	var ids: Array[String] = []
	for i in idxs:
		var qd: Dictionary = pool[i]
		ids.append(String(qd.get("id","")))
	exam_finals[subject] = ids
	exam_revealed[subject] = []

func _pick_unique_indexes(n: int, k: int) -> Array[int]:
	var arr: Array[int] = []
	for i in range(n):
		arr.append(i)
	for i in range(n - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var t: int = arr[i]
		arr[i] = arr[j]
		arr[j] = t
	var out: Array[int] = []
	var lim: int = min(k, n)
	for i in range(lim):
		out.append(arr[i])
	return out

# Returns 5 question dicts for study session (2 finals + 3 fillers)
# Each dict has: id, q, correct, wrong[2] (you'll only display q + correct during study)
func build_study_batch(subject_raw: String) -> Array:
	var subject: String = _get_subject_key_from_choice(subject_raw)
	_ensure_finals(subject)
	var pool: Array = _load_pool(subject)
	if pool.is_empty(): return []

	# index by id
	var by_id: Dictionary = {}
	for q in pool:
		var qd: Dictionary = q
		by_id[String(qd.get("id",""))] = qd

	var finals: Array = exam_finals.get(subject, [])
	var revealed: Array = exam_revealed.get(subject, [])
	var finals_left: Array = []
	for id in finals:
		if revealed.find(id) == -1:
			finals_left.append(id)

	# pick up to 2 finals
	var finals_pick: Array = []
	var num_final: int = min(2, finals_left.size())
	if num_final > 0:
		var idxs: Array[int] = _pick_unique_indexes(finals_left.size(), num_final)
		for i in idxs:
			finals_pick.append(String(finals_left[i]))

	# mark revealed
	for id in finals_pick:
		if revealed.find(id) == -1:
			revealed.append(id)
	exam_revealed[subject] = revealed

	# filler candidates (non-finals)
	var final_set: Dictionary = {}
	for id in finals:
		final_set[id] = true
	var filler_candidates: Array = []
	for q in pool:
		var qid: String = String((q as Dictionary).get("id",""))
		if not final_set.has(qid):
			filler_candidates.append(qid)

	# pick 3 fillers
	var fillers_pick: Array = []
	if filler_candidates.size() > 0:
		var idxs2: Array[int] = _pick_unique_indexes(filler_candidates.size(), 3)
		for i in idxs2:
			fillers_pick.append(String(filler_candidates[i]))

	# assemble
	var result: Array = []
	for id in finals_pick:
		result.append(by_id[id])
	for id in fillers_pick:
		result.append(by_id[id])
	return result

# Build the 10-question exam paper with shuffled choices
# Each item: { id, q, choices:Array[String], correct_index:int }
func build_exam_paper(subject_raw: String) -> Array:
	var subject: String = _get_subject_key_from_choice(subject_raw)
	_ensure_finals(subject)
	var pool: Array = _load_pool(subject)
	if pool.is_empty(): return []

	# index by id
	var by_id: Dictionary = {}
	for q in pool:
		var qd: Dictionary = q
		by_id[String(qd.get("id",""))] = qd

	var finals: Array = exam_finals.get(subject, [])
	var paper: Array = []
	for id in finals:
		var qd: Dictionary = by_id.get(id, {}) as Dictionary
		if qd.is_empty():
			continue
		var correct: String = String(qd.get("correct",""))
		var wrongs: Array = qd.get("wrong", []) as Array
		var opts: Array = [correct, String(wrongs[0]), String(wrongs[1])]
		# shuffle
		var order: Array[int] = _pick_unique_indexes(opts.size(), opts.size())
		var shuffled: Array = []
		var correct_index: int = 0
		for idx in range(order.size()):
			var choice: String = String(opts[order[idx]])
			shuffled.append(choice)
			if choice == correct:
				correct_index = idx
		paper.append({
			"id": String(qd.get("id","")),
			"q": String(qd.get("q","")),
			"choices": shuffled,
			"correct_index": correct_index
		})
	return paper

# Reveal two finals now (for Marko tips) and mark them revealed
# Returns Array[String] of IDs; you can fetch text via get_question_by_id()
func reveal_two_finals(subject_raw: String) -> Array:
	var subject: String = _get_subject_key_from_choice(subject_raw)
	_ensure_finals(subject)
	var finals: Array = exam_finals.get(subject, [])
	var revealed: Array = exam_revealed.get(subject, [])

	var left: Array = []
	for id in finals:
		if revealed.find(id) == -1:
			left.append(id)

	var pick: Array = []
	if left.size() > 0:
		var idxs: Array[int] = _pick_unique_indexes(left.size(), min(2, left.size()))
		for i in idxs:
			pick.append(String(left[i]))

	# mark revealed
	for id in pick:
		if revealed.find(id) == -1:
			revealed.append(id)
	exam_revealed[subject] = revealed
	return pick

# Utility to fetch full question dict by ID (useful for showing Marko's reveal text)
func get_question_by_id(subject_raw: String, qid: String) -> Dictionary:
	var subject: String = _get_subject_key_from_choice(subject_raw)
	var pool: Array = _load_pool(subject)
	for q in pool:
		var qd: Dictionary = q
		if String(qd.get("id","")) == qid:
			return qd
	return {}
