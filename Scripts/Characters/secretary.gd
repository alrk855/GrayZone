extends Button

func _ready():
	pass

func _pressed():
	get_tree().current_scene.start_interaction()
