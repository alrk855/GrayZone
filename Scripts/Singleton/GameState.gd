extends Node

signal system_message(msg: String)
signal clock_started
signal clock_stopped
signal day_advanced(new_day: int, reason: String)
signal task_added(task_id: String)
signal task_updated(task_id: String, step_index: int)
signal flag_changed(flag_id: String, value: bool)
signal money_changed(new_value: int)

var player_name: String = ""
var player_gender: String = ""
var location: String = "Unknown"

var time: int = 12 * 60 + 45
var day: int = 1
var time_speed: float = 2.0
var time_running: bool = false

var money: int = 0
var integrity: int = 0
var reputation: int = 0

var inventory: Array = []
var features_unlocked: Dictionary = {}
var subject1: String = ""
var subject2: String = ""
var flags: Dictionary = {}

var tasks: Array[String] = []
var task_step_index: Dictionary = {}

var task_counters: Dictionary = {}

var PRICES: Dictionary = { "print": 10, "janitor_answer": 100 }

var _timer: Timer
var _freeze_reasons: Array[String] = []

const BASE_WAKE_MINUTES := 7 * 60 + 30
const CURFEW_START_MINUTES := 23 * 60
const FREEZE_AT_MINUTES := 1 * 60

var sleep_freeze_active: bool = false
var home_tasks_locked: bool = false
var overtime_minutes_counter: int = 0

func _ready():
	_timer = Timer.new()
	_timer.name = "TimeTick"
	_timer.wait_time = time_speed
	_timer.one_shot = false
	_timer.autostart = false
	_timer.timeout.connect(_on_minute_passed)
	add_child(_timer)
	print("📂 GameState Ready — timer idle at %s (Day %d)" % [_format_time(), day])

# ---------- Clock ----------
func begin_game(start_day: int = day, start_time_minutes: int = time):
	day = start_day
	time = start_time_minutes
	time_running = true
	_recompute_clock_state()
	emit_signal("system_message", "▶️ Game started at %s (Day %d)" % [_format_time(), day])

func stop_clock(): time_running = false; _recompute_clock_state()
func start_clock(): time_running = true; _recompute_clock_state()

func push_time_freeze(reason: String = "generic"):
	if not _freeze_reasons.has(reason):
		_freeze_reasons.append(reason)
	_recompute_clock_state()
	print("⏸️ Freeze ON:", reason, "stack:", _freeze_reasons)

func pop_time_freeze(reason: String = "generic"):
	_freeze_reasons.erase(reason)
	_recompute_clock_state()
	print("▶️ Freeze OFF:", reason, "stack:", _freeze_reasons)

func is_time_frozen() -> bool:
	return _freeze_reasons.size() > 0 or not time_running or sleep_freeze_active

func _recompute_clock_state():
	var should_tick := time_running and _freeze_reasons.is_empty() and not sleep_freeze_active
	if should_tick:
		if _timer.is_stopped():
			_timer.start(); emit_signal("clock_started")
	else:
		if not _timer.is_stopped():
			_timer.stop(); emit_signal("clock_stopped")

func _on_minute_passed():
	if not time_running: return
	time += 1
	if time >= 24 * 60:
		time = 0; day += 1; emit_signal("day_advanced", day, "midnight")
	if time >= CURFEW_START_MINUTES or time < FREEZE_AT_MINUTES:
		overtime_minutes_counter += 1
	if time == FREEZE_AT_MINUTES and not sleep_freeze_active:
		time_running = false; sleep_freeze_active = true; home_tasks_locked = true
		_recompute_clock_state()
		print("⏸️ Curfew freeze active — sleep required.")
	print("🕒 Time:", _format_time(), " | OT:", overtime_minutes_counter, "min")

func _format_time() -> String:
	var h: int = time / 60; var m: int = time % 60
	return "%02d:%02d" % [h, m]

func adjust_time(value: int):
	var prev_day := day
	time += value
	while time >= 24 * 60: time -= 24 * 60; day += 1
	while time < 0: time += 24 * 60; day = max(1, day - 1)
	if day != prev_day: emit_signal("day_advanced", day, "manual_adjust")
	print("⏱️ Time adjusted by %d → %s (Day %d)" % [value, _format_time(), day])

