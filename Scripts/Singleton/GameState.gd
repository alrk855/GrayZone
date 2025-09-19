extends Node

const Flags = preload("res://Scripts/Singleton/GameFlags.gd")

# -----------------------------
# One-AM handling (no locks, no freezes)
# -----------------------------
const ONE_AM_MINUTES := 60                       # 01:00
const HOME_SCENE_PATH := "res://Scenes/Reusable/Map/Home.tscn"
const J_ONE_AM := "res://Data/System/Narrator_Curfew.json"

var _one_am_paused: bool = false                 # stops ticking/adjust_time after 01:00 only

# -----------------------------
# Signals
# -----------------------------
signal task_added(task_id: String)
signal task_updated(task_id: String, step_index: int)
signal flag_changed(flag: String, value: bool)
signal money_changed(new_money: int)
signal clock_started
signal clock_stopped
signal time_changed(new_time: int, new_day: int)

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
var day: int = 1          # <— persisted in GameState for saves
var time_speed: float = 2.0
var time_running: bool = false
var _freeze_stack: Array[String] = []            # keep available for other systems; not used by 01:00 logic

# -----------------------------
# Status
# -----------------------------
var money: int = 2000
var integrity: int = 20
var reputation: int = 20

# -----------------------------
# Gameplay
# -----------------------------
var inventory: Array = []
var features_unlocked: Dictionary = {}
var subject1: String = ""
var subject2: String = ""
var flags: Dictionary = {}   # canonicalized keys only (via Flags.canon)

# Mailbox / Language Certificate
# Randomized arrival day ∈ [1..4] stored HERE (not in flags) for easy save/load.
var lang_cert_ready_day: int = 0

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
var exam_finals: Dictionary = {}        # subject -> Array[String] (12 ids)
var exam_revealed: Dictionary = {}      # subject -> Array[String] (revealed ids, if you use it elsewhere)
var study_sheet_cache: Dictionary = {}  # subject -> Dictionary(day_string -> Array[String] ids)
var study_guard: Dictionary = {}        # "subject|day" -> bool (counted already for the real in-game day)
var study_reveal_days: Dictionary = {}  # subject -> { "1": true, "2": true, ... } finals-only per session/day
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
	_one_am_paused = false
	emit_signal("time_changed", time, day)
	emit_signal("money_changed", money)
	_start_time_simulation()
	time_running = true
	emit_signal("clock_started")

func _init_default_flags() -> void:
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
	if not time_running or is_time_frozen() or _one_am_paused:
		return
	time += 1
	if time >= 24 * 60:
		time = 0
		day += 1
	# Pause exactly at 01:00; do not lock or freeze UI
	if time == ONE_AM_MINUTES:
		_one_am_paused = true
		call_deferred("_handle_one_am_sequence")
	emit_signal("time_changed", time, day)

func _format_time() -> String:
	var hours: int = int(time / 60) % 24   # 24h loop, safe cast
	var minutes: int = int(time % 60)
	return "%02d:%02d" % [hours, minutes]

func adjust_time(value: int) -> void:
	# After 01:00 pause, ignore further time changes until you resume (e.g., after sleeping)
	if _one_am_paused:
		return

	var orig_time := time
	var new_time := time + value
	var new_day := day

	# Positive wraparound (keep 24h loop)
	while new_time >= 24 * 60:
		new_time -= 24 * 60
		new_day += 1

	# Negative clamp like the original (no going back days)
	if new_time < 0:
		new_time = 0

	# If we were in/after midnight window and we pass 01:00, clamp + pause
	var crossed_midnight: bool = (day != new_day)
	var hit_pause: bool = false

	# Case A: currently between 00:00..00:59 and jumping past 01:00
	if orig_time < ONE_AM_MINUTES and new_time >= ONE_AM_MINUTES and not crossed_midnight:
		hit_pause = true
	# Case B: we crossed midnight and land at/after 01:00
	if crossed_midnight and new_time >= ONE_AM_MINUTES:
		hit_pause = true

	if hit_pause:
		time = ONE_AM_MINUTES
		day = new_day
		_one_am_paused = true
		call_deferred("_handle_one_am_sequence")
		emit_signal("time_changed", time, day)
		return

	time = new_time
	day = new_day
	emit_signal("time_changed", time, day)

# NOTE: keep these available for other systems; NOT used by 01:00 pause flow
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
	_one_am_paused = false  # new day resumes ticking
	print("🛌 Slept. Wake at %s (Day %d), penalty +%d min" % [_format_time(), day, penalty])

# Optional helper if you want to resume ticking without sleeping
func resume_after_one_am() -> void:
	_one_am_paused = false

