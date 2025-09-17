extends Control
# DevTools: PIN gate + live time/day + stats + flags + safe exit (NodePath-driven)

# -----------------------------
# Scene targets (set now or later)
# -----------------------------
const PATH_HOME   := "res://Scenes/Reusable/Map/Home.tscn"
const PATH_CITY   := "res://Scenes/Reusable/Map/City.tscn"
const PATH_SCHOOL := "res://Scenes/Reusable/Map/School.tscn"
const PATH_MVR    := "res://Scenes/Reusable/Map/MVR.tscn"     # placeholder
const PATH_YCO    := "res://Scenes/Reusable/Map/YCO.tscn"     # placeholder

# -----------------------------
# Autoload helpers
# -----------------------------
func _GS() -> Node: return get_node_or_null("/root/GameState")

# -----------------------------
# PIN (local, session-only)
# -----------------------------
@export var default_pin: String = "0000"
var _pin: String = ""
var _unlocked: bool = false

# -----------------------------
# PIN Gate (BG1) — drag these in Inspector
# -----------------------------
@export var bg_gate_path: NodePath                # BG1 container
@export var pin_line_path: NodePath               # BG1/PIN (LineEdit)
@export var wrong_pin_path: NodePath              # BG1/Wrong Pin (Label/Control)
@export var dev_tools_root_path: NodePath         # DEV TOOLS container

@onready var _bg: Control        = get_node_or_null(bg_gate_path) as Control
@onready var _pin_line: LineEdit = get_node_or_null(pin_line_path) as LineEdit
@onready var _wrong_pin: Control = get_node_or_null(wrong_pin_path) as Control
@onready var _tools: Control     = get_node_or_null(dev_tools_root_path) as Control

# -----------------------------
# Locations / Day
# -----------------------------
@export var btn_city_path: NodePath
@export var btn_school_path: NodePath
@export var btn_home_path: NodePath
@export var btn_mvr_path: NodePath
@export var btn_yco_path: NodePath

@export var day_minus_path: NodePath
@export var day_label_path: NodePath               # shows "Day X"
@export var day_plus_path: NodePath

@onready var _btn_city: Button   = get_node_or_null(btn_city_path) as Button
@onready var _btn_school: Button = get_node_or_null(btn_school_path) as Button
@onready var _btn_home: Button   = get_node_or_null(btn_home_path) as Button
@onready var _btn_mvr: Button    = get_node_or_null(btn_mvr_path) as Button
@onready var _btn_yco: Button    = get_node_or_null(btn_yco_path) as Button

@onready var _day_minus: Button  = get_node_or_null(day_minus_path) as Button
@onready var _day_label: Label   = get_node_or_null(day_label_path) as Label
@onready var _day_plus: Button   = get_node_or_null(day_plus_path) as Button

# -----------------------------
# Clock / Time step / Pause / Stats
# -----------------------------
@export var clock_label_path: NodePath
@export var tstep_minus_path: NodePath
@export var tstep_edit_path: NodePath
@export var tstep_plus_path: NodePath
@export var pause_btn_path: NodePath
@export var unpause_btn_path: NodePath
@export var rep_edit_path: NodePath
@export var int_edit_path: NodePath

@onready var _clock_label: Label   = get_node_or_null(clock_label_path) as Label
@onready var _tstep_minus: Button  = get_node_or_null(tstep_minus_path) as Button
@onready var _tstep_edit: LineEdit = get_node_or_null(tstep_edit_path) as LineEdit
@onready var _tstep_plus: Button   = get_node_or_null(tstep_plus_path) as Button
@onready var _pause_btn: Button    = get_node_or_null(pause_btn_path) as Button
@onready var _unpause_btn: Button  = get_node_or_null(unpause_btn_path) as Button
@onready var _rep_edit: LineEdit   = get_node_or_null(rep_edit_path) as LineEdit
@onready var _int_edit: LineEdit   = get_node_or_null(int_edit_path) as LineEdit

