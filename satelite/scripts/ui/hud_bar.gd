extends Control
## Always-on quick access bar, added as the last child of [code]MenuController[/code]
## so it draws on top. The controller hides it whenever a menu is open.
##
## Each button is a placeholder icon: drop a texture in the button's [code]icon[/code]
## property and the label becomes the tooltip only.

@onready var _signals_button: Button = %SignalsButton
@onready var _upgrade_button: Button = %UpgradeButton
@onready var _parts_button: Button = %PartsButton
@onready var _stats_button: Button = %StatsButton
@onready var _downlink_button: Button = %DownlinkButton
@onready var _pause_button: Button = %PauseButton


func _ready() -> void:
	_signals_button.pressed.connect(_on_signals_pressed)
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	_parts_button.pressed.connect(_on_parts_pressed)
	_stats_button.pressed.connect(_on_stats_pressed)
	_downlink_button.pressed.connect(_on_downlink_pressed)
	_pause_button.pressed.connect(_on_pause_pressed)


## The signals screen is not in [code]MenuController.PAUSING_MENUS[/code], so browsing
## the antenna channels does not stop the game.
func _on_signals_pressed() -> void:
	MenuController.open_menu(MenuController.Id.SIGNALS)


func _on_upgrade_pressed() -> void:
	MenuController.open_menu(MenuController.Id.UPGRADE)


## The parts shop is not in [code]MenuController.PAUSING_MENUS[/code], so browsing
## it does not stop the game.
func _on_parts_pressed() -> void:
	MenuController.open_menu(MenuController.Id.PARTS)


func _on_stats_pressed() -> void:
	MenuController.open_menu(MenuController.Id.STATS)


## The downlink is not in [code]MenuController.PAUSING_MENUS[/code] either, so the
## satellite keeps travelling while you pick what to send back.
func _on_downlink_pressed() -> void:
	MenuController.open_menu(MenuController.Id.DOWNLINK)


## The pause menu is registered in [code]MenuController.PAUSING_MENUS[/code], so
## opening it also freezes the game.
func _on_pause_pressed() -> void:
	MenuController.open_menu(MenuController.Id.PAUSE)
