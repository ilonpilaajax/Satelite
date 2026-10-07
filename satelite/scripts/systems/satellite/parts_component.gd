class_name SatelliteParts
extends Node
## The hardware a satellite has fitted: the parts shop catalogue and the purchase
## flow behind it.
##
## Where [SatelliteUpgrades] buys levels on systems that are already there, this
## buys the systems themselves, once each. A part writes a flat stat delta when it
## is fitted, which is the only real difference, so both menus read the same shape
## and neither has to know what the other sells.
##
## The modules this writes to are handed in through [method bind] rather than
## looked up, so the component is testable on its own and never has to know its
## satellite's shape. Everything is reported through signals.

signal part_purchased(part: PartDefinition, owned: int)
signal purchase_rejected(part: PartDefinition, reason: StringName)
signal parts_changed()

const REASON_MAXED := &"maxed"
const REASON_UNKNOWN := &"unknown_part"
const REASON_CANNOT_AFFORD := &"cannot_afford"
const REASON_LOCKED := &"locked"

@export var parts: Array[PartDefinition] = []

## Stat id the prices in [member PartDefinition.price] are paid with. Left empty,
## which means prices are reported but not charged: parts are then limited only by
## [member PartDefinition.max_owned] and [member PartDefinition.requires]. Point
## this at one of your own stats to make them cost something.
@export var currency_stat: StringName = &""

var _stats: SatelliteStats = null
var _appearance: SatelliteAppearance = null
var _actions: SatelliteActions = null
var _owned: Dictionary = {}


## Connects the modules a part writes to. Call once the other modules exist;
## [Satellite] does this for you.
func bind(stats: SatelliteStats, appearance: SatelliteAppearance = null, actions: SatelliteActions = null) -> void:
	if stats == _stats and appearance == _appearance and actions == _actions:
		return
	_stats = stats
	_appearance = appearance
	_actions = actions


func find(part_id: StringName) -> PartDefinition:
	for part in parts:
		if part != null and part.id == part_id:
			return part
	return null


## How many of [param part_id] are fitted. Unknown parts read as 0.
func owned_count(part_id: StringName) -> int:
	return int(_owned.get(part_id, 0))


func owns(part_id: StringName) -> bool:
	return owned_count(part_id) > 0


## True while [member PartDefinition.requires] names a part that is not fitted yet.
func is_locked(part_id: StringName) -> bool:
	var part := find(part_id)
	if part == null or part.requires == &"":
		return false
	return not owns(part.requires)


## Price of the next copy of [param part_id], or 0 when the part is unknown or
## fully fitted.
func price_of(part_id: StringName) -> int:
	var part := find(part_id)
	if part == null or part.is_maxed_at(owned_count(part_id)):
		return 0
	return part.price


func can_purchase(part_id: StringName) -> bool:
	return _rejection(part_id) == &""


## Why [param part_id] cannot be bought right now, or empty when it can. Also tells
## a menu why a row is disabled without duplicating the rules.
func _rejection(part_id: StringName) -> StringName:
	var part := find(part_id)
	if part == null:
		return REASON_UNKNOWN
	if part.is_maxed_at(owned_count(part_id)):
		return REASON_MAXED
	if is_locked(part_id):
		return REASON_LOCKED
	if not _charges():
		return &""
	var value: Variant = _stats.get_stat(currency_stat, 0.0)
	if not (value is float or value is int) or float(value) < float(part.price):
		return REASON_CANNOT_AFFORD
	return &""


## Fits one copy, paying [member PartDefinition.price] when a currency is set.
## Returns false without side effects when the part is unknown, fully fitted,
## locked or unaffordable.
##
## Buying does not write [member PartDefinition.stat_effects]: those land when the copy is
## fitted and finished being set up, so a part in the store and one on the hull pay the same
## way. Only the one-off unlocks are written here, since an action is unlocked by owning the
## hardware, not by where it is standing.
func purchase(part_id: StringName) -> bool:
	var reason := _rejection(part_id)
	if reason != &"":
		var rejected := find(part_id)
		if rejected != null:
			purchase_rejected.emit(rejected, reason)
		return false

	var part := find(part_id)
	var owned := owned_count(part_id)
	if _charges():
		_stats.add_stat(currency_stat, -float(part.price))
	_owned[part_id] = owned + 1
	_on_purchased(part, owned == 0)
	part_purchased.emit(part, owned + 1)
	parts_changed.emit()
	return true


