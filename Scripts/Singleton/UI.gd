extends CanvasLayer

# -------------------- NODE REFERENCES --------------------
# Drag these nodes in the editor to avoid $ paths
@export var time: RichTextLabel
@export var money: RichTextLabel
@export var day: RichTextLabel
@export var notification_nodes: Array = []

# -------------------- NOTIFICATION QUEUE --------------------
var notification_queue: Array = []
var active_notifications: Array = []

# -------------------- READY --------------------
func _ready():
	# Hide all notifications initially


	# Ensure GameState exists before connecting
	await get_tree().process_frame

	if not GameState.is_connected("money_changed", _on_money_changed):
		GameState.money_changed.connect(_on_money_changed)

	if not GameState.is_connected("time_changed", _on_time_changed):
		GameState.time_changed.connect(_on_time_changed)

	# Debug connection list
	print("🔍 time_changed connections:", GameState.get_signal_connection_list("time_changed"))

	# Initial sync
	_on_time_changed(GameState.time, GameState.day)
	_on_money_changed(GameState.money)

	# Optional: hide UI by default (menu/intro scenes)
	visible = false


# -------------------- UPDATE METHODS --------------------
func update_time(new_time: String) -> void:
	if time:
		time.text = new_time

func update_day(new_day: int) -> void:
	if day:
		day.text = "Day %d" % new_day

func update_money(new_money: int) -> void:
	if money:
		money.text = str(new_money)


# -------------------- SIGNAL HANDLERS --------------------
func _on_money_changed(new_money: int) -> void:
	update_money(new_money)

func _on_time_changed(time_minutes: int, current_day: int) -> void:
	print("📥 UI received:", time_minutes, current_day)
	if time:
		time.text = "%02d:%02d" % [time_minutes / 60, time_minutes % 60]
	if day:
		day.text = "Day %d" % current_day


# -------------------- NOTIFICATIONS --------------------
func add_notification(text: String) -> void:
	notification_queue.append(text)
	_try_show_next_notification()

func _try_show_next_notification() -> void:
	if notification_queue.size() == 0:
		return
	for notif in notification_nodes:
		if notif not in active_notifications:
			var msg = notification_queue.pop_front()
			_display_notification(notif, msg)
			break

func _display_notification(notif_node: Control, message: String) -> void:
	active_notifications.append(notif_node)
	notif_node.visible = true
	notif_node.position.y = 0
	notif_node.modulate.a = 1

	# Use the Label child
	var label_node = notif_node.get_node_or_null("Label")
	if label_node:
		label_node.text = message

	# Stack position based on order
	var index = active_notifications.size() - 1
	var offset_y = 100 * (index + 1) # adjust if needed

	var tween = create_tween()
	tween.tween_property(notif_node, "position:y", offset_y, 0.3)
	tween.tween_interval(2.0)
	tween.tween_property(notif_node, "modulate:a", 0, 0.5)
	tween.tween_callback(Callable(self, "_on_notification_finished").bind(notif_node))

func _on_notification_finished(notif_node: Control) -> void:
	notif_node.visible = false
	notif_node.position.y = 0
	active_notifications.erase(notif_node)

	# Restack remaining notifications
	for i in range(active_notifications.size()):
		var n = active_notifications[i]
		var tween = create_tween()
		tween.tween_property(n, "position:y", 100 * (i + 1), 0.3)

	_try_show_next_notification()
