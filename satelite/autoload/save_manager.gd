extends Node
## Global save and load service, autoloaded as [code]SaveManager[/code].
##
## Every slot is one JSON file under [constant SAVE_DIR], readable and editable
## outside the game, and every participant's state is a plain [Dictionary] inside
## it. Nothing about a save depends on this script being loaded: it is a
## dictionary in a file, which is what makes it debuggable.
##
## [b]Four ways to get state in and out[/b], widest first:
##
## [codeblock]
## # 1. The global bag. Saved with every slot, no node needed.
## SaveManager.set_global(&"music_volume", 0.8)
##
## # 2. The contract. Full control over what is written and how it is applied.
## func save_data() -> Dictionary: ...
## func load_data(data: Dictionary) -> void: ...
##
## # 3. A SaveState child. Properties captured for you, no script on the target.
## var state := SaveState.new()
## state.save_key = &"player"
## add_child(state)
##
## # 4. Nothing. A node that implements the contract is found on its own.
## [/codeblock]
##
## [Satellite] uses the contract, through [code]SatelliteController[/code], which
## is why a save covers stats, upgrades, appearance and cooldowns without any of
## those modules knowing a save system exists.
##
## Ids are the node path, or the key given at [method register], so renaming a
## node orphans its slot entry rather than writing the wrong state somewhere.
## Unknown ids on load are skipped and missing ones simply stay at their defaults.

signal save_written(slot: StringName, info: Dictionary)
signal save_read(slot: StringName, info: Dictionary)
signal save_failed(slot: StringName, reason: StringName)

## Folder every slot lives in. Under [code]user://[/code], so it survives an
## export and is writable on a read-only install.
const SAVE_DIR := "user://saves"

const FILE_EXTENSION := ".json"

## Slot used when a caller does not name one.
const DEFAULT_SLOT := &"quicksave"

## Slot [member autosave_enabled] writes to. Kept apart from
## [constant DEFAULT_SLOT] so autosaving cannot overwrite a save the player made
## on purpose.
const AUTOSAVE_SLOT := &"autosave"

## Marks a file as a save. A plain document written through [method write_json]
## has no marker, so the two never get confused.
const SCHEMA := "satelite.save"

## Bumped whenever the shape of a save changes. [method _migrate] is where older
## payloads are brought forward.
const SAVE_VERSION := 1

## Slot used when a caller does not name one.
var current_slot: StringName = DEFAULT_SLOT

## Values saved with every slot and restored from it, for state that is not worth
## a node: settings, unlocks, tutorial flags, best score. Keys are [StringName]s.
var globals: Dictionary = {}

## Write [member AUTOSAVE_SLOT] on a timer. Set to false for a game that only
## saves on request.
@export var autosave_enabled: bool = true

## Seconds between autosaves. Zero or less turns the timer off without unsetting
## [member autosave_enabled], so [method request_autosave] still works.
@export var autosave_interval: float = 120.0

## Also capture script variables that were not exported, for participants with no
## contract of their own. Off by default so a save holds the state you can see in
## the inspector rather than every private cache.
@export var include_hidden_properties: bool = false

## Also capture [Resource] properties, by path.
@export var save_resources: bool = false

## Look for contract implementations anywhere in the tree at save time. Lets a
## node participate without registering itself.
@export var discover_nodes: bool = true

## Indentation written into save files. Empty makes them one long line.
@export var indent: String = "\t"

var _participants: Array[Dictionary] = []
var _since_autosave: float = 0.0
var _autosave_queued: bool = false
var _quit_saved: bool = false


func _ready() -> void:
	# The game freezes whenever a pausing menu is open, and an autosave that stops
	# with the pause menu would only ever fire while the player is busy elsewhere.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if _autosave_queued:
		_autosave_queued = false
		save_game(AUTOSAVE_SLOT)
		return
	if not autosave_enabled or autosave_interval <= 0.0:
		return
	_since_autosave += delta
	if _since_autosave >= autosave_interval:
		_since_autosave = 0.0
		save_game(AUTOSAVE_SLOT)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_on_quit()


