extends TextureRect

@export var MK: Texture2D
@export var EN: Texture2D
@export var rect :TextureRect 
func _ready() -> void:
	_refresh()
	GameState.locale_changed.connect(_on_locale_changed)

func _on_locale_changed(_lc: String) -> void:
	_refresh()

func _refresh() -> void:
	texture = MK if GameState.current_locale == "mk" else EN