## Fits a part for free, e.g. when loading a save. Skips the price and still unlocks its
## actions; its stat effects arrive with the mount that carries it.
func grant(part_id: StringName, count: int = 1) -> void:
	var part := find(part_id)
	if part == null or count <= 0:
		return
	var owned := owned_count(part_id)
	_owned[part_id] = mini(owned + count, part.max_owned)
	_on_purchased(part, owned == 0)
	part_purchased.emit(part, owned_count(part_id))
	parts_changed.emit()


## Every part as one row for a menu, already carrying the price, the fitted count
## and the reason a buy button would be disabled. Built here rather than in the menu
## so the rules live with the rules.
func catalogue() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for part in parts:
		if part == null:
			continue
		var owned := owned_count(part.id)
		var reason := _rejection(part.id)
		result.append({
			"part": part,
			"id": part.id,
			"display_name": part.display_name,
			"description": part.description,
			"icon": part.icon,
			"category": part.category,
			"price": price_of(part.id),
			"owned": owned,
			"max_owned": part.max_owned,
			"fitted_label": part.fitted_label(owned),
			"can_purchase": reason == &"",
			"reason": reason,
		})
	return result


## Every fitted part, ready for a summary screen.
func owned() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for part in parts:
		if part == null:
			continue
		var count := owned_count(part.id)
		if count > 0:
			result.append({"part": part, "id": part.id, "owned": count, "max_owned": part.max_owned})
	return result


## How many distinct parts are fitted, which is what a completion screen wants.
func fitted_count() -> int:
	var result := 0
	for part in parts:
		if part != null and owns(part.id):
			result += 1
	return result


func _charges() -> bool:
	return _stats != null and currency_stat != &""


## Writes [param part]'s stat effects, once per copy that is actually working. Called by
## [SatelliteSlots] when a copy is fitted and its setup finishes, so the satellite's numbers
## follow the hardware rather than the receipt.
##
## Effects are written per activation rather than per copy so that taking a part back off
## the hull can give the numbers back: [method deactivate] is the other half of this pair.
func activate(part: PartDefinition) -> void:
	if _stats != null and not part.stat_effects.is_empty():
		_stats.apply_effects(part.stat_effects, 1)


## Takes [param part]'s stat effects back off, for a copy that has been replaced or taken out
## of its mount. Without this, swapping an antenna would stack its bonus up forever.
func deactivate(part: PartDefinition) -> void:
	if _stats != null and not part.stat_effects.is_empty():
		_stats.apply_effects(part.stat_effects, -1)


## Unlocks a part's actions. Only the first copy unlocks anything, since the second is more
## of the same hardware and adds no new action.
func _grant_actions(part: PartDefinition) -> void:
	if _actions == null:
		return
	for action in part.unlocks_actions:
		_actions.grant(action)


## What buying a copy writes: how the part looks on the satellite, and its actions the first
## time. The stat effects are left out on purpose - they follow the mount, not the receipt,
## so see [method activate]. Appearance is written here because it is a description of what
## the satellite carries rather than a running total that could be given back.
func _on_purchased(part: PartDefinition, first_time: bool) -> void:
	if _appearance != null and not part.appearance_effects.is_empty():
		_appearance.set_visuals(part.appearance_effects)
	if first_time:
		_grant_actions(part)


# --- Persistence ------------------------------------------------------------

## Every fitted part as {part_id: count}.
func owned_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for part_id: Variant in _owned:
		var count := int(_owned[part_id])
		if count > 0:
			result[part_id] = count
	return result


## Puts back what [method owned_snapshot] produced, dropping any part the save does
## not mention and clamping counts to the current [member PartDefinition.max_owned].
##
## Stats and appearance are deliberately left alone: they are restored as absolute
## values by [Satellite], so writing the effects again here would double count
## them. Actions are re-granted, because they are not part of any absolute block.
func restore_owned(owned: Dictionary) -> void:
	_owned.clear()
	for part_id: Variant in owned:
		var part := find(StringName(part_id))
		if part != null:
			_owned[part.id] = clampi(int(owned[part_id]), 0, part.max_owned)
	for part in parts:
		if part == null or not owns(part.id) or _actions == null:
			continue
		for action in part.unlocks_actions:
			_actions.grant(action)
	parts_changed.emit()
