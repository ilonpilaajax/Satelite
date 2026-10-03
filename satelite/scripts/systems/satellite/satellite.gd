class_name Satellite
extends Node2D
## One satellite: the aggregate root that owns the behaviour modules and
## republishes them as a single, small interface.
##
## Every module is optional. The aggregate wires up whatever it finds, so you can
## drop in only the parts a satellite needs and the rest keep working standalone.
##
## [b]The outward contract[/b] is ten signals plus a few accessors, and that is
## deliberate. [code]SatelliteController[/code] binds to this contract using only
## [method Object.has_signal] and [method Object.call], so it never imports the
## module classes. Keeping the dependency one-way is what stops Godot reporting a
## cyclic script reference, and it means a satellite can be replaced by any node
## that honours the same contract.
##
## [codeblock]
## # Anywhere in the project:
## SatelliteController.stats_changed.connect(_on_stats_changed)
## SatelliteController.purchase_upgrade(&"thruster")
## SatelliteController.purchase_part(&"solar_panel")
## [/codeblock]

signal stats_changed(snapshot: Dictionary)
signal upgrade_purchased(upgrade: Resource, level: int)
signal upgrades_changed()
signal part_purchased(part: Resource, owned: int)
signal parts_changed()
signal appearance_changed(snapshot: Dictionary)
signal action_performed(action: Resource)
signal data_transmitted(packet: Resource, sent_count: int)
signal downlink_changed()

@export var id: StringName = &"satellite"
@export var display_name: String = "SATELITE-01"

var _stats: SatelliteStats = null
var _upgrades: SatelliteUpgrades = null
var _parts: SatelliteParts = null
var _appearance: SatelliteAppearance = null
var _actions: SatelliteActions = null
var _motion: SatelliteMotion = null
var _downlink: SatelliteDownlink = null


func _ready() -> void:
	_collect_modules()
	_bind_modules()
	_republish()
	_emit_stats()
	SatelliteController.register(self)


func _exit_tree() -> void:
	# Looked up by path rather than through the global, because during shutdown the
	# autoload is already freed and the global resolves to null.
	var hub := get_node_or_null(^"/root/SatelliteController")
	if hub and hub.has_method(&"unregister"):
		hub.unregister(self)


# --- Modules ---------------------------------------------------------------

func stats() -> SatelliteStats:
	return _stats


func upgrades() -> SatelliteUpgrades:
	return _upgrades


func parts() -> SatelliteParts:
	return _parts


func appearance() -> SatelliteAppearance:
	return _appearance


func actions() -> SatelliteActions:
	return _actions


func motion() -> SatelliteMotion:
	return _motion


func downlink() -> SatelliteDownlink:
	return _downlink


# --- Contract: stats -------------------------------------------------------

func stat_snapshot() -> Dictionary:
	return _stats.snapshot() if _stats != null else {}


## Every stat with its caption, unit and precision. Readouts render this instead
## of a hardcoded list, so they follow whatever this satellite tracks.
func stat_descriptors() -> Array:
	return _stats.descriptors() if _stats != null else []


func set_stat(stat_id: StringName, value: Variant) -> void:
	if _stats != null:
		_stats.set_stat(stat_id, value)


func add_stat(stat_id: StringName, delta: float) -> void:
	if _stats != null:
		_stats.add_stat(stat_id, delta)


# --- Contract: upgrades ----------------------------------------------------

func upgrade_catalogue() -> Array:
	return _upgrades.upgrades if _upgrades != null else []


func level_of(upgrade_id: StringName) -> int:
	return _upgrades.level_of(upgrade_id) if _upgrades != null else 0


func cost_of(upgrade_id: StringName) -> int:
	return _upgrades.cost_of(upgrade_id) if _upgrades != null else 0


func can_purchase(upgrade_id: StringName) -> bool:
	return _upgrades.can_purchase(upgrade_id) if _upgrades != null else false


func purchase_upgrade(upgrade_id: StringName) -> bool:
	return _upgrades.purchase(upgrade_id) if _upgrades != null else false


# --- Contract: parts --------------------------------------------------------

func part_catalogue() -> Array:
	return _parts.catalogue() if _parts != null else []


func owned_count_of(part_id: StringName) -> int:
	return _parts.owned_count(part_id) if _parts != null else 0


func owns_part(part_id: StringName) -> bool:
	return _parts.owns(part_id) if _parts != null else false


func price_of_part(part_id: StringName) -> int:
	return _parts.price_of(part_id) if _parts != null else 0


func can_purchase_part(part_id: StringName) -> bool:
	return _parts.can_purchase(part_id) if _parts != null else false


func purchase_part(part_id: StringName) -> bool:
	return _parts.purchase(part_id) if _parts != null else false


# --- Contract: actions -----------------------------------------------------

func action_catalogue() -> Array:
	return _actions.actions if _actions != null else []


func perform_action(action_id: StringName) -> bool:
	return _actions.perform(action_id) if _actions != null else false


# --- Contract: downlink -----------------------------------------------------

## Every packet this satellite can send, resolved and ready to render.
func downlink_catalogue() -> Array:
	return _downlink.catalogue() if _downlink != null else []


func can_send_data(packet_id: StringName) -> bool:
	return _downlink.can_send(packet_id) if _downlink != null else false


## Sends [param packet_id] back to Earth. False when the packet is unknown or may not
## be sent again.
func transmit_data(packet_id: StringName) -> bool:
	return _downlink.transmit(packet_id) if _downlink != null else false


func sent_count_of(packet_id: StringName) -> int:
	return _downlink.sent_count(packet_id) if _downlink != null else 0


func downlink_totals() -> Dictionary:
	return _downlink.totals() if _downlink != null else {}


