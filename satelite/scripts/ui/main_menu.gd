extends MenuPanel
## Full-screen menu, opened with Escape and used for quitting the game.
##
## [code]%CloseButton[/code] is the Resume button: the controller thaws the tree
## whenever the menu layer closes, so no extra handling is needed here.

@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	super()
	_quit_button.pressed.connect(_on_quit_pressed)


func _on_quit_pressed() -> void:
	get_tree().quit()
