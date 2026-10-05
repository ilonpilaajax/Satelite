extends Node
## Global satellite hub, autoloaded as [code]SatelliteController[/code].
##
## One satellite is active at a time. The hub binds to that satellite's outward
## signals and republishes them, so any node in the project can react to stats,
## upgrades, parts, appearance, actions and the downlink without knowing which
## satellite is active or what modules it is built from:
##
## [codeblock]
## SatelliteController.stats_changed.connect(_on_stats_changed)
## SatelliteController.purchase_upgrade(&"thruster")
## SatelliteController.purchase_part(&"solar_panels")
## SatelliteController.transmit_data(&"spectrum_sweep")
## SatelliteController.set_visual(&"tint", Color.RED)
## [/codeblock]
##
## [b]Satellites are addressed as plain [Node]s[/b], through
## [method Object.has_signal] and [method Object.call]. Importing [Satellite] or
## any module class here would create a cyclic script dependency, because the
## modules and the aggregate all talk back to this autoload. The cost is a few
## thin forwarding methods; the benefit is that the hub works with any node that
## honours the contract, and that adding a module never means editing this file.
##
## For the same reason the hub is also what puts the active satellite into
## [code]SaveManager[/code]: a satellite that implements [code]save_data[/code]
## and [code]load_data[/code] is covered by a save because it is active, with no
## save code anywhere in the satellite itself.

signal active_changed(satellite: Node)
signal stats_changed(snapshot: Dictionary)
signal upgrade_purchased(upgrade: Resource, level: int)
signal upgrades_changed()
signal part_purchased(part: Resource, owned: int)
signal parts_changed()
## What is fitted to which mount changed. [param slot] is -1 when the whole
## arrangement did, which is what a mount count change and a save load report.
signal slots_changed(slot: int)
signal appearance_changed(snapshot: Dictionary)
signal action_performed(action: Resource)
## Republished from the satellite's downlink: [param sent_count] is how many times
## this particular packet has gone down.
signal data_transmitted(packet: Resource, sent_count: int)
signal downlink_changed()

## Id the active satellite's state is stored under in [code]SaveManager[/code].
## Fixed rather than derived from the node path, so moving the satellite in the
## scene does not orphan the entry in existing saves.
const SAVE_KEY := &"satellite"

## Signals the hub binds to on whichever satellite is active. One list, so binding
## and unbinding cannot drift apart, and adding a contract signal means editing
## this and [_handler_for] rather than three call sites.
const BOUND_SIGNALS: Array[StringName] = [
	&"stats_changed",
	&"upgrade_purchased",
	&"upgrades_changed",
	&"part_purchased",
	&"parts_changed",
	&"slots_changed",
	&"appearance_changed",
	&"action_performed",
	&"data_transmitted",
	&"downlink_changed",
]

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
		_forget(_active)
	_active = satellite
	if _active != null:
		_bind(_active)
		_remember(_active)
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


# --- Parts ------------------------------------------------------------------

## Every part the active satellite can fit, already priced and already carrying
## the reason a buy button would be disabled. The parts shop renders this as it
## stands rather than asking the hub a question per row.
func part_catalogue() -> Array:
	var result: Variant = _call_active(&"part_catalogue")
	return (result as Array) if result is Array else []


func owned_count_of(part_id: StringName) -> int:
	return _as_int(_call_active(&"owned_count_of", [part_id]))


func owns_part(part_id: StringName) -> bool:
	return _as_bool(_call_active(&"owns_part", [part_id]))


func price_of_part(part_id: StringName) -> int:
	return _as_int(_call_active(&"price_of_part", [part_id]))


func can_purchase_part(part_id: StringName) -> bool:
	return _as_bool(_call_active(&"can_purchase_part", [part_id]))


func purchase_part(part_id: StringName) -> bool:
	return _as_bool(_call_active(&"purchase_part", [part_id]))


# --- Slots ------------------------------------------------------------------

## One entry per mount on the active satellite, in order: whether anything is
## fitted there, what, and where on the body the mount sits. Fitting picks a
## mount from this list, which is what decides where the part appears.
func slot_states() -> Array:
	var result: Variant = _call_active(&"slot_states")
	return (result as Array) if result is Array else []


## How many mounts the active satellite has. Five today.
func available_slots() -> int:
	return _as_int(_call_active(&"available_slots"))


## Fits [param part_id] into [param slot], replacing whatever was fitted there.
## Reports whether it happened. Refused for a mount this satellite does not
## have, a part that is not in its catalogue, and a part that is not bought yet
## - mounting is a decision, but it is not the one that costs credits.
func fit_part(part_id: StringName, slot: int) -> bool:
	return _as_bool(_call_active(&"fit_part", [part_id, slot]))


## Empties [param slot], returning what was fitted there or null.
func unfit_part(slot: int) -> Resource:
	var result: Variant = _call_active(&"unfit_part", [slot])
	return result as Resource if result is Resource else null