## Writes [member AUTOSAVE_SLOT] at the end of the current frame. For
## anything that might not come back, like quitting.
func request_autosave() -> void:
	_autosave_queued = true


## Saves before [method SceneTree.quit]. A quit does not go through the window
## manager, so it never raises [constant NOTIFICATION_WM_CLOSE_REQUEST] and would
## otherwise leave nothing behind. Deliberately not done from [method
## Node._exit_tree]: by then the main scene has been freed and the save would
## record a game with no satellite in it.
func save_before_quit() -> void:
	_save_on_quit()


# --- Global bag -------------------------------------------------------------

func set_global(key: StringName, value: Variant) -> void:
	globals[key] = value


func get_global(key: StringName, fallback: Variant = null) -> Variant:
	return globals.get(key, fallback)


func has_global(key: StringName) -> bool:
	return globals.has(key)


func erase_global(key: StringName) -> bool:
	return globals.erase(key)


func clear_globals() -> void:
	globals.clear()


# --- Registration -----------------------------------------------------------

## Adds [param node] to every save from now on and returns the id its state is
## stored under. A node that has already registered is kept as it is, so
## re-registering after a reparent cannot silently move a save entry.
func register(node: Object, key: StringName = &"") -> StringName:
	if node == null:
		return &""
	for entry in _live_participants():
		if entry["node"] == node:
			return entry["key"]
	var resolved := key
	if resolved == &"":
		resolved = _derive_key(node)
	resolved = _unused_key(resolved)
	_participants.append({"key": resolved, "node": node})
	return resolved


## Drops [param node] from every future save. Its data in an existing file stays
## there and is ignored.
func unregister(node: Object) -> void:
	for entry: Dictionary in _participants:
		if entry["node"] == node:
			_participants.erase(entry)
			return


func is_registered(node: Object) -> bool:
	for entry in _live_participants():
		if entry["node"] == node:
			return true
	return false


# --- Slots ------------------------------------------------------------------

## Writes every participant plus [member globals] to [param slot]. Returns whether
## the file landed.
func save_game(slot: StringName = &"") -> bool:
	var target := _resolve_slot(slot)
	if target == &"":
		save_failed.emit(slot, &"unknown_slot")
		return false
	var payload := _collect()
	var envelope := {
		"schema": SCHEMA,
		"version": SAVE_VERSION,
		"game_version": _game_version(),
		"slot": str(target),
		"saved_at": Time.get_datetime_string_from_system(true),
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"globals": payload["globals"],
		"nodes": payload["nodes"],
	}
	if not write_json(slot_path(target), envelope):
		save_failed.emit(target, &"write_failed")
		return false
	var info := _info_from(envelope, target)
	save_written.emit(target, info)
	return true


## Restores every participant plus [member globals] from [param slot]. Ids that
## nothing is listening for are reported and skipped, so a save from a build with
## more content still loads.
func load_game(slot: StringName = &"") -> bool:
	var target := _resolve_slot(slot)
	if target == &"":
		save_failed.emit(slot, &"unknown_slot")
		return false
	var raw: Variant = read_json(slot_path(target))
	if not (raw is Dictionary):
		save_failed.emit(target, &"unreadable")
		return false
	var envelope: Dictionary = raw
	if str(envelope.get("schema", "")) != SCHEMA:
		push_warning("SaveManager: '%s' is not a save file." % slot_path(target))
		save_failed.emit(target, &"not_a_save")
		return false
	var version := int(envelope.get("version", 0))
	if version > SAVE_VERSION:
		push_warning("SaveManager: '%s' is version %d, this build understands %d." % [target, version, SAVE_VERSION])
		save_failed.emit(target, &"from_the_future")
		return false
	_restore(_migrate(envelope, version))
	save_read.emit(target, _info_from(envelope, target))
	return true


## Restores [member globals] only, leaving game state alone. For settings that
## should survive independently of where the player is.
func load_globals(slot: StringName = &"") -> bool:
	var raw: Variant = read_json(slot_path(_resolve_slot(slot)))
	if not (raw is Dictionary) or str((raw as Dictionary).get("schema", "")) != SCHEMA:
		return false
	globals = _as_dictionary((raw as Dictionary).get("globals", {}))
	return true


