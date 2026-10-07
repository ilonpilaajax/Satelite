extends Node


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func check_journey(distance:int):
	if distance >= 225-000-000:return "Mars"
	elif distance >= 780-000-000:return "Jupiter"
	elif distance >= 1-430-000-000:return "Saturnus"
	elif distance >= 2-870-000-000:return "Uranus"
	elif distance >= 4-500-000-000:return "Neptunus"
