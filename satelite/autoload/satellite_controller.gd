extends Node
## Global satellite hub, autoloaded as [code]SatelliteController[/code].
##
## One satellite is active at a time. The hub binds to that satellite's five
## outward signals and republishes them, so any node in the project can react to
## stats, upgrades, appearance and actions without knowing which satellite is
## active or what modules it is built from:
##
## [codeblock]
## SatelliteController.stats_changed.connect(_on_stats_changed)
## SatelliteController.purchase_upgrade(&"thruster")
## SatelliteController.set_visual(&"tint", Color.RED)
## [/codeblock]
##
## [b]Satellites are addressed as plain [Node]s[/b], through
## [method Object.has_signal] and [method Object.call]. Importing [Satellite] or
## any module class here would create a cyclic script dependency, because the
## modules and the aggregate all talk back to this autoload. The cost is a few
## thin forwarding methods; the benefit is that the hub works with any node that
## honours the contract, and that adding a module never means editing this file.

signal active_changed(satellite: Node)
signal stats_changed(snapshot: Dictionary)
signal upgrade_purchased(upgrade: Resource, level: int)
signal upgrades_changed()
signal appearance_changed(snapshot: Dictionary)
signal action_performed(action: Resource)

var _satellites: Array[Node] = []
var _active: Node = null


# --- Active satellite ------------------------------------------------------

## Called by [Satellite] on ready. The first satellite to register becomes active.
func register(satellite: Node) -> void:
	if satellite == null or satellite in _satellites:
		return
	_satellites.append(satellite)
	if _active == null:
		set_active(satellite)


## Called by [Satellite] when it leaves the tree. Clears the active slot and
## hands it to another satellite if one is left.
func unregister(satellite: Node) -> void:
	_satellites.erase(satellite)
	if _active == satellite:
		set_active(_satellites[0] if not _satellites.is_empty() else null)


func set_active(satellite: Node) -> void:
	if _active == satellite:
		return
	if _active != null:
		_unbind(_active)
	_active = satellite
	if _active != null:
		_bind(_active)
		_push_stats(stat_snapshot())
	active_changed.emit(_active)


func get_active() -> Node:
	return _active


func get_satellites() -> Array[Node]:
	return _satellites.duplicate()


func is_active(satellite: Node) -> bool:
	return _active == satellite


# --- Stats -----------------------------------------------------------------

func stat_snapshot() -> Dictionary:
	var result: Variant = _call_active(&"stat_snapshot")
	return (result as Dictionary) if result is Dictionary else {}


func stat(id: StringName, fallback: Variant = null) -> Variant:
	return stat_snapshot().get(id, fallback)


## Every stat the active satellite tracks, as {id, caption, unit, decimals, value}.
## A readout should build its labels from this rather than a fixed list.
func stat_descriptors() -> Array:
	var result: Variant = _call_active(&"stat_descriptors")
	return (result as Array) if result is Array else []


func set_stat(id: StringName, value: Variant) -> void:
	_call_active(&"set_stat", [id, value])


func add_stat(id: StringName, delta: float) -> void:
	_call_active(&"add_stat", [id, delta])


# --- Upgrades --------------------------------------------------------------

func upgrade_catalogue() -> Array:
	var result: Variant = _call_active(&"upgrade_catalogue")
	return (result as Array) if result is Array else []


func level_of(upgrade_id: StringName) -> int:
	return _as_int(_call_active(&"level_of", [upgrade_id]))


func cost_of(upgrade_id: StringName) -> int:
	return _as_int(_call_active(&"cost_of", [upgrade_id]))


func can_purchase(upgrade_id: StringName) -> bool:
	return _as_bool(_call_active(&"can_purchase", [upgrade_id]))


func purchase_upgrade(upgrade_id: StringName) -> bool:
	return _as_bool(_call_active(&"purchase_upgrade", [upgrade_id]))


# --- Actions ---------------------------------------------------------------

func action_catalogue() -> Array:
	var result: Variant = _call_active(&"action_catalogue")
	return (result as Array) if result is Array else []


func perform_action(action_id: StringName) -> bool:
	return _as_bool(_call_active(&"perform_action", [action_id]))


# --- Appearance ------------------------------------------------------------

func appearance_snapshot() -> Dictionary:
	var result: Variant = _call_active(&"appearance_snapshot")
	return (result as Dictionary) if result is Dictionary else {}


func set_visual(key: StringName, value: Variant) -> void:
	_call_active(&"set_visual", [key, value])


func set_appearance_state(state: StringName) -> void:
	_call_active(&"set_appearance_state", [state])


## Stops or resumes distance accrual while the game runs.
func set_distance_accrual(enabled: bool) -> void:
	_call_active(&"set_distance_accrual", [enabled])


# --- Signal plumbing -------------------------------------------------------

func _bind(satellite: Node) -> void:
	_bind_signal(satellite, &"stats_changed", _on_stats_changed)
	_bind_signal(satellite, &"upgrade_purchased", _on_upgrade_purchased)
	_bind_signal(satellite, &"upgrades_changed", _on_upgrades_changed)
	_bind_signal(satellite, &"appearance_changed", _on_appearance_changed)
	_bind_signal(satellite, &"action_performed", _on_action_performed)


func _unbind(satellite: Node) -> void:
	for signal_name: StringName in [&"stats_changed", &"upgrade_purchased", &"upgrades_changed", &"appearance_changed", &"action_performed"]:
		if satellite.has_signal(signal_name) and satellite.is_connected(signal_name, _handler_for(signal_name)):
			satellite.disconnect(signal_name, _handler_for(signal_name))


func _bind_signal(satellite: Node, signal_name: StringName, handler: Callable) -> void:
	if satellite.has_signal(signal_name):
		satellite.connect(signal_name, handler)


func _handler_for(signal_name: StringName) -> Callable:
	match signal_name:
		&"stats_changed": return _on_stats_changed
		&"upgrade_purchased": return _on_upgrade_purchased
		&"upgrades_changed": return _on_upgrades_changed
		&"appearance_changed": return _on_appearance_changed
		&"action_performed": return _on_action_performed
	return Callable()


## Calls a contract method on the active satellite. Returns null when nothing is
## active or the satellite does not implement it, which is why every caller narrows
## the result instead of assuming a type.
func _call_active(method: StringName, args: Array = []) -> Variant:
	if _active == null or not _active.has_method(method):
		return null
	return _active.callv(method, args)


func _as_int(value: Variant) -> int:
	return int(value) if (value is int or value is float) else 0


func _as_bool(value: Variant) -> bool:
	return value is bool and value


# --- Republished handlers --------------------------------------------------

func _on_stats_changed(snapshot: Dictionary) -> void:
	_push_stats(snapshot)


func _push_stats(snapshot: Dictionary) -> void:
	stats_changed.emit(snapshot)


func _on_upgrade_purchased(upgrade: Resource, level: int) -> void:
	upgrade_purchased.emit(upgrade, level)


func _on_upgrades_changed() -> void:
	upgrades_changed.emit()


func _on_appearance_changed(snapshot: Dictionary) -> void:
	appearance_changed.emit(snapshot)


func _on_action_performed(action: Resource) -> void:
	action_performed.emit(action)
