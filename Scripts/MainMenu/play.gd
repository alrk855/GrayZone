extends Control  # Use Button if you're attaching directly to one


@onready var hover_sound : AudioStreamPlayer2D = $"../../Hover"
@onready var click_sound : AudioStreamPlayer2D = $"../../Click"
func _ready():
	pass
func _on_mouse_entered() -> void:
	hover_sound.play()

func _pressed()-> void:
	click_sound.play()
	await click_sound.finished

	get_tree().change_scene_to_file("res://Scenes/player_setup.tscn")
