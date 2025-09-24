# res://Scripts/Scenes/SocialMediaKillTime.gd
extends Control

const HOME_SCENE: String = "res://Scenes/Reusable/Map/Home.tscn"

# Relative JSON ID under Data/ (no res:// prefix here)
@export var JSON_ID: String = "Activities/SocialMedia_KillTime.json"

func _ready() -> void:
	GameState.location = "SocialMedia"

	# Always resolve via GameState
	var json_path: String = GameState.get_data_path(JSON_ID)
	var ui: Node = DialogueManager.start_dialogue(json_path, self)
	if ui and ui.has_signal("dialogue_finished"):
		await ui.dialogue_finished

	# JSON has "post_time_cost_minutes" and DialogueManager applies it.
	await fade.fade_to_scene(HOME_SCENE)
