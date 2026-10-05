class_name SatelliteSlots
extends Node
## Where fitted parts sit on the satellite, and what is sitting in them.
##
## A part is bought and then fitted. Buying does not decide where it goes: the player picks
## one of the [member slot_count] mounts, which is what decides the spot on the body it
## appears in. Fitting into an occupied mount replaces what was there, so the hardware can
## be changed at any time rather than being fixed at purchase.
##
## [b]Copies are fitted independently[/b]. A part bought with [member
## PartDefinition.max_owned] above one is one row in the shop and one kind of hardware, but
## each copy bought can be fitted in its own mount: two radio antennas fit in two slots, and
## each one is mounted independently of the other. A mount never holds more copies of a part
## than were bought of it - there is no free copy to fit, so fitting the last one into an
## empty mount moves that copy out of the mount it was in rather than duplicating it.
##
## The mounts themselves are not described here. They are nodes already authored in the
## satellite scene - one [code]Anten-Slot-N[/code] sprite per mount, each one already
## sitting at its own position on the hull - and this module finds them under
## [member mount_root]. So moving a mount is done by moving its node, and adding a mount
## is done by adding another such node and raising [member slot_count].
##
## Replacing does not sell the part it evicts. That part stays bought and simply stops
## being fitted, which keeps "what you own" and "what is on the satellite" separate
## questions: buying is spending credits once, and the mounts are only about where the
## hardware is mounted.
##
## This module owns what is *drawn*. There is no art for a part yet, so a fitted part is
## shown as a coloured shape at its mount, distinct per part so two of them are told apart
## at a glance. [member PartDefinition.slot_texture] takes over the moment there is
## something to show instead.

## Emitted whenever what is fitted, or where, changes. Carries the mount that changed,
## or -1 when the whole arrangement did.
signal slots_changed(slot: int)
## A part has been fitted into [param slot], replacing whatever was there. The replaced
## part is passed back so a caller can put it in an inventory, though nothing needs to yet.
signal part_fitted(part: Resource, slot: int, replaced: Resource)
## [param slot] has been emptied.
signal slot_cleared(slot: int)

## Node the mount sprites are found under, relative to this module.
@export var mount_root: NodePath = ^"../Body/Upper-Module/Satelites"

## How many mounts there are. The satellite has five today; the scene carries a mount node
## per slot, so this only grows when the satellite grows.
@export_range(1, 8, 1) var slot_count: int = 5

## Prefix of the mount nodes under [member mount_root]. Only the first [member slot_count]
## of them are used, so a mount can be authored and left hidden until it is switched on.
@export var mount_prefix: String = "Anten-Slot-"

## Half the width of a fitted part's marker, in body pixels. Fixed rather than scaled to
## the satellite so a mount reads the same size whatever the hull is doing.
@export var marker_size: float = 9.0

## What is fitted to [code]mount_root[/code]: a [PartDefinition] or null, per mount. Read
## [method slots] rather than this - it is the same thing with the reporting the UI wants.
var _fitted: Array = []
## The mount node per slot, in order. Empty where the scene has no such node.
var _mounts: Array[Node2D] = []
## The marker drawn per slot, so re-fitting one does not rebuild the others.
var _markers: Dictionary = {}

var _parts: SatelliteParts = null


func _ready() -> void:
	_discover_mounts()
	_render_all()


# --- Mounts -----------------------------------------------------------------

