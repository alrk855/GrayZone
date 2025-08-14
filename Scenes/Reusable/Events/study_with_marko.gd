extends Control

const STUDY_SCENE_PATH: String       = "res://Scenes/Reusable/Tasks/Study.tscn"
const RETURN_SCENE_FALLBACK: String  = "res://Scenes/Reusable/Events/MarkoFirstEvent.tscn"
const SUBJECT_PICK_DEFAULT: String   = "subject1"

const COUNT_AS_STUDY: bool = true
const TIME_MIN: int = 30

const KEY_STUDY_MODE: String   = "__study_mode"
const KEY_SUBJECT_PICK: String = "__study_subject_pick"
const KEY_RETURN_SCENE: String = "__study_return_scene"

func _ready() -> void:
	GameState.location = "MarkoStudy"

	# Force Marko mode + Subject 1 for this flow
	var pick := SUBJECT_PICK_DEFAULT
	GameState.features_unlocked[KEY_STUDY_MODE] = "marko"
	GameState.features_unlocked[KEY_SUBJECT_PICK] = pick

	# Remember where to return after Done
	var ret_path: String = ""
	if get_tree() and get_tree().current_scene:
		ret_path = String(get_tree().current_scene.get_scene_file_path())
	if ret_path.strip_edges() == "":
		ret_path = RETURN_SCENE_FALLBACK
	GameState.features_unlocked[KEY_RETURN_SCENE] = ret_path

	# Count as a study session (Subject 1)
	if COUNT_AS_STUDY:
		var subject_raw: String = GameState.subject1
		if subject_raw.strip_edges() == "":
			subject_raw = GameState.subject1
		GameState.count_study_if_new(subject_raw, TIME_MIN)

	get_tree().change_scene_to_file(STUDY_SCENE_PATH)
