class_name SatelliteDownlink
extends Node
## The satellite's downlink: what it has, and what it can send back to Earth.
##
## Owns the catalogue of [DataPacketDefinition]s and how many times each has been
## transmitted. Rows are handed to the UI already resolved - [method catalogue]
## carries the reason a packet cannot be sent right now - so the menu never has to
## ask a question per row, exactly like [SatelliteParts].
##
## Signals accepted in the signals menu are held here too, one entry per accepted
## hearing. A signal is sent the same way a packet is, with one difference: it
## takes time. The seconds a send takes grow with the distance to Earth and
## shrink with the satellite's power, so a far, tired satellite waits longer for
## its points than a close, charged one. The points arrive when the transmission
## lands, not when it starts, and a signal that has been sent is spent: there is
## no second of it.
##
## An empty catalogue is a valid state, not an error: the menu shows its empty
## message and the send button is dead. This is the state the satellite ships in,
## because the collectors that produce data are not written yet. Adding a
## [DataPacketDefinition] is all it takes to fill the list.
##
## [b]Collection is not this module's job.[/b] It only remembers what has been sent.
## When a collector is added later it can gate a packet from here without this
## module or the menu changing.

signal data_transmitted(packet: Resource, sent_count: int)
signal downlink_changed()

## Unit [member DataPacketDefinition.size] is counted in, used by the menu to label
## sizes. A const rather than an export because the number means nothing without the
## satellites agreeing on what it means; change both together or not at all.
const SIZE_UNIT := "Mb"

## Unit a signal's [member SignalDefinition.points] are counted in.
const POINTS_UNIT := "pts"

## A queued signal's state: waiting to be sent.
const SIGNAL_QUEUED := 0
## A queued signal's state: its transmission is under way.
const SIGNAL_SENDING := 1
## A queued signal's state: sent, and there is no second of it.
const SIGNAL_SENT := 2

## Packets this satellite can send.
@export var packets: Array[DataPacketDefinition] = []

## Seconds a send takes at zero distance and zero power. The
## distance and power below scale it from there.
@export var base_send_seconds: float = 10.0

## Distance in kilometres that doubles a send's time on its own.
## The further from Earth, the longer a signal takes to arrive.
@export var distance_per_double: float = 50000.0

## Power that halves a send's time on its own. The more power the
## satellite has, the shorter a signal takes to arrive.
@export var power_per_halve: float = 20.0

## Stat credited with [member DataPacketDefinition.size] on every transmission. Left
## empty, sending moves no stat at all, which is the honest default while there is
## nothing to count. Set it to [code]&"data_sent"[/code] and the readout picks up a
## total with no UI change.
@export var data_stat: StringName = SatelliteStats.DATA_SENT

## Set by [Satellite] so a transmission can be written into the stat block.
var _stats: SatelliteStats = null

## Transmissions per packet id, so a count survives closing and reopening the menu.
var _sent: Dictionary = {}

## Signals accepted in the signals menu, one entry per accepted hearing:
## {signal, key, state, progress, duration}. A send runs in [method _process],
## so it pauses with the game like everything else does.
var _signal_queue: Array[Dictionary] = []
## Counter for queue keys, so two accepted hearings of the same
## signal still have entries of their own.
var _next_signal: int = 1


## Connects the stat block this module writes to. [Satellite] does this for you.
func bind(stats: SatelliteStats) -> void:
	_stats = stats


# --- Queries ----------------------------------------------------------------

## Every packet, with its size, its send count and the reason a send button would be
## dead. This is what the downlink menu renders.
func catalogue() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for packet in packets:
		if packet == null:
			continue
		var sent := sent_count(packet.id)
		var reason := _rejection(packet)
		result.append({
			"packet": packet,
			"id": packet.id,
			"display_name": packet.display_name,
			"description": packet.description,
			"icon": packet.icon,
			"category": packet.category,
			"size": packet.size,
			"unit": SIZE_UNIT,
		"sent": sent,
		"sent_label": packet.sent_label(sent),
		"can_send": reason == &"",
		"reason": reason,
	})
	for entry: Variant in _signal_queue:
		var sig: Dictionary = entry
		var definition: SignalDefinition = sig.get("signal") as SignalDefinition
		if definition == null:
			continue
		var state := int(sig.get("state", SIGNAL_QUEUED))
		var reason := _signal_reason(state)
		result.append({
			"kind": &"signal",
			"signal": definition,
			"id": StringName(sig.get("key", &"")),
			"display_name": definition.display_name,
			"description": definition.description,
			"icon": definition.icon,
			"category": str(definition.signal_type),
			"size": definition.points,
			"unit": POINTS_UNIT,
			"sent": 0,
			"sent_label": _signal_state_label(sig),
			"can_send": reason == &"",
			"reason": reason,
		})
	return result


