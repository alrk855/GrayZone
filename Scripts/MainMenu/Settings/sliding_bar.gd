extends Control

@onready var slider: HSlider = $HSlider
@onready var fill_bar: ProgressBar = $FillBar
@onready var toggle: Button = $"../MusicToggle"

@export var bus_name: String = "Music"
var bus_index: int
var last_volume: float = 0.5

func _ready() -> void:
	bus_index = AudioServer.get_bus_index(bus_name)
	# You already set value in the editor; sync it
	fill_bar.value = slider.value
	last_volume = slider.value
	_set_volume(slider.value)

	slider.value_changed.connect(_on_slider_value_changed)
	toggle.pressed.connect(_on_toggle_pressed)

func _process(_delta: float) -> void:
	fill_bar.value = slider.value
	slider.queue_redraw()

func _on_slider_value_changed(value: float) -> void:
	last_volume = value
	if !toggle.button_pressed:
		_set_volume(value)

func _on_toggle_pressed() -> void:
	if toggle.button_pressed:
		_set_volume(0.0)
	else:
		_set_volume(last_volume)

func _set_volume(value: float) -> void:
	if value <= 0.001:
		AudioServer.set_bus_volume_db(bus_index, -80.0)  # Absolute silence
	else:
		var db := linear_to_db(value)
		AudioServer.set_bus_volume_db(bus_index, db)

func linear_to_db(value: float) -> float:
	return 20.0 * log(value) / log(10)
