extends Control

# Path to your Study shell scene (with StudyShell.gd attached)
const STUDY_SCENE_PATH: String = "res://Scenes/Reusable/Tasks/Study.tscn"   # <-- set me

# If auto-detect fails, we’ll return here after Done:
const RETURN_SCENE_FALLBACK: String = "res://Scenes/Reusable/Events/StudyWithMarko.tscn" # <-- adjust if needed

# Which subject Marko is revealing right now by default:
const SUBJECT_PICK_DEFAULT: String = "subject1"   # "subject1" or "subject2"

# Count as a study session (+1 task, +30 min)?
const COUNT_AS_STUDY: bool = true
const TIME_MIN: int = 30

const KEY_STUDY_MODE: String    = "__study_mode"
const KEY_SUBJECT_PICK: String  = "__study_subject_pick"
const KEY_RETURN_SCENE: String  = "__study_return_scene"

func _ready() -> void:
	GameState.location = "MarkoStudy"

	# Subject pick: allow dialogue to pre-set it; otherwise use default
	var pick: String = String(GameState.features_unlocked.get(KEY_SUBJECT_PICK, SUBJECT_PICK_DEFAULT)).to_lower()
	GameState.features_unlocked[KEY_STUDY_MODE] = "marko"
	GameState.features_unlocked[KEY_SUBJECT_PICK] = pick

	# Auto-detect current scene path to return to; fallback constant if needed
	var ret_path: String = ""
	if get_tree() and get_tree().current_scene:
		ret_path = String(get_tree().current_scene.get_scene_file_path())
	if ret_path == "":
		ret_path = RETURN_SCENE_FALLBACK
	GameState.features_unlocked[KEY_RETURN_SCENE] = ret_path

	# Optional: count like a normal study
	if COUNT_AS_STUDY:
		var tid: String = "study_subject1"
		if pick == "subject2":
			tid = "study_subject2"
		GameState.update_task_step(tid)
		GameState.adjust_time(TIME_MIN)

	# Jump into the study shell (it will place the 2 finals at Q2/Q4)
	get_tree().change_scene_to_file(STUDY_SCENE_PATH)