## Writes [member globals] plus whatever is on disk, so a settings change made
## mid-session does not need a full save.
func save_globals(slot: StringName = &"") -> bool:
	var target := _resolve_slot(slot)
	var raw: Variant = read_json(slot_path(target))
	var envelope: Dictionary = raw if raw is Dictionary else {}
	envelope["schema"] = SCHEMA
	envelope["version"] = SAVE_VERSION
	envelope["game_version"] = _game_version()
	envelope["slot"] = str(target)
	envelope["saved_at"] = Time.get_datetime_string_from_system(true)
	envelope["saved_at_unix"] = int(Time.get_unix_time_from_system())
	envelope["globals"] = globals
	if not envelope.has("nodes"):
		envelope["nodes"] = {}
	if not write_json(slot_path(target), envelope):
		save_failed.emit(target, &"write_failed")
		return false
	save_written.emit(target, _info_from(envelope, target))
	return true


func delete_slot(slot: StringName) -> bool:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return false
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		push_warning("SaveManager: could not open '%s'." % path.get_base_dir())
		return false
	# [method DirAccess.remove] answers with an Error, so this has to be compared
	# rather than treated as a truthy value: OK is zero.
	var err := dir.remove(path.get_file())
	if err != OK:
		push_warning("SaveManager: could not delete '%s' (%s)." % [path, error_string(err)])
		return false
	return true


func has_slot(slot: StringName) -> bool:
	return FileAccess.file_exists(slot_path(slot))


## Every slot that reads back, newest first. A file that does not parse is left
## out rather than reported: a corrupt slot should not hide the good ones.
func list_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return result
	for file: String in dir.get_files():
		if not file.ends_with(FILE_EXTENSION):
			continue
		var info := slot_info(StringName(file.trim_suffix(FILE_EXTENSION)))
		if not info.is_empty():
			result.append(info)
	result.sort_custom(_newer_first)
	return result


## Header of one slot: slot, version, saved_at, saved_at_unix, game_version. Empty
## when there is nothing to read.
func slot_info(slot: StringName) -> Dictionary:
	var raw: Variant = read_json(slot_path(slot))
	if not (raw is Dictionary):
		return {}
	return _info_from(raw, slot)


## Slot written most recently, or empty when there are none.
func latest_slot() -> StringName:
	var slots := list_slots()
	if slots.is_empty():
		return &""
	return StringName(slots[0].get("slot", ""))


func slot_path(slot: StringName) -> String:
	return "%s/%s%s" % [SAVE_DIR, slot, FILE_EXTENSION]


# --- JSON files -------------------------------------------------------------

## [param value] as JSON at [param path], which may be any [method FileAccess]
## path. Replaces the target in one step, so an interrupted write leaves the
## previous file intact instead of half a save.
func write_json(path: String, value: Variant) -> bool:
	if not ensure_directory(path.get_base_dir()):
		push_error("SaveManager: could not create '%s'." % path.get_base_dir())
		return false
	var temp := "%s.tmp" % path
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: could not open '%s' (%s)." % [temp, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(SaveCodec.stringify(value, indent))
	file.close()
	if not _replace_file(temp, path):
		push_error("SaveManager: could not replace '%s'." % path)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
		return false
	return true


## JSON at [param path] rebuilt with [SaveCodec], or null when the file is
## missing or unreadable. Shares the null ambiguity of [method SaveCodec.parse].
func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SaveManager: could not open '%s'." % path)
		return null
	var text := file.get_as_text()
	file.close()
	return SaveCodec.parse(text)


# --- Internals --------------------------------------------------------------

