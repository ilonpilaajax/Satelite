class_name SatelliteStats
extends Node
## Live stat block for a single satellite.
##
## Stats live in one [StringName]-keyed dictionary, so upgrades and actions can
## target a stat by name without importing this script. Values are clamped
## against [member stat_ranges] when one is defined, and every change is
## broadcast: nothing downstream needs a reference to this node.
##
## This is a module, not a satellite. Attach it to any node and it works.

signal stat_changed(id: StringName, value: Variant, previous: Variant)
signal stats_changed(snapshot: Dictionary)

## Ids the shipped UI reads. Add your own by exporting them in the inspector.
const NAME := &"name"
const SPEED := &"speed"
const DISTANCE_FROM_EARTH := &"distance_from_earth"

## Starting values, editable in the inspector. Missing ids simply read as null.
@export var stats: Dictionary = {
	NAME: "SATELITE-01",
	SPEED: 0.0,
	DISTANCE_FROM_EARTH: 0.0,
}

## Optional clamping per stat, e.g. {&"speed": {"min": 0.0, "max": 120.0}}.
## Ids that are absent here stay unclamped.
@export var stat_ranges: Dictionary = {}

## Optional presentation metadata per stat, e.g.
## {&"speed": {"caption": "SPEED", "unit": "km/s", "decimals": 1}}.
## Every key is optional: a missing caption is derived from the id, so
## [code]distance_from_earth[/code] reads as "DISTANCE FROM EARTH" with no
## configuration. Read by the readout UI, which is why it lives here rather
## than in the HUD.
@export var stat_meta: Dictionary = {}

var _values: Dictionary = {}


func _ready() -> void:
	_values = stats.duplicate(true)


## Current value of [param id], or [param fallback] when it is not tracked.
func get_stat(id: StringName, fallback: Variant = null) -> Variant:
	return _values.get(id, fallback)


## Writes [param id] and emits. Unchanged values are ignored, so listeners only
## ever see real movement.
func set_stat(id: StringName, value: Variant) -> void:
	var previous: Variant = _values.get(id)
	var next: Variant = _clamp(id, value)
	if previous == next and _values.has(id):
		return
	_values[id] = next
	stat_changed.emit(id, next, previous)
	stats_changed.emit(snapshot())


## Adds [param delta] to a numeric stat. Non-numeric and unknown stats count as 0.
func add_stat(id: StringName, delta: float) -> void:
	var current: Variant = get_stat(id)
	var base := 0.0
	if current is float or current is int:
		base = float(current)
	set_stat(id, base + delta)


## Applies `{stat_id: amount_per_level}` scaled by [param level]. This is the shape
## [UpgradeDefinition.stat_effects] and [SatelliteAction.stat_effects] use, so
## upgrades and actions need no knowledge of the individual stats.
func apply_effects(effects: Dictionary, level: int) -> void:
	for key: Variant in effects:
		var id := StringName(key)
		set_stat(id, float(get_stat(id, 0.0)) + float(effects[key]) * level)


## Replaces the tracked set with [param values]. Ids that are missing stop being
## tracked, which is what loading a save needs; use [method set_stat] to add to
## the set instead.
func set_all(values: Dictionary) -> void:
	var next: Dictionary = {}
	for key: Variant in values:
		var id := StringName(key)
		next[id] = _clamp(id, values[key])
	var previous := _values
	_values = next
	for id: StringName in previous:
		if not _values.has(id):
			stat_changed.emit(id, null, previous[id])
	for id: StringName in _values:
		stat_changed.emit(id, _values[id], previous.get(id))
	stats_changed.emit(snapshot())


func reset_to_defaults() -> void:
	set_all(stats)


## Copy of every tracked value. Treat it as read-only.
func snapshot() -> Dictionary:
	return _values.duplicate()


## Heading for a stat: the one from [member stat_meta], else the id turned into
## words, so [code]&"distance_from_earth"[/code] becomes "DISTANCE FROM EARTH".
func caption_for(id: StringName) -> String:
	var meta := _meta_for(id)
	var configured: Variant = meta.get("caption")
	if configured != null:
		return str(configured)
	return str(id).to_upper().replace("_", " ")


## Every tracked stat as {id, caption, unit, decimals, value}, in the order the
## ids were added. This is what a readout renders, so adding a stat to this node
## makes it appear in the UI with no UI change.
func descriptors() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key: Variant in _values:
		var id := StringName(key)
		var meta := _meta_for(id)
		result.append({
			"id": id,
			"caption": caption_for(id),
			"unit": str(meta.get("unit", "")),
			"decimals": int(meta.get("decimals", 1)),
			"value": _values[key],
		})
	return result


func _meta_for(id: StringName) -> Dictionary:
	var raw: Variant = stat_meta.get(id)
	return (raw as Dictionary) if raw is Dictionary else {}


## Convenience accessors for the values the UI reads most.
var satellite_name: String:
	get:
		return str(get_stat(NAME, ""))
	set(value):
		set_stat(NAME, value)

var speed: float:
	get:
		return float(get_stat(SPEED, 0.0))
	set(value):
		set_stat(SPEED, value)

var distance_from_earth: float:
	get:
		return float(get_stat(DISTANCE_FROM_EARTH, 0.0))
	set(value):
		set_stat(DISTANCE_FROM_EARTH, value)


func _clamp(id: StringName, value: Variant) -> Variant:
	if not (value is float or value is int):
		return value
	var limits: Variant = stat_ranges.get(id)
	if not (limits is Dictionary):
		return value
	var bounds: Dictionary = limits
	var result := float(value)
	var low: Variant = bounds.get("min")
	var high: Variant = bounds.get("max")
	if low != null and result < float(low):
		result = float(low)
	if high != null and result > float(high):
		result = float(high)
	return result
