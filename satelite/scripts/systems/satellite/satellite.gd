class_name Satellite
extends Node2D
## One satellite: the aggregate root that owns the behaviour modules and
## republishes them as a single, small interface.
##
## Every module is optional. The aggregate wires up whatever it finds, so you can
## drop in only the parts a satellite needs and the rest keep working standalone.
##
## [b]The outward contract[/b] is ten signals plus a few accessors, and that is
## deliberate. [code]SatelliteController[/code] binds to this contract using only
## [method Object.has_signal] and [method Object.call], so it never imports the
## module classes. Keeping the dependency one-way is what stops Godot reporting a
## cyclic script reference, and it means a satellite can be replaced by any node
## that honours the same contract.
##
## [codeblock]
## # Anywhere in the project:
## SatelliteController.stats_changed.connect(_on_stats_changed)
## SatelliteController.purchase_upgrade(&"thruster")
## SatelliteController.purchase_part(&"solar_panels")
## [/codeblock]

signal stats_changed(snapshot: Dictionary)
signal upgrade_purchased(upgrade: Resource, level: int)
signal upgrade_purchase_rejected(upgrade: Resource, reason: StringName)
signal upgrades_changed()
signal part_purchased(part: Resource, owned: int)
signal parts_changed()
## What is fitted to which mount changed. [param slot] is -1 when the whole arrangement
## did, which is what a slot count change and a save load report.
signal slots_changed(slot: int)
signal appearance_changed(snapshot: Dictionary)
signal action_performed(action: Resource)
signal data_transmitted(packet: Resource, sent_count: int)
signal downlink_changed()

@export var id: StringName = &"satellite"
@export var display_name: String = "SATELITE-01"
## What kind of satellite this is, as the config menu shows it. A
## property of the satellite rather than of any module, so it lives
## here next to the name; each satellite in a scene carries its own.
@export var satellite_type: String = "SATELITE"
## How much memory this satellite carries, in megabytes. Configuration the
## config menu edits: it is a property of the satellite rather than of any
## module, and nothing reads it yet, but it is saved the way the name is.
@export var config_memory: float = 256.0
## How far a click may land from [member click_center] and still count as a
## click on this satellite, in world pixels. The hull is drawn large, so the
## radius is generous rather than pixel-exact.
@export var click_radius: float = 150.0
## The node a click is measured from, which is the body rather than this root:
## the root sits at the origin while the hull is drawn around the body.
@export var click_center: NodePath = ^"Body"
## How far the pointer may be from a mount and still count as
## hovering the antenna in it, in world pixels. A mount is a small
## target on a large hull, so the radius is generous.
@export var hover_radius: float = 40.0

var _stats: SatelliteStats = null
var _upgrades: SatelliteUpgrades = null
var _parts: SatelliteParts = null
var _slots: SatelliteSlots = null
var _appearance: SatelliteAppearance = null
var _actions: SatelliteActions = null
var _motion: SatelliteMotion = null
var _downlink: SatelliteDownlink = null
## The control panel, found by contract rather than by type: it is an optional module with no
## class name, and this aggregate would otherwise have to import it.
var _control_panel: Node = null
## What a hover over an antenna shows, kept on the satellite so it
## follows the hull wherever the satellite goes.
var _tooltip: Label = null


func _ready() -> void:
	_collect_modules()
	_bind_modules()
	_republish()
	_push_antenna_counts()
	_push_upgrade_levels()
	_emit_stats()
	_tooltip = _make_tooltip()
	SatelliteController.register(self)
	# An accepted signal travels from the panel to the downlink
	# through here: the two modules never know each other, the
	# aggregate is what knows both.
	if _control_panel != null and _control_panel.has_signal(&"signal_accepted"):
		_control_panel.connect(&"signal_accepted", _on_signal_accepted)


## A signal accepted in the signals menu goes to the
## downlink, which is where signals are sent from. The
## downlink announces the new entry itself, so the menus
## keep up with no further wiring.
func _on_signal_accepted(_channel: StringName, found: Resource) -> void:
	if _downlink != null:
		_downlink.queue_signal(found)


