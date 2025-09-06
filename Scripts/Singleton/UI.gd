extends CanvasLayer
# ===== UI (time/day/money + wave-based notifications) =====

# ---- Top bar ----
@export var time: RichTextLabel
@export var money: RichTextLabel
@export var day: RichTextLabel

# ---- Notification slots (Controls that contain a Label) ----
@export var notification_nodes: Array[Control] = []

# ---- Stack config ----
@export var visible_slots: int = 4         # how many to show per wave
@export var anchor_y: int = 50             # final y = anchor_y + step_y * (slot_index+1)
@export var step_y: int = 50
@export var slide_dur: float = 0.30
@export var stay_dur: float = 2.00
@export var fade_dur: float = 0.45

# ---- Extras ----
@export var sfx_show: AudioStream          # optional: drop a whoosh file
@export var notif_font: Font               # optional: custom font for each Label

# ---- Internals ----
var _queue: Array[String] = []
var _active_nodes: Array[Control] = []            # nodes currently visible (this wave)
var _node_slot_index: Dictionary = {}             # Control -> int (0..visible_slots-1)
var _label_cache: Dictionary = {}                 # Control -> Label
var _tweens: Dictionary = {}                      # Control -> Tween
var _sfx_player: AudioStreamPlayer
var _wave_running: bool = false

# ============================ READY ============================
func _ready() -> void:
	# SFX player
	_sfx_player = AudioStreamPlayer.new()
	add_child(_sfx_player)

	# Clamp & reset slots
	visible_slots = clamp(visible_slots, 1, notification_nodes.size())
	for n: Control in notification_nodes:
		if n:
			n.visible = false
			n.modulate.a = 0.0
			n.position.y = anchor_y
			var lbl := _label_for(n)
			if lbl and notif_font:
				lbl.add_theme_font_override("font", notif_font)

	await get_tree().process_frame

	# --- Connect GameState signals (tasks only; no flags) ---
	if is_instance_valid(GameState):
		var c_money := Callable(self, "_on_money_changed")
		if not GameState.is_connected("money_changed", c_money):
			GameState.money_changed.connect(c_money)

		var c_time := Callable(self, "_on_time_changed")
		if not GameState.is_connected("time_changed", c_time):
			GameState.time_changed.connect(c_time)

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
	if not _wave_running:
		_start_next_wave()

func notify_task_added(task_id: String) -> void:
	notify("Task added: " + task_id)

func notify_task_updated(task_id: String, step_index: int) -> void:
	notify("Task updated: %s → Step %d" % [task_id, step_index])

# =================== GameState → notifications ===================
func _on_task_added(task_id: String) -> void:
	notify_task_added(task_id)

func _on_task_updated(task_id: String, step_index: int) -> void:
	notify_task_updated(task_id, step_index)

# ========================= WAVE ENGINE =========================
func _start_next_wave() -> void:
	if _wave_running:
		return
	if _queue.is_empty():
		return

	_wave_running = true
	_active_nodes.clear()
	_node_slot_index.clear()

	# choose nodes from pool and spawn up to visible_slots items
	var count: int = min(visible_slots, notification_nodes.size(), _queue.size())
	var pool: Array[Control] = _free_pool_nodes(count)

	count = min(count, pool.size())
	for i in range(count):
		var node: Control = pool[i]
		var msg: String = String(_queue.pop_front())
		_node_slot_index[node] = i
		_active_nodes.append(node)
		_show_in_slot(node, msg, i)

func _free_pool_nodes(max_count: int) -> Array[Control]:
	var out: Array[Control] = []
	for n: Control in notification_nodes:
		if _active_nodes.has(n):
			continue
		out.append(n)
		if out.size() == max_count:
			break
	return out

func _show_in_slot(node: Control, msg: String, slot_index: int) -> void:
	_set_slot_text(node, msg)

	node.visible = true
	node.position.y = anchor_y
	node.modulate.a = 0.0

	var target_y: int = anchor_y + step_y * (slot_index + 1)

	var tw: Tween = create_tween()
	_tweens[node] = tw
	tw.tween_property(node, "modulate:a", 1.0, 0.15)          # fade in
	tw.tween_property(node, "position:y", target_y, slide_dur) # slide
	tw.tween_interval(stay_dur)                                # stay
	tw.tween_property(node, "modulate:a", 0.0, fade_dur)       # fade out
	tw.tween_callback(Callable(self, "_on_toast_finished").bind(node))

	_play_notify_sound()

func _on_toast_finished(node: Control) -> void:
	if node:
		node.visible = false
		node.position.y = anchor_y
		_tweens.erase(node)

	_active_nodes.erase(node)
	_node_slot_index.erase(node)

	# When the last one is gone, start the next wave (if queued)
	if _active_nodes.is_empty():
		_wave_running = false
		_start_next_wave()

# ======================== Convenience =========================
func set_notifications_spacing(step: int) -> void:
	step_y = max(0, step)
	_reposition_active()

func set_notifications_anchor(y: int) -> void:
	anchor_y = y
	_reposition_active()

func show_ui() -> void:
	visible = true

func hide_ui() -> void:
	visible = false

# Reposition active to their slot targets (used if you tweak anchor/spacing mid-wave)
func _reposition_active() -> void:
	for node: Control in _active_nodes:
		var idx: int = int(_node_slot_index.get(node, 0))
		var target_y: int = anchor_y + step_y * (idx + 1)
		var tw: Tween = create_tween()
		_tweens[node] = tw
		tw.tween_property(node, "position:y", target_y, 0.2)

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
