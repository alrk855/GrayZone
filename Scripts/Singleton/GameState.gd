extends Node

const Flags = preload("res://Scripts/Singleton/GameFlags.gd")

# -----------------------------
# Signals
# -----------------------------
signal task_added(task_id: String)
signal task_updated(task_id: String, step_index: int)
signal flag_changed(flag: String, value: bool)
signal money_changed(new_money: int)
signal clock_started
signal clock_stopped
signal time_changed(new_time: String, new_day: int)

# -----------------------------
# Basic Player / World
# -----------------------------
var player_name: String = ""
var player_gender: String = ""
var location: String = "Unknown"

# -----------------------------
# Time
# -----------------------------
var time: int = 12 * 60 + 45
var day: int = 1
var time_speed: float = 2.0
var time_running: bool = false
var _freeze_stack: Array[String] = []

# -----------------------------
# Status
# -----------------------------
var money: int = 2000
var integrity: int = 50
var reputation: int = 50

# -----------------------------
# Gameplay
# -----------------------------
var inventory: Array = []
var features_unlocked: Dictionary = {}
var subject1: String = ""
var subject2: String = ""
var flags: Dictionary = {}   # canonicalized keys only (via Flags.canon)

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
var exam_finals: Dictionary = {}        # subject -> Array[String] (10 ids)
var exam_revealed: Dictionary = {}      # subject -> Array[String] (revealed)
var study_sheet_cache: Dictionary = {}  # subject -> Dictionary(day_string -> Array[String] 5 ids)
var study_guard: Dictionary = {}        # "subject|day" -> bool (counted already?)
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# -------------------------------------------------
# Lifecycle
# -------------------------------------------------
func _ready() -> void:
	_init_default_flags()
	_rng.randomize()
	print("📂 GameState Ready — timer idle at %s (Day %d)" % [_format_time(), day])

func begin_game(day_start: int, time_start: int) -> void:
	_init_default_flags()
	day = day_start
	time = time_start
	emit_signal("time_changed", _format_time(), day)
	emit_signal("money_changed", money)
	_start_time_simulation()
	time_running = true
	emit_signal("clock_started")

func _init_default_flags() -> void:
	# Pull all defaults from the static Flags singleton
	for k in Flags.DEFAULTS.keys():
		if not flags.has(k):
			flags[k] = Flags.DEFAULTS[k]

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
	emit_signal("time_changed", _format_time(), day)
	print("📢 Emitted time_changed:", time, day)

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
	emit_signal("time_changed", _format_time(), day)

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

func sleep_now() -> void:
	var wake_base: int = 7 * 60 + 30
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
	if delta < 0 and not has_flag("spent_money_once"):
		set_flag("spent_money_once", true)
		print("[MoneyWatch] First spend detected — Tutoring unlocked.")
		add_task("Tutoring Task") # swap to your real task id
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
# Flags (canonicalized)
# -------------------------------------------------
func has_flag(flag: String) -> bool:
	var f: String = Flags.canon(flag)
	return bool(flags.get(f, false))

func set_flag(flag: String, value: bool = true) -> void:
	var f: String = Flags.canon(flag)
	var prev: bool = bool(flags.get(f, false))
	flags[f] = value
	if prev != value:
		emit_signal("flag_changed", f, value)

func clear_flag(flag: String) -> void:
	var f: String = Flags.canon(flag)
	if flags.has(f):
		flags.erase(f)
		emit_signal("flag_changed", f, false)

# Optional typed helpers for non-boolean state stored alongside flags
func set_int(key: String, value: int) -> void:
	var k: String = Flags.canon(key)
	flags[k] = int(value)

func get_int(key: String, default_val: int = 0) -> int:
	var k: String = Flags.canon(key)
	return int(flags.get(k, default_val))

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
# Dialogue JSON action router (canonicalized flag ops)
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
			var fs2: Variant = line.get("flags", null)
			if fs2 is Array:
				for f2 in (fs2 as Array):
					clear_flag(String(f2))
			elif fs2 is String:
				clear_flag(String(fs2))

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
			pass

# -------------------------------------------------
# Text helpers (for UI)
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

# Finals pair ids for "today": (0,1),(2,3),(4,5),(6,7),(8,9)
func get_today_finals_pair_ids(subject_raw: String) -> Array[String]:
	var subject: String = _get_subject_key_from_choice(subject_raw)
	_ensure_finals(subject)
	var finals: Array = exam_finals.get(subject, [])
	if finals.size() < 2:
		return []
	var base_index: int = int(((day - 1) % 5) * 2)
	if base_index + 1 >= finals.size():
		base_index = max(0, finals.size() - 2)
	return [ String(finals[base_index]), String(finals[base_index + 1]) ]

