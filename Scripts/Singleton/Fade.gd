extends CanvasLayer
class_name Fade

## Public config
@export var default_color: Color = Color.BLACK
@export var default_duration: float = 0.35
@export var default_ease: float = 1.0   # 1.0 = linear; use easing via "trans_type" below
@export var default_trans_type: int = Tween.TRANS_SINE
@export var default_ease_type: int = Tween.EASE_IN_OUT

## Nodes
var _overlay: ColorRect = null
var _input_blocker: Control = null

## State
var _busy: bool = false
var _current_tween: Tween = null

signal fade_started(kind: String)    # "in" | "out" | "to_scene"
signal fade_finished(kind: String)

func _ready() -> void:
	# Ensure we sit on top of everything
	layer = 1000
	_make_nodes()
	_resize_to_viewport()
	# ✨ Always start unblocked and transparent
	_set_blocking(false)
	_overlay.modulate.a = 0.0
	get_viewport().size_changed.connect(_resize_to_viewport)

func _exit_tree() -> void:
	# Defensive: never leave the app blocked on exit/change
	_kill_tween()
	_set_blocking(false)

func _make_nodes() -> void:
	_input_blocker = Control.new()
	_input_blocker.name = "InputBlocker"
	_input_blocker.mouse_filter = Control.MOUSE_FILTER_STOP  # blocks clicks when visible
	_input_blocker.focus_mode = Control.FOCUS_ALL
	add_child(_input_blocker)

	_overlay = ColorRect.new()
	_overlay.name = "FadeOverlay"
	_overlay.color = default_color
	_overlay.visible = true
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE       # <- overlay itself never blocks
	add_child(_overlay)

	# Start transparent (no fade applied) & not blocking
	_overlay.modulate.a = 0.0
	_input_blocker.visible = false

func _resize_to_viewport() -> void:
	var size := get_viewport().get_visible_rect().size
	_input_blocker.size = size
	_overlay.size = size
	_input_blocker.position = Vector2.ZERO
	_overlay.position = Vector2.ZERO

func _kill_tween() -> void:
	if _current_tween != null:
		_current_tween.kill()
	_current_tween = null

func _set_blocking(b: bool) -> void:
	_input_blocker.visible = b
	_input_blocker.mouse_filter = Control.MOUSE_FILTER_STOP if b else Control.MOUSE_FILTER_IGNORE

func _tween_alpha(target_a: float, duration: float, trans_type: int, ease_type: int) -> void:
	_kill_tween()
	var t := create_tween()
	_current_tween = t
	t.set_trans(trans_type)
	t.set_ease(ease_type)
	t.tween_property(_overlay, "modulate:a", target_a, max(duration, 0.0))

# -----------------------
# Public API
# -----------------------

## Fade the screen to opaque (usually before a scene change).
func fade_out(duration: float = -1.0, color: Color = Color(-1,-1,-1,-1)) -> Signal:
	# If already fading, wait for it first
	if _busy and _current_tween != null:
		var prev := _current_tween
		await prev.finished

	var dur := duration
	if dur < 0.0:
		dur = default_duration

	if color.a >= 0.0:
		_overlay.color = color
	else:
		_overlay.color = default_color

	_busy = true
	emit_signal("fade_started", "out")
	_set_blocking(true)
	_tween_alpha(1.0, dur, default_trans_type, default_ease_type)

	# Capture tween locally to avoid races
	var t := _current_tween
	if t != null:
		await t.finished

	_busy = false
	emit_signal("fade_finished", "out")
	return fade_finished

## Fade the screen from opaque to transparent (usually after a scene change).
func fade_in(duration: float = -1.0) -> Signal:
	# If already fading, wait for it first
	if _busy and _current_tween != null:
		var prev := _current_tween
		await prev.finished

	var dur := duration
	if dur < 0.0:
		dur = default_duration

	_busy = true
	emit_signal("fade_started", "in")
	_set_blocking(true)
	_tween_alpha(0.0, dur, default_trans_type, default_ease_type)

	var t := _current_tween
	if t != null:
		await t.finished

	_set_blocking(false)
	_busy = false
	emit_signal("fade_finished", "in")
	return fade_finished

## Convenience: fade out → change scene → fade in.
func fade_to_scene(scene_path: String, out_dur: float = -1.0, in_dur: float = -1.0) -> void:
	if out_dur < 0.0:
		out_dur = default_duration
	if in_dur < 0.0:
		in_dur = default_duration

	emit_signal("fade_started", "to_scene")
	await fade_out(out_dur)
	get_tree().change_scene_to_file(scene_path)
	await fade_in(in_dur)
	emit_signal("fade_finished", "to_scene")

## Instantly set faded state without tween (useful for scene setup).
func set_immediate_faded(faded: bool, color: Color = Color(-1,-1,-1,-1)) -> void:
	_kill_tween()
	if color.a >= 0.0:
		_overlay.color = color
	if faded:
		_overlay.modulate.a = 1.0
		_set_blocking(true)
	else:
		_overlay.modulate.a = 0.0
		_set_blocking(false)

## True while a fade is in progress.
func is_busy() -> bool:
	return _busy

## Panic button: ensure nothing is blocking (optional helper)
func ensure_unblocked() -> void:
	_kill_tween()
	_set_blocking(false)
	_overlay.modulate.a = 0.0
