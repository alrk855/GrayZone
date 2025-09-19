extends Control

# ---------- Background ----------
@export var background_node_path: NodePath = "background"
@onready var _bg_node: Node = get_node_or_null(background_node_path)
@export var bg_teacher: Texture2D
@export var bg_principal: Texture2D

# ---------- Fade ----------
@onready var screen_fader: ColorRect = $ColorRect

# ---------- Choice panel ----------
@onready var choice_panel_scene: PackedScene = preload("res://Scenes/Reusable/CharacterChoiceButtons.tscn")
var _choice_panel: Control = null
var _dialogue_ui: Node = null

# subject multi-select state
var _subject_all_ids: Array[String] = []              # canonical IDs from JSON
var _subject_selected_ids: Array[String] = []         # selected IDs
var _subject_display: Dictionary = {}                 # id -> Capitalized display
var _subject_max: int = 2

func _ready() -> void:
	GameUi.visible = true
	GameState.location = "Classroom"
	_set_bg(bg_teacher)

	_dialogue_ui = DialogueManager.start_dialogue("res://Data/StartEvent.json", self)
	if _dialogue_ui and _dialogue_ui.has_signal("dialogue_finished"):
		_dialogue_ui.connect("dialogue_finished", Callable(self, "_on_start_event_finished"))

# ---------- Dialogue hooks ----------
func on_dialogue_action(line: Dictionary) -> void:
	var act := String(line.get("action", ""))

	match act:
		# Background swaps (action-based)
		"principal_enters":
			await _swap_bg_async("principal")
		"bg_principal":
			await _swap_bg_async("principal")
		"bg_teacher":
			await _swap_bg_async("teacher")
		"set_bg":
			var who := String(line.get("who", line.get("bg", ""))).strip_edges().to_lower()
			if who != "":
				await _swap_bg_async(who)

		# Explicit subject two-pick
		"show_subject_pick":
			var opts = line.get("options", [])
			var mx := int(line.get("max_select", 2))
			_begin_subject_multiselect(_normalize_options(opts), mx)

		# Generic choices; if max_select >= 2 treat like subject-pick, else single-choice
		"show_choices", "show_choice_buttons":
			var opts2 := _normalize_options(line.get("options", []))
			var mx2 := int(line.get("max_select", 1))
			if mx2 >= 2:
				_begin_subject_multiselect(opts2, mx2)
			else:
				_show_single_choices(opts2)

		_:
			GameState.apply_action(line)

# If your JSON uses scene_transition instead of action:
func on_scene_transition(namee: String) -> void:
	var key := String(namee).strip_edges().to_lower()
	if key == "principal_enters":
		await _swap_bg_async("principal")
	elif key == "teacher_enters" or key == "teacher":
		await _swap_bg_async("teacher")

# Keep compatibility with your older flow
func on_choices_selected(selected: Array) -> void:
	# This receives DISPLAY NAMES (capitalized) from our finalize step
	if selected.size() >= 2:
		GameState.subject1 = String(selected[0])
		GameState.subject2 = String(selected[1])
		print("📘 Subjects chosen:", GameState.subject1, GameState.subject2)

func _on_start_event_finished(_dlg_id: String = "", _payload: Variant = null) -> void:
	GameState.begin_game(GameState.day, GameState.time)
	await fade_out()
	get_tree().change_scene_to_file("res://Scenes/Reusable/Map/School.tscn")

# ---------- Single-choice ----------
func _show_single_choices(options: Array) -> void:
	_ensure_choice_panel()
	_choice_panel.call("show_options", options, Callable(self, "_on_single_choice_clicked"))

func _on_single_choice_clicked(id: String) -> void:
	_hide_choice_panel()
	if _dialogue_ui and _dialogue_ui.has_method("apply_choices"):
		_dialogue_ui.call("apply_choices", [id])

# ---------- Subject multi-select (keeps panel visible, no dots/checks) ----------
func _begin_subject_multiselect(options: Array, max_select: int) -> void:
	_subject_all_ids.clear()
	_subject_selected_ids.clear()
	_subject_display.clear()
	_subject_max = max(2, max_select)

	# Build ID + capitalized display map
	for o in options:
		var id := String(o.get("id", ""))
		if id == "":
			continue
		_subject_all_ids.append(id)
		_subject_display[id] = _capitalize_first(String(o.get("text", id)))

	_render_subject_multiselect()

