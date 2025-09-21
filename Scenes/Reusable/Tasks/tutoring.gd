# res://Scripts/Scenes/TutoringScene.gd
extends Control

signal session_chosen(kind: String)  # "1h" | "3h"

# ---------- Background ----------
@export_node_path(TextureRect) var texture_rect_path: NodePath = "TextureRect"
@onready var bg_rect: TextureRect = get_node_or_null(texture_rect_path)
@export var bg_male: Texture2D
@export var bg_female: Texture2D

# ---------- Dialogue / JSONs ----------
@export_file("*.json") var intro_json_path: String  = "res://Data/Activities/Tutoring/Tutoring_Intro.json"
@export_file("*.json") var json_1h_path: String     = "res://Data/Activities/Tutoring/Tutoring_1h.json"
@export_file("*.json") var json_3h_path: String     = "res://Data/Activities/Tutoring/Tutoring_3h.json"

# ---------- Choice panel ----------
@export_file("*.tscn") var choice_panel_path: String = "res://Scenes/Reusable/CharacterChoiceButtons.tscn"
var _choice_panel: Control = null

# ---------- Return scene ----------
@export_file("*.tscn") var return_scene_path: String = "res://Scenes/Reusable/Map/City.tscn"

# ---------- Rewards / Durations ----------
const MONEY_1H: int = 200
const TIME_1H: int = 60

const MONEY_3H: int = 600
const TIME_3H: int = 180

func _ready() -> void:
	GameState.location = "Tutoring"
	_set_background_for_gender()

	# Intro narration
	await _run_dialogue(intro_json_path)

	# Ask using CharacterChoiceButtons
	var pick := await _ask_session_choice()
	if pick == "1h":
		await _run_dialogue(json_1h_path)
		_apply_rewards(MONEY_1H, TIME_1H)
	elif pick == "3h":
		await _run_dialogue(json_3h_path)
		_apply_rewards(MONEY_3H, TIME_3H)
	else:
		# Safety: if something went weird, default to 1h
		await _run_dialogue(json_1h_path)
		_apply_rewards(MONEY_1H, TIME_1H)

	# Exit smoothly
	await fade.fade_out()
	get_tree().change_scene_to_file(return_scene_path)
	await fade.fade_in()

# -----------------------------
# Helpers
# -----------------------------
func _set_background_for_gender() -> void:
	if bg_rect == null:
		push_error("TutoringScene: TextureRect not found. Check 'texture_rect_path'.")
		return

	var g := ""
	if GameState != null:
		var tmp = GameState.get("player_gender")
		if tmp != null:
			g = String(tmp).to_lower()

	if g == "female":
		bg_rect.texture = bg_female
	else:
		bg_rect.texture = bg_male

func _run_dialogue(json_path: String) -> void:
	var ui = DialogueManager.start_dialogue(json_path, self)
	if ui != null and ui.has_signal("dialogue_finished"):
		await ui.dialogue_finished

func _apply_rewards(money: int, minutes: int) -> void:
	# Money
	if GameState != null:
		if GameState.has_method("add_money"):
			GameState.add_money(money)
		elif GameState.has_method("change_money"):
			GameState.change_money(money)
		else:
			var cur = GameState.get("money")
			if cur == null:
				cur = 0
			GameState.set("money", int(cur) + money)
			if GameState.has_signal("money_changed"):
				GameState.emit_signal("money_changed", GameState.get("money"))

	# Time (+minutes forward)
	if GameState.has_method("advance_time_minutes"):
		GameState.advance_time_minutes(minutes)
	elif GameState.has_method("add_minutes"):
		GameState.add_minutes(minutes)
	else:
		var t = int(GameState.get("time") if GameState.has_method("get") else 0)
		var d = int(GameState.get("day") if GameState.has_method("get") else 1)
		var new_total := t + minutes
		var per_day := 24 * 60
		var day_bump := new_total / per_day
		var new_minutes := new_total % per_day
		GameState.set("time", new_minutes)
		GameState.set("day", d + day_bump)
		if GameState.has_signal("time_changed"):
			GameState.emit_signal("time_changed", GameState.get("time"), GameState.get("day"))

# -----------------------------
# CharacterChoiceButtons usage
# -----------------------------
func _ask_session_choice() -> String:
	# Instantiate your reusable panel
	var scene := load(choice_panel_path)
	if scene == null:
		push_error("TutoringScene: Cannot load CharacterChoiceButtons.tscn")
		return "1h"

	_choice_panel = scene.instantiate()
	add_child(_choice_panel)

	# Find two buttons inside that scene and configure them.
	var btns := _find_choice_buttons(_choice_panel)
	if btns.size() < 2:
		push_error("TutoringScene: Could not find two buttons in CharacterChoiceButtons.")
		return "1h"

	# Configure exactly two choices; hide/disable the rest if present
	for i in btns.size():
		btns[i].visible = i < 2
		btns[i].disabled = i >= 2

	btns[0].text = "1 hour (200 ден)"
	btns[1].text = "3 hours (600 ден)"

	# Wire up signals to emit our own unified signal
	if not is_connected("session_chosen", Callable(self, "_on_session_chosen_internal")):
		connect("session_chosen", Callable(self, "_on_session_chosen_internal"))

	btns[0].pressed.connect(func():
		_disable_buttons(btns)
		emit_signal("session_chosen", "1h")
	)
	btns[1].pressed.connect(func():
		_disable_buttons(btns)
		emit_signal("session_chosen", "3h")
	)

	var kind := await session_chosen
	if is_instance_valid(_choice_panel):
		_choice_panel.queue_free()
	return kind

func _on_session_chosen_internal(_kind: String) -> void:
	# noop, but keeps a clear hook if you want side-effects on selection
	pass

func _disable_buttons(btns: Array) -> void:
	for b in btns:
		if b is Button:
			b.disabled = true

func _find_choice_buttons(root: Node) -> Array[Button]:
	var out: Array[Button] = []
	_collect_buttons_recursive(root, out)
	# Prefer deterministic order by node name
	out.sort_custom(func(a, b): return String(a.name) < String(b.name))
	return out

func _collect_buttons_recursive(n: Node, out: Array[Button]) -> void:
	if n is Button:
		out.append(n)
	for c in n.get_children():
		_collect_buttons_recursive(c, out)
