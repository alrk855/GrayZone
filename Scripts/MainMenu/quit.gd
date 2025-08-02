extends Button  # Use Button if you're attaching directly to one


@onready var hover_sound : AudioStreamPlayer2D = $"../../Hover"
@onready var click_sound : AudioStreamPlayer2D = $"../../Click"

func _ready():
	pass
func _on_mouse_entered() -> void:
	hover_sound.play()
	
func _pressed():
	click_sound.play()
	if Engine.is_editor_hint():
		print("Exiting play mode (editor)...")
		get_tree().quit()  # Ends the play session in editor
	else:
		print("Quitting game...")
		get_tree().quit()  # Exits the exported game normally
