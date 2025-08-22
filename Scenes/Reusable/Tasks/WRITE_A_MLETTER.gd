extends Control

@onready var lab : Label = $"a"
@onready var text_library : Array[String] = ["Dear Committee, I come from a modest background, but I've worked hard to maintain my grades. I believe this scholarship can help me continue my education and give back to the community. Thank you for the opportunity. Sincerely, Me"
, "Dear Committee, I'm the first in my family to attend college. This scholarship would let me keep my grades up and continue mentoring local kids. Thank you. Sincerely, Me"
, "Dear Committee, Hard work lifted my GPA to 3.9 despite tight finances. Your support keeps me in school and giving back. Thanks. Best, Me"
, "Dear Esteemed Committee, My journey began at a kitchen table where bills often outnumbered paychecks. From that table, I learned that perseverance is a currency more reliable than cash. It bought me top grades, leadership roles in two campus clubs, and the chance every Saturday to serve meals at the youth shelter."
, "Dear Committee, I juggle jobs and classes to stay on the Dean's List. Help me finish my degree and keep tutoring teens. Thank you."]
@onready var header : Label = $"gamebox/Header"
@onready var edit : LineEdit = $"gamebox/LineEdit"
@onready var debLabel : Label = $"outrobox/DebugLabel"
@onready var gamebox : Control = $"gamebox"
@onready var outrobox : Control = $"outrobox"
@onready var box : Control = $"box"
@onready var msg : AnimationPlayer = $"message/AnimationPlayer"
@onready var status : Label = $"outrobox/status"
var current : int = 0
var words : PackedStringArray = []
var current_word : int = 0
var correct : int = 0
var wrong : int = 0
var freed : bool = false

# SFX
var zvuci = [
	preload("res://Audio/MotivLetterSounds/b1.mp3"),
	preload("res://Audio/MotivLetterSounds/b2.mp3"),
	preload("res://Audio/MotivLetterSounds/b3.mp3"),
	preload("res://Audio/MotivLetterSounds/b4.mp3"),
	preload("res://Audio/MotivLetterSounds/b5.mp3")
]
@onready var zvuk_end : AudioStreamPlayer2D = $"end"
@onready var zvuk_wrong : AudioStreamPlayer2D = $"wrong"

func _ready() -> void:
	$SceneAnimation.play("LetterIntro")
	current = randi() % 5
	words = text_library[current].split(" ", false)
	header.text = words[current_word]
	current_word = 100
	await $SceneAnimation.animation_finished

func _on_line_edit_text_submitted(new_text) -> void:
	if(new_text == header.text):
		current_word+=1
		correct+=1
		edit.text = ""
		SFX_play()
	else:
		wrong+=1
		current_word+=1
		edit.grab_focus()
		edit.text = ""
		if !zvuk_wrong.playing:
			zvuk_wrong.play()

func _process(_delta: float) -> void:
	debLabel.text = "Correct: %d" %correct + "
	Errors: %d" %wrong + "
	Status:        "
	#print(words.size())
	if current_word < words.size():
	# Only update header when starting a new word
		header.text = words[current_word]

		if edit.text == header.text:
			current_word += 1
			correct += 1
			edit.text = ""
			SFX_play()
	elif !freed:
		freed = true
		gamebox.visible = false
		outro()


func _on_button_pressed() -> void:
	gamebox.modulate.a = 0
	create_tween().tween_property(gamebox, "modulate:a", 1, 2)
	box.visible = false
	gamebox.visible = true
	msg.play("mesg")

func outro() -> void:
	zvuk_end.play()
	debLabel.visible_ratio = 0
	status.visible = false
	var tween : Tween = create_tween()
	status.text = "Fuck you"
	outrobox.visible = true
	if(wrong == 0):
		status.text = "Perfect"
	elif(wrong > 0 && wrong < 4):
		status.text = "Almost Perfect"
	elif(wrong > 3 && wrong < 7):
		status.text = "Mid"
	else:
		status.text = "Bad"
	tween.tween_property(debLabel, "visible_ratio", 1, 1)
	await tween.finished
	create_tween().tween_property(status, "modulate:a", 1, 1).set_trans(Tween.TRANS_CUBIC)
	status.visible = true

func SFX_play(): #poliranje
	var sound = AudioStreamPlayer2D.new()
	add_child(sound)
	sound.stream = zvuci[randi() % 5]
	sound.play()
	await sound.finished
	sound.queue_free()
