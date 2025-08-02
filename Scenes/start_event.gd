extends Control

func _ready():
	GameState.location = "Classroom"
	DialogueManager.start_dialogue("res://Dialogue/prologue.json")
