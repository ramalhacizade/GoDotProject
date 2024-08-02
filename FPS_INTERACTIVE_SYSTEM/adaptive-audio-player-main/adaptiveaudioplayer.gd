extends AudioStreamPlayer3D

# AAP settings
@export var adaptionRange: int = 25
@export var AAPAutoPlay: bool = false
@export var ContinuousAdapt: bool = false
@export var debug: bool = false

func _ready() -> void:
	if AAPAutoPlay:
		play_sfx()

func play_sfx() -> void:
	play()
