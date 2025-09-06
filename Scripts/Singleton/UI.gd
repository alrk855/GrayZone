extends CanvasLayer
# =================== UI (time/day/money + notifications) ===================

# ---- Assign in the inspector ----
@export var time: RichTextLabel
@export var money: RichTextLabel
@export var day: RichTextLabel

# Slots can be PanelContainers/HBoxes/etc.; each must contain a Label somewhere inside.
@export var notification_nodes: Array[Control] = []

# ---- Notification config ----
@export var visible_slots: int = 4
@export var anchor_y: int = 50        # final y = anchor_y + step_y * (1..N)
@export var step_y: int = 50
@export var slide_dur: float = 0.30
@export var stay_dur: float = 2.00
@export var fade_dur: float = 0.45

# ---- Extras ----
@export var sfx_show: AudioStream     # optional whoosh; drop a file here later
@export var notif_font: Font          # optional custom font for the slot Labels

var _queue: Array[String] = []
var _active: Array[Control] = []      # oldest first
var _tweens: Dictionary = {}          # node -> Tween
var _label_cache: Dictionary = {}     # Control -> Label
var _sfx_player: AudioStreamPlayer

# ============================ READY ============================
func _ready() -> void:
	# SFX player (simple; uses defaults)
	_sfx_player = AudioStreamPlayer.new()
	add_child(_sfx_player)

	# Hide/reset notifications and prep fonts
	for n: Control in notification_nodes:
		if n:
			n.visible = false
			n.modulate.a = 0.0
			n.position.y = anchor_y
			var lbl := _label_for(n)
			if lbl and notif_font:
				lbl.add_theme_font_override("font", notif_font)

	# wait a frame so singletons/autoloads are ready
	await get_tree().process_frame

	# --- Connect GameState signals ---
	if is_instance_valid(GameState):
		var c_money := Callable(self, "_on_money_changed")
		if not GameState.is_connected("money_changed", c_money):
			GameState.money_changed.connect(c_money)

		var c_time := Callable(self, "_on_time_changed")
		if not GameState.is_connected("time_changed", c_time):
			GameState.time_changed.connect(c_time)

		# Task notifications only (no flag toasts)
		var c_added := Callable(self, "_on_task_added")
		if not GameState.is_connected("task_added", c_added):
			GameState.task_added.connect(c_added)

		var c_updated := Callable(self, "_on_task_updated")
		if not GameState.is_connected("task_updated", c_updated):
			GameState.task_updated.connect(c_updated)

	# Initial sync
	_on_time_changed(GameState.time, GameState.day)
	_on_money_changed(GameState.money)

# ===================== TOP-BAR UPDATE HANDLERS =====================
func _on_money_changed(new_money: int) -> void:
	if money:
		money.text = str(new_money)

func _on_time_changed(time_minutes: int, current_day: int) -> void:
	if time:
		time.text = "%02d:%02d" % [time_minutes / 60, time_minutes % 60]
	if day:
		day.text = "Day %d" % current_day

# ======================== PUBLIC NOTIFY API ========================
func notify(text: String) -> void:
	var msg: String = text.strip_edges()
	if msg == "":
		return
	_queue.append(msg)
	_drain_queue()

func notify_task_added(task_id: String) -> void:
	notify("Task added: " + task_id)

func notify_task_updated(task_id: String, step_index: int) -> void:
	notify("Task updated: %s → Step %d" % [task_id, step_index])

# =================== GameState → notifications ===================
func _on_task_added(task_id: String) -> void:
	notify_task_added(task_id)

func _on_task_updated(task_id: String, step_index: int) -> void:
	notify_task_updated(task_id, step_index)

# ========================= NOTIFY ENGINE =========================
func _drain_queue() -> void:
	var cap: int = clamp(visible_slots, 1, notification_nodes.size())
	while _queue.size() > 0 and _active.size() < cap:
		var slot: Control = _get_free_slot()
		if slot == null:
			break
		var msg: String = String(_queue.pop_front())
		_show_in_slot(slot, msg)

func _get_free_slot() -> Control:
	for n: Control in notification_nodes:
		if n and _active.find(n) == -1:
			return n
	return null

func _show_in_slot(node: Control, msg: String) -> void:
	_set_slot_text(node, msg)
	_active.append(node)

	node.visible = true
	node.position.y = anchor_y
	node.modulate.a = 0.0

	var target_y: int = anchor_y + step_y * _active.size() # 1-based stacking
	var tw: Tween = create_tween()
	_tweens[node] = tw

	tw.tween_property(node, "modulate:a", 1.0, 0.15)              # fade in
	tw.tween_property(node, "position:y", target_y, slide_dur)     # slide down
	tw.tween_interval(stay_dur)                                    # stay
	tw.tween_property(node, "modulate:a", 0.0, fade_dur)           # fade out
	tw.tween_callback(Callable(self, "_finish_slot").bind(node))

	_play_notify_sound()

func _finish_slot(node: Control) -> void:
	if node:
		node.visible = false
		node.position.y = anchor_y
		_tweens.erase(node)

	_active.erase(node)
	_restack_active()
	_drain_queue()

func _restack_active() -> void:
	for i in range(_active.size()):
		var n: Control = _active[i]
		var target_y: int = anchor_y + step_y * (i + 1)
		var tw: Tween = create_tween()
		_tweens[n] = tw
		tw.tween_property(n, "position:y", target_y, slide_dur * 0.8)

# ======================== Convenience =========================
func set_notifications_spacing(step: int) -> void:
	step_y = max(0, step)
	_restack_active()

func set_notifications_anchor(y: int) -> void:
	anchor_y = y
	_restack_active()

func show_ui() -> void:
	visible = true

func hide_ui() -> void:
	visible = false

# ======================== Internals =========================
func _label_for(node: Control) -> Label:
	if _label_cache.has(node):
		return _label_cache[node]
	var lbl := _find_label_recursive(node)
	_label_cache[node] = lbl
	return lbl

func _find_label_recursive(n: Node) -> Label:
	if n is Label:
		return n as Label
	for c in n.get_children():
		var l := _find_label_recursive(c)
		if l:
			return l
	return null

func _set_slot_text(node: Control, msg: String) -> void:
	var lbl := _label_for(node)
	if lbl:
		if notif_font:
			lbl.add_theme_font_override("font", notif_font)
		lbl.text = msg

func _play_notify_sound() -> void:
	if sfx_show == null:
		return
	_sfx_player.stream = sfx_show
	_sfx_player.play()
