class_name SatelliteActions
extends Node
## The actions a satellite can perform, with costs and cooldowns.
##
## Actions arrive either from the inspector or from upgrades that grant them, so
## the upgrade menu and the action bar can both be written against this one
## component. Effects are stat deltas; nothing here knows what they mean.

signal action_performed(action: SatelliteAction)
signal action_rejected(action: SatelliteAction, reason: StringName)
signal cooldown_changed(action: SatelliteAction, remaining: float)
signal action_granted(action: SatelliteAction)

const REASON_ON_COOLDOWN := &"on_cooldown"
const REASON_UNKNOWN := &"unknown_action"

@export var actions: Array[SatelliteAction] = []

var _stats: SatelliteStats = null
var _cooldowns: Dictionary = {}
## Actions [member actions] started with. Anything beyond this set was granted at
## runtime, which is what a save has to record.
var _initial_ids: Array[StringName] = []


func _ready() -> void:
	_initial_ids = ids()


## Connects the stat block this component spends from. Call after the stats
## module exists; [Satellite] does this for you.
func bind(stats: SatelliteStats) -> void:
	_stats = stats


func _process(delta: float) -> void:
	_tick_cooldowns(delta)


func find(action_id: StringName) -> SatelliteAction:
	for action in actions:
		if action != null and action.id == action_id:
			return action
	return null


func has(action_id: StringName) -> bool:
	return find(action_id) != null


## Adds an action if it is not registered yet. Used by upgrades.
func grant(action: SatelliteAction) -> void:
	if action == null or has(action.id):
		return
	actions.append(action)
	action_granted.emit(action)


## Id of every action currently available, in order.
func ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for action in actions:
		if action != null:
			result.append(action.id)
	return result


func remaining_cooldown(action_id: StringName) -> float:
	return maxf(0.0, float(_cooldowns.get(action_id, 0.0)))


func is_ready(action_id: StringName) -> bool:
	return find(action_id) != null and remaining_cooldown(action_id) <= 0.0


## Runs the action's stat effects if it is off cooldown. Returns whether it ran.
func perform(action_id: StringName) -> bool:
	var action := find(action_id)
	if action == null:
		action_rejected.emit(null, REASON_UNKNOWN)
		return false
	if remaining_cooldown(action_id) > 0.0:
		action_rejected.emit(action, REASON_ON_COOLDOWN)
		return false

	if _stats != null and not action.stat_effects.is_empty():
		_stats.apply_effects(action.stat_effects, 1)
	if action.cooldown > 0.0:
		_cooldowns[action_id] = action.cooldown
		cooldown_changed.emit(action, action.cooldown)
	action_performed.emit(action)
	return true


## Cooldowns still running, as {action_id: seconds left}.
func cooldowns_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for id: Variant in _cooldowns:
		result[StringName(id)] = float(_cooldowns[id])
	return result


## Actions that were granted at runtime, i.e. by an upgrade or a part rather than
## shipped in [member actions]. The shipped ones come back with the scene, so a
## save only has to name what was added.
func granted_snapshot() -> Array[StringName]:
	var result: Array[StringName] = []
	for id in ids():
		if not id in _initial_ids:
			result.append(id)
	return result


## Puts back the actions from [method granted_snapshot] and the cooldowns that
## were still running. A cooldown resumes where it left off, so a save taken
## mid-boost comes back as a boost in progress.
##
## Named rather than [code]load_data[/code] on purpose: [Satellite] composes every
## module into one payload, so nothing below the aggregate root answers the save
## contract and a save file holds one entry per satellite instead of one per
## module.
func restore(granted: Variant, cooldowns: Variant) -> void:
	for id: Variant in _ids_from(granted):
		var action := find(StringName(id))
		if action != null:
			grant(action)
	_cooldowns.clear()
	if not (cooldowns is Dictionary):
		return
	for id: Variant in (cooldowns as Dictionary):
		_cooldowns[StringName(id)] = float((cooldowns as Dictionary)[id])


static func _ids_from(raw: Variant) -> Array:
	var result: Array = []
	if raw is Array:
		for id: Variant in (raw as Array):
			result.append(id)
	elif raw is PackedStringArray:
		for id: String in (raw as PackedStringArray):
			result.append(StringName(id))
	return result


func _tick_cooldowns(delta: float) -> void:
	if _cooldowns.is_empty():
		return
	for action_id: Variant in _cooldowns.keys():
		var id := StringName(action_id)
		var left := maxf(0.0, float(_cooldowns[action_id]) - delta)
		if is_zero_approx(left):
			_cooldowns.erase(action_id)
		else:
			_cooldowns[action_id] = left
		cooldown_changed.emit(find(id), left)
