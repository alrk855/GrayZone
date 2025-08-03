extends Node

# === Time & Calendar ===
var day: int = 1
var hour: int = 12
var minute: int = 35

# === Player Identity ===
var player_name: String = ""
var player_gender: String = ""

# === World Info ===
var location: String = "Unknown"  # Set by active scene

# === Stats ===
var money: int = 0
var integrity: int = 50
var reputation: int = 50

# === Gameplay Systems ===
var subject1: String
var subject2: String
var tasks: Array = []
var unlocked_features: Dictionary = {}  # e.g. { "study": true, "exam": true }

# === TIME CONTROL ===
func adjust_time(minutes_to_add: int):
	var total_minutes = hour * 60 + minute + minutes_to_add
	var wrapped_day = floor(total_minutes / 1440.0)  # Use float division then floor
	var new_minutes = total_minutes % 1440

	hour = int(new_minutes / 60)
	minute = new_minutes % 60

	if wrapped_day > 0:
		day += int(wrapped_day)
		print("New day: Day", day)

	print("Time advanced to %02d:%02d on Day %d" % [hour, minute, day])

# === TASK SYSTEM ===
func add_task(task: String):
	if task not in tasks:
		tasks.append(task)
		print("📌 Task added:", task)

# === FEATURE UNLOCKS ===
func unlock_game_feature(name: String):  # Renamed to avoid shadowing Node
	unlocked_features[name] = true
	print("🆓 Feature unlocked:", name)

# === REPUTATION ===
func adjust_reputation(amount: int):
	reputation = clamp(reputation + amount, 0, 100)

func adjust_integrity(amount: int):
	integrity = clamp(integrity + amount, 0, 100)

func adjust_money(amount: int):
	money += amount