## Ids every registered node is stored under, discovered nodes included. Walks the
## tree without asking anybody for their state, since listing what a save will
## cover should not have to build it first.
func participant_keys() -> PackedStringArray:
	var keys: Array[StringName] = []
	var claimed: Array[Object] = []
	for entry: Dictionary in _live_participants():
		claimed.append(entry["node"])
		keys.append(entry["key"])
	if discover_nodes:
		var tree := get_tree()
		if tree != null:
			_gather_keys(tree.root, keys, claimed)
	var sorted := PackedStringArray()
	for key: StringName in keys:
		sorted.append(str(key))
	sorted.sort()
	return sorted


## The whole game state as it would be written right now.
func _collect() -> Dictionary:
	return {
		"globals": globals.duplicate(true),
		"nodes": _collect_nodes(),
	}


func _collect_nodes() -> Dictionary:
	var result: Dictionary = {}
	var claimed: Array[Object] = []
	for entry: Dictionary in _live_participants():
		claimed.append(entry["node"])
		result[entry["key"]] = _capture(entry["node"])
	if discover_nodes:
		var tree := get_tree()
		if tree != null:
			_discover(tree.root, result, claimed)
	# Sorted so two saves of the same state produce the same file, which makes a
	# save diffable and a save checksum stable.
	var keys: Array = result.keys()
	keys.sort()
	var ordered: Dictionary = {}
	for key: Variant in keys:
		ordered[str(key)] = result[key]
	return ordered


func _discover(node: Node, result: Dictionary, claimed: Array[Object]) -> void:
	for child: Node in node.get_children():
		if child == self or not is_instance_valid(child) or child in claimed:
			continue
		# The tree is mid-tear-down during shutdown, and a node can already be
		# detached by the time its turn comes.
		if not child.is_inside_tree():
			continue
		if _claims_state(child):
			var key := _unused_key(_derive_key(child))
			result[key] = _capture(child)
		_discover(child, result, claimed)


func _gather_keys(node: Node, keys: Array[StringName], claimed: Array[Object]) -> void:
	for child: Node in node.get_children():
		if child == self or not is_instance_valid(child) or child in claimed:
			continue
		if not child.is_inside_tree():
			continue
		if _claims_state(child):
			keys.append(_derive_key(child))
		_gather_keys(child, keys, claimed)


## A node participates by implementing both halves of the contract. Requiring the
## loader as well means a save can never reference state nothing can restore.
func _claims_state(node: Node) -> bool:
	return node.has_method(&"save_data") and node.has_method(&"load_data")


## Drops participants whose node has since been freed, which is what happens to
## anything a scene queue_free removed since the last save.
func _live_participants() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dead: Array[Dictionary] = []
	for entry: Dictionary in _participants:
		if is_instance_valid(entry["node"]):
			result.append(entry)
		else:
			dead.append(entry)
	for entry: Dictionary in dead:
		_participants.erase(entry)
	return result


func _capture(node: Object) -> Dictionary:
	if node.has_method(&"save_data"):
		var result: Variant = node.call(&"save_data")
		return _as_dictionary(result)
	return SaveState.capture_properties(node, _property_options(node))


func _apply(node: Object, data: Dictionary) -> void:
	if node.has_method(&"load_data"):
		node.call(&"load_data", data)
		return
	SaveState.apply_properties(node, data, _property_options(node))


func _property_options(node: Object) -> Dictionary:
	var options := {
		"properties": PackedStringArray(),
		"include_hidden": include_hidden_properties,
		"save_resources": save_resources,
	}
	# A node can name its own whitelist, so a system that only wants two values in
	# its save does not have to reimplement the contract.
	if node.has_method(&"save_property_filter"):
		var filter: Variant = node.call(&"save_property_filter")
		if filter is Array or filter is PackedStringArray:
			options["properties"] = filter
	return options


func _restore(envelope: Dictionary) -> void:
	if envelope.has("globals"):
		globals = _as_dictionary(envelope.get("globals"))
	var nodes := _as_dictionary(envelope.get("nodes", {}))
	var keys: Array = nodes.keys()
	keys.sort()
	for key: Variant in keys:
		var id := StringName(key)
		var entry := _entry_for(id)
		if entry.is_empty():
			push_warning("SaveManager: nothing is listening for '%s' in this save." % key)
			continue
		_apply(entry["node"], _as_dictionary(nodes[key]))


