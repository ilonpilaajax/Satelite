extends CanvasLayer
## Global menu controller, autoloaded as [code]MenuController[/code].
##
## It owns the full-screen menu layer, instantiates every menu scene exactly once
## and keeps at most one of them visible. [constant HUD_PATH] is the quick access
## bar that sits along the bottom of the screen while no menu is open.
##
## Scenes are [code]load()[/code]ed at runtime on purpose: preloading them here
## would create a cyclic script dependency, because every menu script talks back
## to this autoload. That is also why menus are driven through duck-typed
## [method MenuPanel.open] / [method MenuPanel.close] calls.

signal menu_opened(id: int)
signal menu_closed(id: int)
signal menu_layer_visibility_changed(is_visible: bool)
## Emitted whenever this controller freezes or thaws the tree.
signal pause_changed(paused: bool)

enum Id {
	MAIN,
	PAUSE,
	SIGNALS,
	UPGRADE,
	STATS,
	PARTS,
	DOWNLINK,
}

const MENU_PATHS := {
	Id.MAIN: "res://scenes/ui/main_menu.tscn",
	Id.PAUSE: "res://scenes/ui/pause_menu.tscn",
	Id.SIGNALS: "res://scenes/ui/signals_menu.tscn",
	Id.UPGRADE: "res://scenes/ui/upgrade_menu.tscn",
	Id.STATS: "res://scenes/ui/stats_menu.tscn",
	Id.PARTS: "res://scenes/ui/parts_menu.tscn",
	Id.DOWNLINK: "res://scenes/ui/downlink_menu.tscn",
}

const HUD_PATH := "res://scenes/ui/hud_bar.tscn"

## Full-screen menu reached with Escape. Acts as the quit menu.
const BASE_MENU: int = Id.MAIN

## Menus that freeze the game while they are on screen. The signals, upgrade, stats,
## parts and downlink screens are overlays you can browse through while the game
## keeps running.
const PAUSING_MENUS: Array[int] = [Id.MAIN, Id.PAUSE]

## Set to [code]true[/code] to boot straight into [constant BASE_MENU].
@export var open_on_ready: bool = false
## Escape closes the open menu, or opens [constant BASE_MENU] when nothing is open.
@export var close_on_escape: bool = true

var _menus: Dictionary[int, Control] = {}
var _hud: Control = null
var _current_id: int = -1
var _is_open: bool = false
var _paused_by_menu: bool = false


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_menus()
	_build_hud()
	if open_on_ready:
		open_menu(BASE_MENU)
	else:
		close_all()


func _unhandled_input(event: InputEvent) -> void:
	if not close_on_escape or not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _is_open:
		close_all()
	else:
		open_menu(BASE_MENU)


## True while any menu is on screen.
func is_open() -> bool:
	return _is_open


func is_menu_open(id: int) -> bool:
	return _is_open and _current_id == id


## True while this controller is holding the tree frozen.
func is_paused() -> bool:
	return _paused_by_menu


func current_menu_id() -> int:
	return _current_id


func get_menu(id: int) -> Control:
	return _menus.get(id)


func get_hud() -> Control:
	return _hud


## Shows [param id] and hides whichever menu was visible before. Freezes the game
## when [param id] is one of [constant PAUSING_MENUS].
func open_menu(id: int) -> void:
	var menu := get_menu(id)
	if menu == null:
		push_warning("MenuController: no menu registered for id %d." % id)
		return
	_hide_current()
	_current_id = id
	_is_open = true
	menu.call(&"open")
	_apply_pause(PAUSING_MENUS.has(id))
	if _hud:
		_hud.visible = false
	menu_opened.emit(id)
	menu_layer_visibility_changed.emit(true)


func open_main_menu() -> void:
	open_menu(BASE_MENU)


## Hides the whole menu layer, thaws the game and brings the access bar back.
func close_all() -> void:
	_hide_current()
	_current_id = -1
	_is_open = false
	_apply_pause(false)
	if _hud:
		_hud.visible = true
	menu_layer_visibility_changed.emit(false)


## Closes the layer if [param id] is showing, otherwise opens [param id].
func toggle_menu(id: int) -> void:
	if is_menu_open(id):
		close_all()
	else:
		open_menu(id)


func _build_menus() -> void:
	for key in MENU_PATHS:
		var id: int = key
		var path: String = MENU_PATHS[id]
		if not ResourceLoader.exists(path):
			push_error("MenuController: menu scene '%s' does not exist." % path)
			continue
		var menu: Control = (load(path) as PackedScene).instantiate()
		menu.visible = false
		add_child(menu)
		_menus[id] = menu


func _build_hud() -> void:
	if not ResourceLoader.exists(HUD_PATH):
		push_error("MenuController: HUD scene '%s' does not exist." % HUD_PATH)
		return
	_hud = (load(HUD_PATH) as PackedScene).instantiate()
	add_child(_hud)


func _hide_current() -> void:
	if _current_id == -1:
		return
	var current := get_menu(_current_id)
	if current:
		current.call(&"close")
	menu_closed.emit(_current_id)


func _apply_pause(paused: bool) -> void:
	if paused == _paused_by_menu:
		return
	_paused_by_menu = paused
	get_tree().paused = paused
	pause_changed.emit(paused)
