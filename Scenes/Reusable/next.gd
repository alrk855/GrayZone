extends Button

var pager: Node = null

func _ready() -> void:
	# 👇 replace this with your actual node path to the Camera2D
	pager = get_node("../../Camera2D")

	pressed.connect(_on_pressed)

	if pager:
		pager.connect("move_started", Callable(self, "_on_move_started"))
		pager.connect("move_finished", Callable(self, "_on_move_finished"))

func _on_pressed() -> void:
	if pager and pager.can_move():
		pager.go_right()

func _on_move_started(_idx: int) -> void:
	disabled = true

func _on_move_finished(_idx: int) -> void:
	disabled = false
