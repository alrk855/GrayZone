extends RichTextLabel

@onready var modul : RichTextLabel = get_node("/root/Intro/Panel/RichTextLabel")
@export var transit : Tween.TransitionType
@onready var aud : AudioStreamPlayer2D = get_node("/root/Intro/Panel/AudioStreamPlayer2D")

func _ready() -> void:
	modul.modulate.a = 0.0

func _on_timer_timeout() -> void: 
	create_tween().tween_property(modul, "modulate:a", 1, 1,).set_trans(transit)

func _on_pop_timeout() -> void:
	aud.play()
	print("playing timeout")

#optimizirano