# -----------------------------
# Flags UI
# -----------------------------
@export var flag_list_path: NodePath
@export var search_edit_path: NodePath
@export var toggle_btn_path: NodePath

@onready var _flag_list: ItemList   = get_node_or_null(flag_list_path) as ItemList
@onready var _search_edit: LineEdit = get_node_or_null(search_edit_path) as LineEdit
@onready var _toggle_btn: Button    = get_node_or_null(toggle_btn_path) as Button

# -----------------------------
# Exit / Back
# -----------------------------
@export var exit_btn_path: NodePath
@onready var _exit_btn: Button = get_node_or_null(exit_btn_path) as Button

# -----------------------------
# Internal state
# -----------------------------
var _pending_scene: String = ""
var _flag_keys: Array[String] = []

# -----------------------------
# Lifecycle
# -----------------------------
func _ready() -> void:
	_pin = default_pin
	_unlocked = false

	# Overlay behavior: hide game HUD while devtools is open
	GameUi.hide_ui()

	# Force "Unknown" logical location while panel is up
	var gs := _GS()
	if gs:
		gs.set("location", "Unknown")

	_wire_signals()
	_apply_unlock_state(false)     # start on PIN screen
	_setup_field_limits()
	_refresh_all_ui()
	# Apply theme to toggle button
	if _toggle_btn:
		var theme := load("res://Themes/DEVTOOLSBTNS.tres") as Theme
		if theme:
			_toggle_btn.theme = theme
func _setup_field_limits() -> void:
	if _tstep_edit:
		_tstep_edit.max_length = 2
	if _rep_edit:
		_rep_edit.max_length = 3
	if _int_edit:
		_int_edit.max_length = 3
	if _wrong_pin:
		_wrong_pin.visible = false

# -----------------------------
# Signals wiring
# -----------------------------
func _wire_signals() -> void:
	# PIN submit: Enter inside LineEdit submits
	if _pin_line:
		_pin_line.text_submitted.connect(_on_pin_submitted)

	# Location select
	if _btn_city:
		_btn_city.pressed.connect(func(): _select_scene(PATH_CITY))
	if _btn_school:
		_btn_school.pressed.connect(func(): _select_scene(PATH_SCHOOL))
	if _btn_home:
		_btn_home.pressed.connect(func(): _select_scene(PATH_HOME))
	if _btn_mvr:
		_btn_mvr.pressed.connect(func(): _select_scene(PATH_MVR))
	if _btn_yco:
		_btn_yco.pressed.connect(func(): _select_scene(PATH_YCO))

	# Day +/-
	if _day_minus:
		_day_minus.pressed.connect(func(): _nudge_day(-1))
	if _day_plus:
		_day_plus.pressed.connect(func(): _nudge_day(1))

	# Time step +/-
	if _tstep_minus:
		_tstep_minus.pressed.connect(func(): _nudge_time(-_read_step_minutes()))
	if _tstep_plus:
		_tstep_plus.pressed.connect(func(): _nudge_time(_read_step_minutes()))
	if _tstep_edit:
		_tstep_edit.text_submitted.connect(func(_t: String): _clamp_step_field())

	# Pause/Unpause
	if _pause_btn:
		_pause_btn.pressed.connect(func(): _freeze_true())
	if _unpause_btn:
		_unpause_btn.pressed.connect(func(): _freeze_false())

	# Rep/Int updates (Enter or focus exit)
	if _rep_edit:
		_rep_edit.text_submitted.connect(func(_t: String): _apply_rep_from_field())
		_rep_edit.focus_exited.connect(_apply_rep_from_field)
	if _int_edit:
		_int_edit.text_submitted.connect(func(_t: String): _apply_int_from_field())
		_int_edit.focus_exited.connect(_apply_int_from_field)

	# Flags & search
	if _flag_list:
		_flag_list.item_selected.connect(_on_flag_selected)
	if _search_edit:
		_search_edit.text_changed.connect(func(t: String): _rebuild_flags_list(t))
	if _toggle_btn:
		_toggle_btn.pressed.connect(_on_toggle_flag)

	# Exit
	if _exit_btn:
		_exit_btn.pressed.connect(_on_exit_pressed)

	# GameState signals
	var gs := _GS()
	if gs:
		if gs.has_signal("time_changed"):
			gs.connect("time_changed", Callable(self, "_on_time_changed"))
		if gs.has_signal("flag_changed"):
			gs.connect("flag_changed", Callable(self, "_on_flag_changed"))

