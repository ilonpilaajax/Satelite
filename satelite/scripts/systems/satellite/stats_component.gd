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
## Spendable balance. What [SatelliteUpgrades.currency_stat] and
## [SatelliteParts.currency_stat] point at when parts should cost something.
const CREDITS := &"credits"
## Data volume sent back to Earth, credited by [SatelliteDownlink] on every
## transmission. Zero-seeded so the readout shows the running total from the start
## rather than appearing on the first send.
const DATA_SENT := &"data_sent"

## Starting values, editable in the inspector. Missing ids simply read as null.
@export var stats: Dictionary = {
	NAME: "SATELITE-01",
	SPEED: 0.0,
	DISTANCE_FROM_EARTH: 0.0,
	CREDITS: 250.0,
	DATA_SENT: 0.0,
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
##
## A stat may also ask for a second readout in another unit, derived from the same
## tracked value rather than tracked alongside it:
## [code]{&"distance_from_earth": {"unit": "km", "secondary_unit": "AU",
## "secondary_conversion": "km_to_au", "secondary_whole_numbers": true}}[/code].
## See [constant SECONDARY_CONVERSIONS] for the conversions and
## [code]secondary_scale[/code] for a raw multiplier instead.
##
## A stat may also say where it belongs:
## [code]"hud": true[/code] puts it on the top readout bar, and a
## [code]"tab"[/code] names the stats-menu submenu it is listed under. The two
## readouts split the stats between them - the bar takes what claims
## [code]hud[/code] and the menu lists the rest - so a stat can never end up in
## both places or in neither, and neither readout needs a list of its own.
@export var stat_meta: Dictionary = {}

## One astronomical unit in kilometres, from the IAU's 2012 exact definition. The
## number every AU readout is derived from, kept here so it is stated once.
const AU_IN_KM := 149597870.7

## Named conversions for a stat's secondary unit, keyed by the name a scene puts in
## [code]stat_meta[/code]'s [code]secondary_conversion[/code]. A scene says
## [code]"km_to_au"[/code] rather than carrying [code]6.68e-9[/code], which nobody can
## read and nobody can check.
##
## Each entry is what the stat's own number is divided by, rather than a multiplier to
## apply. That is because this figure decides where a whole-number readout changes over:
## dividing lands exactly on that boundary, while multiplying by the reciprocal of
## [constant AU_IN_KM] loses the last bit and can report the next whole AU a fraction
## of a kilometre early.
const SECONDARY_CONVERSIONS: Dictionary = {
	"km_to_au": AU_IN_KM,
}

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


## Every tracked stat as {id, caption, unit, decimals, value, hud, tab}, in the
## order the ids were added. This is what a readout renders, so adding a stat to
## this node makes it appear in the UI with no UI change.
##
## Carries a [code]secondary[/code] block for any stat whose [member stat_meta] asks
## for a second unit. It is computed from [code]value[/code] right here, which is
## the point: the second unit is a view of the one tracked number, not a second number
## that has to be kept in step with it.
##
## [code]hud[/code] and [code]tab[/code] say which readout the stat belongs to. See
## [member stat_meta]; [method format_value] renders the value they carry.
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
			"secondary": _secondary_for(id, _values[key]),
			"hud": bool(meta.get("hud", false)),
			"tab": str(meta.get("tab", "")),
		})
	return result


## A descriptor's value as it should be read on screen.
##
## Static, and here rather than in either readout, so the top bar and the stats menu cannot
## drift into formatting the same number two different ways.
static func format_value(descriptor: Dictionary) -> String:
	var primary := _format_in(descriptor.get("value"), str(descriptor.get("unit", "")),
		int(descriptor.get("decimals", 1)))
	var secondary: Variant = descriptor.get("secondary")
	if not (secondary is Dictionary):
		return primary
	var alt: Dictionary = secondary
	var alt_unit := str(alt.get("unit", ""))
	if alt_unit.is_empty():
		return primary
	# The secondary unit first, because that is the order the stat asked for, and because
	# a stat with a secondary unit is being read at two scales at once, coarse to fine.
	return "%s / %s" % [_format_in(alt.get("value"), alt_unit, int(alt.get("decimals", 1))), primary]


static func _format_in(value: Variant, unit: String, decimals: int) -> String:
	var text: String
	if value is float:
		text = String.num(float(value), decimals)
	else:
		# Ints and strings alike: a stat is free to hold something that is not a number,
		# and the satellite's own name is one.
		text = str(value)
	return "%s %s" % [text, unit] if not unit.is_empty() else text


## The second readout for [param id] as {unit, decimals, value}, or an empty
## dictionary when the stat asks for none or holds something non-numeric.
##
## [param tracked_value] is the value already in the block, so this never reads a
## different source than the primary readout does.
##
## [code]secondary_whole_numbers[/code] is for a coarse unit like AU, where a
## continuously updated fraction is noise: the readout then ticks in whole units and
## shows nothing at all until a whole one has accumulated.
func _secondary_for(id: StringName, tracked_value: Variant) -> Dictionary:
	var meta := _meta_for(id)
	var unit := str(meta.get("secondary_unit", ""))
	if unit.is_empty() or not (tracked_value is float or tracked_value is int):
		return {}
	var converted := _convert(meta, float(tracked_value))
	var decimals := int(meta.get("secondary_decimals", 1))
	if bool(meta.get("secondary_whole_numbers", false)):
		# Floored rather than rounded, so the coarse unit still reads 1 while a second
		# one has not fully gone down. Rounding would claim 2 while short of it, which
		# is the same kind of ahead-of-the-fact number this mode exists to avoid.
		converted = floor(converted)
		if converted < 1.0:
			# Nothing whole to say yet. Showing "0 AU" every frame is worse than
			# showing no AU at all, so the readout falls back to the primary unit.
			return {}
		# Forced to 0: there is nothing to gain from decimals on a value already
		# floored to a whole number, so secondary_decimals does not apply here.
		decimals = 0
	return {
		"unit": unit,
		"decimals": decimals,
		"value": converted,
	}


## Applies whichever secondary conversion the scene asked for: a named one, or a raw
## multiplier for anything [constant SECONDARY_CONVERSIONS] does not cover. No
## conversion at all leaves the value alone, which shows the secondary unit reporting
## the same number under a different name rather than silently reporting a wrong one.
func _convert(meta: Dictionary, tracked_value: float) -> float:
	var named := str(meta.get("secondary_conversion", ""))
	if not named.is_empty():
		return tracked_value / float(SECONDARY_CONVERSIONS.get(named, 1.0))
	return tracked_value * float(meta.get("secondary_scale", 1.0))


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

var credits: float:
	get:
		return float(get_stat(CREDITS, 0.0))
	set(value):
		set_stat(CREDITS, value)


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