## Finds the mount nodes and pairs them with empty mounts. Called once on ready, and again
## by [method set_slot_count] when the satellite's slot count changes.
func _discover_mounts() -> void:
	_fitted.clear()
	_mounts.clear()
	var root: Node = get_node_or_null(mount_root)
	if root == null:
		return
	# In name order, so Anten-Slot-10 would sort after Anten-Slot-9 rather than beside
	# Anten-Slot-1. Well past the shipped count, but free to get right.
	var found: Array[Node2D] = []
	for child in root.get_children():
		if child is Node2D and str(child.name).begins_with(mount_prefix):
			found.append(child as Node2D)
	found.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)

	# Markers are freed rather than reused: a mount may have been moved or resized between
	# rediscovers, and a stale marker would keep the old transform.
	for stale: Variant in _markers.values():
		if stale is Node:
			(stale as Node).queue_free()
	_markers.clear()

	for index: int in mini(slot_count, found.size()):
		var mount := found[index]
		_mounts.append(mount)
		_fitted.append(null)

		var marker := Polygon2D.new()
		# Above the hull sprite, which sits at 1, so a part mounted on the near side is not
		# hidden behind it. Relative, so this reads as "two above the mount node" rather than
		# a global ordering that would depend on what else shares the canvas.
		marker.z_index = 2
		marker.visible = false
		# On [member mount_root], not on the mount itself. A mount sprite is scaled up to
		# roughly eighty times to draw a small texture over the hull, and a marker parented
		# to it would inherit that scale and draw hundreds of pixels across - the size is
		# meant to be [member marker_size] in body pixels. The mount root is unscaled, so the
		# marker keeps its own size and still sits under the hull, which is what carries the
		# idle pulse the marker rides along with.
		root.add_child(marker)
		_markers[index] = marker
	_render_all()


## How many mounts this satellite actually has. Never more than [member slot_count], and
## fewer if the scene has not been given that many mount nodes yet.
func available_slots() -> int:
	return _mounts.size()


## Changes how many mounts are in use. Parts fitted past the new count are removed, since a
## mount that does not exist cannot show anything.
func set_slot_count(count: int) -> void:
	slot_count = maxi(count, 1)
	_discover_mounts()
	slots_changed.emit(-1)


# --- Fitting ---------------------------------------------------------------

## Fits [param part_id] into [param slot], replacing whatever was there. Reports whether
## the fit happened; what it replaced is on [signal part_fitted] rather than the return, so
## that fitting into a mount that already holds this part - which replaces nothing - is not
## read as a failure.
##
## Refused when the mount is not one this satellite has, when the part is not in the
## catalogue, or when it is not bought yet. Refusing an unknown part rather than fitting it
## means a part deleted from the game cannot linger on the body after a reload, and refusing
## an unbought one keeps mounting a decision that costs credits.
##
## A copy that has not been fitted yet goes into an empty mount and stays there, so the same
## part can be fitted in as many mounts as were bought. When every copy is already fitted,
## the fit is a move: the copy in the lowest-numbered mount it occupies comes across, which
## is what keeps the number of mounts showing a part equal to the number bought.
func fit(part_id: StringName, slot: int) -> bool:
	if slot < 0 or slot >= _mounts.size():
		return false
	var part := _find(part_id)
	if part == null or not _owns(part_id):
		return false
	var held := _fitted[slot] as PartDefinition
	# Already this part in this mount: nothing to do. Reported as a success so a picker
	# left open over a mount the player already chose does not claim the fit failed.
	if held != null and held.id == part_id:
		return true

	# Where a free copy goes when there is one. An occupied mount is still fair game: the
	# part it held stops being fitted and stays bought, which is the replacement rule.
	var vacated := -1
	if fitted_count_of(part_id) >= owned_count_of(part_id):
		vacated = slot_of(part_id)
		if vacated < 0:
			return false
		_fitted[vacated] = null
		_render(vacated)
		slots_changed.emit(vacated)

	_fitted[slot] = part
	_render(slot)
	part_fitted.emit(part, slot, held)
	slots_changed.emit(slot)
	return true


## Empties [param slot] and returns what was in it, or null. The part is not sold: it goes
## back to being bought but not mounted, which is the same state as a part that has been
## bought and never fitted.
func clear(slot: int) -> PartDefinition:
	if slot < 0 or slot >= _mounts.size():
		return null
	var removed := _fitted[slot] as PartDefinition
	if removed == null:
		return null
	_fitted[slot] = null
	_render(slot)
	slot_cleared.emit(slot)
	slots_changed.emit(slot)
	return removed


