# res://Scenes/Reusable/Endings.gd
extends Control

@export var text_label: RichTextLabel                     # assign in editor
@export var enable_crawl: bool = true
@export var crawl_speed_pps: float = 40.0                 # pixels per second
@export var side_margin_ratio: float = 0.12               # 12% screen margins

func _ready() -> void:
	if text_label == null:
		push_error("Endings: text_label is not assigned.")
		return

	# 1) Pick ending id (no dev/override flags; real data only)
	var ending_id := _pick_ending_id()

	# 2) Load JSON via locale-aware relative path
	var rel := "Dialogue/Endings/%s.json" % ending_id
	var path := GameState.get_data_path(rel)
	var text := _load_ending_text(path)
	if text == "":
		text = "[center][b]Missing ending JSON[/b]\n" + ending_id + "[/center]"

	# 3) Feed label
	text_label.bbcode_enabled = true
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	text_label.scroll_active = false
	text_label.bbcode_text = text

	# Ensure a comfortable width
	var vp := get_viewport().get_visible_rect().size
	var target_w = max(400.0, vp.x * (1.0 - side_margin_ratio * 2.0))
	text_label.size = Vector2(target_w, text_label.size.y)
	text_label.position.x = (vp.x - target_w) * 0.5

	# Let the label layout once so content height is correct
	await get_tree().process_frame

	# 4) Optional crawl
	if enable_crawl:
		_play_crawl()
	else:
		# Center on screen if not crawling
		var ch := _content_height_safe(text_label)
		text_label.position.y = max(0.0, (vp.y - ch) * 0.5)

# -------------------------------
# Ending selection (priority order)
# -------------------------------
func _pick_ending_id() -> String:
	# 0) Hard locks
	if GameState.has_flag("submission_failed"):
		return "ending_forgotten_applicant"         # Missed the deadline

	if _finals_failed():
		return "ending_repeat_next_year"            # Finals fail forces redo

	# 1) Cheating detected (letter only; this is the real 'caught' flag you track)
	if GameState.has_flag("doc_review_banned"):
		return "ending_cheating_consequences"

	# 2) Cheated but not caught (major fake present + academics OK)
	if _major_fake_present() and _academics_ok():
		return "ending_liar_got_away"

	# 3) Clean win (academics OK + full/green submission + good stats + no cheating)
	if _academics_ok() and _file_full_green() and !_any_cheat_flag() and _rep_good() and _int_good():
		return "ending_right_way"

	# 4) Built on Sand (major fake + integrity bad + academics OK)
	if _academics_ok() and _major_fake_present() and !_int_good():
		return "ending_built_on_sand"

	# 5) Success… For Now (minor fake letter + not banned + shaky stats + academics OK)
	if _academics_ok() and GameState.has_flag("motivation_ai_generated") and !GameState.has_flag("doc_review_banned"):
		if !_rep_good() or !_int_good():
			return "ending_success_for_now"

	# 6) He Had Potential (submitted incomplete but passed academics)
	if GameState.has_flag("submitted_incomplete_docs") and _academics_ok():
		return "ending_potential"

	# 7) Regional Hero (real docs, no cheating, academics OK, stats mixed)
	if _academics_ok() and _file_full_green() and !_any_cheat_flag():
		if (_rep_good() != _int_good()):  # one good, one not
			return "ending_regional"

	# 8) Honest Failure (finals passed, project failed, clean intent)
	if !_project_passed() and !_any_cheat_flag() and _int_good() and _finals_passed():
		return "ending_honest_failure"

	# Fallback: if nothing matched, default to Potential (safe neutral)
	return "ending_potential"

# -------------------------------
# Compact helpers (real data only)
# -------------------------------
func _finals_passed() -> bool:
	return (GameState.scores1 >= 3) and (GameState.scores2 >= 3)

func _finals_failed() -> bool:
	return (GameState.scores1 < 3) or (GameState.scores2 < 3)

func _project_passed() -> bool:
	return GameState.get_int("project_score", 0) >= 3

func _academics_ok() -> bool:
	return _finals_passed() and _project_passed()

func _rep_good() -> bool:
	return GameState.reputation > 50

func _int_good() -> bool:
	return GameState.integrity > 50

func _attendance_ok() -> bool:
	var missed := 0
	for i in range(1, 5):
		var attended := GameState.has_flag("attended_morning_day_%d" % i)
		if !attended and i < GameState.day:
			missed += 1
	return missed <= 1   # green in your task view

func _any_cheat_flag() -> bool:
	return _major_fake_present() or GameState.has_flag("motivation_ai_generated")

func _major_fake_present() -> bool:
	return GameState.has_flag("bought_project") \
		or GameState.has_flag("project_plagiarized") \
		or GameState.has_flag("bought_answers_s1") \
		or GameState.has_flag("bought_answers_s2")

# Strict “full green” submission (uses your real flags; no Secretary code changes)
func _file_full_green() -> bool:
	return GameState.has_flag("project_submitted") \
		and GameState.has_flag("printed_cv") \
		and GameState.has_flag("printed_motivation") \
		and !GameState.has_flag("doc_review_banned") \
		and (GameState.has_flag("have_language_certificate") or GameState.has_flag("lang_cert_picked")) \
		and GameState.has_flag("have_birth_certificate") \
		and _attendance_ok()

# -------------------------------
# JSON load + crawl
# -------------------------------
func _load_ending_text(abs_path: String) -> String:
	if abs_path == "" or !FileAccess.file_exists(abs_path):
		return ""
	var raw := FileAccess.get_file_as_string(abs_path)
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	var arr: Array = (parsed as Dictionary).get("lines", []) as Array
	if arr.is_empty():
		return ""
	var chunks: Array[String] = []
	for v in arr:
		if typeof(v) == TYPE_DICTIONARY:
			var t := String((v as Dictionary).get("text", ""))
			if t.strip_edges() != "":
				chunks.append(t)
	return "\n\n".join(chunks)

func _play_crawl() -> void:
	var vp := get_viewport().get_visible_rect().size
	# Place label just below the bottom edge
	var start_y := vp.y + 24.0
	var end_y := -_content_height_safe(text_label) - 48.0
	text_label.position.y = start_y

	var distance := start_y - end_y
	var speed = max(1.0, crawl_speed_pps)
	var duration = distance / speed

	var tw := create_tween()
	tw.tween_property(text_label, "position:y", end_y, duration)
	# Optional tiny fade at the very end
	# tw.tween_interval(0.1).tween_property(text_label, "modulate:a", 0.0, 0.6)

func _content_height_safe(lbl: RichTextLabel) -> float:
	# Godot 4 RichTextLabel provides get_content_height()
	if lbl.has_method("get_content_height"):
		return float(lbl.call("get_content_height"))
	# Fallback: use size if method unavailable
	return lbl.size.y
