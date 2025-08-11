extends Button

@export var reason: String = "test_button_freeze"

var _my_freeze_on: bool = false

func _ready() -> void:
	pressed.connect(_on_pressed)
	_update_label()

func _on_pressed() -> void:
	# Toggle only *our* freeze reason; other freezes may still be active
	if _my_freeze_on:
		GameState.pop_time_freeze(reason)
		_my_freeze_on = false
		print("▶️ Unfreeze (%s). is_time_frozen=%s" % [reason, str(GameState.is_time_frozen())])
	else:
		GameState.push_time_freeze(reason)
		_my_freeze_on = true
		print("⏸️ Freeze ON (%s). is_time_frozen=%s" % [reason, str(GameState.is_time_frozen())])

	_update_label()

func _update_label() -> void:
	if _my_freeze_on:
		text = "Unfreeze Time (test)"
	else:
		text = "Freeze Time (test)"
