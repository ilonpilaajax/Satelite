extends Node
## The satellite's instrument panel: what its antennas are picking up.
##
## This is where a [b]signal is found[/b]. [member channels] says where to listen,
## [member signals] says what could turn up, and [method detect_new_signal] files
## whatever was heard as a finding. The signals menu lists those findings and nothing
## else, so the panel is the single source of what has been picked up.
##
## Every channel is described by one entry in [member channels], naming the fields on
## this node it reads. Adding a channel is one table entry plus the fields it names -
## there is no per-channel code anywhere in this file, which is why the four near
## identical [code]run_radio[/code]-style functions it used to have are gone.
##
## [b]Distance from Earth does not live here[/b]. It used to, as a plain
## [code]distance_from_earth[/code] variable fed by [code]add_distance()[/code], which
## left two sources of truth for the same number: this one and the distance stat on
## [SatelliteStats]. Only the stat reaches the UI and only the stat is saved, so the
## copy here was dead weight that silently disagreed with what the player sees.
##
## It now lives where it belongs:
##
## [codeblock]
## # Read it, and change it, through the stat block:
## SatelliteController.stat(&"distance_from_earth")          # km from Earth
## SatelliteController.add_stat(&"distance_from_earth", 10)  # e.g. a cheat or an event
##
## # Decide how fast it grows, by implementing the seam on SatelliteMotion:
## SatelliteMotion.distance_for_delta(delta)                  # km added this frame
## [/codeblock]
##
## The readout needs no code at all: [code]stats_hud.gd[/code] renders every stat
## the satellite tracks, so the distance appears and updates on its own.

## Emitted whenever a signal is heard, so a menu listing findings does not have to
## poll. [param count] is how many times in total.
signal signal_found(channel: StringName, found: Resource, count: int)
## Emitted when findings are cleared or the catalogue changes.
signal signals_changed()

## The channels this panel listens on, in tab order. Each entry names the fields on
## this node it reads, so this is the only place that knows how a channel maps onto the
## satellite - the signals menu renders whatever is listed here rather than keeping its
## own copy of these names.
##
## [code]active_field[/code] gates detection for the channel, so switching it off also
## stops that channel accumulating findings. [code]period[/code] is how many seconds
## pass between listens; [code]timer_field[/code] counts down to the next one, and a
## timer left at zero means "listen on the next frame", which is why the panel hears
## something immediately on the first frame rather than after a full period.
@export var channels: Array[Dictionary] = [
	{
		"id": &"radio",
		"label": "Radio",
		"caption": "RADIO SIGNALS",
		"active_field": "detecting_radio_signals",
		"strength_field": "anten_strenght_radio",
		"range_field": "search_range_radio",
		"timer_field": "timer_radio",
		"period": 5.0,
	},
	{
		"id": &"radiation",
		"label": "Radiation",
		"caption": "RADIATION LEVEL",
		"active_field": "detecting_radiation_level",
		"strength_field": "anten_strenght_radiation",
		"range_field": "search_range_radiation",
		"timer_field": "timer_radiation",
		"period": 7.0,
	},
	{
		"id": &"light",
		"label": "Light",
		"caption": "LIGHT",
		"active_field": "detecting_light",
		"strength_field": "anten_strenght_light",
		"range_field": "search_range_light",
		"timer_field": "timer_light",
		"period": 6.0,
	},
	{
		"id": &"particles",
		"label": "Particles",
		"caption": "PARTICLES",
		"active_field": "detecting_particles",
		"strength_field": "anten_strenght_particles",
		"range_field": "search_range_particles",
		"timer_field": "timer_particles",
		"period": 9.0,
	},
]

## Signals this panel is able to detect. Anything here whose [member
## SignalDefinition.channel] matches a channel can turn up on it. An empty catalogue is
## valid: nothing is ever found, and the signals menu shows its empty message.
@export var signals: Array[SignalDefinition] = []

## How likely each channel is to hear something, against its reach. The chance of a
## detection on a listen is strength / range, so widening the range makes a channel
## quieter rather than just busier.
##
## Detection is on for every channel, so the satellite is listening from the first
## frame. Set an [code]active_field[/code] false in the inspector to take a channel
## offline.
var detecting_radio_signals: bool = true
var anten_strenght_radio: float = 20.0
var search_range_radio: float = 100.0
var detecting_radiation_level: bool = true
var anten_strenght_radiation: float = 15.0
var search_range_radiation: float = 80.0
var detecting_light: bool = true
var anten_strenght_light: float = 25.0
var search_range_light: float = 120.0
var detecting_particles: bool = true
var anten_strenght_particles: float = 10.0
var search_range_particles: float = 60.0

## Seconds until each channel next listens. Zero means "now", so all four start at zero
## and the panel hears on its first frame. Named by [code]timer_field[/code] in
## [member channels].
var timer_radio: float = 0.0
var timer_radiation: float = 0.0
var timer_light: float = 0.0
var timer_particles: float = 0.0

