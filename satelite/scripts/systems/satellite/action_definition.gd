class_name SatelliteAction
extends Resource
## Data-only description of something a satellite can do.
##
## The action itself is generic: it waits out a cooldown and writes stat deltas.
## What it *means* lives entirely in the [member stat_effects] values, so adding
## an action never means writing a new script. Create instances with
## [code]New SatelliteAction[/code] in the inspector, or save them as
## [code].tres[/code] so several satellites can share the same action.

@export var id: StringName = &""
@export var display_name: String = "Action"
@export_multiline var description: String = ""
@export var icon: Texture2D = null

## Stat ids and the amount added per use, e.g. {&"speed": 12.0}. A negative value
## subtracts, which is how braking is expressed.
@export var stat_effects: Dictionary = {}

## Seconds before the action can be used again. Zero disables the cooldown.
@export var cooldown: float = 0.0
