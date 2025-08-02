extends Button

@onready var camera = $"../../../../../../../Camera2D"
@onready var swoosh = $"../Swoosh"
@export var transit: Tween.TransitionType

var is_moving := false  # prevents spam

func _pressed():
	if is_moving:
		return

	is_moving = true
	swoosh.play()

	var target_position = camera.position - Vector2(0, 1080)
	var tween = create_tween()
	tween.tween_property(camera, "position", target_position, 1.0).set_trans(transit)
	tween.finished.connect(_on_tween_finished)

func _on_tween_finished():
	is_moving = false
