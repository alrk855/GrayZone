extends RichTextLabel

@onready var anim_player: AnimationPlayer = $"../../AnimationPlayer"

@export var fade_duration: float = 6.5
@export var reveal_time: float = 0.

func _ready() -> void:
	# Hide until reveal time
	visible = false
	
	# Wait (fade_duration - reveal_time) seconds
	await get_tree().create_timer(fade_duration - reveal_time).timeout
	
	# Show and play the fade animation
	visible = true
	var anim: Animation = anim_player.get_animation("Fade")
	anim.loop_mode = Animation.LOOP_PINGPONG
	anim_player.play("Fade")
