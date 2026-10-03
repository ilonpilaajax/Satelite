class_name DataPacketDefinition
extends Resource
## Data-only description of one thing the satellite can send back to Earth.
##
## A packet is a *result*, not a piece of hardware. Nothing here is behaviour: drop a
## [DataPacketDefinition] into [member SatelliteDownlink.packets] and it appears in
## the downlink list, already sized and already carrying whatever it does when sent.
## That is the whole extension point - the collectors that actually produce data are
## not written yet, so a packet is sendable as soon as it is listed.
##
## Keep them as [code].tres[/code] files if several satellites should share a
## catalogue, exactly as with [PartDefinition].

@export var id: StringName = &""
@export var display_name: String = "Data"
@export_multiline var description: String = ""
@export var icon: Texture2D = null

## Grouping shown as a tag on the row, e.g. [code]&"imaging"[/code]. Purely
## presentational: nothing else reads it.
@export var category: StringName = &""

## How much data one transmission is worth, counted in the unit
## [code]SatelliteDownlink.SIZE_UNIT[/code]. Zero sends without moving
## [member SatelliteDownlink.data_stat], which is the right value for a packet whose
## only effect is the one in [member stat_effects].
@export var size: int = 0

## Stat deltas written **once per transmission**, e.g. {&"credits": 40}. Any stat id
## works, including ids no node tracks yet, so a collector can pay out without this
## definition knowing what it is paying for.
@export var stat_effects: Dictionary = {}

## Whether the same packet may be sent more than once. A live reading - a spectrum
## sweep, a downlink ping - is repeatable; a captured image usually is not.
@export var repeatable: bool = true


## True once this packet has been sent as many times as it may be. The first send of
## a non-repeatable packet exhausts it.
func is_exhausted(sent: int) -> bool:
	return sent > 0 and not repeatable


## Empty until it has been sent, so a row carries no counter before it means
## something: [code]"SENT"[/code] for a spent non-repeatable packet, [code]"3x"[/code]
## for a repeated one.
func sent_label(sent: int) -> String:
	if sent <= 0:
		return ""
	if not repeatable:
		return "SENT"
	return "%dx" % sent