# --- Contract: appearance --------------------------------------------------

func set_visual(key: StringName, value: Variant) -> void:
	if _appearance != null:
		_appearance.set_visual(key, value)


func set_appearance_state(state: StringName) -> void:
	if _appearance != null:
		_appearance.set_state(state)


func appearance_snapshot() -> Dictionary:
	return _appearance.snapshot() if _appearance != null else {}


## Stops or resumes distance accrual. The distance stat keeps its current value.
func set_distance_accrual(enabled: bool) -> void:
	if _motion != null:
		_motion.accrual_enabled = enabled


# --- Contract: persistence -------------------------------------------------

## Everything a save needs to bring this satellite back: identity, stats, upgrade
## levels, fitted parts, granted actions, appearance and downlink send counts. Read
## by [code]SaveManager[/code] through the contract, so no module here knows that
## saves exist.
##
## [Satellite] is the only node in the tree that answers the contract. Every module
## below it exposes a plain snapshot/restore pair and is composed here, which is
## what keeps a save file to one entry per satellite.
func save_data() -> Dictionary:
	var actions: Dictionary = {
		"granted": _actions.granted_snapshot(),
		"cooldowns": _actions.cooldowns_snapshot(),
	}
	return {
		"id": str(id),
		"display_name": display_name,
		"stats": _stats.snapshot() if _stats != null else {},
		"upgrades": _upgrades.levels_snapshot() if _upgrades != null else {},
		"parts": _parts.owned_snapshot() if _parts != null else {},
		"actions": actions if _actions != null else {},
		"appearance": _appearance.snapshot() if _appearance != null else {},
		"downlink": _downlink.sent_snapshot() if _downlink != null else {},
	}


## Restores what [method save_data] produced.
##
## The order is the whole trick. Levels and parts come first, because they are what
## own the unlocked actions. Stats and appearance then go back as the absolute
## values the save recorded, overwriting anything the reapplication produced -
## applying the effects a second time on top would double count them.
func load_data(data: Dictionary) -> void:
	var raw_id: Variant = data.get("id")
	if raw_id != null:
		id = StringName(raw_id)
	var raw_name: Variant = data.get("display_name")
	if raw_name != null:
		display_name = str(raw_name)
	if _upgrades != null:
		_upgrades.restore_levels(_as_dictionary(data.get("upgrades")))
	if _parts != null:
		_parts.restore_owned(_as_dictionary(data.get("parts")))
	if _actions != null:
		var actions := _as_dictionary(data.get("actions"))
		_actions.restore(actions.get("granted", []), actions.get("cooldowns", {}))
	if _stats != null:
		_stats.set_all(_as_dictionary(data.get("stats")))
	if _appearance != null:
		_appearance.restore(_as_dictionary(data.get("appearance")))
	if _downlink != null:
		_downlink.restore_sent(_as_dictionary(data.get("downlink")))


func _as_dictionary(value: Variant) -> Dictionary:
	return (value as Dictionary) if value is Dictionary else {}


# --- Internals -------------------------------------------------------------

func _collect_modules() -> void:
	for child in get_children():
		if child is SatelliteStats:
			_stats = child as SatelliteStats
		elif child is SatelliteUpgrades:
			_upgrades = child as SatelliteUpgrades
		elif child is SatelliteParts:
			_parts = child as SatelliteParts
		elif child is SatelliteAppearance:
			_appearance = child as SatelliteAppearance
		elif child is SatelliteActions:
			_actions = child as SatelliteActions
		elif child is SatelliteMotion:
			_motion = child as SatelliteMotion
		elif child is SatelliteDownlink:
			_downlink = child as SatelliteDownlink


func _bind_modules() -> void:
	if _actions != null:
		_actions.bind(_stats)
	if _motion != null:
		_motion.bind(_stats)
	if _downlink != null:
		_downlink.bind(_stats)
	if _upgrades != null:
		_upgrades.bind(_stats, _appearance, _actions)
	if _parts != null:
		_parts.bind(_stats, _appearance, _actions)


func _republish() -> void:
	if _stats != null:
		_stats.stats_changed.connect(_on_stats_changed)
	if _upgrades != null:
		_upgrades.upgrade_purchased.connect(_on_upgrade_purchased)
		_upgrades.upgrades_changed.connect(_on_upgrades_changed)
	if _parts != null:
		_parts.part_purchased.connect(_on_part_purchased)
		_parts.parts_changed.connect(_on_parts_changed)
	if _appearance != null:
		_appearance.appearance_changed.connect(_on_appearance_changed)
	if _actions != null:
		_actions.action_performed.connect(_on_action_performed)
	if _downlink != null:
		_downlink.data_transmitted.connect(_on_data_transmitted)
		_downlink.downlink_changed.connect(_on_downlink_changed)


func _emit_stats() -> void:
	if _stats != null:
		stats_changed.emit(_stats.snapshot())


func _on_stats_changed(snapshot: Dictionary) -> void:
	stats_changed.emit(snapshot)


func _on_upgrade_purchased(upgrade: Resource, level: int) -> void:
	upgrade_purchased.emit(upgrade, level)


func _on_upgrades_changed() -> void:
	upgrades_changed.emit()


func _on_part_purchased(part: Resource, owned: int) -> void:
	part_purchased.emit(part, owned)


func _on_parts_changed() -> void:
	parts_changed.emit()


func _on_appearance_changed(snapshot: Dictionary) -> void:
	appearance_changed.emit(snapshot)


func _on_action_performed(action: Resource) -> void:
	action_performed.emit(action)


func _on_data_transmitted(packet: Resource, count: int) -> void:
	data_transmitted.emit(packet, count)


func _on_downlink_changed() -> void:
	downlink_changed.emit()