func _render_subject_multiselect() -> void:
	_ensure_choice_panel()

	# Build options with clean, capitalized labels (no markers)
	var options_for_panel: Array = []
	for id in _subject_all_ids:
		var label := String(_subject_display.get(id, id))
		options_for_panel.append({"id": id, "text": label})

	_choice_panel.call("show_options", options_for_panel, Callable(self, "_on_subject_toggle"))

	# If your CharacterChoiceButtons supports highlighting, sync selection
	if _choice_panel and _choice_panel.has_method("set_selected_ids"):
		_choice_panel.call("set_selected_ids", _subject_selected_ids)

func _on_subject_toggle(id: String) -> void:
	var sid := String(id)

	# toggle selection
	if _subject_selected_ids.has(sid):
		_subject_selected_ids.erase(sid)
	else:
		if _subject_selected_ids.size() < _subject_max:
			_subject_selected_ids.append(sid)

	# finalize once quota is met
	if _subject_selected_ids.size() == _subject_max:
		_finalize_subject_selection()
		return

	_render_subject_multiselect()

func _finalize_subject_selection() -> void:
	# Build DISPLAY names for GameState (capitalized)
	var picked_display: Array = []
	for sid in _subject_selected_ids:
		picked_display.append(String(_subject_display.get(sid, sid)))

	# Old hook (so your GameState.subject1/2 get set nicely)
	on_choices_selected(picked_display)

	# Pass canonical IDs back to Dialogue so it can branch on IDs
	if _dialogue_ui and _dialogue_ui.has_method("apply_choices"):
		_dialogue_ui.call("apply_choices", _subject_selected_ids)

	_hide_choice_panel()

# ---------- Panel helpers ----------
func _ensure_choice_panel() -> void:
	if _choice_panel and is_instance_valid(_choice_panel):
		return
	_choice_panel = choice_panel_scene.instantiate()
	add_child(_choice_panel)

func _hide_choice_panel() -> void:
	if _choice_panel and is_instance_valid(_choice_panel):
		_choice_panel.queue_free()
	_choice_panel = null

func _normalize_options(raw: Variant) -> Array:
	var out: Array = []
	if raw is Array:
		for it in raw:
			if typeof(it) == TYPE_DICTIONARY:
				var id := String(it.get("id", ""))
				var text := String(it.get("text", id))
				if id == "" and text != "":
					id = text
				out.append({"id": id, "text": text})
			else:
				var s := String(it)
				out.append({"id": s, "text": s})
	return out

func _capitalize_first(s: String) -> String:
	if s.length() == 0:
		return s
	var head := s.substr(0, 1).to_upper()
	var tail := ""
	if s.length() > 1:
		tail = s.substr(1, s.length() - 1) # keep original casing for the rest if you prefer: `.to_lower()` if needed
	return head + tail

# ---------- BG / Fade ----------
func _set_bg(tex: Texture2D) -> void:
	if _bg_node == null or tex == null:
		return
	if _bg_node is TextureRect:
		(_bg_node as TextureRect).texture = tex
	elif _bg_node is Sprite2D:
		(_bg_node as Sprite2D).texture = tex
	elif _bg_node.has_method("set_texture"):
		_bg_node.call("set_texture", tex)

func _bg_for_key(key: String) -> Texture2D:
	var k := key.strip_edges().to_lower()
	if k == "principal":
		return bg_principal
	return bg_teacher

func _swap_bg_async(who: String) -> void:
	await fade_out()
	_set_bg(_bg_for_key(who))
	await fade_in()

func fade_out() -> void:
	screen_fader.visible = true
	screen_fader.modulate.a = 0.0
	var t = create_tween()
	t.tween_property(screen_fader, "modulate:a", 1.0, 0.5)
	await t.finished

func fade_in() -> void:
	var t = create_tween()
	t.tween_property(screen_fader, "modulate:a", 0.0, 0.5)
	await t.finished
	screen_fader.visible = false
