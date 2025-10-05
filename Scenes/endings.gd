# res://Scenes/Reusable/Endings.gd
extends Control

signal crawl_finished
signal scroll_started(kind: String)    # "camera"
signal scroll_finished(kind: String)

# ---------- Assign in Inspector ----------
@export var text_label: RichTextLabel
@export var camera2d: Camera2D
@export var game_ui_path: NodePath                  # e.g. StatusBar / GameUI root
@export var post_credits_vbox_path: NodePath        # shown AFTER crawl, during 6s wait

# ---------- Layout / Motion ----------
@export var side_margin_ratio: float = 0.12         # 0.12 => 12% margins on both sides
@export var crawl_speed_pps: float = 40.0           # label crawl speed (px/sec)
@export var wait_after_crawl_sec: float = 6.0       # pause between crawl and camera
@export var content_end_y: float = 12700.0          # bottom Y of your giant TextureRect
@export var camera_speed_pps: float = 40.0          # camera glide speed (px/sec)

# ---------- Music ----------
@export var credits_music_stream: AudioStream        # optional: dedicated credits track
@export var credits_music_player_path: NodePath      # optional: reuse an existing player
@export var music_bus: String = "Music"

# ---------- Exit / Fade ----------
@export var exit_fade_seconds: float = 10.0
var _fade_overlay: ColorRect = null

func _ready() -> void:
	GameState.switch_locale("mk")
	if text_label == null:
		push_error("Endings: text_label is not assigned.")
		return


	GameUi.visible=false

	# Ensure post-credits VBox starts hidden
	var post_vbox := _get_vbox()
	if post_vbox:
		post_vbox.visible = false

	# Kill existing BG music (your GameState API)
	if Engine.has_singleton("GameState") and GameState.has_method("stop_bg_music"):
		GameState.stop_bg_music()

	# Load ending text
	var ending_id := _pick_ending_id()
	var rel := "Dialogue/Endings/%s.json" % ending_id
	var path := GameState.get_data_path(rel)
	var text := _load_ending_text(path)
	if text == "":
		text = "[center][b]Missing ending JSON[/b]\n" + ending_id + "[/center]"

	# Prepare label sizing/position
	await _setup_label_bbcode(text)

	# Optional credits music
	_play_credits_music_if_any()

	# Phase 1: Label crawl → emit signal
	await _play_label_crawl()
	crawl_finished.emit()

	# >>> SHOW VBOX NOW (during the 6s wait) <<<
	post_vbox = _get_vbox()
	if post_vbox:
		post_vbox.visible = true

	# Hold for N seconds before the camera starts
	if wait_after_crawl_sec > 0.0:
		await get_tree().create_timer(wait_after_crawl_sec).timeout

	# Phase 2: Camera glide (or finish if no camera)
	if camera2d:
		await _start_camera_scroll()
	else:
		await _finish_and_exit()

# -------------------------------
# Ending selection (your logic)
# -------------------------------
func _pick_ending_id() -> String:
	if GameState.has_flag("submission_failed"):
		return "ending_forgotten_applicant"

	if _finals_failed():
		return "ending_repeat_next_year"

	if GameState.has_flag("doc_review_banned"):
		return "ending_cheating_consequences"

	if _major_fake_present() and _academics_ok():
		return "ending_liar_got_away"

	if _academics_ok() and _file_full_green() and !_any_cheat_flag() and _rep_good() and _int_good():
		return "ending_right_way"

	if _academics_ok() and _major_fake_present() and !_int_good():
		return "ending_built_on_sand"

	if _academics_ok() and GameState.has_flag("motivation_ai_generated") and !GameState.has_flag("doc_review_banned"):
		if !_rep_good() or !_int_good():
			return "ending_success_for_now"

	if GameState.has_flag("submitted_incomplete_docs") and _academics_ok():
		return "ending_potential"

	if _academics_ok() and _file_full_green() and !_any_cheat_flag():
		if (_rep_good() != _int_good()):
			return "ending_regional"

	if !_project_passed() and !_any_cheat_flag() and _int_good() and _finals_passed():
		return "ending_honest_failure"

	return "ending_potential"

# -------------------------------
# Compact helpers
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
	return missed <= 1

func _any_cheat_flag() -> bool:
	return _major_fake_present() or GameState.has_flag("motivation_ai_generated")

func _major_fake_present() -> bool:
	return GameState.has_flag("bought_project") \
		or GameState.has_flag("project_plagiarized") \
		or GameState.has_flag("bought_answers_s1") \
		or GameState.has_flag("bought_answers_s2")

