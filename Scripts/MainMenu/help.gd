extends Control  # Use Button if you're attaching directly to one

@onready var tween := create_tween()
@onready var original_pos := position

func _ready():
	var offset := 2  # pixel distance in all directions
	var duration := 1.0  # time per corner

	tween.set_loops()  # Infinite loop

	tween.tween_property(self, "position", original_pos + Vector2(offset, -offset), duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)  # Top-right

	tween.tween_property(self, "position", original_pos + Vector2(offset, offset), duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)  # Bottom-right

	tween.tween_property(self, "position", original_pos + Vector2(-offset, offset), duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)  # Bottom-left

	tween.tween_property(self, "position", original_pos + Vector2(-offset, -offset), duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)  # Top-left

	tween.tween_property(self, "position", original_pos, duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)  # Return to center
