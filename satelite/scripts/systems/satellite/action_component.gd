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