func _exit_tree() -> void:
	# Looked up by path rather than through the global, because during shutdown the
	# autoload is already freed and the global resolves to null.
	var hub := get_node_or_null(^"/root/SatelliteController")
	if hub and hub.has_method(&"unregister"):
		hub.unregister(self)


## A click on the hull makes this satellite the one in focus and opens its
## config menu. The menu reads through the hub, so the screen that comes up
## describes this satellite; making it active first is what puts it there.
## A hover over a mount shows what antenna is in it and how that antenna
## is set, which is the same the config menu lists one antenna at a time.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
			return
		if get_viewport().is_input_handled():
			return
		if click.position.distance_to(_click_center()) > click_radius:
			return
		get_viewport().set_input_as_handled()
		_hide_tooltip()
		SatelliteController.set_active(self)
		MenuController.open_menu(MenuController.Id.CONFIG)
	elif event is InputEventMouseMotion:
		_on_mouse_motion(event as InputEventMouseMotion)


## Where a click on this satellite is measured from: the body's position in
## the world, or this root's own when the scene has no body to point at.
func _click_center() -> Vector2:
	var body: Node = get_node_or_null(click_center)
	if body is Node2D:
		return (body as Node2D).global_position
	return global_position


## The antenna under the pointer, if there is one. A mount is
## where an antenna lives, so the pointer is checked against the
## mounts, and a mount only answers when it holds an antenna -
## an empty mount or a part with no channel is nothing to read.
func _on_mouse_motion(event: InputEventMouseMotion) -> void:
	var slot := _slots.mount_at(event.position, hover_radius) if _slots != null and _slots.has_method(&"mount_at") else -1
	var channel := _channel_of_slot(slot)
	if channel.is_empty():
		_hide_tooltip()
		return
	_show_tooltip(channel, event.position)


## The channel the antenna in [param slot] listens on, or empty
## when nothing is fitted there or it is not an antenna.
func _channel_of_slot(slot: int) -> StringName:
	if slot < 0 or _slots == null:
		return &""
	var states: Array = _slots.slots()
	if slot >= states.size():
		return &""
	var entry: Dictionary = states[slot]
	return StringName(entry.get(&"antenna_channel", &""))


## Shows what [param channel]'s antennas are and how they are set,
## beside the pointer. The control panel is what keeps the values,
## so the hover reads them through the same contract the config
## menu does.
func _show_tooltip(channel: StringName, at: Vector2) -> void:
	if _tooltip == null or _control_panel == null or not _control_panel.has_method(&"antenna_config"):
		return
	var config: Dictionary = _control_panel.call(&"antenna_config", channel)
	_tooltip.text = "%s ANTENNA x%d\nSTRENGTH %d\nRANGE %s" % [
		str(config.get(&"type", channel)).to_upper(),
		int(config.get(&"count", 0)),
		int(config.get(&"strength", 0)),
		_number_text(float(config.get(&"range", 0.0))),
	]
	_tooltip.position = to_local(at) + Vector2(14, 14)
	_tooltip.visible = true


func _hide_tooltip() -> void:
	if _tooltip != null:
		_tooltip.visible = false


## A number as whole when it is one, so a range reads as 4 rather
## than 4.0.
func _number_text(value: float) -> String:
	if is_equal_approx(value, float(int(value))):
		return "%d" % int(value)
	return String.num(value, 2)


## The hover readout: a small dark label with a border, so it reads
## over the hull art whatever it is drawn on.
func _make_tooltip() -> Label:
	var label := Label.new()
	label.visible = false
	label.z_index = 10
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.0862745, 0.0941176, 0.129412, 0.980392)
	background.border_color = Color(0.239216, 0.270588, 0.380392, 1)
	background.set_border_width_all(1)
	background.set_corner_radius_all(4)
	background.content_margin_left = 8.0
	background.content_margin_top = 4.0
	background.content_margin_right = 8.0
	background.content_margin_bottom = 4.0
	label.add_theme_stylebox_override(&"normal", background)
	add_child(label)
	return label