## How many times [param packet_id] has been transmitted. Unknown ids count as 0.
func sent_count(packet_id: StringName) -> int:
	return int(_sent.get(packet_id, 0))


func can_send(packet_id: StringName) -> bool:
	var packet := _packet_of(packet_id)
	return packet != null and _rejection(packet) == &""


## Transmissions made across every packet. The headline number in the menu.
func total_transmissions() -> int:
	var result := 0
	for key: Variant in _sent:
		result += int(_sent[key])
	return result


## Data volume sent across every packet, in [constant SIZE_UNIT]. Counts each packet
## its size times how often it went down.
func total_volume() -> int:
	var result := 0
	for key: Variant in _sent:
		var packet := _packet_of(StringName(key))
		if packet != null:
			result += packet.size * int(_sent[key])
	return result


## Both totals in one call, because the menu shows them together and the hub should
## not have to be asked twice for one label.
func totals() -> Dictionary:
	return {
		"transmissions": total_transmissions(),
		"volume": total_volume(),
		"unit": SIZE_UNIT,
	}


# --- Actions ----------------------------------------------------------------

## Sends [param id] down. For a queued signal this starts the timed
## transmission - the sending begins here, the points arrive when it
## lands; for a packet it goes down at once, as before. Returns false
## when the id is unknown or may not be sent right now, which is the
## same answer as [method can_send] and the reason the menu reports
## rather than a second rule.
func transmit(id: StringName) -> bool:
	if _transmit_signal(id):
		return true
	var packet := _packet_of(id)
	if packet == null or not can_send(id):
		return false
	var sent := sent_count(packet.id) + 1
	_sent[packet.id] = sent
	_apply(packet)
	data_transmitted.emit(packet, sent)
	downlink_changed.emit()
	return true


func _apply(packet: DataPacketDefinition) -> void:
	if _stats == null:
		return
	if not data_stat.is_empty() and packet.size != 0:
		_stats.add_stat(data_stat, float(packet.size))
	if not packet.stat_effects.is_empty():
		_stats.apply_effects(packet.stat_effects, 1)


## Why this packet cannot be sent, as an id the menu turns into a sentence.
func _rejection(packet: DataPacketDefinition) -> StringName:
	if packet.is_exhausted(sent_count(packet.id)):
		return &"exhausted"
	return &""


func _packet_of(packet_id: StringName) -> DataPacketDefinition:
	if packet_id.is_empty():
		return null
	for packet in packets:
		if packet != null and packet.id == packet_id:
			return packet
	return null


# --- Accepted signals -------------------------------------------------------

## Takes [param sig] from the signals menu, as one entry of
## its own: two accepted hearings of the same signal are two
## entries, because each is sent and paid for on its own.
func queue_signal(sig: Resource) -> bool:
	if sig == null or StringName(str(sig.get(&"id"))).is_empty():
		return false
	_signal_queue.append({
		"signal": sig,
		"key": _queue_key(),
		"state": SIGNAL_QUEUED,
		"progress": 0.0,
		"duration": 0.0,
	})
	downlink_changed.emit()
	return true


## Advances the sends under way. Points are written when a
## transmission lands, not when it starts, which is the whole
## point of a send that takes time.
func _process(delta: float) -> void:
	var ticked := false
	for entry: Variant in _signal_queue:
		var sig: Dictionary = entry
		if int(sig.get("state", SIGNAL_QUEUED)) != SIGNAL_SENDING:
			continue
		var duration := float(sig.get("duration", 0.0))
		var before := int(duration - float(sig.get("progress", 0.0)))
		sig["progress"] = float(sig.get("progress", 0.0)) + delta
		var after := int(duration - float(sig.get("progress", 0.0)))
		if after != before:
			ticked = true
		if float(sig.get("progress", 0.0)) >= duration:
			_deliver(sig)
			ticked = true
	if ticked:
		downlink_changed.emit()


