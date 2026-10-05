extends Node
## The satellite's instrument panel: what its antennas are picking up.
##
## The four [code]run_*[/code] functions below are the detection loop: each counts its
## own channel off, and on a hit calls [method detect_new_signal] with that channel's
## id. That is where a [b]signal is found[/b] - it picks one of the catalogue's
## [SignalDefinition]s for the channel and files it, and the signals menu lists the
## findings.
##
## [member channels] exists only so the signals menu knows what to put in its tabs; the
## detection itself reads the fields on this node directly, so adding a channel is a
## [code]run_*[/code] function, four fields and one [member channels] entry.
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

## Emitted whenever a signal is heard, so the menu listing findings does not have to
## poll. [param count] is how many times in total.
signal signal_found(channel: StringName, found: Resource, count: int)
## Emitted when findings are cleared.
signal signals_changed()
## Emitted when the antenna counts change, carrying {channel: count}. A part fitted to a
## mount is one antenna, so mounting hardware changes what the panel is listening with.
signal antenna_counts_changed(counts: Dictionary)

## The channels this panel listens on, in tab order. Presentation only - the signals
## menu builds its tabs from this, and nothing here reads it, so a channel appearing on
## screen is a one-entry change.
@export var channels: Array[Dictionary] = [
	{"id": &"radio", "label": "Radio", "caption": "RADIO SIGNALS"},
	{"id": &"radiation", "label": "Radiation", "caption": "RADIATION LEVEL"},
	{"id": &"light", "label": "Light", "caption": "LIGHT"},
	{"id": &"particles", "label": "Particles", "caption": "PARTICLES"},
]

## Which channel each id passed to [method detect_new_signal] refers to, in the order
## the [code]run_*[/code] functions pass them: radio 0, radiation 1, light 2,
## particles 3. Kept next to those calls so the numbers stay traceable.
const CHANNEL_BY_ID: Array[StringName] = [&"radio", &"radiation", &"light", &"particles"]

## Signals this panel is able to detect. Anything here whose [member
## SignalDefinition.channel] matches a channel can turn up on it. An empty catalogue is
## valid: nothing is ever found, and the signals menu shows its empty message.
@export var signals: Array[SignalDefinition] = []

# Satelite

# Solar Panels
var solar_panel_level:int


# Radio
var detecting_radio_signals:bool = true
var anten_ammount_radio:int = 0
var anten_strenght_radio:int = 3
var timer_radio:float
var search_range_radio:float = 3

# Radiation
var detecting_radiation_level:bool = true
var anten_ammount_radiation:int = 0
var anten_strenght_radiation:int
var timer_radiation:float
var search_range_radiation:float

# Light
var detecting_light:bool = true
var anten_ammount_light:int = 0
var anten_strenght_light:int
var timer_light:float
var search_range_light:float

# Particles
var detecting_particles:bool = true
var anten_ammount_particles:int = 0
var anten_strenght_particles:int
var timer_particles:float
var search_range_particles:float

# --- Antennas ---------------------------------------------------------------

## Antenna counts per channel, as {channel: count}. Fitted hardware writes this through
## [method set_antenna_counts]; nothing else keeps it up to date, because the mounts are the
## only place that knows what is on the satellite.
var _antenna_counts: Dictionary = {}

## Findings, keyed by channel then by signal id, so a signal heard again is counted
## rather than listed twice. Each entry is {definition, count, strength}.
var _found: Dictionary = {}


## Takes the antenna counts off the satellite's mounts. [param counts] is {channel: count},
## counting each fitted part once per mount it is fitted to, which is what makes a second
## copy of an antenna a second antenna rather than the same one twice.
##
## Channels absent from [param counts] go to zero rather than being left as they were: a
## channel whose last antenna was replaced is no longer being listened to, and keeping the
## old number would report hardware that is not there. The per-channel fields above and
## [method antenna_counts] are both written here, so they cannot disagree.
func set_antenna_counts(counts: Dictionary) -> void:
	var next: Dictionary = {}
	for channel: StringName in CHANNEL_BY_ID:
		var count := maxi(int(counts.get(channel, 0)), 0)
		next[channel] = count
		_set_channel_count(channel, count)
	# A channel this panel does not keep a field for still counts, so a new kind of
	# antenna is readable without adding a field for it first.
	for channel: Variant in counts:
		var id := StringName(channel)
		if id.is_empty() or next.has(id):
			continue
		next[id] = maxi(int(counts[channel]), 0)
	if next == _antenna_counts:
		return
	_antenna_counts = next
	antenna_counts_changed.emit(next)