# --- Modules ---------------------------------------------------------------

func stats() -> SatelliteStats:
	return _stats


func upgrades() -> SatelliteUpgrades:
	return _upgrades


func parts() -> SatelliteParts:
	return _parts


func appearance() -> SatelliteAppearance:
	return _appearance


func actions() -> SatelliteActions:
	return _actions


func motion() -> SatelliteMotion:
	return _motion


func downlink() -> SatelliteDownlink:
	return _downlink


## The satellite's control panel, or null when it has none. Typed as [Node] because it is
## addressed by contract: [method Object.has_method] on [code]"set_antenna_counts"[/code].
func control_panel() -> Node:
	return _control_panel


# --- Contract: stats -------------------------------------------------------

func stat_snapshot() -> Dictionary:
	return _stats.snapshot() if _stats != null else {}


## Every stat with its caption, unit and precision. Readouts render this instead
## of a hardcoded list, so they follow whatever this satellite tracks.
##
## The speed readout carries the solar array's scale, so the screens show
## how fast the satellite actually travels rather than the raw sum its
## thrusters and upgrades add up to. The stat block itself keeps the raw
## sum: saves, effect reapplication and prices all read that one number.
func stat_descriptors() -> Array:
	var result := _stats.descriptors() if _stats != null else []
	_apply_solar_scale(result)
	return result


## Multiplies the speed entry in [param descriptors] - the copy
## [method stat_descriptors] hands out, never the stat block - by the
## solar array's scale, second unit included, since that is derived
## from the same value. Leaves every other stat, and a satellite with
## no motion module, untouched.
func _apply_solar_scale(descriptors: Array) -> void:
	if _motion == null:
		return
	var scale := _motion.solar_scale()
	if scale == 1.0:
		return
	for entry: Variant in descriptors:
		if not (entry is Dictionary):
			continue
		var descriptor: Dictionary = entry
		if StringName(descriptor.get("id", &"")) != SatelliteStats.SPEED:
			continue
		descriptor["value"] = float(descriptor.get("value", 0.0)) * scale
		var secondary: Variant = descriptor.get("secondary")
		if secondary is Dictionary:
			var alt: Dictionary = secondary
			alt["value"] = float(alt.get("value", 0.0)) * scale


func set_stat(stat_id: StringName, value: Variant) -> void:
	if _stats != null:
		_stats.set_stat(stat_id, value)


func add_stat(stat_id: StringName, delta: float) -> void:
	if _stats != null:
		_stats.add_stat(stat_id, delta)


# --- Contract: upgrades ----------------------------------------------------

func upgrade_catalogue() -> Array:
	return _upgrades.upgrades if _upgrades != null else []


func level_of(upgrade_id: StringName) -> int:
	return _upgrades.level_of(upgrade_id) if _upgrades != null else 0


func cost_of(upgrade_id: StringName) -> int:
	return _upgrades.cost_of(upgrade_id) if _upgrades != null else 0


func can_purchase(upgrade_id: StringName) -> bool:
	return _upgrades.can_purchase(upgrade_id) if _upgrades != null else false


## Why [param upgrade_id] cannot be bought right now, or empty when it can. What a menu row
## shows on its disabled button, so the rule stays in one place.
func upgrade_purchase_reason(upgrade_id: StringName) -> StringName:
	return _upgrades.rejection_reason(upgrade_id) if _upgrades != null else &"unknown_upgrade"


func purchase_upgrade(upgrade_id: StringName) -> bool:
	return _upgrades.purchase(upgrade_id) if _upgrades != null else false


# --- Contract: parts --------------------------------------------------------

func part_catalogue() -> Array:
	return _parts.catalogue() if _parts != null else []


func owned_count_of(part_id: StringName) -> int:
	return _parts.owned_count(part_id) if _parts != null else 0


