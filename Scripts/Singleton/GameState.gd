extends Node 

const Flags = preload("res://Scripts/Singleton/GameFlags.gd")

# -----------------------------
# One-AM handling (no locks, no freezes)
# -----------------------------
const ONE_AM_MINUTES := 60                       # 01:00
const HOME_SCENE_PATH := "res://Scenes/Reusable/Map/Home.tscn"
const J_ONE_AM := "System/Narrator_Curfew.json"  # relative path now, resolved at runtime


# MVR LOGIC KEYS / MARKERS
const K_MVR_METHOD                := "MVR_METHOD"                # 0/1/2/3
const K_MVR_READY_DAY             := "MVR_BCERT_READY_DAY"       # int day
const K_MVR_LAST_WAIT_BUMP_DAY    := "__MVR_LAST_WAIT_BUMP_DAY"  # int day marker (last day we bumped "birth")
const K_MVR_BRIBE_WAIT_BUMPED     := "__MVR_BRIBE_WAIT_BUMPED"   # bool marker (bumped at/after 17:00 on ready day)
const K_MVR_LAST_CHECK_DAY        := "__MVR_LAST_CHECK_DAY"      # int day marker (last day reconcile saw)
const T_BRIBE_PICK                := 17 * 60
# --- Exam/quiz scores (just values) ---
var scores1: int = 0
var scores2: int = 0

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
var integrity: int = 45
var reputation: int = 45

# -----------------------------
# Gameplay
# -----------------------------
var inventory: Array = []
var features_unlocked: Dictionary = {}
var subject1: String = ""
var subject2: String = ""
var flags: Dictionary = {}   # canonicalized keys only (via Flags.canon)
var master_volume: float = 0.8     # linear 0..1
var master_muted: bool = false
var music_volume: float = 0.8   # linear 0..1
var music_muted: bool = false

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
	"science":    "Study/Science.json",
	"geography":  "Study/Geography.json",
	"math":       "Study/Math.json",
	"macedonian": "Study/Macedonian.json",
	"english":    "Study/English.json",
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
	GameState.location =" YCO"
func begin_game(day_start: int, time_start: int) -> void:
	_init_default_flags()
	day = day_start
	time = time_start
	_one_am_paused = false
	_emit_time_changed()               # <— wrapper ensures MVR reconcile happens
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

	_emit_time_changed()  # <— unified emit (runs reconcile first)

func _format_time() -> String:
	var hours: int = int(time / 60) % 24   # 24h loop, safe cast
	var minutes: int = int(time % 60)
	return "%02d:%02d" % [hours, minutes]

# ---- central wrapper: reconcile first, then emit ----
func _emit_time_changed() -> void:
	reconcile_mvr_wait_progress()
	reconcile_submission_deadline() 
	emit_signal("time_changed", time, day)

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
		_emit_time_changed()   # <— wrapper
		return

	time = new_time
	day = new_day
	_emit_time_changed()       # <— wrapper

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

# ...everything else in GameState.gd stays the same...

func sleep_now() -> void:
	# Discrete wake times based on when you go to sleep
	# 22:00–22:59  -> 08:00
	# 23:00–23:59  -> 08:15
	# 00:00–01:00  -> 08:30  (same calendar day; day already advanced at midnight)
	# <22:00       -> 07:30
	var wake: int = 7 * 60 + 30

	if time >= 22 * 60 and time < 23 * 60:
		wake = 8 * 60
	elif time >= 23 * 60 and time < 24 * 60:
		wake = 8 * 60 + 15
	elif time >= 0 and time <= ONE_AM_MINUTES:
		wake = 8 * 60 + 30

	# Advance the calendar ONLY if we are NOT already past midnight.
	# If time is 00:00..01:00, the day has already rolled — don't add another.
	var should_advance_day := time > ONE_AM_MINUTES
	if should_advance_day:
		day += 1

	time = wake

	# Clear the 01:00 pause so the new day ticks normally
	_one_am_paused = false
	_emit_time_changed()
	print("🛌 Slept. Wake at %s (Day %d)" % [_format_time(), day])

# Optional: ask the GameState what today's school entry status is,
# based on current clock (call this right after waking to decide UI locks).
func morning_entry_status() -> String:
	# < 08:15  -> "regular"
	# < 08:30  -> "late"
	# >=08:30  -> "closed"
	var t := time
	if t < 8 * 60 + 15:
		return "regular"
	elif t < 8 * 60 + 30:
		return "late"
	return "closed"