## What is fitted to [param slot], or null.
func fitted_at(slot: int) -> PartDefinition:
	if slot < 0 or slot >= _mounts.size():
		return null
	return _fitted[slot] as PartDefinition


func is_occupied(slot: int) -> bool:
	return fitted_at(slot) != null


## Which mount [param part_id] is fitted to, or -1 when it is not fitted anywhere. A part
## bought but not yet mounted reads -1, as does a part that has been replaced.
##
## The lowest-numbered mount, which is one of several when the part is fitted to more than
## one. [method slots_of] is the answer to "where is all of it".
func slot_of(part_id: StringName) -> int:
	for slot: int in _fitted.size():
		var part: PartDefinition = _fitted[slot]
		if part != null and part.id == part_id:
			return slot
	return -1


## Every mount [param part_id] is fitted to, in order. Empty when it is fitted nowhere.
func slots_of(part_id: StringName) -> Array:
	var result: Array = []
	for slot: int in _fitted.size():
		var part: PartDefinition = _fitted[slot]
		if part != null and part.id == part_id:
			result.append(slot)
	return result


## How many mounts hold [param part_id]: how many of the copies bought are actually on the
## satellite. Never more than [method owned_count_of], so this is the count a part's own
## stat effects are already paying for.
func fitted_count_of(part_id: StringName) -> int:
	return slots_of(part_id).size()


## Whether one more copy of [param part_id] could be fitted without moving one that already
## is. What the shop asks to decide between buying a copy and moving an existing one.
func can_fit(part_id: StringName) -> bool:
	return owned_count_of(part_id) > fitted_count_of(part_id)


## How many copies of [param part_id] have been bought. Owned rather than fitted: a copy
## that has been replaced or is still waiting for a mount is still bought.
func owned_count_of(part_id: StringName) -> int:
	return _parts.owned_count(part_id) if _parts != null else 0


## Swaps the contents of two mounts. Refused when either index is not a mount this
## satellite has, which leaves both as they were.
func swap(first: int, second: int) -> bool:
	if first < 0 or second < 0 or first >= _mounts.size() or second >= _mounts.size():
		return false
	if first == second:
		return false
	var held: Variant = _fitted[first]
	_fitted[first] = _fitted[second]
	_fitted[second] = held
	_render(first)
	_render(second)
	slots_changed.emit(first)
	slots_changed.emit(second)
	return true


## One entry per mount, in order, as the UI wants it: whether something is in it, what, the
## position on screen the mount sits at, so a picker can say where each one is, and which
## channel that part serves, so a satellite can add up its antenna counts without asking the
## parts catalogue for each entry again.
func slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot: int in _mounts.size():
		var part: PartDefinition = _fitted[slot]
		result.append({
			"index": slot,
			"occupied": part != null,
			"part_id": part.id if part != null else &"",
			"display_name": part.display_name if part != null else "",
			"antenna_channel": part.antenna_channel if part != null else &"",
			"position": _mounts[slot].position,
		})
	return result


## How many fitted parts serve [param channel], which is how many of that channel the
## satellite can hear: one per mount, because each mount is one piece of hardware.
##
## Read off the mounts rather than off what was bought, so a part that has been replaced is
## not counted and a copy that is bought but not mounted is not counted either.
func antenna_counts() -> Dictionary:
	var result: Dictionary = {}
	for entry: Dictionary in slots():
		if not bool(entry.get("occupied", false)):
			continue
		var channel := StringName(entry.get("antenna_channel", &""))
		if channel.is_empty():
			continue
		result[channel] = int(result.get(channel, 0)) + 1
	return result


# --- Catalogue -------------------------------------------------------------