## Registered nodes first, then one discovery pass for a node that appeared since
## the last save. Returns an empty dictionary when no live node claims [param id].
func _entry_for(id: StringName) -> Dictionary:
	for entry: Dictionary in _live_participants():
		if entry["key"] == id:
			return entry
	if not discover_nodes:
		return {}
	var tree := get_tree()
	if tree == null:
		return {}
	var found: Dictionary = {}
	var claimed: Array[Object] = []
	for entry: Dictionary in _live_participants():
		claimed.append(entry["node"])
	_discover_for(tree.root, id, found, claimed)
	return found


func _discover_for(node: Node, id: StringName, found: Dictionary, claimed: Array[Object]) -> void:
	if not found.is_empty():
		return
	for child: Node in node.get_children():
		if child == self or not is_instance_valid(child) or child in claimed:
			continue
		if not child.is_inside_tree():
			continue
		if _claims_state(child) and _derive_key(child) == id:
			found["key"] = id
			found["node"] = child
			return
		_discover_for(child, id, found, claimed)


## Seam for version bumps. Adding a field to a save means bumping
## [constant SAVE_VERSION] and filling in the step from the previous number here,
## so old files keep loading instead of quietly losing whatever moved.
func _migrate(envelope: Dictionary, from_version: int) -> Dictionary:
	if from_version < 1:
		push_warning("SaveManager: save is version %d, which predates this format." % from_version)
		return {}
	return envelope


func _resolve_slot(slot: StringName) -> StringName:
	return slot if slot != &"" else current_slot


func _unused_key(base: StringName) -> StringName:
	var result := base
	var suffix := 2
	while _key_taken(result):
		result = StringName("%s_%d" % [base, suffix])
		suffix += 1
	return result


func _key_taken(id: StringName) -> bool:
	for entry: Dictionary in _live_participants():
		if entry["key"] == id:
			return true
	return false


## Node path without the /root prefix, which is stable for as long as the node is
## named the same, and readable in the save file. A node that is already detached
## has no path to derive from, which happens while the tree tears down.
func _derive_key(node: Object) -> StringName:
	if node is Node:
		var scene_node := node as Node
		if scene_node.is_inside_tree():
			var path := String(scene_node.get_path())
			if path.begins_with("/root/"):
				path = path.substr("/root/".length())
			if not path.is_empty():
				return StringName(path)
	return StringName(node.get_class())


func _info_from(envelope: Dictionary, slot: StringName) -> Dictionary:
	return {
		"slot": StringName(envelope.get("slot", str(slot))),
		"version": int(envelope.get("version", 0)),
		"game_version": str(envelope.get("game_version", "")),
		"saved_at": str(envelope.get("saved_at", "")),
		"saved_at_unix": int(envelope.get("saved_at_unix", 0)),
	}


func _newer_first(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("saved_at_unix", 0)) > int(b.get("saved_at_unix", 0))


func _game_version() -> String:
	return str(ProjectSettings.get_setting(&"application/config/version", ""))


func _save_on_quit() -> void:
	if _quit_saved or not autosave_enabled or not is_inside_tree():
		return
	_quit_saved = true
	save_game(AUTOSAVE_SLOT)


static func ensure_directory(path: String) -> bool:
	if path.is_empty() or DirAccess.dir_exists_absolute(path):
		return true
	return DirAccess.make_dir_recursive_absolute(path) == OK


## Rename in two steps rather than one: some platforms refuse to rename onto an
## existing file, and clobbering a save on the way is exactly what this avoids.
static func _replace_file(from: String, to: String) -> bool:
	var dir := DirAccess.open(from.get_base_dir())
	if dir == null:
		return false
	if dir.rename(from.get_file(), to.get_file()) == OK:
		return true
	if dir.file_exists(to.get_file()):
		dir.remove(to.get_file())
		return dir.rename(from.get_file(), to.get_file()) == OK
	return false


static func _as_dictionary(value: Variant) -> Dictionary:
	return (value as Dictionary) if value is Dictionary else {}