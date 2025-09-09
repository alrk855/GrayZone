extends Camera2D

@export var slide_width: int = 1920
@export var slide_count: int = 8          # you said 1/8 → 8/8
@export var move_duration: float = 0.45

signal move_started(new_index: int)
signal move_finished(new_index: int)

var current_index: int = 0
var _moving: bool = false
var _tween: Tween
var _base_x: float = 0.0

func _ready() -> void:
	# Keep your initial placement as the “base”
	_base_x = position.x

func can_move() -> bool:
	return not _moving

func go_left() -> void:
	go_to(current_index - 1)

func go_right() -> void:
	go_to(current_index + 1)

func go_to(index: int) -> void:
	if _moving:
		return

	# Wrap around
	if index < 0:
		index = slide_count - 1
	elif index >= slide_count:
		index = 0

	if index == current_index:
		return

	_moving = true
	emit_signal("move_started", index)
	current_index = index

	var target_x: float = _base_x + float(slide_width * current_index)

	if _tween and is_instance_valid(_tween):
		_tween.kill()

	_tween = create_tween()
	_tween.tween_property(self, "position:x", target_x, move_duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.finished.connect(func ():
		_moving = false
		emit_signal("move_finished", current_index)
	)