func owns_part(part_id: StringName) -> bool:
	return _parts.owns(part_id) if _parts != null else false


func price_of_part(part_id: StringName) -> int:
	return _parts.price_of(part_id) if _parts != null else 0


func can_purchase_part(part_id: StringName) -> bool:
	return _parts.can_purchase(part_id) if _parts != null else false


func purchase_part(part_id: StringName) -> bool:
	return _parts.purchase(part_id) if _parts != null else false


## One entry per mount, in order: what is fitted there and where on the body it sits.
func slot_states() -> Array:
	return _slots.slots() if _slots != null else []


func available_slots() -> int:
	return _slots.available_slots() if _slots != null else 0


## Fits [param part_id] into [param slot], replacing whatever was fitted there. Reports
## whether it happened; what it replaced is on [signal SatelliteSlots.part_fitted].
##
## Each copy bought can be fitted in its own mount, so fitting a part the satellite already
## carries mounts another copy rather than moving the first one. The antenna that lands
## in the mount is given its own stats, seeded from its channel's defaults, so every
## antenna carries its own from the moment it is mounted.
func fit_part(part_id: StringName, slot: int) -> bool:
	var fitted := _slots != null and _slots.fit(part_id, slot)
	if fitted:
		_seed_slot_stats(slot)
	return fitted


## Gives the antenna in [param slot] its own stats, taken
## from its channel's defaults. Skips a mount that already
## carries stats, so re-fitting the antenna that is already
## there does not wipe what it was set to.
func _seed_slot_stats(slot: int) -> void:
	if _slots == null or _control_panel == null:
		return
	var channel := _channel_of_slot(slot)
	if channel.is_empty():
		return
	if not _slots.antenna_at(slot).is_empty():
		return
	var stats: Dictionary = {
		&"strength": _control_panel.call(&"antenna_strength_of", channel),
		&"range": _control_panel.call(&"antenna_range_of", channel),
	}
	_slots.seed_antenna_stats(slot, stats)


## Empties [param slot] and returns what was in it, or null. The part stays bought.
func unfit_part(slot: int) -> Resource:
	return _slots.clear(slot) if _slots != null else null


## Which mount [param part_id] is fitted to, or -1 when it is fitted nowhere. The lowest of
## the mounts when it is fitted to several; [method slots_of_part] is the whole list.
func slot_of_part(part_id: StringName) -> int:
	return _slots.slot_of(part_id) if _slots != null else -1


## Every mount [param part_id] is fitted to, in order. Empty when it is fitted nowhere.
func slots_of_part(part_id: StringName) -> Array:
	return _slots.slots_of(part_id) if _slots != null else []


## How many copies of [param part_id] are fitted, which is at most how many were bought.
func fitted_count_of_part(part_id: StringName) -> int:
	return _slots.fitted_count_of(part_id) if _slots != null else 0


## Whether another copy of [param part_id] could be fitted as it is, without moving one that
## already is.
func can_fit_part(part_id: StringName) -> bool:
	return _slots != null and _slots.can_fit(part_id)


## Seconds of setup left on [param slot], or 0 when the mount is empty or already working.
## What a readout counts down.
func install_remaining(slot: int) -> float:
	return _slots.install_remaining(slot) if _slots != null else 0.0


## Whether [param slot] holds hardware that is up and running: fitted, and past its setup
## wait. False for an empty mount and for an antenna still being installed.
func is_installed(slot: int) -> bool:
	return _slots != null and _slots.is_installed(slot)


# --- Contract: actions -----------------------------------------------------

func action_catalogue() -> Array:
	return _actions.actions if _actions != null else []


func perform_action(action_id: StringName) -> bool:
	return _actions.perform(action_id) if _actions != null else false


# --- Contract: downlink -----------------------------------------------------

## Every packet this satellite can send, resolved and ready to render.
func downlink_catalogue() -> Array:
	return _downlink.catalogue() if _downlink != null else []


func can_send_data(packet_id: StringName) -> bool:
	return _downlink.can_send(packet_id) if _downlink != null else false