# -----------------------------
# Unlock state (local)
# -----------------------------
func apply_unlock_state(unlocked: bool) -> void:
	_apply_unlock_state(unlocked)

func set_unlocked(unlocked: bool) -> void:
	_apply_unlock_state(unlocked)

func _apply_unlock_state(unlocked: bool) -> void:
	_unlocked = unlocked
	if _bg:
		_bg.visible = not _unlocked
	if _tools:
		_tools.visible = _unlocked
	if _unlocked:
		if _tools:
			_tools.grab_focus()
	else:
		if _wrong_pin:
			_wrong_pin.visible = false

# -----------------------------
# PIN handling (local compare)
# -----------------------------
func _on_pin_submitted(text: String) -> void:
	var pin := text.strip_edges()
	if pin == "":
		return

	if pin == _pin:
		_apply_unlock_state(true)
		if _pin_line:
			_pin_line.clear()
	else:
		if _wrong_pin:
			_wrong_pin.visible = true
			await get_tree().create_timer(2.0).timeout
			_wrong_pin.visible = false

# -----------------------------
# Locations / Exit
# -----------------------------
func _select_scene(path: String) -> void:
	_pending_scene = path
	_set_location_button_states(path)

func _set_location_button_states(path: String) -> void:
	var buttons: Array[Button] = []
	if _btn_city:
		buttons.append(_btn_city)
	if _btn_school:
		buttons.append(_btn_school)
	if _btn_home:
		buttons.append(_btn_home)
	if _btn_mvr:
		buttons.append(_btn_mvr)
	if _btn_yco:
		buttons.append(_btn_yco)

	for b in buttons:
		b.disabled = false

	if path == PATH_CITY and _btn_city:
		_btn_city.disabled = true
	elif path == PATH_SCHOOL and _btn_school:
		_btn_school.disabled = true
	elif path == PATH_HOME and _btn_home:
		_btn_home.disabled = true
	elif path == PATH_MVR and _btn_mvr:
		_btn_mvr.disabled = true
	elif path == PATH_YCO and _btn_yco:
		_btn_yco.disabled = true

func _on_exit_pressed() -> void:
	_emergency_close_interactions()

	# Restore UI before we leave
	GameUi.show_ui()

	# Jump if a target was picked
	if _pending_scene != "":
		var fade := get_node_or_null("/root/Fade")
		if fade and fade.has_method("fade_to_scene"):
			fade.call("fade_to_scene", _pending_scene)
		else:
			get_tree().change_scene_to_file(_pending_scene)
		_pending_scene = ""

	# Close the overlay
	queue_free()

# -----------------------------
# Emergency close: dialogues / choices
# -----------------------------
func _emergency_close_interactions() -> void:
	var dm := get_node_or_null("/root/DialogueManager")
	if dm:
		if dm.has_method("abort"):
			dm.call("abort")
		if dm.has_method("stop"):
			dm.call("stop")
		if dm.has_method("end_dialogue"):
			dm.call("end_dialogue")
		if dm.has_method("finish"):
			dm.call("finish")
		if dm.has_method("close"):
			dm.call("close")

	var names := [
		"CharacterChoiceButtons", "ChoicePanel", "choice_panel",
		"DialoguePanel", "DialogueUI", "DialogueBox", "Dialog", "Dialogue"
	]
	for n in names:
		var node := get_tree().root.find_child(n, true, false)
		if node and node is Control:
			(node as Control).hide()

