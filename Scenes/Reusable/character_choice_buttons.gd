extends Control 

@onready var choices_box := $"Choice Control Node/ChoiceBox"
@onready var choice_buttons := [
	choices_box.get_node("Button"),
	choices_box.get_node("Button2"),
	choices_box.get_node("Button3"),
	choices_box.get_node("Button4"),
	choices_box.get_node("Button5")
]

var choice_callback: Callable = Callable()

# --- SFX (add your files in the Inspector) ---
@export var hover_sound: AudioStream
@export var press_sound: AudioStream
var _hover_player: AudioStreamPlayer
var _press_player: AudioStreamPlayer
# ---------------------------------------------

func _ready():
	# Create lightweight audio players (Master bus by default)
	_hover_player = AudioStreamPlayer.new()
	add_child(_hover_player)

	_press_player = AudioStreamPlayer.new()
	add_child(_press_player)

	# Connect hover/press once for each button (separate from your option handler)
	for b in choice_buttons:
		if b:
			if not b.is_connected("mouse_entered", Callable(self, "_on_btn_mouse_entered")):
				b.connect("mouse_entered", Callable(self, "_on_btn_mouse_entered"))
			if not b.is_connected("pressed", Callable(self, "_on_btn_pressed_sound")):
				b.connect("pressed", Callable(self, "_on_btn_pressed_sound"))

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

		# Prevent multiple connections (kept your pattern)
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

# ---------------------------
# SFX handlers (tiny & safe)
# ---------------------------
func _on_btn_mouse_entered():
	if hover_sound and _hover_player:
		_hover_player.stream = hover_sound
		_hover_player.play()

func _on_btn_pressed_sound():
	if press_sound and _press_player:
		_press_player.stream = press_sound
		_press_player.play()
