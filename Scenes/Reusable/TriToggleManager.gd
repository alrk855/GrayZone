extends Control
# --- BUTTON PATHS (edit these to your actual node paths) ---
var time_btn_path:  NodePath = NodePath("time")
var day_btn_path:   NodePath = NodePath("day")
var money_btn_path: NodePath = NodePath("money")
 
# --- LABEL PATHS (these live in your other panel) ---
var label_time_path:   NodePath = NodePath("../Padding/Border/Time")
var label_day_path:    NodePath = NodePath("../Padding/Border/Day")
var label_money_path:  NodePath = NodePath("../Padding/Border/Money")
var label_default_path:NodePath = NodePath("../Padding/Border/Default")

# --- resolved refs ---
var _btn_time:  BaseButton
var _btn_day:   BaseButton
var _btn_money: BaseButton

var _lbl_time:    CanvasItem
var _lbl_day:     CanvasItem
var _lbl_money:   CanvasItem
var _lbl_default: CanvasItem

var _guard := false  # prevent re-entrant toggled() loops

func _ready() -> void:
	# Resolve buttons
	_btn_time  = get_node_or_null(time_btn_path)  as BaseButton
	_btn_day   = get_node_or_null(day_btn_path)   as BaseButton
	_btn_money = get_node_or_null(money_btn_path) as BaseButton

	# Ensure toggle_mode and connect
	_setup_btn(_btn_time,  "_on_btn_toggled_time")
	_setup_btn(_btn_day,   "_on_btn_toggled_day")
	_setup_btn(_btn_money, "_on_btn_toggled_money")

	# Resolve labels
	_lbl_time    = get_node_or_null(label_time_path)    as CanvasItem
	_lbl_day     = get_node_or_null(label_day_path)     as CanvasItem
	_lbl_money   = get_node_or_null(label_money_path)   as CanvasItem
	_lbl_default = get_node_or_null(label_default_path) as CanvasItem

	# Initial state
	_set_all_pressed_false()
	_show_default()

func _setup_btn(b: BaseButton, method_name: String) -> void:
	if b == null: return
	if not b.toggle_mode:
		b.toggle_mode = true
	b.set_pressed_no_signal(false)
	b.toggled.connect(Callable(self, method_name))

# --- Toggled handlers (one per button, simple & explicit) ---
func _on_btn_toggled_time(pressed: bool) -> void:
	_on_btn_toggled(pressed, "time")

func _on_btn_toggled_day(pressed: bool) -> void:
	_on_btn_toggled(pressed, "day")

func _on_btn_toggled_money(pressed: bool) -> void:
	_on_btn_toggled(pressed, "money")

func _on_btn_toggled(pressed: bool, which: String) -> void:
	if _guard: return
	_guard = true

	if pressed:
		# exclusivity
		match which:
			"time":
				_btn_day.set_pressed_no_signal(false)
				_btn_money.set_pressed_no_signal(false)
				_show_only_time()
			"day":
				_btn_time.set_pressed_no_signal(false)
				_btn_money.set_pressed_no_signal(false)
				_show_only_day()
			"money":
				_btn_time.set_pressed_no_signal(false)
				_btn_day.set_pressed_no_signal(false)
				_show_only_money()
	else:
		# if none remain pressed -> show default
		if not _any_pressed():
			_show_default()

	_guard = false

func _any_pressed() -> bool:
	return ((_btn_time and _btn_time.button_pressed)
		or  (_btn_day and _btn_day.button_pressed)
		or  (_btn_money and _btn_money.button_pressed))

func _set_all_pressed_false() -> void:
	if _btn_time:  _btn_time.set_pressed_no_signal(false)
	if _btn_day:   _btn_day.set_pressed_no_signal(false)
	if _btn_money: _btn_money.set_pressed_no_signal(false)

# --- label helpers ---
func _hide_all_specific() -> void:
	if _lbl_time:  _lbl_time.visible = false
	if _lbl_day:   _lbl_day.visible = false
	if _lbl_money: _lbl_money.visible = false

func _show_default() -> void:
	_hide_all_specific()
	if _lbl_default: _lbl_default.visible = true

func _show_only_time() -> void:
	if _lbl_default: _lbl_default.visible = false
	_hide_all_specific()
	if _lbl_time: _lbl_time.visible = true

func _show_only_day() -> void:
	if _lbl_default: _lbl_default.visible = false
	_hide_all_specific()
	if _lbl_day: _lbl_day.visible = true

func _show_only_money() -> void:
	if _lbl_default: _lbl_default.visible = false
	_hide_all_specific()
	if _lbl_money: _lbl_money.visible = true
