# Splash.gd
extends Control
@export var next_scene: String = "res://Scenes/TitleScreen.tscn"
@onready var player: VideoStreamPlayer = $VideoStreamPlayer
@onready var audio: AudioStreamPlayer = $AudioStreamPlayer

func _ready() -> void:
	player.finished.connect(_on_video_finished)

func _input(event: InputEvent) -> void:
	if event.is_pressed():
		_end_splash()

func _on_video_finished() -> void:
	_end_splash()

func _end_splash() -> void:
	# Fade audio only, no global fade overlay
	var t := create_tween()
	t.tween_property(audio, "volume_db", -80.0, 0.3)
	await t.finished
	audio.stop()
	get_tree().change_scene_to_file(next_scene)
