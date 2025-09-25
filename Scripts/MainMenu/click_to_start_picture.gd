extends ColorRect

@export var fade_duration: float = 6.5
@export var menu_audio: AudioStreamPlayer

func _ready() -> void:
	# Start fully black and visible
	modulate.a = 1.0
	visible = true
	
	# Fade out over duration
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, fade_duration)
	
	# When done: hide and start audio
	tween.finished.connect(_on_fade_done)

func _on_fade_done() -> void:
	visible = false   # overlay no longer blocks input
