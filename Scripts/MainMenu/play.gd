extends Control 


@onready var hover_sound : AudioStreamPlayer2D = $"../../Hover"
@onready var click_sound : AudioStreamPlayer2D = $"../../Click"
@onready var main : Node2D = $"/root/Game/main_menu"
func _ready():
	pass
func _on_mouse_entered() -> void:
	hover_sound.play()

func _pressed()-> void:
	click_sound.play()
	var twn = create_tween()
	twn.tween_property(main, "modulate", Color(0, 0, 0, 1), 2)
	await twn.finished
	get_tree().change_scene_to_file("res://Scenes/player_setup.tscn")
