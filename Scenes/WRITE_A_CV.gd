extends Control

@onready var target_text_label : Label = $mainbox/TargetText
@onready var input_field : TextEdit = $mainbox/Input
@onready var feedback_label : Label = $mainbox/Feedback

var target_text : Array[String] = ["Lorem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industry's standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book. It has survived not only five centuries, but also the leap into electronic typesetting, remaining essentially unchanged."]
var current_target : int = 0

func _ready():
	target_text_label.text = target_text[current_target]
	feedback_label.text = ""
	input_field.text = ""
	input_field.grab_focus()  # Autofocus on input field

func _on_PlayerInput_text_changed(new_text):
	if new_text == target_text:
		feedback_label.text = "✅ Correct!"
	elif target_text[current_target].begins_with(new_text):
		feedback_label.text = "✏️ Keep going..."
	else:
		feedback_label.text = "❌ Incorrect"

# Optional: when player presses Enter
func _process(_delta: float) -> void:
	if target_text[current_target] == input_field.text:
		feedback_label.text = "🎉 You did it!"
	else:
		feedback_label.text = "Try again!"
