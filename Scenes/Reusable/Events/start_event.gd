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
var _subject_all: Array[String] = []
var _subject_selected: Array[String] = []
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
		"principal_enters":
			await fade_out()
			_set_bg(bg_principal)
			await fade_in()

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

# Keep compatibility with your older flow
func on_choices_selected(selected: Array) -> void:
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

# ---------- Subject multi-select (keeps panel visible) ----------
func _begin_subject_multiselect(options: Array, max_select: int) -> void:
	_subject_all.clear()
	_subject_selected.clear()
	_subject_max = max(2, max_select)

	for o in options:
		_subject_all.append(String(o.get("id", "")))

	_render_subject_multiselect()

func _render_subject_multiselect() -> void:
	_ensure_choice_panel()

	var options_for_panel: Array = []
	for sid in _subject_all:
		var picked := _subject_selected.has(sid)
		var label_prefix := "✓ " if picked else "• "
		var label := label_prefix + sid
		options_for_panel.append({"id": sid, "text": label})

	# Re-bind the SAME panel; do not destroy between clicks
	_choice_panel.call("show_options", options_for_panel, Callable(self, "_on_subject_toggle"))

func _on_subject_toggle(id: String) -> void:
	var sid := String(id)

	# toggle selection
	if _subject_selected.has(sid):
		_subject_selected.erase(sid)
	else:
		if _subject_selected.size() < _subject_max:
			_subject_selected.append(sid)

	# finalize once quota is met
	if _subject_selected.size() == _subject_max:
		_finalize_subject_selection()
		return

	_render_subject_multiselect()

func _finalize_subject_selection() -> void:
	on_choices_selected(_subject_selected.duplicate())

	if _dialogue_ui and _dialogue_ui.has_method("apply_choices"):
		_dialogue_ui.call("apply_choices", _subject_selected)

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
