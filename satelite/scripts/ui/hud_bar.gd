extends Control
## Always-on quick access bar, added as the last child of [code]MenuController[/code]
## so it draws on top. The controller hides it whenever a menu is open.
##
## Each button is a placeholder icon: drop a texture in the button's [code]icon[/code]
## property and the label becomes the tooltip only.

@onready var _gallery_button: Button = %GalleryButton
@onready var _upgrade_button: Button = %UpgradeButton
@onready var _stats_button: Button = %StatsButton
@onready var _pause_button: Button = %PauseButton


func _ready() -> void:
	_gallery_button.pressed.connect(_on_gallery_pressed)
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	_stats_button.pressed.connect(_on_stats_pressed)
	_pause_button.pressed.connect(_on_pause_pressed)


func _on_gallery_pressed() -> void:
	MenuController.open_menu(MenuController.Id.GALLERY)


func _on_upgrade_pressed() -> void:
	MenuController.open_menu(MenuController.Id.UPGRADE)


func _on_stats_pressed() -> void:
	MenuController.open_menu(MenuController.Id.STATS)


## The pause menu is registered in [code]MenuController.PAUSING_MENUS[/code], so
## opening it also freezes the game.
func _on_pause_pressed() -> void:
	MenuController.open_menu(MenuController.Id.PAUSE)