## Binds the parts block, so a mount can be matched to a real part rather than an id that
## might no longer exist.
func bind(parts: SatelliteParts) -> void:
	if parts == _parts:
		return
	_parts = parts


func _find(part_id: StringName) -> PartDefinition:
	return _parts.find(part_id) if _parts != null else null


func _owns(part_id: StringName) -> bool:
	return _parts != null and _parts.owns(part_id)


# --- Drawing ---------------------------------------------------------------

## Draws one mount from what is fitted to it, or hides the marker when nothing is.
func _render_all() -> void:
	for slot: int in _mounts.size():
		_render(slot)


func _render(slot: int) -> void:
	var marker: Variant = _markers.get(slot)
	if not (marker is Polygon2D):
		return
	var shape := marker as Polygon2D
	# Sat at the mount it stands for rather than parented to it, so moving a mount moves
	# its marker. Done on every render rather than once at discovery, so a mount moved
	# afterwards does not leave its marker behind on the hull.
	if slot < _mounts.size():
		shape.position = _mounts[slot].position
	var part := fitted_at(slot)
	shape.visible = part != null
	if part == null:
		return
	# The shape and colour are derived from the part rather than configured on it, so a new
	# part is distinguishable on the body without anyone having to invent art for it. When
	# slot art exists it replaces this whole step.
	shape.polygon = _marker_polygon(part.id)
	shape.color = _marker_color(part.id)


## Marker outline for a part: three shapes, so two parts are told apart by outline as well as
## by colour and neither cue has to carry it alone.
func _marker_polygon(part_id: StringName) -> PackedVector2Array:
	var size := marker_size
	match _shape_index(part_id):
		0:
			return PackedVector2Array([
				Vector2(-size, -size), Vector2(size, -size), Vector2(size, size), Vector2(-size, size)])
		1:
			# A diamond, a satellite panel read from above.
			return PackedVector2Array([
				Vector2(0, -size), Vector2(size, 0), Vector2(0, size), Vector2(-size, 0)])
		_:
			# An octagon, which is as close to a dish as a polygon gets.
			var points := PackedVector2Array()
			for step: int in 8:
				var angle := TAU * float(step) / 8.0
				points.append(Vector2(cos(angle), sin(angle)) * size)
			return points


func _marker_color(part_id: StringName) -> Color:
	var hue := fmod(float(abs(hash(str(part_id)))) * 0.6180339887, 1.0)
	return Color.from_hsv(hue, 0.55, 0.95, 1.0)


func _shape_index(part_id: StringName) -> int:
	return abs(hash(str(part_id))) % 3


# --- Persistence -----------------------------------------------------------

## Which part is in which mount, as {slot: part_id}. A mount holding nothing is left out
## rather than stored as null, so an empty save block stays small. The same part appears
## once per mount it is fitted to, which is what makes a second copy a second mount.
func slot_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for slot: int in _fitted.size():
		var part: PartDefinition = _fitted[slot]
		if part != null:
			result[slot] = part.id
	return result


## Puts a saved arrangement back. A mount saved with a part the catalogue no longer has is
## left empty rather than filled with nothing: the part was removed from the game, and the
## hardware with it. A mount saved with more copies of one part than were bought is dropped
## too, for the same reason the live rules refuse to fit one: a save is not a way to mount
## hardware that was never bought.
##
## Runs after the parts block is restored, so the parts are back before they are looked up.
func restore_slots(saved: Dictionary) -> void:
	for slot: int in _fitted.size():
		_fitted[slot] = null
	var restored: Dictionary = {}
	for key: Variant in saved:
		var slot := int(key)
		if slot < 0 or slot >= _fitted.size():
			continue
		var part := _find(StringName(saved[key]))
		if part == null or not _owns(part.id):
			continue
		var placed := int(restored.get(part.id, 0))
		if placed >= owned_count_of(part.id):
			continue
		restored[part.id] = placed + 1
		_fitted[slot] = part
	_render_all()
	slots_changed.emit(-1)