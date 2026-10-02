class_name UpgradeDefinition
extends Resource
## Data-only description of one upgrade.
##
## An upgrade is levels of a stat delta, an appearance change, and/or a set of
## actions it grants. Buying one never needs a new script: drop a
## [SatelliteAction] into [member unlocks_actions] and it appears on the
## satellite. Keep them as [code].tres[/code] files if several satellites should
## share a catalogue.

@export var id: StringName = &""
@export var display_name: String = "Upgrade"
@export_multiline var description: String = ""
@export var icon: Texture2D = null

## Stat ids and the amount added **per level**, e.g. {&"speed": 1.5}. Level 3
## therefore applies the delta three times, on top of the two previous levels.
@export var stat_effects: Dictionary = {}

## Appearance keys written once the level changes, e.g. {&"tint": Color.RED}.
## Re-purchased at every level, so later levels can dial in a stronger value.
@export var appearance_effects: Dictionary = {}

## Actions granted the first time the upgrade is bought.
@export var unlocks_actions: Array[SatelliteAction] = []

@export var max_level: int = 5

## Price of the first level. Only charged when
## [member SatelliteUpgrades.currency_stat] names a stat to spend.
@export var base_cost: int = 50

## Multiplier per level already owned, so prices rise geometrically.
@export_range(1.0, 4.0, 0.05) var cost_growth: float = 1.35


## Price of the level that follows [param owned_levels].
func cost_at(owned_levels: int) -> int:
	return int(round(base_cost * pow(cost_growth, maxi(0, owned_levels))))


func is_maxed_at(owned_levels: int) -> bool:
	return owned_levels >= max_level