## Findings, keyed by channel then by signal id, so a signal heard again is counted
## rather than listed twice. Each entry is {definition, count, strength}.
var _found: Dictionary = {}


func _process(_delta: float) -> void:
	for entry: Dictionary in channels:
		if _flag(entry, "active_field"):
			_run(entry)


## One listen. Counts the channel's timer down; on the frame it runs out, refills it to
## the channel's period and rolls for a detection.
func _run(entry: Dictionary) -> void:
	var remaining := _number(entry, "timer_field") - get_process_delta_time()
	if remaining > 0.0:
		_set_number(entry, "timer_field", remaining)
		return
	_set_number(entry, "timer_field", float(entry.get("period", 5.0)))
	var reach := _number(entry, "range_field")
	if reach <= 0.0:
		return
	# randi_range wants whole numbers; a float range used to raise here, which meant the
	# detection path had never actually run.
	if float(randi_range(0, int(reach))) > _number(entry, "strength_field"):
		return
	detect_new_signal(StringName(entry.get("id", &"")))


# --- What has been found ----------------------------------------------------

## Files a detection on [param channel]: one of the catalogue's signals for that
## channel, at random, recorded with the strength it came in at.
##
## This is where a finding comes from. [method _run] decides whether to listen; this
## decides what was heard.
func detect_new_signal(channel: StringName) -> void:
	var options := signals_for(channel)
	if options.is_empty():
		return
	var definition: SignalDefinition = options[randi() % options.size()]
	var by_channel: Dictionary = _found.get(channel, {})
	var entry: Dictionary = by_channel.get(definition.id, {})
	var count := int(entry.get("count", 0)) + 1
	by_channel[definition.id] = {
		"definition": definition,
		"count": count,
		"strength": randf(),
	}
	_found[channel] = by_channel
	signal_found.emit(channel, definition, count)


## What has been heard on [param channel], one row per signal, already carrying
## everything a list needs to render: id, name, type, icon, description, the signal's
## own details, the measured strength and how many times it has been heard.
##
## Resolved here rather than in the menu so the two can never disagree, in the same
## spirit as [method SatelliteStats.descriptors] driving the stats readout.
func findings_for(channel: StringName) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var by_channel: Dictionary = _found.get(channel, {})
	for key: Variant in by_channel:
		var found: Dictionary = by_channel[key]
		var definition: SignalDefinition = found.get("definition")
		if definition == null:
			continue
		var details: Dictionary = (definition.details as Dictionary).duplicate()
		# The measured strength and the count are added to whatever the definition
		# declared. They go in last so a measurement always wins over a description
		# that happened to use the same key.
		details["Strength"] = "%d%%" % roundi(float(found.get("strength", 0.0)) * 100.0)
		var count := int(found.get("count", 0))
		if count > 1:
			details["Heard"] = "%d times" % count
		rows.append({
			"id": definition.id,
			"display_name": definition.display_name,
			"signal_type": definition.signal_type,
			"icon": definition.icon,
			"description": definition.description,
			"details": details,
			"count": count,
		})
	return rows


## Catalogue entries available on [param channel]. Empty for an unknown channel, and for
## a channel whose signals have no [member SignalDefinition.channel] set.
func signals_for(channel: StringName) -> Array[SignalDefinition]:
	var result: Array[SignalDefinition] = []
	for entry in signals:
		if entry != null and entry.channel == channel:
			result.append(entry)
	return result


## Every channel as {id, label, caption, found, total}, which is what the signals menu
## builds its tabs from, so adding a channel here is all it takes to get a tab.
func channel_tabs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in channels:
		var id := StringName(entry.get("id", &""))
		result.append({
			"id": id,
			"label": str(entry.get("label", "")),
			"caption": str(entry.get("caption", "")),
			"found": findings_for(id).size(),
			"total": signals_for(id).size(),
		})
	return result


## Forgets everything heard on [param channel], or on every channel when left empty.
## Findings are not part of the save, so this is also how a new game starts clean.
func clear_findings(channel: StringName = &"") -> void:
	if channel.is_empty():
		_found.clear()
	else:
		_found.erase(channel)
	signals_changed.emit()


# --- Reading the channel table -----------------------------------------------

## The field an entry names, read as a number. 0 for a name that is absent or holds
## something non-numeric, so a renamed field quietly disables that channel rather than
## raising every frame.
func _number(entry: Dictionary, key: String) -> float:
	var value: Variant = get(str(entry.get(key, "")))
	return float(value) if (value is float or value is int) else 0.0


func _set_number(entry: Dictionary, key: String, value: float) -> void:
	var field := str(entry.get(key, ""))
	if not field.is_empty():
		set(field, value)


func _flag(entry: Dictionary, key: String) -> bool:
	var value: Variant = get(str(entry.get(key, "")))
	return value is bool and value
