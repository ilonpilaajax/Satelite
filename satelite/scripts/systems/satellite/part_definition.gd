class_name PartDefinition
extends Resource
## Data-only description of one part you can fit to a satellite.
##
## A part is hardware you buy once, as opposed to an [UpgradeDefinition], which is
## a level you buy again and again on the same system. Nothing here is behaviour:
## drop a [PartDefinition] into [member SatelliteParts.parts] and it appears in the
## parts shop, already priced and already wired to whatever it changes.
##
## Buying it writes [member stat_effects] into the stat block once, so a part is a
## flat bonus while an upgrade is a per-level one. Keep them as [code].tres[/code]
## files if several satellites should share a catalogue.

@export var id: StringName = &""
@export var display_name: String = "Part"
@export_multiline var description: String = ""
@export var icon: Texture2D = null

## Grouping for filtering in the shop, e.g. [code]&"propulsion"[/code] or
## [code]&"sensor"[/code]. Purely presentational: the shop shows it as a tag and
## nothing else reads it.
@export var category: StringName = &""

## Which channel of the satellite's control panel this hardware works for, e.g.
## [code]&"radio"[/code] or [code]&"particles"[/code]. Empty for a part that serves
## no channel.
##
## This is what turns fitted hardware into the panel's antenna counts: how many copies of a
## part are mounted is how much of that channel the satellite can hear, which is what
## [code]set_antenna_counts[/code] in [code]control-panel.gd[/code] is told. A part with no
## channel is still bought and still drawn on the body - it simply has no channel to
## contribute to, which is the right answer for anything that is not an instrument.
##
## Set this on the part, not on a mount: one part definition is however many copies of that
## antenna the satellite carries, and each copy fitted in its own mount adds one to the count.
@export var antenna_channel: StringName = &""

## Stat deltas written **once**, when the part is fitted, e.g. {&"speed": 2.0}.
## Any stat id works, including ids no node tracks yet: the stat block accepts new
## ids and the readout picks them up from its descriptors.
@export var stat_effects: Dictionary = {}

## Appearance keys written once the part is fitted, e.g. {&"antenna_count": 2}.
@export var appearance_effects: Dictionary = {}

## Actions this part makes available. Fitted the first time it is bought.
@export var unlocks_actions: Array[SatelliteAction] = []

## Part that has to be fitted first. Empty means available from the start, which
## is how a shop gets an unlock order without any code.
@export var requires: StringName = &""

## Price, charged against [member SatelliteParts.currency_stat]. Left alone when no
## currency is set, which means the part is free - the same rule upgrades follow.
@export var price: int = 0

## How many may be fitted. One is the normal case; a second solar panel is not.
@export_range(1, 8, 1) var max_owned: int = 1


func is_maxed_at(owned: int) -> bool:
	return owned >= max_owned


## [code]"3/5"[/code] once [param max_owned] is above one, empty otherwise, so a
## single-fit part does not carry a pointless counter.
func fitted_label(owned: int) -> String:
	return "%d/%d" % [owned, max_owned] if max_owned > 1 else ""
