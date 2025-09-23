# res://Scripts/Scenes/SocialMediaKillTime.gd
extends Control

const JSON_PATH: String = "res://Data/Activities/SocialMedia_KillTime.json"
const HOME_SCENE: String = "res://Scenes/Reusable/Map/Home.tscn"  # your canonical Home

func _ready() -> void:
	GameState.location = "SocialMedia"
	var ui := DialogueManager.start_dialogue(JSON_PATH, self)
	if ui and ui.has_signal("dialogue_finished"):
		await ui.dialogue_finished
	# JSON has "post_time_cost_minutes": 120 so time is applied by DialogueManager -> GameState
	await fade.fade_to_scene(HOME_SCENE)
