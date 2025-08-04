extends Control

func _ready():
	GameState.location = "School"  # ✅ Required for TaskManager or other location-based logic