## How many antennas are fitted on [param channel], or 0.
func antenna_count_of(channel: StringName) -> int:
	return int(_antenna_counts.get(channel, 0))


## Every channel's antenna count, as {channel: count}.
func antenna_counts() -> Dictionary:
	return _antenna_counts.duplicate()


## Writes one count to whichever field the panel keeps for that channel. Matched by channel
## rather than written by id, so adding a channel is a field and an entry in
## [constant CHANNEL_BY_ID] and nothing else.
func _set_channel_count(channel: StringName, count: int) -> void:
	match channel:
		&"radio": anten_ammount_radio = count
		&"radiation": anten_ammount_radiation = count
		&"light": anten_ammount_light = count
		&"particles": anten_ammount_particles = count


func _ready():
	pass

## A newly bought antenna does not wait for the next scheduled listen: it sweeps as soon as
## it is bought, and whatever it hears is filed on its channel like any other finding.
##
## [param part] is the antenna that was bought. Anything without an
## [member PartDefinition.antenna_channel] - solar panels, say - is not an antenna, so
## buying it does nothing here. Called without an argument it is a no-op rather than an
## error, which keeps a bare call from anywhere harmless.
func detect_new_anten(part: Resource = null) -> void:
	var channel := _channel_of(part)
	if channel.is_empty() or not _is_listening(channel):
		return
	_record(channel)


## Which channel [param part] listens on, or empty when it is null or carries no channel.
## Read off the part rather than typed, so the panel keeps working with any resource the
## shop can sell and does not have to import the parts catalogue.
func _channel_of(part: Resource) -> StringName:
	if part == null:
		return &""
	var channel: Variant = part.get(&"antenna_channel")
	return StringName(channel) if channel != null else &""


## Whether [param channel] is switched on, read from the same field its [code]run_*[/code]
## function checks, so a fresh antenna obeys a muted channel exactly as a scheduled listen
## does.
func _is_listening(channel: StringName) -> bool:
	match channel:
		&"radio": return detecting_radio_signals
		&"radiation": return detecting_radiation_level
		&"light": return detecting_light
		&"particles": return detecting_particles
	return false

func _process(delta: float) -> void:
	if detecting_radio_signals:run_radio(delta)
	if detecting_radiation_level:run_radiation(delta)
	if detecting_light:run_light(delta)
	if detecting_particles:run_particles(delta)

func run_radio(delta):
	timer_radio -= delta
	if timer_radio <= 0:
		timer_radio = randi_range(2,8)
		# randi_range takes whole numbers, so the float range is cast here. Without it
		# this raised every call and the channel never detected anything.
		var random_value = randi_range(0, int(search_range_radio))
		if random_value <= anten_strenght_radio:detect_new_signal(0)

func run_radiation(delta):
	timer_radiation -= delta
	if timer_radiation <= 0:
		timer_radiation = randi_range(2,8)
		var random_value = randi_range(0, int(anten_strenght_radiation))
		if random_value <= anten_strenght_radiation:detect_new_signal(1)

func run_light(delta):
	timer_light -= delta
	if timer_light <= 0:
		timer_light = randi_range(2,8)
		var random_value = randi_range(0, int(search_range_light))
		if random_value <= anten_strenght_light:detect_new_signal(2)

func run_particles(delta):
	timer_particles -= delta
	if timer_particles <= 0:
		timer_particles = randi_range(2,8)
		var random_value = randi_range(0, int(search_range_particles))
		if random_value <= anten_strenght_particles:detect_new_signal(3)


## Records a detection on the channel [param id] refers to. The id cases are the ones
## this always had; what each does now is file a finding rather than nothing.
func detect_new_signal(id:int):
	print("detected", id)
	match id:
		0:
			_record(&"radio")
		1:
			_record(&"radiation")
		2:
			_record(&"light")
		3:
			_record(&"particles")
		4:
			pass


## Files one of the catalogue's signals for [param channel] as heard, at a random
## strength. Repeat detections of the same signal raise its count instead of adding a
## second row, so a channel that keeps hearing one carrier still lists it once.
func _record(channel: StringName) -> void:
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
func findings_for(channel: StringName) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var by_channel: Dictionary = _found.get(channel, {})
	for key: Variant in by_channel:
		var found: Dictionary = by_channel[key]
		var definition: SignalDefinition = found.get("definition")
		if definition == null:
			continue
		var details: Dictionary = (definition.details as Dictionary).duplicate()
		# The measured strength and the count go in last, so a measurement always wins
		# over a description that happened to use the same key.
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
## builds its tabs from.
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
