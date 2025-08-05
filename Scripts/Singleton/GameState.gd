### GameState.gd ###
extends Node

# --- Basic Player Info ---
var player_name := ""
var player_gender := ""
var location := "Unknown"

# --- Time & Day ---
var time := 13 * 60  # 13:00 in minutes
var day := 1
var time_speed := 2.0  # Real seconds per in-game minute
var time_running := true

# --- Status ---
var money := 0
var integrity := 0
var reputation := 0

# --- Gameplay Systems ---
var inventory: Array = []
var features_unlocked := {}  # feature_id: { limit = x }
var subject1 := ""
var subject2 := ""
var flags := {}  # ✅ Needed for secretary_met etc.

# --- Task Management ---
var tasks: Array = []  # Task IDs (e.g., "Visit Secretary")
var task_step_index: Dictionary = {}  # task_id: step_index (e.g., "gather_requirements": 2)

func _ready():
	print("📂 GameState Ready — Starting Time Simulation")
	_start_time_simulation()

# --- TIME SIMULATION ---
func _start_time_simulation():
	var timer = Timer.new()
	timer.name = "TimeTick"
	timer.wait_time = time_speed
	timer.autostart = true
	timer.one_shot = false
	timer.timeout.connect(_on_minute_passed)
	add_child(timer)

func _on_minute_passed():
	if time_running:
		time += 1
		if time >= 24 * 60:
			time = 0
			day += 1
			print("🌅 Day advanced to Day %d" % day)
		print("🕒 Time: " + _format_time())

func _format_time() -> String:
	var hours = time / 60
	var minutes = time % 60
	return "%02d:%02d" % [hours, minutes]

func adjust_time(value: int):
	time += value
	if time >= 24 * 60:
		time = 0
		day += 1
	elif time < 0:
		time = 0
	print("⏱️ Time adjusted by %d → %s" % [value, _format_time()])

# --- TASK SYSTEM ---
func add_task(task_id: String):
	if not tasks.has(task_id):
		tasks.append(task_id)
		task_step_index[task_id] = 0
		print("➕ Task added:", task_id)

func update_task_step(task_id: String):
	if not task_step_index.has(task_id):
		task_step_index[task_id] = 0
	task_step_index[task_id] += 1
	print("✅ Step advanced to index", task_step_index[task_id], "in", task_id)

func get_task_progress(task_id: String) -> int:
	return task_step_index.get(task_id, 0)

# --- FEATURE SYSTEM ---
func unlock_game_feature(feature_id: String, limit: Variant = null):
	if not features_unlocked.has(feature_id):
		features_unlocked[feature_id] = {}
	if limit != null:
		features_unlocked[feature_id]["limit"] = limit
	print("🔓 Feature unlocked:", feature_id, "Limit:", limit)

func has_feature(feature_id: String) -> bool:
	return features_unlocked.has(feature_id)