func apply_dialogue_time_cost(minutes: int, label: String = "dialogue"):
	if minutes <= 0: return
	adjust_time(minutes)
	var msg := "🕒 +%d min spent in %s → %s" % [minutes, label, _format_time()]
	print(msg); emit_signal("system_message", msg)

# ---------- Sleep ----------
func can_do_home_task() -> bool: return not home_tasks_locked
func is_sleep_needed() -> bool: return sleep_freeze_active or time >= CURFEW_START_MINUTES or time < FREEZE_AT_MINUTES
func get_sleep_penalty_minutes() -> int: return int(ceil(overtime_minutes_counter / 4.0))

func sleep_now():
	var penalty := get_sleep_penalty_minutes()
	var wake_minutes := BASE_WAKE_MINUTES + penalty
	if not (time < FREEZE_AT_MINUTES): day += 1; emit_signal("day_advanced", day, "sleep")
	time = min(wake_minutes, 24 * 60 - 1)
	overtime_minutes_counter = 0; sleep_freeze_active = false; home_tasks_locked = false
	time_running = true; _recompute_clock_state()
	var msg := "😴 You slept. Wake-up at %s (penalty +%d min)." % [_format_time(), penalty]
	print(msg); emit_signal("system_message", msg)

# ---------- Tasks / Flags ----------
func _norm_id(id: String) -> String: return id.strip_edges()

func ensure_task(task_id: String) -> void:
	var c := _norm_id(task_id)
	if not tasks.has(c):
		tasks.append(c)
		if not task_step_index.has(c): task_step_index[c] = 0
		print("➕ Task added:", c)
		emit_signal("task_added", c)

func add_task(task_id: String):
	var c := _norm_id(task_id)
	if not tasks.has(c):
		tasks.append(c); task_step_index[c] = 0
		print("➕ Task added:", c)
		emit_signal("task_added", c)

func update_task_step(task_id: String):
	var c := _norm_id(task_id)
	if not task_step_index.has(c): task_step_index[c] = 0
	task_step_index[c] += 1
	print("✅ Step advanced to index", task_step_index[c], "in", c)
	emit_signal("task_updated", c, task_step_index[c])

func get_task_progress(task_id: String) -> int:
	return int(task_step_index.get(_norm_id(task_id), 0))

func inc_task_counter(task_id: String, key: String, amount: int = 1) -> int:
	var c := _norm_id(task_id)
	var d: Dictionary = task_counters.get(c, {})
	var v: int = int(d.get(key, 0)) + amount
	d[key] = v; task_counters[c] = d; return v

func get_task_counter(task_id: String, key: String, default_value: int = 0) -> int:
	return int(task_counters.get(_norm_id(task_id), {}).get(key, default_value))

func set_flag(flag_id: String, value: bool = true) -> void:
	var old := bool(flags.get(flag_id, false))
	flags[flag_id] = value
	if old != value: emit_signal("flag_changed", flag_id, value)

func clear_flag(flag_id: String) -> void: set_flag(flag_id, false)
func has_flag(flag_id: String) -> bool: return bool(flags.get(flag_id, false))

func format_placeholders(s: String) -> String:
	return s.format({ "subject1": subject1, "subject2": subject2 })

func apply_action(line: Dictionary) -> void:
	var act: String = String(line.get("action", ""))
	match act:
		"add_task":
			for t in line.get("tasks", []): add_task(String(t))
		"update_task_step":
			update_task_step(String(line.get("task", "")))
		"set_flags":
			for f in line.get("flags", []): set_flag(String(f), true)
		"clear_flags":
			for f in line.get("flags", []): clear_flag(String(f))
		"money":
			var delta: int = int(line.get("delta", 0))
			money += delta; emit_signal("money_changed", money); emit_signal("system_message", "💰 Money: " + str(money))
		"adjust_time":
			adjust_time(int(line.get("value", 0)))
		"unlock_feature":
			unlock_game_feature(String(line.get("feature", "")))
		_:
			print("⚠ Unknown action:", act)

# ---------- Features ----------
func unlock_game_feature(feature_id: String, limit: Variant = null):
	if not features_unlocked.has(feature_id):
		features_unlocked[feature_id] = {}
	if limit != null:
		(features_unlocked[feature_id] as Dictionary)["limit"] = limit
	print("🔓 Feature unlocked:", feature_id, "Limit:", limit)

func has_feature(feature_id: String) -> bool: return features_unlocked.has(feature_id)
