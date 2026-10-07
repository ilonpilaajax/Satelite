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
## poll. [param count] is the hearing's own count, which is one: findings
## do not stack, so every hearing files a row of its own.
signal signal_found(channel: StringName, found: Resource, count: int)
## One finding was accepted in the signals menu. Whoever listens hands
## the signal to the downlink, which is where a signal is sent from.
signal signal_accepted(channel: StringName, found: Resource)
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

## Strength added to every channel per level of the antenna strength upgrade.
const STRENGTH_PER_LEVEL := 5

## Signals this panel is able to detect. Anything here whose [member
## SignalDefinition.channel] matches a channel can turn up on it. An empty catalogue is
## valid: nothing is ever found, and the signals menu shows its empty message.
@export var signals: Array[SignalDefinition] = []

# Satelite

# Upgrades. How many times each has been bought, pushed in from the upgrades block by
# [method set_upgrade_levels]. These are counts, not numbers the panel computes: the upgrades
# module owns what a level means and this only remembers it, so the same level count drives
# the listening numbers below and whatever else reads it.
var solar_panel_level: int = 0
var antenna_strength_level: int = 0
var antenna_focus_level: int = 0
var antenna_uptime_level: int = 0

# Radio
var detecting_radio_signals:bool = true
var anten_ammount_radio:int = 0
var anten_strenght_radio:int = 20
var timer_radio:float
var search_range_radio:float = 4.0

# Radiation
var detecting_radiation_level:bool = true
var anten_ammount_radiation:int = 0
var anten_strenght_radiation:int = 15
var timer_radiation:float
var search_range_radiation:float = 80.0

# Light
var detecting_light:bool = true
var anten_ammount_light:int = 0
var anten_strenght_light:int = 25
var timer_light:float
var search_range_light:float = 120.0

# Particles
var detecting_particles:bool = true
var anten_ammount_particles:int = 0
var anten_strenght_particles:int = 10
var timer_particles:float
var search_range_particles:float = 60.0

# --- Antennas ---------------------------------------------------------------

## Antenna counts per channel, as {channel: count}. Fitted hardware writes this through
## [method set_antenna_counts]; nothing else keeps it up to date, because the mounts are the
## only place that knows what is on the satellite.
var _antenna_counts: Dictionary = {}

## Upgrade levels as {upgrade_id: level}, the same block the upgrades block was given.
var _upgrade_levels: Dictionary = {}

## What has been heard, keyed by channel: an Array with one entry per
## hearing. Findings do not stack - the same signal heard twice is two
## entries, because each hearing is accepted and sent on its own. Each
## entry is {definition, strength, key, accepted}, where key names that
## one hearing so a row can be pointed at even when two hearings are
## the same signal.
var _found: Dictionary = {}
## Counter for finding keys, so every hearing has a name of its own.
var _next_finding: int = 1


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


## The base strength every channel listens at. One number rather than one per
## channel, which is what a single strength setting for the satellite reads
## as. The channels started life with different strengths, so this is the
## radio one until something gives them all the same.
func antenna_strength() -> int:
	return anten_strenght_radio


## The base strength [param channel] listens at, before the strength
## upgrade. What the config menu shows for that one antenna.
func antenna_strength_of(channel: StringName) -> int:
	match channel:
		&"radio": return anten_strenght_radio
		&"radiation": return anten_strenght_radiation
		&"light": return anten_strenght_light
		&"particles": return anten_strenght_particles
	return 0


## How wide [param channel]'s listen is, before the focus upgrade. What
## the config menu shows for that one antenna.
func antenna_range_of(channel: StringName) -> float:
	match channel:
		&"radio": return search_range_radio
		&"radiation": return search_range_radiation
		&"light": return search_range_light
		&"particles": return search_range_particles
	return 0.0


## The configuration of the antennas on [param channel]: what type they are,
## how many are fitted, the base strength they listen at and how wide a listen
## is. One dictionary per antenna, which is what the config menu shows.
func antenna_config(channel: StringName) -> Dictionary:
	return {
		"type": str(channel),
		"count": antenna_count_of(channel),
		"strength": antenna_strength_of(channel),
		"range": antenna_range_of(channel),
	}