# 01:00 sequence: show JSON warning (Narrator), then go Home. No locks.
func _handle_one_am_sequence() -> void:
	var played := false
	var dm := get_node_or_null("/root/DialogueManager")
	if dm and (dm.has_method("play_json_blocking") or dm.has_method("play_json")):
		played = true
		if dm.has_method("play_json_blocking"):
			await dm.play_json_blocking(J_ONE_AM)
		else:
			await dm.play_json(J_ONE_AM)
	if not played:
		var ad := AcceptDialog.new()
		ad.dialog_text = "It's 1:00 AM. We should really go to sleep or we can't progress."
		ad.title = "Narrator"
		get_tree().root.add_child(ad)
		ad.popup_centered()
		await ad.confirmed
		ad.queue_free()

	location = "Home"
	var err := get_tree().change_scene_to_file(HOME_SCENE_PATH)
	if err != OK:
		push_error("01:00 teleport to Home failed with code: %s" % [str(err)])

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
	if task_id == "":
		return
	if not tasks.has(task_id):
		tasks.append(task_id)
		task_step_index[task_id] = 0
		print("➕ Task added:%s" % task_id)
		emit_signal("task_added", task_id)

func update_task_step(task_id: String) -> void:
	if task_id == "":
		return
	var idx: int = int(task_step_index.get(task_id, 0))
	idx += 1
	task_step_index[task_id] = idx
	print("✅ Step advanced to %d in %s" % [idx, task_id])
	emit_signal("task_updated", task_id, idx)

func get_task_progress(task_id: String) -> int:
	return int(task_step_index.get(task_id, 0))

func get_task_counter(task_id: String, key: String, default_val: int) -> int:
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
	if exam_finals.has(subject):
		var existing: Array = exam_finals.get(subject, [])
		if existing.size() >= 12:
			return
	var pool: Array = _load_pool(subject)
	if pool.is_empty():
		return
	var idxs: Array[int] = _pick_unique_indexes(pool.size(), 12)
	var ids: Array[String] = []
	for i in idxs:
		var qd: Dictionary = pool[i]
		ids.append(String(qd.get("id","")))
	exam_finals[subject] = ids
	exam_revealed[subject] = []

func _pick_unique_indexes(n: int, k: int) -> Array[int]:
	var arr: Array[int] = []
	var i: int = 0
	while i < n:
		arr.append(i)
		i += 1
	var j: int = n - 1
	while j > 0:
		var r: int = _rng.randi_range(0, j)
		var t: int = arr[j]
		arr[j] = arr[r]
		arr[r] = t
		j -= 1
	var out: Array[int] = []
	var lim: int = k
	if lim > n:
		lim = n
	var q: int = 0
	while q < lim:
		out.append(arr[q])
		q += 1
	return out

func _finals_triple_for_day(subject: String, day_index: int) -> Array[String]:
	_ensure_finals(subject)
	var finals: Array = exam_finals.get(subject, [])
	var out: Array[String] = []
	if finals.is_empty():
		return out
	var d: int = day_index
	if d < 1:
		d = 1
	if d > 4:
		d = 4
	var base: int = ((d - 1) % 4) * 3
	var i: int = 0
	while i < 3 and base + i < finals.size():
		out.append(String(finals[base + i]))
		i += 1
	return out

func mark_today_finals_revealed(subject_raw: String) -> void:
	var subject: String = _get_subject_key_from_choice(subject_raw)
	var d: int = day
	if d < 1:
		d = 1
	if d > 4:
		d = 4
	if not study_reveal_days.has(subject):
		study_reveal_days[subject] = {}
	var m: Dictionary = study_reveal_days[subject]
	m[str(d)] = true
	study_reveal_days[subject] = m
	# Invalidate today's cached sheet so it rebuilds as finals-only
	if study_sheet_cache.has(subject):
		var by_day: Dictionary = study_sheet_cache[subject]
		var key: String = str(d)
		if by_day.has(key):
			by_day.erase(key)
			study_sheet_cache[subject] = by_day

func get_study_sheet_for_session(subject_raw: String, session_index: int) -> Array:
	var subject: String = _get_subject_key_from_choice(subject_raw)
	var d: int = session_index
	if d < 1:
		d = 1
	if d > 4:
		d = 4
	var ids: Array[String] = _get_or_build_sheet_ids(subject, d)
	return _ids_to_questions(subject_raw, ids)

func get_daily_study_sheet(subject_raw: String) -> Array:
	var subject: String = _get_subject_key_from_choice(subject_raw)
	var d: int = day
	if d < 1:
		d = 1
	if d > 4:
		d = 4
	var ids: Array[String] = _get_or_build_sheet_ids(subject, d)
	return _ids_to_questions(subject_raw, ids)

