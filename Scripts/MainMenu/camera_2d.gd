extends Camera2D

@export var target_node: NodePath  # Drag Click_to_Start_Control here in the editor

func _ready():
	var target = get_node_or_null(target_node)
	if target:
		var screen_size = get_viewport().get_visible_rect().size
		# Camera centers on target’s top-left by adding half the screen
		position = target.global_position + (screen_size * 0.5)
