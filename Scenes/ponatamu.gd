extends Button

@onready var audio : AudioStreamPlayer2D = get_node("/root/Intro/Panel/AudioStreamPlayer2D")
@onready var tekst : RichTextLabel = get_node("/root/Intro/Panel/RichTextLabel")
@onready var aud : AudioStreamPlayer2D = $Click_sound
@onready var timer_end : Timer = $end

func _ready() -> void:
	self.modulate.a = 0.0

func _on_timer_timeout() -> void:
	var tween : Tween = create_tween()
	tween.tween_property(self, "modulate:a", 1, 1.0).set_trans(Tween.TRANS_EXPO)

func _pressed() -> void:
	aud.play()
	var tween : Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0, 0.5).set_trans(Tween.TRANS_EXPO)
	await tween.finished
	create_tween().tween_property(tekst, "modulate:a", 0, 0.5).set_trans(Tween.TRANS_EXPO)
	timer_end.start()

func _on_end_timeout() -> void:
	get_tree().change_scene_to_file("res://Scenes/StartEvent.tscn")

#optimizirano