func _get_or_build_sheet_ids(subject: String, day_index: int) -> Array[String]:
	if not study_sheet_cache.has(subject):
		study_sheet_cache[subject] = {}
	var by_day: Dictionary = study_sheet_cache[subject]
	var key: String = str(day_index)
	if by_day.has(key):
		return by_day[key]
	var built: Array[String] = _build_sheet_ids_for_day(subject, day_index)
	by_day[key] = built
	study_sheet_cache[subject] = by_day
	return built

func _build_sheet_ids_for_day(subject: String, day_index: int) -> Array[String]:
	var out: Array[String] = []
	var pool: Array = _load_pool(subject)
	if pool.is_empty():
		return out

	var finals_today: Array[String] = _finals_triple_for_day(subject, day_index)

	var finals_only: bool = false
	if study_reveal_days.has(subject):
		var m: Dictionary = study_reveal_days[subject]
		finals_only = bool(m.get(str(day_index), false))

	var i: int = 0
	while i < finals_today.size():
		out.append(finals_today[i])
		i += 1

	if not finals_only:
		# choose 2 deterministic non-final fillers (not in any finals)
		var finals_set: Dictionary = {}
		var all_finals: Array = exam_finals.get(subject, [])
		var j: int = 0
		while j < all_finals.size():
			finals_set[String(all_finals[j])] = true
			j += 1

		var candidates: Array[String] = []
		for qv in pool:
			var qd: Dictionary = qv
			var qid: String = String(qd.get("id",""))
			if not finals_set.has(qid):
				candidates.append(qid)

		if candidates.size() > 0:
			var start: int = (day_index * 7) % candidates.size()
			var count: int = 2
			if count > candidates.size():
				count = candidates.size()
			var k: int = 0
			while k < count:
				out.append(candidates[(start + k) % candidates.size()])
				k += 1

	return out

func _ids_to_questions(subject_raw: String, ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		var qd: Dictionary = get_question_by_id(subject_raw, String(id))
		if not qd.is_empty():
			out.append(qd)
	return out

func build_exam_paper(subject_raw: String) -> Array:
	var subject: String = _get_subject_key_from_choice(subject_raw)
	_ensure_finals(subject)
	var pool: Array = _load_pool(subject)
	if pool.is_empty():
		return []
	var by_id: Dictionary = {}
	for q in pool:
		var qd: Dictionary = q
		by_id[String(qd.get("id",""))] = qd
	var finals: Array = exam_finals.get(subject, [])
	var paper: Array = []
	for id in finals:
		var qd2: Dictionary = by_id.get(id, {}) as Dictionary
		if qd2.is_empty():
			continue
		var correct: String = String(qd2.get("correct",""))
		var wrongs: Array = qd2.get("wrong", []) as Array
		var opts: Array = []
		opts.append(correct)
		if wrongs.size() >= 1:
			opts.append(String(wrongs[0]))
		if wrongs.size() >= 2:
			opts.append(String(wrongs[1]))
		var order: Array[int] = _pick_unique_indexes(opts.size(), opts.size())
		var shuffled: Array[String] = []
		var correct_index: int = 0
		var idx: int = 0
		while idx < order.size():
			var choice: String = String(opts[order[idx]])
			shuffled.append(choice)
			if choice == correct:
				correct_index = idx
			idx += 1
		paper.append({
			"id": String(qd2.get("id","")),
			"q": String(qd2.get("q","")),
			"choices": shuffled,
			"correct_index": correct_index
		})
	return paper

# Legacy helper (kept for compatibility). Returns first two from today's triple.
func get_today_finals_pair_ids(subject_raw: String) -> Array[String]:
	var subject: String = _get_subject_key_from_choice(subject_raw)
	var d: int = day
	if d < 1:
		d = 1
	if d > 4:
		d = 4
	var triple: Array[String] = _finals_triple_for_day(subject, d)
	var out: Array[String] = []
	if triple.size() >= 1:
		out.append(triple[0])
	if triple.size() >= 2:
		out.append(triple[1])
	return out

# Utility to fetch full question dict by ID
func get_question_by_id(subject_raw: String, qid: String) -> Dictionary:
	var subject: String = _get_subject_key_from_choice(subject_raw)
	var pool: Array = _load_pool(subject)
	for q in pool:
		var qd: Dictionary = q
		if String(qd.get("id","")) == qid:
			return qd
	return {}

# --------- study count guard (once per *in-game* day per subject) ----------
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