## Every channel's antenna configuration, as {channel: config}. Built from
## [constant CHANNEL_BY_ID] rather than the [member channels] export, because
## these are the channels the panel can actually hear on.
func antenna_configs() -> Dictionary:
	var result: Dictionary = {}
	for channel: StringName in CHANNEL_BY_ID:
		result[channel] = antenna_config(channel)
	return result


## Records how many levels each upgrade has been bought, as {upgrade_id: level}. The same
## shape the upgrades block reports, so the panel is handed its own data rather than reaching
## into the upgrades module.
##
## The four fields above are written from this, so the panel and its per-upgrade counts cannot
## disagree. An id with no field of its own is still kept, so an upgrade this panel does not
## know about yet is not lost.
func set_upgrade_levels(levels: Dictionary) -> void:
	_upgrade_levels = levels.duplicate()
	solar_panel_level = maxi(int(_upgrade_levels.get(&"solar_panels", 0)), 0)
	antenna_strength_level = maxi(int(_upgrade_levels.get(&"antenna_strength", 0)), 0)
	antenna_focus_level = maxi(int(_upgrade_levels.get(&"antenna_focus", 0)), 0)
	antenna_uptime_level = maxi(int(_upgrade_levels.get(&"antenna_uptime", 0)), 0)


## How many levels of [param upgrade_id] have been bought, or 0.
func upgrade_level_of(upgrade_id: StringName) -> int:
	return maxi(int(_upgrade_levels.get(upgrade_id, 0)), 0)


## Every upgrade level the panel knows about, as {upgrade_id: level}.
func upgrade_levels() -> Dictionary:
	return _upgrade_levels.duplicate()


## How much stronger each channel hears, as its base strength plus the antenna strength
## upgrade. One place, so every channel is upgraded the same way and a level bought once
## counts for all of them.
func _strength_of(channel: StringName) -> int:
	var base := 0
	match channel:
		&"radio": base = anten_strenght_radio
		&"radiation": base = anten_strenght_radiation
		&"light": base = anten_strenght_light
		&"particles": base = anten_strenght_particles
	return base + antenna_strength_level * STRENGTH_PER_LEVEL


## How wide a channel's listen is: its base range divided by the antenna focus upgrade, so
## each focus level narrows the window and makes a find likelier. Never below 1, because a
## window of zero would make the roll a certainty rather than a search.
func _window_of(channel: StringName) -> int:
	var base := 0.0
	match channel:
		&"radio": base = search_range_radio
		&"radiation": base = search_range_radiation
		&"light": base = search_range_light
		&"particles": base = search_range_particles
	return maxi(int(round(base / float(1 + antenna_focus_level))), 1)


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
## buying it does nothing here. Called without an argument it is a no-op rather than
## an error, which keeps a bare call from anywhere harmless.
func detect_new_anten(part: Resource = null) -> void:
	var channel := _channel_of(part)
	if channel.is_empty() or not _is_listening(channel):
		return
	# The antenna that was just bought hears on this sweep even before it is
	# fitted anywhere, which is why it counts itself in.
	_listen(channel, 1)


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
		_listen(&"radio")

func run_radiation(delta):
	timer_radiation -= delta
	if timer_radiation <= 0:
		timer_radiation = randi_range(2,8)
		_listen(&"radiation")

func run_light(delta):
	timer_light -= delta
	if timer_light <= 0:
		timer_light = randi_range(2,8)
		_listen(&"light")

func run_particles(delta):
	timer_particles -= delta
	if timer_particles <= 0:
		timer_particles = randi_range(2,8)
		_listen(&"particles")


## One listen on [param channel]: roll once across the channel's window and file a
## finding when the roll comes in at or below its strength, so the chance of hearing
## something is strength over window. Both come from the base fields plus the antenna
## upgrades, which is what makes buying those upgrades change what the satellite hears.
##
## Every antenna fitted on the channel is another chance to find something, so its
## count multiplies the strength. A channel with no antenna - and none that just
## bought its way in - hears nothing at all and files nothing.
##
## [param extra] counts antennas that are not fitted yet but should still hear this
## once, which is the antenna that was just bought.
##
## One function for every channel rather than a copy per channel, so the four channels cannot
## drift apart - which they had: radiation rolled against its strength and light and particles
## had neither a strength nor a window at all.
func _listen(channel: StringName, extra: int = 0) -> void:
	var index := CHANNEL_BY_ID.find(channel)
	if index < 0:
		return
	var antennas := antenna_count_of(channel) + extra
	if antennas <= 0:
		return
	# randi_range takes whole numbers, so the window is cast here. Without it this raised
	# every call and the channel never detected anything.
	if randi_range(0, _window_of(channel)) <= _strength_of(channel) * antennas:
		detect_new_signal(index)


