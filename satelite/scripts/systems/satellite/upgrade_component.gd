class_name SatelliteUpgrades
extends Node
## Owns one satellite's upgrade catalogue: levels, prices and the purchase flow.
##
## The other modules are handed in through [method bind] rather than looked up, so
## this component is testable on its own and never has to know its satellite's
## shape. Everything is reported through signals, which is how the upgrade menu
## and any other listener stay decoupled.

signal upgrade_purchased(upgrade: UpgradeDefinition, level: int)
signal level_changed(upgrade: UpgradeDefinition, level: int)
signal purchase_rejected(upgrade: UpgradeDefinition, reason: StringName)
signal upgrades_changed()

@export var upgrades: Array[UpgradeDefinition] = []

## Stat id the prices in [UpgradeDefinition.base_cost] are paid with. Left empty,
## which means prices are reported but not charged: upgrades are then limited only
## by [member UpgradeDefinition.max_level]. Point this at one of your own stats to
## make them cost something.
@export var currency_stat: StringName = &""

const REASON_MAXED := &"maxed"
const REASON_CANNOT_AFFORD := &"cannot_afford"
const REASON_UNKNOWN := &"unknown_upgrade"

var _stats: SatelliteStats = null
var _appearance: SatelliteAppearance = null
var _actions: SatelliteActions = null
var _levels: Dictionary = {}


## Connects the modules this upgrade applies to. Owned levels are reapplied so a
## fresh stats block still produces the right numbers, and re-binding the same
## modules is a no-op rather than a second application of every effect.
func bind(stats: SatelliteStats, appearance: SatelliteAppearance = null, actions: SatelliteActions = null) -> void:
	if stats == _stats and appearance == _appearance and actions == _actions:
		return
	_stats = stats
	_appearance = appearance
	_actions = actions
	_reapply_all()


func find(upgrade_id: StringName) -> UpgradeDefinition:
	for upgrade in upgrades:
		if upgrade != null and upgrade.id == upgrade_id:
			return upgrade
	return null


func level_of(upgrade_id: StringName) -> int:
	return int(_levels.get(upgrade_id, 0))


## Price of the next level, or 0 when the upgrade is unknown or maxed out.
func cost_of(upgrade_id: StringName) -> int:
	var upgrade := find(upgrade_id)
	if upgrade == null or upgrade.is_maxed_at(level_of(upgrade_id)):
		return 0
	return upgrade.cost_at(level_of(upgrade_id))


func can_purchase(upgrade_id: StringName) -> bool:
	return _rejection(upgrade_id) == &""


## Why [param upgrade_id] cannot be bought right now, or empty when it can. Public so a menu
## can say why its button is dead without duplicating the rules.
func rejection_reason(upgrade_id: StringName) -> StringName:
	return _rejection(upgrade_id)


## Why [param upgrade_id] cannot be bought right now, or empty when it can.
func _rejection(upgrade_id: StringName) -> StringName:
	var upgrade := find(upgrade_id)
	if upgrade == null:
		return REASON_UNKNOWN
	if upgrade.is_maxed_at(level_of(upgrade_id)):
		return REASON_MAXED
	if not _charges():
		return &""
	var value: Variant = _stats.get_stat(currency_stat, 0.0)
	if not (value is float or value is int) or float(value) < float(upgrade.cost_at(level_of(upgrade_id))):
		return REASON_CANNOT_AFFORD
	return &""


## Buys the next level. Returns false without side effects when it is already
## maxed out, or cannot be paid for.
func purchase(upgrade_id: StringName) -> bool:
	var reason := _rejection(upgrade_id)
	if reason != &"":
		var rejected := find(upgrade_id)
		if rejected != null:
			purchase_rejected.emit(rejected, reason)
		return false

	var owned := level_of(upgrade_id)
	var upgrade := find(upgrade_id)
	if _charges():
		_stats.add_stat(currency_stat, -float(upgrade.cost_at(owned)))
	_levels[upgrade_id] = owned + 1
	# Only the newly bought level's delta, since every earlier level already
	# contributed when it was bought.
	_apply(upgrade, 1, owned == 0)
	level_changed.emit(upgrade, owned + 1)
	upgrade_purchased.emit(upgrade, owned + 1)
	upgrades_changed.emit()
	return true


## Grants levels for free, e.g. when loading a save. Skips the cost and still
## applies the effects.
func grant(upgrade_id: StringName, level: int) -> void:
	var upgrade := find(upgrade_id)
	if upgrade == null or level <= 0:
		return
	var owned := level_of(upgrade_id)
	_levels[upgrade_id] = level
	_apply(upgrade, level - owned, owned == 0)
	level_changed.emit(upgrade, level)
	upgrades_changed.emit()


## Every owned level as {upgrade_id: level}, ready for a save file.
func levels_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for upgrade in upgrades:
		if upgrade == null:
			continue
		var level := level_of(upgrade.id)
		if level > 0:
			result[upgrade.id] = level
	return result


## Puts back the levels from [method levels_snapshot], dropping any level the save
## does not mention.
##
## Stats and appearance are deliberately left alone: they are restored as absolute
## values by [Satellite], so applying the effects again here would double count
## them. Unlocked actions are re-granted, because they are not part of any
## absolute block - this is what brings back an action the level paid for.
func restore_levels(levels: Dictionary) -> void:
	_levels.clear()
	for key: Variant in levels:
		var upgrade := find(StringName(key))
		if upgrade != null:
			_levels[upgrade.id] = maxi(0, int(levels[key]))
	for upgrade in upgrades:
		if upgrade == null or level_of(upgrade.id) <= 0 or _actions == null:
			continue
		for action in upgrade.unlocks_actions:
			_actions.grant(action)
	upgrades_changed.emit()


## True when [param upgrade_id] has been bought at least once.
func is_owned(upgrade_id: StringName) -> bool:
	return level_of(upgrade_id) > 0


## Every owned upgrade with its level, ready to feed a menu.
func owned() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for upgrade in upgrades:
		if upgrade == null:
			continue
		var level := level_of(upgrade.id)
		if level > 0:
			result.append({"upgrade": upgrade, "level": level, "max_level": upgrade.max_level})
	return result


## [param stat_levels] is how many levels' worth of stat delta to add, which is 1
## for a normal purchase and the difference for a jump. [param first_time] gates
## the one-off effects: granting actions only happens when the upgrade goes from
## unowned to owned.
func _charges() -> bool:
	return _stats != null and currency_stat != &""


func _apply(upgrade: UpgradeDefinition, stat_levels: int, first_time: bool) -> void:
	if stat_levels > 0 and _stats != null and not upgrade.stat_effects.is_empty():
		_stats.apply_effects(upgrade.stat_effects, stat_levels)
	if _appearance != null and not upgrade.appearance_effects.is_empty():
		_appearance.set_visuals(upgrade.appearance_effects)
	if first_time and _actions != null:
		for action in upgrade.unlocks_actions:
			_actions.grant(action)


func _reapply_all() -> void:
	for upgrade in upgrades:
		if upgrade == null:
			continue
		var level := level_of(upgrade.id)
		if level > 0:
			# Grants already happened, so only the stat deltas are rebuilt here.
			_apply(upgrade, level, false)
