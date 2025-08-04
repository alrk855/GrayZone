extends Control

@onready var choices_box := $choices_box
@onready var choice_buttons := [
	choices_box.get_node("Button"),
	choices_box.get_node("Button2"),
	choices_box.get_node("Button3"),
	choices_box.get_node("Button4"),
	choices_box.get_node("Button5")
]

var choice_callback: Callable = Callable()

func _ready():
	hide_all()

func show_options(options: Array, callback: Callable):
	choice_callback = callback
	hide_all()

	for i in options.size():
		if i >= choice_buttons.size():
			continue

		var btn = choice_buttons[i]
		var option_data = options[i]

		btn.text = option_data.get("text", "Option")
		btn.visible = true

		# Prevent multiple connections
		if btn.is_connected("pressed", Callable(self, "_on_button_pressed")):
			btn.disconnect("pressed", Callable(self, "_on_button_pressed"))
		btn.pressed.connect(_on_button_pressed.bind(option_data.get("id", str(i))))

	self.visible = true

func _on_button_pressed(option_id):
	self.visible = false
	if choice_callback:
		choice_callback.call(option_id)

func hide_all():
	for b in choice_buttons:
		b.visible = false
	self.visible = false
