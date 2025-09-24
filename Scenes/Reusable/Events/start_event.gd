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
var _subject_all_ids: Array[String] = []      # canonical IDs from JSON
var _subject_selected_ids: Array[String] = [] # selected IDs
var _subject_display: Dictionary = {}         # id -> Capitalized display
var _subject_max: int = 2

# map ids <-> buttons for toggling
var _btn_by_id: Dictionary = {}   # id -> Button
var _id_by_btn: Dictionary = {}   # Button -> id

func _ready() -> void:
	GameUi.visible = true
	GameState.location = "Classroom"  # logic string; unchanged
	_set_bg(bg_teacher)

	# Locale-aware start dialogue path
	_dialogue_ui = DialogueManager.start_dialogue(GameState.get_data_path("StartEvent.json"), self)
	if _dialogue_ui and _dialogue_ui.has_signal("dialogue_finished"):
		_dialogue_ui.connect("dialogue_finished", Callable(self, "_on_start_event_finished"))

# ---------- Dialogue hooks ----------
func on_dialogue_action(line: Dictionary) -> void:
	var act := String(line.get("action", ""))

	match act:
		# --- Background swaps (action-based) ---
		"principal_enters", "bg_principal":
			await _swap_bg_async("principal")
		"bg_teacher":
			await _swap_bg_async("teacher")
		"set_bg":
			var who := String(line.get("who", line.get("bg", ""))).strip_edges().to_lower()
			if who != "":
				await _swap_bg_async(who)

		# --- Explicit subject two-pick ---
		"show_subject_pick":
			var opts = line.get("options", [])
			var mx := int(line.get("max_select", 2))
			_begin_subject_multiselect(_normalize_options(opts), mx)

		# --- Generic choices; if max_select >= 2 treat like subject-pick, else single-choice ---
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
	# Day 1 attendance → add & bump so TaskManager fires the notification
	GameState.ensure_task("Attend Morning Classes")
	GameState.set_flag("attended_morning_day_1", true)
	GameState.update_task_step("Attend Morning Classes")

	# Proceed to the world
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

# ---------- Subject multi-select (TOGGLEABLE) ----------
func _begin_subject_multiselect(options: Array, max_select: int) -> void:
	_subject_all_ids.clear()
	_subject_selected_ids.clear()
	_subject_display.clear()
	_btn_by_id.clear()
	_id_by_btn.clear()
	_subject_max = max(2, max_select)

	for o in options:
		var id := String(o.get("id", ""))
		if id == "":
			continue
		_subject_all_ids.append(id)
		_subject_display[id] = _capitalize_first(String(o.get("text", id)))

	_render_subject_multiselect()

func _render_subject_multiselect() -> void:
	_ensure_choice_panel()

	var btns := _collect_choice_buttons(_choice_panel)
	btns.sort_custom(func(a, b): return String(a.name) < String(b.name))

	var count = min(_subject_all_ids.size(), btns.size())
	for i in range(btns.size()):
		var b := btns[i]
		if i < count:
			var id := _subject_all_ids[i]
			var label := String(_subject_display.get(id, id))

			b.toggle_mode = true
			b.text = label
			b.visible = true

			if b.is_connected("pressed", Callable(self, "_on_choice_button_pressed")):
				b.disconnect("pressed", Callable(self, "_on_choice_button_pressed"))
			if b.is_connected("toggled", Callable(self, "_on_choice_button_toggled")):
				b.disconnect("toggled", Callable(self, "_on_choice_button_toggled"))

			var is_sel := _subject_selected_ids.has(id)
			b.set_pressed_no_signal(is_sel)
			_apply_button_visual(b, is_sel)

			_btn_by_id[id] = b
			_id_by_btn[b] = id
			b.toggled.connect(Callable(self, "_on_choice_button_toggled").bind(id))
		else:
			b.visible = false

	_choice_panel.visible = true
	_update_button_disable_states()

func _on_choice_button_toggled(pressed: bool, id: String) -> void:
	var sid := String(id)
	if pressed:
		if not _subject_selected_ids.has(sid):
			if _subject_selected_ids.size() < _subject_max:
				_subject_selected_ids.append(sid)
			else:
				var b = _btn_by_id.get(sid, null)
				if b:
					b.set_pressed_no_signal(false)
				return
	else:
		_subject_selected_ids.erase(sid)

	_apply_button_visual_state_all()
	_update_button_disable_states()

	if _subject_selected_ids.size() == _subject_max:
		_finalize_subject_selection()

func _apply_button_visual_state_all() -> void:
	for id in _btn_by_id.keys():
		var b: Button = _btn_by_id[id]
		var sel := _subject_selected_ids.has(String(id))
		_apply_button_visual(b, sel)

func _apply_button_visual(b: Button, selected: bool) -> void:
	# Dim when selected, normal when not
	b.modulate = Color(1, 1, 1, 0.65) if selected else Color(1, 1, 1, 1)
	b.tooltip_text = tr("Click to unselect") if selected else tr("Click to select")

func _update_button_disable_states() -> void:
	var at_cap := _subject_selected_ids.size() >= _subject_max
	for id in _btn_by_id.keys():
		var b: Button = _btn_by_id[id]
		var sel := _subject_selected_ids.has(String(id))
		b.disabled = (at_cap and not sel)

func _finalize_subject_selection() -> void:
	var picked_display: Array = []
	for sid in _subject_selected_ids:
		picked_display.append(String(_subject_display.get(sid, sid)))

	on_choices_selected(picked_display)

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

func _collect_choice_buttons(root: Node) -> Array[Button]:
	var out: Array[Button] = []
	_collect_buttons_recursive(root, out)
	return out

func _collect_buttons_recursive(n: Node, out: Array[Button]) -> void:
	if n is Button:
		out.append(n)
	for c in n.get_children():
		_collect_buttons_recursive(c, out)

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
		tail = s.substr(1, s.length() - 1)
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
