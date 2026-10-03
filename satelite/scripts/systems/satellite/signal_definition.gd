class_name SignalDefinition
extends Resource
## One kind of signal the satellite can pick up.
##
## A catalogue entry, not a finding. Dropping a [SignalDefinition] into the control
## panel's [code]signals[/code] makes it something the satellite is able to detect; a
## finding - one actually picked up - is a definition plus how strong it came in and how
## many times, which the control panel records and the signals menu lists.
##
## Keep them as [code].tres[/code] files so several satellites can share a catalogue,
## exactly as with [PartDefinition].

@export var id: StringName = &""
@export var display_name: String = "Signal"

## What kind of signal it is, shown as a tag on the row: [code]&"carrier"[/code],
## [code]&"burst"[/code], [code]&"beacon"[/code]. Distinct from [member channel], which
## decides the tab it appears under rather than how it reads.
@export var signal_type: StringName = &""

## Channel this signal is detected on, matching one of the control panel's channels:
## [code]&"radio"[/code], [code]&"radiation"[/code], [code]&"light"[/code] or
## [code]&"particles"[/code]. An empty channel is never detected, so a signal left
## unassigned sits in the catalogue without ever appearing.
@export var channel: StringName = &""

## Shown beside the name. Optional: the row lays out without it, so a signal works
## before any art exists.
@export var icon: Texture2D = null

@export_multiline var description: String = ""

## The signal's own readings, rendered as the line under its name, e.g.
## {&"Frequency": "868.5 MHz", &"Bandwidth": "125 kHz"}.
##
## A dictionary rather than fixed fields, because signals do not all measure the same
## things: a carrier has a frequency, a radiation alert has a dose rate, a particle
## track has a count. Anything that can be rendered as text can go in here, and a
## finding may override any of it with what was actually measured.
@export var details: Dictionary = {}