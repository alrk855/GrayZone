extends Button

const DELTA_MINUTES: int = -30

func _ready() -> void:
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	GameState.adjust_time(DELTA_MINUTES)
	print("⏪ %d min → %s (Day %d)" % [DELTA_MINUTES, GameState._format_time(), GameState.day])