## Which mount [param part_id] is fitted to, or -1 when it is fitted nowhere. The lowest of
## the mounts when it is fitted to several; a part bought but not yet mounted reads -1, as
## does one that has been replaced.
func slot_of_part(part_id: StringName) -> int:
	return _as_int(_call_active(&"slot_of_part", [part_id]))


## Every mount [param part_id] is fitted to, in order. Empty when it is fitted nowhere. A
## part bought more than once can be fitted to several mounts at once, so this is the whole
## answer to "where is all of it" rather than [method slot_of_part] alone.
func slots_of_part(part_id: StringName) -> Array:
	var result: Variant = _call_active(&"slots_of_part", [part_id])
	return (result as Array) if result is Array else []


## How many copies of [param part_id] are fitted to a mount, which is never more than were
## bought. What a part's stat effects have already been paying for.
func fitted_count_of_part(part_id: StringName) -> int:
	return _as_int(_call_active(&"fitted_count_of_part", [part_id]))


## Whether another copy of [param part_id] could be fitted as things stand, without moving
## one that already is. What a shop row uses to decide between buying another copy and
## moving the ones it has.
func can_fit_part(part_id: StringName) -> bool:
	return _as_bool(_call_active(&"can_fit_part", [part_id]))


# --- Actions ---------------------------------------------------------------

func action_catalogue() -> Array:
	var result: Variant = _call_active(&"action_catalogue")
	return (result as Array) if result is Array else []


func perform_action(action_id: StringName) -> bool:
	return _as_bool(_call_active(&"perform_action", [action_id]))


# --- Downlink ----------------------------------------------------------------

## Every packet the active satellite can send back to Earth, already carrying its
## size, its send count and the reason a send button would be dead. The downlink menu
## renders this rather than asking the hub a question per row.
func downlink_catalogue() -> Array:
	var result: Variant = _call_active(&"downlink_catalogue")
	return (result as Array) if result is Array else []


func can_send_data(packet_id: StringName) -> bool:
	return _as_bool(_call_active(&"can_send_data", [packet_id]))


## Sends [param packet_id] back to Earth. False when the packet is unknown or may not
## be sent again.
func transmit_data(packet_id: StringName) -> bool:
	return _as_bool(_call_active(&"transmit_data", [packet_id]))


func sent_count_of(packet_id: StringName) -> int:
	return _as_int(_call_active(&"sent_count_of", [packet_id]))


## `{transmissions, volume, unit}` for the menu's summary line. Empty when the active
## satellite has no downlink module.
func downlink_totals() -> Dictionary:
	var result: Variant = _call_active(&"downlink_totals")
	return (result as Dictionary) if result is Dictionary else {}


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

## Hands the active satellite to [code]SaveManager[/code] under [constant
## SAVE_KEY]. This is the only line connecting the two, and it goes through
## [method Object.has_method] like everything else here, so the satellite still
## never imports the save system and the save system never imports the satellite.
func _remember(satellite: Node) -> void:
	var manager := get_node_or_null(^"/root/SaveManager")
	if manager and manager.has_method(&"register"):
		manager.call(&"register", satellite, SAVE_KEY)


func _forget(satellite: Node) -> void:
	var manager := get_node_or_null(^"/root/SaveManager")
	if manager and manager.has_method(&"unregister"):
		manager.call(&"unregister", satellite)


## Loops [constant BOUND_SIGNALS] rather than listing the connections out, which is
## what the constant is for: a signal added there and forgotten here would still be
## unbound correctly on teardown but never bound, so it would silently never fire.
func _bind(satellite: Node) -> void:
	for signal_name: StringName in BOUND_SIGNALS:
		_bind_signal(satellite, signal_name, _handler_for(signal_name))


func _unbind(satellite: Node) -> void:
	for signal_name: StringName in BOUND_SIGNALS:
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
		&"part_purchased": return _on_part_purchased
		&"parts_changed": return _on_parts_changed
		&"slots_changed": return _on_slots_changed
		&"appearance_changed": return _on_appearance_changed
		&"action_performed": return _on_action_performed
		&"data_transmitted": return _on_data_transmitted
		&"downlink_changed": return _on_downlink_changed
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


func _on_part_purchased(part: Resource, owned: int) -> void:
	part_purchased.emit(part, owned)


func _on_parts_changed() -> void:
	parts_changed.emit()


func _on_slots_changed(slot: int) -> void:
	slots_changed.emit(slot)


func _on_appearance_changed(snapshot: Dictionary) -> void:
	appearance_changed.emit(snapshot)


func _on_action_performed(action: Resource) -> void:
	action_performed.emit(action)


func _on_data_transmitted(packet: Resource, count: int) -> void:
	data_transmitted.emit(packet, count)


func _on_downlink_changed() -> void:
	downlink_changed.emit()
