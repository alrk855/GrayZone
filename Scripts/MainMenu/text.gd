extends RichTextLabel

@onready var anim_player: AnimationPlayer = $"../AnimationPlayer"

func _ready() -> void:
	await get_tree().process_frame
	var anim : Animation = anim_player.get_animation("Fade")
	
	anim.loop_mode = Animation.LOOP_PINGPONG  # Goes forward then backward
	
	anim_player.play("Fade")