## Records a detection on the channel [param id] refers to. The id cases are the ones
## this always had; what each does now is file a finding rather than nothing.
func detect_new_signal(id:int):
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


## Files one hearing of a signal drawn from [param channel]'s own
## catalogue, at a random strength. The roll is per hearing, so the
## same signal can come up again on the next one - it arrives as a
## finding of its own rather than as a bigger number on the one
## already filed.
func _record(channel: StringName) -> void:
	var options := signals_for(channel)
	if options.is_empty():
		return
	var definition: SignalDefinition = options[randi() % options.size()]
	var findings: Array = _found.get(channel, [])
	if findings == null:
		findings = []
	findings.append({
		"definition": definition,
		"strength": randf(),
		"key": _finding_key(),
		"accepted": false,
	})
	_found[channel] = findings
	signal_found.emit(channel, definition, 1)


## A name no hearing has had yet, so a row can be pointed at -
## accepted, sent - without comparing signal types, which two
## hearings may well share.
func _finding_key() -> StringName:
	var key := StringName("finding-%d" % _next_finding)
	_next_finding += 1
	return key


## What has been heard on [param channel], one row per hearing, already
## carrying everything a list needs to render: id, name, type, icon,
## description, the signal's own details, the measured strength, and the
## hearing's key and accepted state. One hearing is one row, even when
## it is the same signal as the row above it, because each is accepted
## on its own.
func findings_for(channel: StringName) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var findings: Array = _found.get(channel, [])
	if findings == null:
		return rows
	for entry: Variant in findings:
		var finding: Dictionary = entry
		var definition: SignalDefinition = finding.get("definition")
		if definition == null:
			continue
		var details: Dictionary = (definition.details as Dictionary).duplicate()
		# The measured strength goes in last, so a measurement always wins
		# over a description that happened to use the same key.
		details["Strength"] = "%d%%" % roundi(float(finding.get("strength", 0.0)) * 100.0)
		rows.append({
			"id": definition.id,
			"display_name": definition.display_name,
			"signal_type": definition.signal_type,
			"icon": definition.icon,
			"description": definition.description,
			"details": details,
			"key": StringName(finding.get("key", &"")),
			"accepted": bool(finding.get("accepted", false)),
		})
	return rows


## Marks the hearing [param key] filed on [param channel] as accepted,
## which announces it through [code]signal_accepted[/code] so it can go
## to the downlink. False when there is no such hearing, or it has been
## accepted already: one hearing is accepted once.
func accept_finding(channel: StringName, key: StringName) -> bool:
	var findings: Array = _found.get(channel, [])
	if findings == null:
		return false
	for entry: Variant in findings:
		var finding: Dictionary = entry
		if StringName(finding.get("key", &"")) != key:
			continue
		if bool(finding.get("accepted", false)):
			return false
		finding["accepted"] = true
		var definition: SignalDefinition = finding.get("definition")
		signal_accepted.emit(channel, definition)
		signals_changed.emit()
		return true
	return false


## Catalogue entries available on [param channel]. Empty for an unknown channel, and for
## a channel whose signals have no [member SignalDefinition.channel] set.
func signals_for(channel: StringName) -> Array[SignalDefinition]:
	var result: Array[SignalDefinition] = []
	for entry in signals:
		if entry != null and entry.channel == channel:
			result.append(entry)
	return result


## The catalogue entry with this id, or null. A save names the signals
## the downlink is holding by id, and this is how a loaded queue
## becomes the definitions again.
func signal_of(signal_id: StringName) -> SignalDefinition:
	for entry in signals:
		if entry != null and entry.id == signal_id:
			return entry
	return null


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
## Findings are not part of the save, so this is also how a new game starts clean:
## nothing carried over, because a new game hears everything for the first time.
func clear_findings(channel: StringName = &"") -> void:
	if channel.is_empty():
		_found.clear()
		_next_finding = 1
	else:
		_found[channel] = []
	signals_changed.emit()