# -----------------------------
# Day / Time
# -----------------------------
func _nudge_day(delta: int) -> void:
	var gs := _GS()
	if gs == null:
		return
	var d: int = int(gs.get("day")) + delta
	if d < 1:
		d = 1
	gs.set("day", d)
	if gs.has_signal("time_changed"):
		gs.emit_signal("time_changed", int(gs.get("time")), d)

func _read_step_minutes() -> int:
	var step: int = 30
	if _tstep_edit:
		var t: String = _tstep_edit.text.strip_edges()
		if t.is_valid_int():
			step = int(t)
	if step < 1:
		step = 1
	if step > 99:
		step = 99
	_clamp_step_field_value(step)
	return step

func _clamp_step_field() -> void:
	var step: int = _read_step_minutes()
	_clamp_step_field_value(step)

func _clamp_step_field_value(v: int) -> void:
	if _tstep_edit:
		_tstep_edit.text = str(v)

func _nudge_time(delta_minutes: int) -> void:
	var gs := _GS()
	if gs == null:
		return
	gs.call("adjust_time", delta_minutes)  # respects curfew & emits time_changed

func _on_time_changed(new_time: int, new_day: int) -> void:
	_update_day_label(new_day)
	_update_clock_label(new_time)

func _update_day_label(d: int) -> void:
	if _day_label:
		_day_label.text = "Day " + str(d)

func _update_clock_label(t: int) -> void:
	if _clock_label:
		var h: int = t / 60
		var m: int = t % 60
		_clock_label.text = "%02d:%02d" % [h, m]

# -----------------------------
# Pause / Unpause
# -----------------------------
func _freeze_true() -> void:
	var gs := _GS()
	if gs:
		gs.call("push_time_freeze", "__devtools__")

func _freeze_false() -> void:
	var gs := _GS()
	if gs:
		gs.call("pop_time_freeze", "__devtools__")

# -----------------------------
# Rep / Integrity absolute set
# -----------------------------
func _apply_rep_from_field() -> void:
	if _rep_edit == null:
		return
	var gs := _GS()
	if gs == null:
		return
	var current: int = int(gs.get("reputation"))
	var v: int = _parse_int_0_100(_rep_edit.text, current)
	gs.set("reputation", v)
	_rep_edit.clear()
	_rep_edit.placeholder_text = str(v)

func _apply_int_from_field() -> void:
	if _int_edit == null:
		return
	var gs := _GS()
	if gs == null:
		return
	var current: int = int(gs.get("integrity"))
	var v: int = _parse_int_0_100(_int_edit.text, current)
	gs.set("integrity", v)
	_int_edit.clear()
	_int_edit.placeholder_text = str(v)

func _parse_int_0_100(s: String, fallback: int) -> int:
	var v: int = fallback
	var t: String = s.strip_edges()
	if t.is_valid_int():
		v = int(t)
	if v < 0:
		v = 0
	if v > 100:
		v = 100
	return v

# -----------------------------
# Flags list / search / toggle
# -----------------------------
func _rebuild_flags_list(filter_text: String) -> void:
	if _flag_list == null:
		return
	_flag_list.clear()
	_flag_keys.clear()

	var gs := _GS()
	if gs == null:
		return
	var flags_dict := gs.get("flags") as Dictionary

	var keys_raw := flags_dict.keys() as Array
	var keys: Array[String] = []
	for k in keys_raw:
		keys.append(String(k))
	keys.sort()

	var f: String = filter_text.strip_edges().to_lower()
	for key in keys:
		var val = flags_dict.get(key)
		if typeof(val) != TYPE_BOOL:
			continue
		var passes := true
		if f != "":
			if not key.to_lower().contains(f):
				passes = false
		if not passes:
			continue

		var on: bool = bool(val)
		var label: String = ""
		if on:
			label = "✓ " + key
		else:
			label = "✗ " + key

		var idx: int = _flag_list.add_item(label)
		_flag_keys.append(key)
		_colorize_flag_row(idx, on)
		_flag_list.set_item_metadata(idx, key)

	_update_toggle_btn_enabled(_flag_list.get_selected_items().size() > 0)

