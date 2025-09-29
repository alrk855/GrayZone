extends Control

signal quiz_finished(total: int, correct: int, score: int)

# ---------- Scene nodes ----------
@onready var question_label : Label = $ColorRect/Label
@onready var option_buttons : Array[Button] = [$"Option 1", $"Option 2", $"Option 3"]
@onready var score_label    : Label = $score
@onready var timer          : Timer = $Timer
@onready var timePAN        : Panel = $ColorRect/TimePanel
@onready var title_label    : Label = $Map

# ---------- Styling (drag & drop in Inspector) ----------
@export var theme_neutral : Theme
@export var theme_right   : Theme
@export var theme_wrong   : Theme

# ---------- Config ----------
@export var subject : String = ""            # e.g., "english" / "math"; set by Finals or Inspector
@export var mode    : String = "auto"        # "auto" | "legit" | "bought"
@export var seconds_per_question : float = 10.0
@export var points_per_correct   : int = 10

# ---------- Auto-return to Finals when opened standalone ----------
@export var auto_return_to_finals : bool = true
@export var finals_scene_path     : String = "res://Scenes/Finals.tscn"
@export var auto_return_delay     : float = 1.25

# ---------- Keys / Flags ----------
const K_FINALS_COUNTER    := "__finals_counter"      # 0 -> 1 -> 2
const K_QUIZ_SUBJECT_KEY  := "__quiz_subject_key"    # string
const K_QUIZ_MODE         := "__quiz_mode"           # "legit" | "bought"
const BOUGHT_ANSWERS_S1   := "bought_answers_s1"
const BOUGHT_ANSWERS_S2   := "bought_answers_s2"

# ---------- Runtime state ----------
var _paper : Array = []   # [{ id, q, choices:Array[String], correct_index:int }]
var _idx   : int = 0
var _correct_count : int = 0
var _score : int = 0
var _timebar_full_width : float = 0.0
var _timebar_full_height : float = 0.0
var _bought_mode : bool = false
var _clicks_enabled : bool = false

func _ready() -> void:
	# Prefer Finals-provided config (overrides Inspector values)
	if GameState and GameState.features_unlocked.has(K_QUIZ_SUBJECT_KEY):
		subject = String(GameState.features_unlocked[K_QUIZ_SUBJECT_KEY])
		GameState.features_unlocked.erase(K_QUIZ_SUBJECT_KEY)
	if GameState and GameState.features_unlocked.has(K_QUIZ_MODE):
		mode = String(GameState.features_unlocked[K_QUIZ_MODE])
		GameState.features_unlocked.erase(K_QUIZ_MODE)

	_set_title_from_subject()

	# Load questions (prefer exam paper; fallback to daily study sheet normalized)
	_paper = _fetch_paper(subject)
	if _paper.is_empty():
		push_error("Quiz: no questions for subject: " + subject)
		end_quiz()
		return

	# Decide mode (true => bought visuals)
	_bought_mode = _resolve_mode(subject)

	# Connect buttons once, binding each index
	for i in range(option_buttons.size()):
		var b := option_buttons[i]
		if not b.pressed.is_connected(_on_option_pressed):
			b.pressed.connect(_on_option_pressed.bind(i))

	# Ensure timer timeout is connected (if not wired in editor)
	if not timer.timeout.is_connected(_on_Timer_timeout):
		timer.timeout.connect(_on_Timer_timeout)

	# Time bar baseline (keep editor height; only scale width)
	_timebar_full_width  = timePAN.size.x
	_timebar_full_height = timePAN.size.y

	_idx = 0
	_correct_count = 0
	_score = 0
	update_score()

	_show_question(_idx)
	_start_timer()

func _process(_dt: float) -> void:
	if timer.wait_time <= 0.0:
		return
	var ratio := 0.0
	if timer.wait_time > 0.0:
		ratio = timer.time_left / timer.wait_time
	if ratio < 0.0:
		ratio = 0.0
	if ratio > 1.0:
		ratio = 1.0
	timePAN.size = Vector2(_timebar_full_width * ratio, _timebar_full_height)

# ----------------------- Loading -----------------------

func _fetch_paper(subj_raw: String) -> Array:
	var subj := _subject_key(subj_raw)

	# Preferred: already UI-ready
	if GameState and GameState.has_method("build_exam_paper"):
		var p := GameState.build_exam_paper(subj)
		if p is Array and not p.is_empty():
			return p

	# Fallback: daily sheet -> normalize to UI-ready
	var sheet := []
	if GameState and GameState.has_method("get_daily_study_sheet"):
		sheet = GameState.get_daily_study_sheet(subj)
	elif GameState and GameState.has_method("get_study_sheet_for_session"):
		sheet = GameState.get_study_sheet_for_session(subj, GameState.day)

	var out := []
	for qd in sheet:
		if not (qd is Dictionary):
			continue
		if not qd.has("q") or not qd.has("correct"):
			continue

		var correct := String(qd.get("correct", ""))
		var wrongs  := qd.get("wrong", []) as Array

		var opts := []
		opts.append(correct)
		if wrongs.size() >= 1:
			opts.append(String(wrongs[0]))
		if wrongs.size() >= 2:
			opts.append(String(wrongs[1]))

		# shuffle into choices and compute correct_index
		var order := _pick_unique_indexes(opts.size(), opts.size())
		var shuffled : Array[String] = []
		var c_idx := 0
		for j in order:
			var ch := String(opts[j])
			shuffled.append(ch)
			if ch == correct:
				c_idx = shuffled.size() - 1

		out.append({
			"id":            String(qd.get("id","")),
			"q":             String(qd.get("q","")),
			"choices":       shuffled,
			"correct_index": c_idx
		})
	return out

