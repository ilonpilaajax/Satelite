class_name Satellite
extends Node2D
## One satellite: the aggregate root that owns the behaviour modules and
## republishes them as a single, small interface.
##
## Every module is optional. The aggregate wires up whatever it finds, so you can
## drop in only the parts a satellite needs and the rest keep working standalone.
##
## [b]The outward contract[/b] is five signals plus a few accessors, and that is
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
## [/codeblock]

signal stats_changed(snapshot: Dictionary)
signal upgrade_purchased(upgrade: Resource, level: int)
signal upgrades_changed()
signal appearance_changed(snapshot: Dictionary)
signal action_performed(action: Resource)

@export var id: StringName = &"satellite"
@export var display_name: String = "SATELITE-01"

var _stats: SatelliteStats = null
var _upgrades: SatelliteUpgrades = null
var _appearance: SatelliteAppearance = null
var _actions: SatelliteActions = null
var _motion: SatelliteMotion = null


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


func appearance() -> SatelliteAppearance:
	return _appearance


func actions() -> SatelliteActions:
	return _actions


func motion() -> SatelliteMotion:
	return _motion


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


# --- Contract: actions -----------------------------------------------------

func action_catalogue() -> Array:
	return _actions.actions if _actions != null else []


func perform_action(action_id: StringName) -> bool:
	return _actions.perform(action_id) if _actions != null else false


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


# --- Internals -------------------------------------------------------------

func _collect_modules() -> void:
	for child in get_children():
		if child is SatelliteStats:
			_stats = child as SatelliteStats
		elif child is SatelliteUpgrades:
			_upgrades = child as SatelliteUpgrades
		elif child is SatelliteAppearance:
			_appearance = child as SatelliteAppearance
		elif child is SatelliteActions:
			_actions = child as SatelliteActions
		elif child is SatelliteMotion:
			_motion = child as SatelliteMotion


func _bind_modules() -> void:
	if _actions != null:
		_actions.bind(_stats)
	if _motion != null:
		_motion.bind(_stats)
	if _upgrades != null:
		_upgrades.bind(_stats, _appearance, _actions)


func _republish() -> void:
	if _stats != null:
		_stats.stats_changed.connect(_on_stats_changed)
	if _upgrades != null:
		_upgrades.upgrade_purchased.connect(_on_upgrade_purchased)
		_upgrades.upgrades_changed.connect(_on_upgrades_changed)
	if _appearance != null:
		_appearance.appearance_changed.connect(_on_appearance_changed)
	if _actions != null:
		_actions.action_performed.connect(_on_action_performed)


func _emit_stats() -> void:
	if _stats != null:
		stats_changed.emit(_stats.snapshot())


func _on_stats_changed(snapshot: Dictionary) -> void:
	stats_changed.emit(snapshot)


func _on_upgrade_purchased(upgrade: Resource, level: int) -> void:
	upgrade_purchased.emit(upgrade, level)


func _on_upgrades_changed() -> void:
	upgrades_changed.emit()


func _on_appearance_changed(snapshot: Dictionary) -> void:
	appearance_changed.emit(snapshot)


func _on_action_performed(action: Resource) -> void:
	action_performed.emit(action)
