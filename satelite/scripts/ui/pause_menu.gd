extends MenuPanel
## Pause menu. Opened from the access bar, which also freezes the game because
## [code]MenuController.PAUSING_MENUS[/code] lists this screen. Resume closes it
## and thaws the game.
##
## Save and Load are the pause options so far. Both go through [code]SaveManager[/code],
## which writes [code]user://saves[/code] as JSON, so this script holds no save
## logic of its own and can grow to any number of slots later.

@onready var _save_button: Button = get_node_or_null("%SaveButton")
@onready var _load_button: Button = get_node_or_null("%LoadButton")
@onready var _status_label: Label = get_node_or_null("%Status")


func _ready() -> void:
	super()
	if _save_button:
		_save_button.pressed.connect(_on_save_pressed)
	if _load_button:
		_load_button.pressed.connect(_on_load_pressed)
	_refresh()


func _on_open() -> void:
	_refresh()


func _on_save_pressed() -> void:
	var slot := SaveManager.current_slot
	if SaveManager.save_game(slot):
		_set_status("Saved %s." % SaveManager.slot_path(slot))
	else:
		_set_status("Save failed. See the log.")
	# There is something to load now, and this menu is still open.
	_refresh()


func _on_load_pressed() -> void:
	var slot := SaveManager.current_slot
	if not SaveManager.has_slot(slot):
		_set_status("Nothing saved yet.")
		return
	if SaveManager.load_game(slot):
		_set_status("Loaded %s." % SaveManager.slot_path(slot))
	else:
		_set_status("Load failed. See the log.")
	_refresh()


## Load stays greyed out until there is something to load, so the button never
## has to report the same failure twice.
func _refresh() -> void:
	if _load_button:
		_load_button.disabled = not SaveManager.has_slot(SaveManager.current_slot)


func _set_status(text: String) -> void:
	if _status_label:
		_status_label.text = text