func _subject_key(s: String) -> String:
	var t := s.strip_edges().to_lower()
	match t:
		"science":
			return "science"
		"geography":
			return "geography"
		"math (algebra basics)", "math":
			return "math"
		"macedonian":
			return "macedonian"
		"english":
			return "english"
		_:
			return t

# ----------------------- Title -----------------------

func _set_title_from_subject() -> void:
	var s1 := GameState.subject1
	var s2 := GameState.subject2
	var key := _subject_key(subject)
	var label_text := key

	if _subject_key(s1) == key:
		label_text = GameState.format_placeholders("{subject1}")
	elif _subject_key(s2) == key:
		label_text = GameState.format_placeholders("{subject2}")
	else:
		label_text = GameState.format_placeholders(key.capitalize())

	title_label.text = label_text

# ----------------------- Mode -----------------------

func _resolve_mode(subj_raw: String) -> bool:
	# explicit override
	if mode == "bought":
		return true
	if mode == "legit":
		return false

	# auto: infer from S1/S2 flags
	var s := _subject_key(subj_raw)
	var s1 := _subject_key(GameState.subject1)
	var s2 := _subject_key(GameState.subject2)

	if s == s1 and GameState.has_flag(BOUGHT_ANSWERS_S1):
		return true
	if s == s2 and GameState.has_flag(BOUGHT_ANSWERS_S2):
		return true
	return false

# ----------------------- Timer -----------------------

func _start_timer() -> void:
	timer.stop()
	if seconds_per_question < 0.1:
		seconds_per_question = 0.1
	timer.wait_time = seconds_per_question
	timer.start()
	_clicks_enabled = true

func _on_Timer_timeout() -> void:
	# Time’s up → reveal as if wrong, then advance
	if _idx < _paper.size():
		var q = _paper[_idx]
		_reveal_styles(int(q.get("correct_index", 0)))
		_clicks_enabled = false
		await get_tree().create_timer(0.9).timeout
		_advance()

# ----------------------- UI flow -----------------------

func _show_question(i: int) -> void:
	if i >= _paper.size():
		end_quiz()
		return

	var q = _paper[i]
	question_label.visible_characters = 0
	question_label.text = String(q.get("q",""))
	create_tween().tween_property(question_label, "visible_characters", question_label.text.length(), 0.75)

	# Reset styles & fill texts
	for k in range(option_buttons.size()):
		var b := option_buttons[k]
		var choices := q.get("choices", []) as Array
		if k < choices.size():
			b.text = String(choices[k])
		else:
			b.text = ""
		b.disabled = false
		_apply_theme(b, theme_neutral)

	# Bought mode: preview correct (green) and others (red) immediately
	if _bought_mode:
		_preview_bought(int(q.get("correct_index", 0)))

	_clicks_enabled = true

func _on_option_pressed(selected_index: int) -> void:
	if not _clicks_enabled:
		return
	_clicks_enabled = false

	var q = _paper[_idx]
	var correct_index := int(q.get("correct_index", 0))

	# Reveal visuals
	_reveal_styles(correct_index)

	# Score
	if selected_index == correct_index:
		_correct_count += 1
		_score += points_per_correct
		update_score()

	# short pause then advance
	await get_tree().create_timer(0.9).timeout
	_advance()

func _advance() -> void:
	_idx += 1
	if _idx >= _paper.size():
		end_quiz()
		return
	_show_question(_idx)
	_start_timer()

func _reveal_styles(correct_idx: int) -> void:
	for k in range(option_buttons.size()):
		var b := option_buttons[k]
		b.disabled = true
		if k == correct_idx:
			_apply_theme(b, theme_right)
		else:
			_apply_theme(b, theme_wrong)

func _preview_bought(correct_idx: int) -> void:
	for k in range(option_buttons.size()):
		var b := option_buttons[k]
		if k == correct_idx:
			_apply_theme(b, theme_right)
		else:
			_apply_theme(b, theme_wrong)

func _apply_theme(b: Button, t: Theme) -> void:
	if t != null:
		b.theme = t
	else:
		b.theme = null

# ----------------------- Score / End -----------------------

func update_score() -> void:
	score_label.text = tr("Score: %d") % _score

func end_quiz() -> void:
	timer.stop()
	timePAN.visible = false
	question_label.text = "Quiz Finished!"
	question_label.visible_characters = question_label.text.length()
	for b in option_buttons:
		b.visible = false
	update_score()

	# store numeric score in GameState (fills scores1, else scores2)
	if GameState and GameState.has_method("push_exam_score_value"):
		GameState.push_exam_score_value(_score)

	# emit so embedding/tests can await
	quiz_finished.emit(_paper.size(), _correct_count, _score)

	# bump finals counter (0 -> 1 -> 2)
	var c := 0
	if GameState:
		c = GameState.get_int(K_FINALS_COUNTER, 0)
		GameState.set_int(K_FINALS_COUNTER, c + 1)

	# If opened standalone, bounce back to Finals
	if auto_return_to_finals and self == get_tree().current_scene and ResourceLoader.exists(finals_scene_path):
		await get_tree().create_timer(auto_return_delay).timeout
		await fade.fade_to_scene(finals_scene_path)

# ----------------------- Utils -----------------------

func _pick_unique_indexes(n: int, k: int) -> Array[int]:
	var a : Array[int] = []
	var i := 0
	while i < n:
		a.append(i)
		i += 1
	var j := n - 1
	while j > 0:
		var r := randi_range(0, j)
		var t := a[j]
		a[j] = a[r]
		a[r] = t
		j -= 1
	if k > n:
		k = n
	return a.slice(0, k)