## Starts the send of the queued signal [param key], which
## is the only way a queued signal leaves the queue: the
## seconds it takes come from [method _send_duration].
func _transmit_signal(key: StringName) -> bool:
	var sig := _signal_entry(key)
	if sig.is_empty() or int(sig.get("state", SIGNAL_SENT)) != SIGNAL_QUEUED:
		return false
	sig["state"] = SIGNAL_SENDING
	sig["progress"] = 0.0
	sig["duration"] = _send_duration()
	downlink_changed.emit()
	return true


## How many seconds a send takes right now. The distance to
## Earth stretches the time and the satellite's power shortens
## it: every [member distance_per_double] kilometres of distance
## double it, every [member power_per_halve] power halve it.
func _send_duration() -> float:
	var distance := 0.0
	var power := 0.0
	if _stats != null:
		distance = float(_stats.get_stat(SatelliteStats.DISTANCE_FROM_EARTH, 0.0))
		power = float(_stats.get_stat(&"power", 0.0))
	return base_send_seconds * (1.0 + distance / distance_per_double) \
		/ (1.0 + power / power_per_halve)


## Lands a finished transmission: the points are paid out, the
## signal is spent, and the hub and the log hear about it.
func _deliver(sig: Dictionary) -> void:
	sig["state"] = SIGNAL_SENT
	sig["progress"] = float(sig.get("duration", 0.0))
	var definition: SignalDefinition = sig.get("signal") as SignalDefinition
	if definition == null:
		return
	var points := definition.points
	if _stats != null and points > 0:
		_stats.add_stat(SatelliteStats.CREDITS, float(points))
	data_transmitted.emit(definition, 1)


func _signal_entry(key: StringName) -> Dictionary:
	for entry: Variant in _signal_queue:
		var sig: Dictionary = entry
		if StringName(sig.get("key", &"")) == key:
			return sig
	return {}


func _queue_key() -> StringName:
	var key := StringName("signal-%d" % _next_signal)
	_next_signal += 1
	return key


## Why a queued signal cannot be sent, as an id the menu turns
## into a sentence.
func _signal_reason(state: int) -> StringName:
	match state:
		SIGNAL_SENDING:
			return &"sending"
		SIGNAL_SENT:
			return &"sent"
	return &""


func _signal_state_label(sig: Dictionary) -> String:
	match int(sig.get("state", SIGNAL_QUEUED)):
		SIGNAL_SENDING:
			var remaining := int(float(sig.get("duration", 0.0)) - float(sig.get("progress", 0.0)))
			return "SENDING %ds" % maxi(remaining, 0)
		SIGNAL_SENT:
			return "SENT"
	return "QUEUED"


# --- Persistence ------------------------------------------------------------

## Send counts only. The catalogue is part of the scene, not the save, so a save
## never has to be kept in step with the packet list.
func sent_snapshot() -> Dictionary:
	return _sent.duplicate()


func restore_sent(values: Dictionary) -> void:
	_sent = {}
	for key: Variant in values:
		_sent[StringName(key)] = int(values[key])
	downlink_changed.emit()


## The accepted signals as {signal: id, state: state}, one
## entry per hearing. Definitions live in the scene, so a save
## names them and [method restore_queue] puts them back
## together with the catalogue. A signal that has been sent
## is spent, so it is left out: there is no second of it.
func signal_snapshot() -> Array:
	var result: Array = []
	for entry: Variant in _signal_queue:
		var sig: Dictionary = entry
		if int(sig.get("state", SIGNAL_QUEUED)) == SIGNAL_SENT:
			continue
		var definition: SignalDefinition = sig.get("signal") as SignalDefinition
		if definition == null:
			continue
		result.append({
			"signal": StringName(definition.id),
			"state": int(sig.get("state", SIGNAL_QUEUED)),
		})
	return result


## Puts back what [method signal_snapshot] produced, with the
## definitions already resolved against the control panel's
## catalogue. A send that was still under way comes back
## waiting: it never landed, so there is nothing to resume
## and nothing to pay out - the player sends it again.
func restore_queue(entries: Array) -> void:
	_signal_queue = []
	for entry: Variant in entries:
		var saved: Dictionary = entry
		var definition: SignalDefinition = saved.get("signal") as SignalDefinition
		if definition == null:
			continue
		_signal_queue.append({
			"signal": definition,
			"key": _queue_key(),
			"state": SIGNAL_QUEUED,
			"progress": 0.0,
			"duration": 0.0,
		})
	downlink_changed.emit()