## Sends [param packet_id] back to Earth. False when the packet is unknown or may not
## be sent again.
func transmit_data(packet_id: StringName) -> bool:
	return _downlink.transmit(packet_id) if _downlink != null else false


func sent_count_of(packet_id: StringName) -> int:
	return _downlink.sent_count(packet_id) if _downlink != null else 0


func downlink_totals() -> Dictionary:
	return _downlink.totals() if _downlink != null else {}


# --- Contract: appearance --------------------------------------------------

func set_visual(key: StringName, value: Variant) -> void:
	if _appearance != null:
		_appearance.set_visual(key, value)


func set_appearance_state(state: StringName) -> void:
	if _appearance != null:
		_appearance.set_state(state)


func appearance_snapshot() -> Dictionary:
	return _appearance.snapshot() if _appearance != null else {}


## Stops or resumes distance accrual. The distance stat keeps its current value.
func set_distance_accrual(enabled: bool) -> void:
	if _motion != null:
		_motion.accrual_enabled = enabled


# --- Contract: config --------------------------------------------------------

## What the config menu shows: where the satellite is, how strongly its
## antennas listen, how much memory it carries and what kind of satellite
## it is. One dictionary because the four travel together - a menu opens
## on a whole satellite, not on a value.
func config_snapshot() -> Dictionary:
	return {
		"position": position,
		"strength": _antenna_strength(),
		"memory": config_memory,
		"type": satellite_type,
	}


## The base strength the control panel listens at, or 0 when this satellite has
## no panel. Read through the contract because the panel has no class name, the
## same as every other panel access here.
func _antenna_strength() -> int:
	if _control_panel != null and _control_panel.has_method(&"antenna_strength"):
		return int(_control_panel.call(&"antenna_strength"))
	return 0


## Every antenna's configuration, as {channel: {type, count, strength, range}}.
## What the config menu's antenna section is built from, so each antenna shows
## its own type and settings rather than the satellite's as a whole.
func antenna_configs() -> Dictionary:
	if _control_panel != null and _control_panel.has_method(&"antenna_configs"):
		var result: Variant = _control_panel.call(&"antenna_configs")
		return (result as Dictionary) if result is Dictionary else {}
	return {}


# --- Contract: persistence -------------------------------------------------

## Everything a save needs to bring this satellite back: identity, stats, upgrade
## levels, fitted parts, granted actions, appearance and downlink send counts. Read
## by [code]SaveManager[/code] through the contract, so no module here knows that
## saves exist.
##
## [Satellite] is the only node in the tree that answers the contract. Every module
## below it exposes a plain snapshot/restore pair and is composed here, which is
## what keeps a save file to one entry per satellite.
func save_data() -> Dictionary:
	var actions: Dictionary = {
		"granted": _actions.granted_snapshot(),
		"cooldowns": _actions.cooldowns_snapshot(),
	}
	var state: Dictionary = {
		"id": str(id),
		"display_name": display_name,
		"position": position,
		"memory": config_memory,
		"stats": _stats.snapshot() if _stats != null else {},
		"upgrades": _upgrades.levels_snapshot() if _upgrades != null else {},
		"parts": _parts.owned_snapshot() if _parts != null else {},
		"slots": _slots.slot_snapshot() if _slots != null else {},
		"installed": _slots.installed_snapshot() if _slots != null else {},
		"antenna_stats": _slots.antenna_stats_snapshot() if _slots != null else {},
		"actions": actions if _actions != null else {},
		"appearance": _appearance.snapshot() if _appearance != null else {},
		"downlink": _downlink.sent_snapshot() if _downlink != null else {},
	}
	# Accepted signals are state, not catalogue: a save names
	# them by id, and load_data resolves them against the
	# panel's catalogue again.
	if _downlink != null:
		state["downlink_signals"] = _downlink.signal_snapshot()
	return state


