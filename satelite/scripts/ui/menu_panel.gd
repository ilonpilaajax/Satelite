class_name MenuPanel
extends Control
## Base class for every menu screen owned by [code]MenuController[/code].
##
## Provides the shared chrome: full-rect layout, the optional [code]%Heading[/code],
## [code]%Subtitle[/code] and [code]%ContentPlaceholder[/code] labels plus the
## [code]%CloseButton[/code] wiring. A menu scene only has to expose those unique
## node names; its own logic goes into [method _on_open] / [method _on_close].
##
## The controller drives this class through [method open] and [method close] using
## duck-typed calls, which is why this script may reference the autoload but the
## autoload never references [code]MenuPanel[/code] directly.

## One of the [code]MenuController.Id[/code] values.
@export var menu_id: int = 0
## Title rendered at the top. Ignored when the scene has no [code]%Heading[/code].
@export var heading: String = "Menu"
## Small line under the heading. Hidden when left empty.
@export var subtitle: String = ""
## Fills the body until the real content is added.
@export var content_placeholder: String = "Nothing here yet."

var is_open: bool = false

@onready var _heading_label: Label = get_node_or_null("%Heading")
@onready var _subtitle_label: Label = get_node_or_null("%Subtitle")
@onready var _placeholder_label: Label = get_node_or_null("%ContentPlaceholder")
@onready var _close_button: Button = get_node_or_null("%CloseButton")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_apply_chrome()
	if _close_button:
		_close_button.pressed.connect(_on_close_button_pressed)


## Called by [code]MenuController.open_menu[/code].
func open() -> void:
	is_open = true
	visible = true
	_on_open()
	var target := _find_focusable(self)
	if target:
		target.grab_focus()


## Called by [code]MenuController[/code] when another menu takes over.
func close() -> void:
	is_open = false
	visible = false
	_on_close()


## Menu logic goes here, right after the screen becomes visible.
func _on_open() -> void:
	pass


## Menu logic goes here, right after the screen is hidden.
func _on_close() -> void:
	pass


## Closes the whole menu layer and hands control back to the game.
func _on_close_button_pressed() -> void:
	MenuController.close_all()


func _apply_chrome() -> void:
	if _heading_label:
		_heading_label.text = heading
	if _subtitle_label:
		_subtitle_label.text = subtitle
		_subtitle_label.visible = not subtitle.is_empty()
	if _placeholder_label:
		_placeholder_label.text = content_placeholder


func _find_focusable(node: Node) -> Control:
	for child in node.get_children():
		if child is Control and (child as Control).visible and (child as Control).focus_mode != Control.FOCUS_NONE:
			return child as Control
		var found := _find_focusable(child)
		if found:
			return found
	return null
