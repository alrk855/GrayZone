extends Button
@onready var camera = $"../../../../../Camera2D"
@onready var swoosh =$"../../../../../Click_to_Start_Control/Click_To_Start_Picture/Swoosh"
@onready var hover_sound : AudioStreamPlayer2D = $"../../Hover"
@onready var click_sound : AudioStreamPlayer2D = $"../../Click"
@export var transit: Tween.TransitionType
func _pressed():

	swoosh.play()
	click_sound.play()
	var screen_height = get_viewport().get_visible_rect().size.y
	var target_position = camera.position + Vector2(0, screen_height)

	var tween = create_tween()

	# Step 1: Move camera down
	tween.tween_property(camera, "position", target_position, 1.0).set_trans(transit)
func _on_mouse_entered() -> void:
	hover_sound.play()