## Restores what [method save_data] produced.
##
## The order is the whole trick. Levels and parts come first, because they are what
## own the unlocked actions. Stats and appearance then go back as the absolute
## values the save recorded, overwriting anything the reapplication produced -
## applying the effects a second time on top would double count them.
func load_data(data: Dictionary) -> void:
	var raw_id: Variant = data.get("id")
	if raw_id != null:
		id = StringName(raw_id)
	var raw_name: Variant = data.get("display_name")
	if raw_name != null:
		display_name = str(raw_name)
	var raw_position: Variant = data.get("position")
	if raw_position is Vector2:
		position = raw_position
	var raw_memory: Variant = data.get("memory")
	if raw_memory != null:
		config_memory = float(raw_memory)
	if _upgrades != null:
		_upgrades.restore_levels(_as_dictionary(data.get("upgrades")))
	if _parts != null:
		_parts.restore_owned(_as_dictionary(data.get("parts")))
	# After the parts, because a mount is only restored to a part the catalogue still has.
	# The installed block rides along so a mount that was already working is not set up a
	# second time and paid for twice: the stats restored below already count it.
	if _slots != null:
		_slots.restore_slots(
			_as_dictionary(data.get("slots")),
			_as_dictionary(data.get("installed")))
		_slots.restore_antenna_stats(_as_dictionary(data.get("antenna_stats")))
		# A save written before antennas carried their own stats has none,
		# so each restored antenna is seeded from its channel's defaults.
		for slot: int in _slots.available_slots():
			_seed_slot_stats(slot)
	if _actions != null:
		var actions := _as_dictionary(data.get("actions"))
		_actions.restore(actions.get("granted", []), actions.get("cooldowns", {}))
	if _stats != null:
		_stats.set_all(_as_dictionary(data.get("stats")))
	if _appearance != null:
		_appearance.restore(_as_dictionary(data.get("appearance")))
	if _downlink != null:
		_downlink.restore_sent(_as_dictionary(data.get("downlink")))
		# Accepted signals come back as entries of their own, resolved
		# against the panel's catalogue because a save names them by id.
		var restored: Array[Dictionary] = []
		for entry: Variant in _as_array(data.get("downlink_signals")):
			var saved: Dictionary = entry
			var definition: SignalDefinition = _signal_of(StringName(saved.get("signal", &"")))
			if definition != null:
				restored.append({
					"signal": definition,
					"state": int(saved.get("state", SatelliteDownlink.SIGNAL_QUEUED)),
				})
		_downlink.restore_queue(restored)


## The control panel's catalogue entry with this id, or null.
## The panel owns the signal catalogue, so the aggregate asks
## it by contract rather than reaching into it.
func _signal_of(signal_id: StringName) -> SignalDefinition:
	if _control_panel == null or not _control_panel.has_method(&"signal_of"):
		return null
	var found: Variant = _control_panel.call(&"signal_of", signal_id)
	return found as SignalDefinition


func _as_dictionary(value: Variant) -> Dictionary:
	return (value as Dictionary) if value is Dictionary else {}


func _as_array(value: Variant) -> Array:
	return (value as Array) if value is Array else []


# --- Internals -------------------------------------------------------------

func _collect_modules() -> void:
	for child in get_children():
		if child is SatelliteStats:
			_stats = child as SatelliteStats
		elif child is SatelliteUpgrades:
			_upgrades = child as SatelliteUpgrades
		elif child is SatelliteParts:
			_parts = child as SatelliteParts
		elif child is SatelliteSlots:
			_slots = child as SatelliteSlots
		elif child is SatelliteAppearance:
			_appearance = child as SatelliteAppearance
		elif child is SatelliteActions:
			_actions = child as SatelliteActions
		elif child is SatelliteMotion:
			_motion = child as SatelliteMotion
		elif child is SatelliteDownlink:
			_downlink = child as SatelliteDownlink
		elif child.has_method(&"set_antenna_counts"):
			_control_panel = child