func _file_full_green() -> bool:
	return GameState.has_flag("project_submitted") \
		and GameState.has_flag("printed_cv") \
		and GameState.has_flag("printed_motivation") \
		and !GameState.has_flag("doc_review_banned") \
		and (GameState.has_flag("have_language_certificate") or GameState.has_flag("lang_cert_picked")) \
		and GameState.has_flag("have_birth_certificate") \
		and _attendance_ok()

# -------------------------------
# JSON load + label layout
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
		match typeof(v):
			TYPE_DICTIONARY:
				var t := String((v as Dictionary).get("text", ""))
				if t.strip_edges() != "":
					chunks.append(t)
			TYPE_STRING:
				var s := String(v)
				if s.strip_edges() != "":
					chunks.append(s)
	return "\n\n".join(chunks)

func _setup_label_bbcode(text: String) -> void:
	text_label.bbcode_enabled = true
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	text_label.scroll_active = false
	text_label.bbcode_text = text

	var vp := get_viewport().get_visible_rect().size
	var target_w = max(400.0, vp.x * (1.0 - side_margin_ratio * 2.0))
	text_label.size.x = target_w
	text_label.position.x = (vp.x - target_w) * 0.5

	await get_tree().process_frame

	var ch := _content_height_safe(text_label)
	text_label.size.y = ch
	text_label.custom_minimum_size.y = ch

# -------------------------------
# Phase 1: Label crawl (awaits)
# -------------------------------
func _play_label_crawl() -> void:
	var vp := get_viewport().get_visible_rect().size
	var start_y := vp.y + 24.0
	var end_y := -_content_height_safe(text_label) - 48.0
	text_label.position.y = start_y

	var distance := start_y - end_y
	var speed = max(1.0, crawl_speed_pps)
	var duration = distance / speed

	var tw := create_tween()
	tw.tween_property(text_label, "position:y", end_y, duration)
	await tw.finished

# -------------------------------
# Phase 2: Camera glide (awaits)
# -------------------------------
func _start_camera_scroll() -> void:
	emit_signal("scroll_started", "camera")

	var from_y := camera2d.position.y
	var to_y := content_end_y
	var distance = abs(to_y - from_y)
	var speed = max(1.0, camera_speed_pps)
	var duration = distance / speed

	var tw := create_tween()
	tw.tween_property(camera2d, "position:y", to_y, duration)
	await tw.finished

	emit_signal("scroll_finished", "camera")

	await _finish_and_exit()

# -------------------------------
# Wrap-up: fade -> quit
# -------------------------------
func _finish_and_exit() -> void:
	await _fade_to_black_and_quit(exit_fade_seconds)

# -------------------------------
# Helpers
# -------------------------------
func _content_height_safe(lbl: RichTextLabel) -> float:
	if lbl.has_method("get_content_height"):
		return float(lbl.call("get_content_height"))
	return lbl.size.y

func _get_vbox() -> VBoxContainer:
	if post_credits_vbox_path == NodePath(""):
		return null
	var n := get_node_or_null(post_credits_vbox_path)
	if n and n is VBoxContainer:
		return n
	return null

func _ensure_fade_overlay() -> ColorRect:
	if _fade_overlay:
		return _fade_overlay
	_fade_overlay = ColorRect.new()
	_fade_overlay.color = Color(0,0,0,0)  # transparent black
	_fade_overlay.name = "EndFadeOverlay"
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_overlay.z_index = 999
	_fade_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade_overlay)
	return _fade_overlay

func _fade_to_black_and_quit(seconds: float) -> void:
	var overlay := _ensure_fade_overlay()
	overlay.visible = true
	overlay.modulate.a = 0.0
	var d = max(0.01, seconds)
	var tw := create_tween()
	tw.tween_property(overlay, "modulate:a", 1.0, d)
	await tw.finished
	get_tree().quit()

# ---------- Audio ----------
func _play_credits_music_if_any() -> void:
	if credits_music_stream == null:
		return

	var player: AudioStreamPlayer = null

	if credits_music_player_path != NodePath(""):
		var n := get_node_or_null(credits_music_player_path)
		if n and n is AudioStreamPlayer:
			player = n as AudioStreamPlayer

	if player == null:
		player = AudioStreamPlayer.new()
		player.name = "CreditsMusicPlayer"
		add_child(player)

	player.stream = credits_music_stream
	player.bus = music_bus
	player.volume_db = 0.0
	player.autoplay = false
	player.play()
