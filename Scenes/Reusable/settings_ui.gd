extends CanvasLayer
# Root is a CanvasLayer; there is another CanvasLayer inside for the Buttons.

# --- Paths (adjust if needed) ---
const HELP_SCENE_PATH      := "res://Scenes/Reusable/Tutorial.tscn"
const MAIN_MENU_SCENE_PATH := "res://Scenes/main_menu.tscn"
const CLICK_SFX_PATH       := "res://Audio/u4.mp3"
const HOVER_SFX_PATH       := "res://Audio/u1.mp3"
# --------------------------------

# Layers
@onready var _root_layer    : CanvasLayer = self
@onready var _buttons_layer : CanvasLayer = $Settings_Control/CardRoot/PanelContainer/VBoxContainer/CanvasLayer  # inner layer

# UI (match your hierarchy)
@onready var _help_btn          : Button = $Settings_Control/CardRoot/PanelContainer/VBoxContainer/TitleRow/HelpSettings
@onready var _exit_btn          : Button = $Settings_Control/CardRoot/PanelContainer/VBoxContainer/TitleRow/ExitSettings

@onready var _click_player      : AudioStreamPlayer2D = $Settings_Control/CardRoot/PanelContainer/VBoxContainer/Click
@onready var _hover_player      : AudioStreamPlayer2D = $Settings_Control/CardRoot/PanelContainer/VBoxContainer/Hover

@onready var _padding_container : HBoxContainer = $Settings_Control/CardRoot/PanelContainer/VBoxContainer/PaddingContainer

@onready var _buttons_box       : VBoxContainer   = $Settings_Control/CardRoot/PanelContainer/VBoxContainer/CanvasLayer/Buttons
@onready var _btn_main_menu     : Button          = $Settings_Control/CardRoot/PanelContainer/VBoxContainer/CanvasLayer/Buttons/MainMenu
@onready var _btn_quit          : Button          = $Settings_Control/CardRoot/PanelContainer/VBoxContainer/CanvasLayer/Buttons/Quit   # repurposed
@onready var _btn_load_hidden   : Button          = $Settings_Control/CardRoot/PanelContainer/VBoxContainer/CanvasLayer/Buttons/Load   # hidden

func _ready() -> void:
	# Keep layers above the world/HUD
	if _root_layer.layer < 100:
		_root_layer.layer = 100
	if _buttons_layer:
		_buttons_layer.layer = _root_layer.layer + 1

	# Start closed (autoload opens it)
	hide_settings()

	# SFX
	_set_stream_if_empty(_click_player, CLICK_SFX_PATH)
	_set_stream_if_empty(_hover_player, HOVER_SFX_PATH)

	# Rewire buttons: Save -> Quit; hide Load
	_btn_load_hidden.visible = false
	_btn_load_hidden.disabled = true

	# Wire handlers
	_help_btn.pressed.connect(_on_help_pressed)
	_exit_btn.pressed.connect(_on_exit_pressed)

	_btn_main_menu.pressed.connect(_on_main_menu_pressed)
	_btn_quit.pressed.connect(_on_quit_pressed)

	# Hover/click SFX for visible buttons
	for b in [_help_btn, _exit_btn, _btn_main_menu, _btn_quit]:
		b.mouse_entered.connect(_play_hover_sfx)
		b.pressed.connect(_play_click_sfx)

# --------- Public API (used by Autoload) ---------

func show_settings() -> void:
	_root_layer.visible = true
	if _buttons_layer:
		_buttons_layer.visible = true
	_show_menu_state()

func hide_settings() -> void:
	_root_layer.visible = false
	if _buttons_layer:
		_buttons_layer.visible = false

func is_open() -> bool:
	if _root_layer.visible:
		return true
	if _buttons_layer and _buttons_layer.visible:
		return true
	return false

# --------------- UI state -----------------

func _show_menu_state() -> void:
	_buttons_box.visible = true
	_padding_container.visible = true

# --------------- Handlers -----------------

func _on_help_pressed() -> void:
	var tree := get_tree()

	# Mark context BEFORE switching: opened from in-game (not menu)
	tree.set_meta("tutorial_from_menu", false)

	# Remember previous scene path
	var prev := ""
	if tree.current_scene != null:
		prev = tree.current_scene.scene_file_path
	tree.set_meta("tutorial_prev_scene_path", prev)

	# Hide your persistent game UI (Singleton)
	GameUi.visible = false

	# Lock location so nothing else opens over tutorial
	tree.set_meta("tutorial_prev_location", String(GameState.location))
	GameState.location = "Unknown"

	# Freeze gameplay time WITHOUT pausing the engine
	GameState.push_time_freeze("tutorial")

	hide_settings()  # optional: hide settings before switching
	tree.change_scene_to_file(HELP_SCENE_PATH)

func _on_exit_pressed() -> void:
	hide_settings()

func _on_main_menu_pressed() -> void:
	# Block while dialogue is active (no UI change, just ignore)
	if _is_dialogue_active():
		_play_click_sfx() # soft feedback
		return
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)

func _on_quit_pressed() -> void:
	get_tree().quit()

# --------------- Dialogue detection -----------------

func _is_dialogue_active() -> bool:
	var root: Node = get_tree().get_root()

	# 1) Our always-used choice UI
	var ccb: Node = root.find_child("CharacterChoiceButtons", true, false)
	if ccb is Control and (ccb as Control).visible:
		return true

	# 2) Common dialogue groups (if you use them)
	for group_name in ["dialogue", "dialogue_ui", "Dialogue", "DialogueUI"]:
		for n in get_tree().get_nodes_in_group(group_name):
			if n is Control and (n as Control).visible:
				return true

	# 3) Common node names
	var dlg: Node = root.find_child("Dialogue", true, false)
	if dlg is Control and (dlg as Control).visible:
		return true

	return false

# ----------------- SFX --------------------

func _set_stream_if_empty(player: AudioStreamPlayer2D, res_path: String) -> void:
	if player and player.stream == null and res_path != "":
		var s: Resource = load(res_path)
		if s:
			player.stream = s

func _play_click_sfx() -> void:
	if _click_player and _click_player.stream:
		_click_player.play()

func _play_hover_sfx() -> void:
	if _hover_player and _hover_player.stream:
		_hover_player.play()
