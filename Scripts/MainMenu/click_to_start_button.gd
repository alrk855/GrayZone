extends Button

@onready var camera: Camera2D = $"../../../Camera2D"
@onready var menu_container: Control = $"../../../Main_Menu_Control/Main_Menu_Picture/V_Button_Container"
@onready var orn1: Control = $"../../../Main_Menu_Control/Main_Menu_Picture/OrnamentsL"
@onready var orn2: Control =$"../../../Main_Menu_Control/Main_Menu_Picture/OrnamentsR"
@onready var main_orn: Control = $"../../../Main_Menu_Control/Main_Menu_Picture/HBoxContainer/MainOrnament"
@onready var swoosh: AudioStreamPlayer2D = $"../Swoosh"

@export var transit: Tween.TransitionType
var triggered: bool = false

func _ready():
	main_orn.modulate.a = 0.0
	# FADE MAIN ORNAMENT INITIALLY INVISIBLE


func _pressed():
	if triggered:
		return
	triggered = true
	swoosh.play(0)

	var target_position = camera.position + Vector2(0, 1080)

	var tween = create_tween()

	# Step 1: Move camera down
	tween.tween_property(camera, "position", target_position, 1.0).set_trans(transit)

	# Step 2: Ornaments slide in AFTER camera
	tween = tween.chain()

	var vbox_pos = menu_container.global_position
	var vbox_size = menu_container.size

	var orn1_target_x = vbox_pos.x + 240
	var orn2_target_x = vbox_pos.x + vbox_size.x - 230 - orn2.size.x

	tween.tween_property(orn1, "global_position:x", orn1_target_x, 1.5).set_trans(transit)
	tween.parallel().tween_property(orn2, "global_position:x", orn2_target_x, 1.5).set_trans(transit)

	# Step 3: Main ornament fade in after ornaments
	tween = tween.chain()
	tween.tween_property(main_orn, "modulate:a", 1.0, 1.0).set_trans(transit)
