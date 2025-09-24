extends Button

@onready var hover_sound : AudioStreamPlayer2D = $"../../Click"
@onready var click_sound : AudioStreamPlayer2D = $"../../Click"

func _on_mouse_entered() -> void:
	hover_sound.play()

func _pressed() -> void:
	click_sound.play()
	GameState.switch_locale("en")   # force English