# Optional helper if you want to resume ticking without sleeping
func resume_after_one_am() -> void:
	_one_am_paused = false

# 01:00 sequence: show JSON warning (Narrator), then go Home. No locks.
func _handle_one_am_sequence() -> void:
	var dm := get_node_or_null("/root/DialogueManager")
	if dm == null or not dm.has_method("start_dialogue"):
		push_error("DialogueManager not found or missing start_dialogue; cannot show 01:00 JSON.")
		# Still go Home to avoid softlock
		location = "Home"
		var err := get_tree().change_scene_to_file(HOME_SCENE_PATH)
		if err != OK:
			push_error("01:00 teleport to Home failed with code: %s" % [str(err)])
		return

	# Start the JSON dialogue exactly like the rest of your project
	var path = GameState.get_data_path(J_ONE_AM)
	var ui = dm.start_dialogue(path, self)


	# Prefer awaiting the UI's own 'dialogue_finished' if present
	var waited := false
	if ui and ui.has_signal("dialogue_finished"):
		await ui.dialogue_finished
		waited = true
	elif dm.has_signal("dialogue_finished"):
		# Manager emits dialogue_finished(id). Await the next finish.
		await dm.dialogue_finished
		waited = true

	# If nothing to await, just continue (dialogue may be non-blocking)
	if not waited:
		await get_tree().process_frame

	# After the JSON is over, send the player Home
	location = "Home"
	var err2 := get_tree().change_scene_to_file(HOME_SCENE_PATH)
	if err2 != OK:
		push_error("01:00 teleport to Home failed with code: %s" % [str(err2)])
	
func apply_dialogue_time_cost(minutes: int, _dlg_id: String = "") -> void:
	# Respect the 01:00 pause: if a dialogue ends after 01:00, keep time paused.
	if _one_am_paused:
		return
	adjust_time(minutes)

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
	var act: String = (line.get("action", "") as String)

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

	# Localized subjects (quick & dirty map)
	if current_locale == "mk":
		var dict := {
			"science":    "Природни Науки",
			"geography":  "Географија",
			"math":       "Математика",
			"macedonian": "Македонски",
			"english":    "Англиски"
		}
		var s1 := subject1
		var s2 := subject2
		if dict.has(s1): s1 = dict[s1]
		if dict.has(s2): s2 = dict[s2]
		s = s.replace("{subject1}", s1).replace("{subject2}", s2)
		s = s.replace("[Subject 1]", s1).replace("[Subject 2]", s2)
	else:
		# Default English
		s = s.replace("{subject1}", subject1.capitalize())
		s = s.replace("{subject2}", subject2.capitalize())
		s = s.replace("[Subject 1]", subject1.capitalize())
		s = s.replace("[Subject 2]", subject2.capitalize())

	# Missed days placeholder
	var ndays := str(get_missed_morning_count())
	s = s.replace("{ndays}", ndays)
# Birth certificate ETA (UPPERCASE)
	var bcert_days := str(days_until_birth_cert_ready())
	s = s.replace("{NDAYS}", bcert_days)

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

	var rel: String = String(study_paths.get(subject, ""))
	if rel == "":
		push_error("Study pool missing for subject: " + subject)
		return []

	var path: String = GameState.get_data_path(rel)
	if not FileAccess.file_exists(path):
		push_error("Study pool file not found: " + path)
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