func _bind_modules() -> void:
	if _actions != null:
		_actions.bind(_stats)
	if _motion != null:
		_motion.bind(_stats, _slots, _upgrades)
	if _downlink != null:
		_downlink.bind(_stats)
	if _upgrades != null:
		_upgrades.bind(_stats, _appearance, _actions)
	if _parts != null:
		_parts.bind(_stats, _appearance, _actions)
	# After the parts, so a mount can be matched against a part that is already there.
	if _slots != null:
		_slots.bind(_parts)


func _republish() -> void:
	if _stats != null:
		_stats.stats_changed.connect(_on_stats_changed)
	if _upgrades != null:
		_upgrades.upgrade_purchased.connect(_on_upgrade_purchased)
		_upgrades.purchase_rejected.connect(_on_upgrade_rejected)
		_upgrades.upgrades_changed.connect(_on_upgrades_changed)
	if _parts != null:
		_parts.part_purchased.connect(_on_part_purchased)
		_parts.parts_changed.connect(_on_parts_changed)
	if _slots != null:
		_slots.slots_changed.connect(_on_slots_changed)
	if _appearance != null:
		_appearance.appearance_changed.connect(_on_appearance_changed)
	if _actions != null:
		_actions.action_performed.connect(_on_action_performed)
	if _downlink != null:
		_downlink.data_transmitted.connect(_on_data_transmitted)
		_downlink.downlink_changed.connect(_on_downlink_changed)


func _emit_stats() -> void:
	if _stats != null:
		stats_changed.emit(_stats.snapshot())


func _on_stats_changed(snapshot: Dictionary) -> void:
	stats_changed.emit(snapshot)


func _on_upgrade_purchased(upgrade: Resource, level: int) -> void:
	_push_upgrade_levels()
	upgrade_purchased.emit(upgrade, level)


func _on_upgrade_rejected(upgrade: Resource, reason: StringName) -> void:
	upgrade_purchase_rejected.emit(upgrade, reason)


func _on_upgrades_changed() -> void:
	_push_upgrade_levels()
	upgrades_changed.emit()


func _on_part_purchased(part: Resource, owned: int) -> void:
	# A new antenna listens as soon as it is bought, before it is fitted anywhere, so the
	# panel hears with the hardware the player just paid for rather than waiting for a
	# mount to be chosen. Parts with no channel are not antennas and do nothing here.
	if _control_panel != null and _control_panel.has_method(&"detect_new_anten"):
		_control_panel.call(&"detect_new_anten", part)
	part_purchased.emit(part, owned)


func _on_parts_changed() -> void:
	parts_changed.emit()


func _on_slots_changed(slot: int) -> void:
	_push_antenna_counts()
	slots_changed.emit(slot)


## Tells the control panel how many levels of each upgrade have been bought, so the panel
## keeps a count per upgrade rather than every reader going back to the upgrades block.
##
## The panel is optional and answered by contract, so a satellite without one loses nothing.
## Pushed as a whole block rather than one level at a time: a level can be granted or restored
## in a jump, and the panel would rather be told the answer than keep up with the steps.
func _push_upgrade_levels() -> void:
	if _upgrades == null or _control_panel == null:
		return
	if not _control_panel.has_method(&"set_upgrade_levels"):
		return
	_control_panel.call(&"set_upgrade_levels", _upgrades.levels_snapshot())


## Tells the control panel how many pieces of hardware it has per channel, counted off the
## mounts rather than off what was bought: one mount is one antenna, so a part fitted twice
## is two, and one that was bought but never mounted is none.
##
## The panel is optional and answered by contract, so a satellite without one loses nothing.
func _push_antenna_counts() -> void:
	if _slots == null or _control_panel == null:
		return
	_control_panel.call(&"set_antenna_counts", _slots.antenna_counts())


func _on_appearance_changed(snapshot: Dictionary) -> void:
	appearance_changed.emit(snapshot)


func _on_action_performed(action: Resource) -> void:
	action_performed.emit(action)


func _on_data_transmitted(packet: Resource, count: int) -> void:
	data_transmitted.emit(packet, count)


func _on_downlink_changed() -> void:
	downlink_changed.emit()
