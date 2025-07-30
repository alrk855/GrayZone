extends TextureRect

@onready var pan : TextureRect = $"."

func _ready() -> void:
	pan.modulate.a = 0.0

	# Now fade in to alpha = 1 over 2 seconds
	create_tween().tween_property(pan, "modulate:a", 1.0, 2)