# ------------------------ MVR reconcile (one-shot per route) ------------------------
func reconcile_mvr_wait_progress() -> void:
	var method := get_int(K_MVR_METHOD, 0)   # 1=Standard, 2=Expedited, 3=Bribery
	var ready  := get_int(K_MVR_READY_DAY, 0)

	# No active request or already finished → reset markers and exit.
	if method == 0 or ready <= 0 or has_flag(Flags.HAVE_BIRTH_CERTIFICATE):
		set_int(K_MVR_LAST_WAIT_BUMP_DAY, 0)
		set_flag(K_MVR_BRIBE_WAIT_BUMPED, false)
		set_int(K_MVR_LAST_CHECK_DAY, day)
		return

	# -------- Standard (3-day) & Expedited (1-day) --------
	# Exactly one bump when we've reached the ready calendar day.
	if method == 1 or method == 2:
		var last := get_int(K_MVR_LAST_WAIT_BUMP_DAY, 0)
		if day >= ready and last < ready:
			ensure_task("birth")
			update_task_step("birth")
			set_int(K_MVR_LAST_WAIT_BUMP_DAY, ready)

	# -------- Bribery (same-day @ 17:00 or later) --------
	if method == 3 and not has_flag(K_MVR_BRIBE_WAIT_BUMPED):
		# Case A: on ready day, at/after 17:00
		if day == ready and time >= T_BRIBE_PICK:
			ensure_task("birth")
			update_task_step("birth")
			set_flag(K_MVR_BRIBE_WAIT_BUMPED, true)
		# Case B: player skipped past the window (day already advanced)
		elif day > ready:
			ensure_task("birth")
			update_task_step("birth")
			set_flag(K_MVR_BRIBE_WAIT_BUMPED, true)

	# Record that we've reconciled for today's date
	set_int(K_MVR_LAST_CHECK_DAY, day)

const KEY_MISSED_MORNING_COUNT := "missed_morning_count"

func get_missed_morning_count() -> int:
	return get_int(KEY_MISSED_MORNING_COUNT, 0)
# ==========================
# Localization support
# ==========================

# Current language code ("en", "mk", etc.)
var current_locale: String = "en"

# Get JSON path depending on language
func get_data_path(relative: String) -> String:
	var base = "res://Data/"
	if current_locale == "mk":
		base = "res://DataMK/"   # or Data2/, whatever you name it
	return base + relative

# Switch language at runtime
signal locale_changed(new_locale: String)
func switch_locale(new_locale: String) -> void:
	current_locale = new_locale
	TranslationServer.set_locale(new_locale)  # flips all tr() UI strings
	print("Locale switched to:", new_locale)
	locale_changed.emit(new_locale)
# ---------- Background Music (single track, manual play/stop) ----------
var music_path: String = "res://Audio/BackgroundTheme.mp3"
var _music_player: AudioStreamPlayer = null
var _music_started: bool = false

func start_bg_music() -> void:
	if _music_started:
		return

	if _music_player == null:
		_music_player = AudioStreamPlayer.new()
		_music_player.bus = "Music"  # optional: your audio bus
		add_child(_music_player)

		var stream := load(music_path)
		if stream is AudioStream:
			stream.loop = true   # ✅ direct property, no has_property check
			_music_player.stream = stream
		else:
			push_error("Failed to load music: " + music_path)
			return

	_music_player.play()
	_music_started = true


func stop_bg_music() -> void:
	if _music_player and _music_player.playing:
		_music_player.stop()
	_music_started = false

func days_until_birth_cert_ready() -> int:
	var method := get_int(K_MVR_METHOD, 0)          # 1/2/3 if active
	var ready  := get_int(K_MVR_READY_DAY, 0)       # target day
	# If no active request, or already picked up, show 0.
	if method == 0 or ready <= 0 or has_flag(Flags.HAVE_BIRTH_CERTIFICATE):
		return 0
	var rem := ready - day
	return rem if rem > 0 else 0
func push_exam_score_value(score: int) -> void:
	if scores1 == 0:
		scores1 = score
	else:
		scores2 = score
		
		
const DEADLINE_DAY := 5
const DEADLINE_MINUTE := 19 * 60 + 15   # 19:01
const ENDINGS_SCENE_PATH := "res://Scenes/ENDINGS.tscn"  # <-- set your real path
const FLAG_APP_SUBMITTED := "application_submitted"
const FLAG_SUBMISSION_FAILED := "submission_failed"
var _deadline_triggered: bool = false

func reconcile_submission_deadline() -> void:
	if _deadline_triggered:
		return

	var past_deadline := (day > DEADLINE_DAY) or (day == DEADLINE_DAY and time >= DEADLINE_MINUTE)
	if not past_deadline:
		return

	# Only mark failure if no submission was made
	if has_flag(FLAG_APP_SUBMITTED):
		return

	_deadline_triggered = true
	set_flag(FLAG_SUBMISSION_FAILED, true)
	time_running = false  # stop ticking to avoid re-entry

	var err := get_tree().change_scene_to_file(ENDINGS_SCENE_PATH)
	if err != OK:
		push_error("Failed to load endings scene: %s" % str(err))