# Deterministic daily 5-item sheet (2 finals for today + 3 non-final fillers)
# Cached per (subject, day). Returns Array[Dictionary] (q objects).
func get_daily_study_sheet(subject_raw: String) -> Array:
	var subject: String = _get_subject_key_from_choice(subject_raw)
	_ensure_finals(subject)

	var day_key: String = str(day)
	if not study_sheet_cache.has(subject):
		study_sheet_cache[subject] = {}
	var by_day: Dictionary = study_sheet_cache[subject]

	if by_day.has(day_key):
		return _ids_to_questions(subject_raw, by_day[day_key] as Array)

	# create new sheet for today
	var pool: Array = _load_pool(subject)
	if pool.is_empty(): return []

	# ids for today's finals
	var pair_ids: Array[String] = get_today_finals_pair_ids(subject_raw)
	var finals_set: Dictionary = {}
	for id in pair_ids: finals_set[id] = true

	# collect candidate fillers (non-finals)
	var candidate_ids: Array[String] = []
	for qv in pool:
		var qd: Dictionary = qv
		var qid: String = String(qd.get("id",""))
		if not finals_set.has(qid) and exam_finals.get(subject, []).find(qid) == -1:
			# ensure it's not any of the 10 finals (we want true non-finals)
			candidate_ids.append(qid)

	# deterministic pick of 3 fillers based on (subject, day)
	var fillers: Array[String] = []
	if candidate_ids.size() > 0:
		var start: int = (day * 3) % candidate_ids.size()
		var count: int = min(3, candidate_ids.size())
		for i in range(count):
			fillers.append(candidate_ids[(start + i) % candidate_ids.size()])

	# store id order: [final1, final2, filler1, filler2, filler3]
	var today_ids: Array[String] = []
	for id in pair_ids: today_ids.append(id)
	for id in fillers:   today_ids.append(id)

	by_day[day_key] = today_ids
	study_sheet_cache[subject] = by_day
	return _ids_to_questions(subject_raw, today_ids)

# turn id list into full question dicts
func _ids_to_questions(subject_raw: String, ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		var qd: Dictionary = get_question_by_id(subject_raw, String(id))
		if not qd.is_empty():
			out.append(qd)
	return out

# Build the 10-question exam paper (shuffled choices)
func build_exam_paper(subject_raw: String) -> Array:
	var subject: String = _get_subject_key_from_choice(subject_raw)
	_ensure_finals(subject)
	var pool: Array = _load_pool(subject)
	if pool.is_empty(): return []
	var by_id: Dictionary = {}
	for q in pool:
		var qd: Dictionary = q
		by_id[String(qd.get("id",""))] = qd
	var finals: Array = exam_finals.get(subject, [])
	var paper: Array = []
	for id in finals:
		var qd: Dictionary = by_id.get(id, {}) as Dictionary
		if qd.is_empty(): continue
		var correct: String = String(qd.get("correct",""))
		var wrongs: Array = qd.get("wrong", []) as Array
		var opts: Array = [correct, String(wrongs[0]), String(wrongs[1])]
		var order: Array[int] = _pick_unique_indexes(opts.size(), opts.size())
		var shuffled: Array[String] = []
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

# Reveal two finals now (for Marko), mark them revealed
func reveal_two_finals(subject_raw: String) -> Array:
	var subject: String = _get_subject_key_from_choice(subject_raw)
	_ensure_finals(subject)
	var finals: Array[String] = exam_finals.get(subject, [])
	var revealed: Array[String] = exam_revealed.get(subject, [])

	var left: Array[String] = []
	for id in finals:
		if revealed.find(id) == -1:
			left.append(id)

	var pick: Array[String] = []
	if left.size() > 0:
		var idxs: Array[int] = _pick_unique_indexes(left.size(), min(2, left.size()))
		for i in idxs:
			pick.append(String(left[i]))

	for id in pick:
		if revealed.find(id) == -1:
			revealed.append(id)
	exam_revealed[subject] = revealed
	return pick

# Utility to fetch full question dict by ID
func get_question_by_id(subject_raw: String, qid: String) -> Dictionary:
	var subject: String = _get_subject_key_from_choice(subject_raw)
	var pool: Array = _load_pool(subject)
	for q in pool:
		var qd: Dictionary = q
		if String(qd.get("id","")) == qid:
			return qd
	return {}

# --------- study count guard (once per day per subject) ----------
func _which_subject_slot(subject_raw: String) -> String:
	var key_raw: String = _get_subject_key_from_choice(subject_raw)
	var s1: String = _get_subject_key_from_choice(subject1)
	var s2: String = _get_subject_key_from_choice(subject2)
	if key_raw == s2:
		return "subject2"
	return "subject1"

# Returns true if it counted; false if already counted today.
func count_study_if_new(subject_raw: String, add_time_minutes: int) -> bool:
	var key_raw: String = _get_subject_key_from_choice(subject_raw)
	var k: String = key_raw + "|" + str(day)
	if study_guard.has(k):
		return false
	study_guard[k] = true

	var slot: String = _which_subject_slot(subject_raw)
	var tid: String = ""
	if slot == "subject2":
		tid = "study_subject2"
	else:
		tid = "study_subject1"

	update_task_step(tid)
	if add_time_minutes > 0:
		adjust_time(add_time_minutes)
	return true
