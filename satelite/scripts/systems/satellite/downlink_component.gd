class_name SatelliteDownlink
extends Node
## The satellite's downlink: what it has, and what it can send back to Earth.
##
## Owns the catalogue of [DataPacketDefinition]s and how many times each has been
## transmitted. Rows are handed to the UI already resolved - [method catalogue]
## carries the reason a packet cannot be sent right now - so the menu never has to
## ask a question per row, exactly like [SatelliteParts].
##
## An empty catalogue is a valid state, not an error: the menu shows its empty
## message and the send button stays dead. This is the state the satellite ships in,
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

## Packets this satellite can send.
@export var packets: Array[DataPacketDefinition] = []

## Stat credited with [member DataPacketDefinition.size] on every transmission. Left
## empty, sending moves no stat at all, which is the honest default while there is
## nothing to count. Set it to [code]&"data_sent"[/code] and the readout picks up a
## total with no UI change.
@export var data_stat: StringName = SatelliteStats.DATA_SENT

## Set by [Satellite] so a transmission can be written into the stat block.
var _stats: SatelliteStats = null

## Transmissions per packet id, so a count survives closing and reopening the menu.
var _sent: Dictionary = {}


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

## Transmits [param packet_id] once. Returns false when the packet is unknown or may
## not be sent again, which is the same answer as [method can_send] and the reason
## the menu reports rather than a second rule.
func transmit(packet_id: StringName) -> bool:
	var packet := _packet_of(packet_id)
	if packet == null or not can_send(packet_id):
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