func _colorize_flag_row(index: int, on: bool) -> void:
	if _flag_list == null:
		return
	var col: Color
	if on:
		col = Color(0.75, 1.0, 0.75)
	else:
		col = Color(1.0, 0.75, 0.75)
	_flag_list.set_item_custom_fg_color(index, col)

func _on_flag_selected(index: int) -> void:
	var key: String = _get_flag_key_by_index(index)
	if key == "":
		_update_toggle_btn_enabled(false)
		return
	_update_toggle_btn_enabled(true)
	_update_toggle_label_for_flag(key)

func _on_toggle_flag() -> void:
	if _flag_list == null:
		return
	var sel: PackedInt32Array = _flag_list.get_selected_items()
	if sel.size() == 0:
		return
	var index: int = int(sel[0])
	var key: String = _get_flag_key_by_index(index)
	if key == "":
		return

	var gs := _GS()
	if gs == null:
		return
	var flags_dict := gs.get("flags") as Dictionary
	var cur: bool = bool(flags_dict.get(key, false))
	var next: bool = not cur
	gs.call("set_flag", key, next)  # emits flag_changed

	var label: String = ""
	if next:
		label = "✓ " + key
	else:
		label = "✗ " + key

	_flag_list.set_item_text(index, label)
	_colorize_flag_row(index, next)
	_update_toggle_label(next)

func _get_flag_key_by_index(index: int) -> String:
	if index >= 0 and index < _flag_keys.size():
		return _flag_keys[index]
	return ""

func _update_toggle_btn_enabled(en: bool) -> void:
	if _toggle_btn == null:
		return
	_toggle_btn.disabled = not en
	if not en:
		_toggle_btn.text = "(Select a flag)"

func _update_toggle_label_for_flag(key: String) -> void:
	if _toggle_btn == null:
		return
	var gs := _GS()
	if gs == null:
		return
	var flags_dict := gs.get("flags") as Dictionary
	var val: bool = bool(flags_dict.get(key, false))
	_update_toggle_label(val)

func _update_toggle_label(current_val: bool) -> void:
	if _toggle_btn == null:
		return
	if current_val:
		_toggle_btn.text = "FALSE"
	else:
		_toggle_btn.text = "TRUE"

func _on_flag_changed(flag: String, value: bool) -> void:
	if _flag_list == null:
		return
	var idx: int = _flag_keys.find(flag)
	if idx == -1:
		return

	var label: String = ""
	if value:
		label = "✓ " + flag
	else:
		label = "✗ " + flag

	_flag_list.set_item_text(idx, label)
	_colorize_flag_row(idx, value)
	_update_toggle_label(value)

# -----------------------------
# Initial UI refresh
# -----------------------------
func _refresh_all_ui() -> void:
	_refresh_stats_placeholders()
	_rebuild_flags_list(_search_text())
	_refresh_time_and_day_now()

func _refresh_stats_placeholders() -> void:
	var gs := _GS()
	if gs == null:
		return
	if _rep_edit:
		_rep_edit.placeholder_text = str(int(gs.get("reputation")))
	if _int_edit:
		_int_edit.placeholder_text = str(int(gs.get("integrity")))

func _refresh_time_and_day_now() -> void:
	var gs := _GS()
	if gs == null:
		return
	_on_time_changed(int(gs.get("time")), int(gs.get("day")))

func _search_text() -> String:
	if _search_edit:
		return _search_edit.text
	return ""
