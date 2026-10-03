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
	# Quitting does not raise the window manager's close request, so the autosave
	# has to be asked for explicitly or the session is simply lost.
	SaveManager.save_before_quit()
	get_tree().quit()
