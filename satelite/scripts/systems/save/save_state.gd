class_name SaveState
extends Node
## Zero-code save participation, plus the property capture [code]SaveManager[/code]
## falls back to for any node that does not implement the contract itself.
##
## Attach it as a child of any node and that node's properties are written on save
## and put back on load, with no script on the node at all:
##
## [codeblock]
## var state := SaveState.new()
## state.save_key = &"player"
## add_child(state)
## [/codeblock]
##
## [b]How much gets captured[/b], from narrowest to widest:
##
## - [member properties], when filled, is the whole list.
## - Otherwise the node's exported properties, which is how this project already
##   configures everything. Predictable, and free of read-only helpers.
## - Otherwise every script variable, when [member include_hidden] is set. This
##   also picks up private caches, which is occasionally what you want and
##   sometimes double counts a value an exported property already holds.
##
## References to other nodes and resources are left out unless
## [member save_resources] is set, and anything [SaveCodec] cannot represent is
## skipped rather than written as a placeholder. Ids the node no longer has are
## ignored on load, so an old save never crashes a new build.
##
## A node that needs to decide for itself - or wants to report state that is not
## a property - implements [code]save_data()[/code] and
## [code]load_data(data)[/code] instead. [code]SaveManager[/code] prefers those
## over this helper, which is what [Satellite] does.

## Ids this node stores under in the save file. Left empty, [code]SaveManager[/code]
## derives one from the node path.
@export var save_key: StringName = &""

## Node whose state is captured. Defaults to the parent, since this node is
## normally added as a child of whatever it is saving.
@export var target_path: NodePath = ^".."

## Whitelist of property names. Empty means "every property that qualifies".
@export var properties: Array[StringName] = []

## Also capture script variables that are not exported.
@export var include_hidden: bool = false

## Also capture [Resource] properties, by resource path. Off by default because
## most resources here are configuration that lives in the scene already.
@export var save_resources: bool = false

var _key: StringName = &""


func _enter_tree() -> void:
	# Looked up by path rather than through the global, the way [Satellite] looks
	# up its own hub, so this script never references the autoload it belongs to.
	var manager := get_node_or_null(^"/root/SaveManager")
	if manager == null or not manager.has_method(&"register"):
		return
	_key = manager.call(&"register", self, save_key)


func _exit_tree() -> void:
	var manager := get_node_or_null(^"/root/SaveManager")
	if manager == null or not manager.has_method(&"unregister"):
		return
	manager.call(&"unregister", self)


## The node whose state is captured, resolved from [member target_path].
func target() -> Object:
	if not target_path.is_empty():
		var found := get_node_or_null(target_path)
		if found != null:
			return found
	return get_parent()


# --- Contract ---------------------------------------------------------------

func save_data() -> Dictionary:
	return capture_properties(target(), options())


func load_data(data: Dictionary) -> void:
	apply_properties(target(), data, options())


func options() -> Dictionary:
	return {
		"properties": properties,
		"include_hidden": include_hidden,
		"save_resources": save_resources,
	}


# --- Static capture ---------------------------------------------------------

## Every qualifying property of [param node], as {property: value}. Values are
## left as they are; [SaveCodec] does the type work later, so a dictionary of this
## shape is safe to print, diff and edit.
static func capture_properties(node: Object, options: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {}
	if node == null:
		return result
	var filter := _filter_for(node, options)
	for info: Dictionary in node.get_property_list():
		var name := StringName(str(info.get(&"name", "")))
		if name == &"" or not _qualifies(info, options):
			continue
		if not filter.is_empty() and not filter.has(name):
			continue
		var value: Variant = node.get(name)
		if not SaveCodec.is_supported(value):
			continue
		result[name] = value
	return result


## Writes [param data] back onto [param node]. Ids that are not properties of this
## node are skipped, so a save written before a rename loads without complaint.
static func apply_properties(node: Object, data: Dictionary, options: Dictionary = {}) -> void:
	if node == null:
		return
	var filter := _filter_for(node, options)
	for key: Variant in data:
		var name := StringName(key)
		if not filter.is_empty() and not filter.has(name):
			continue
		var value: Variant = data[key]
		if value == null or not SaveCodec.is_supported(value):
			continue
		node.set(name, value)


## Property names [param options] would touch on [param node]. An empty result
## means "no whitelist in force", not "nothing qualified", so callers check it
## against the whitelist rather than against emptiness.
static func _filter_for(node: Object, options: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for name: StringName in _string_names(options.get("properties", [])):
		result[name] = true
	return result


static func _qualifies(info: Dictionary, options: Dictionary) -> bool:
	var usage := int(info.get(&"usage", 0))
	if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
		# Engine properties such as "position" are not game state, and Node has
		# hundreds of them.
		return false
	if not bool(options.get("include_hidden", false)) and not (usage & PROPERTY_USAGE_STORAGE):
		return false
	if usage & PROPERTY_USAGE_READ_ONLY:
		# A getter with no setter. Writing it would error at load time.
		return false
	var type := int(info.get(&"type", TYPE_NIL))
	if type == TYPE_CALLABLE or type == TYPE_SIGNAL or type == TYPE_RID:
		return false
	if type == TYPE_OBJECT and not bool(options.get("save_resources", false)):
		return false
	return true


static func _string_names(value: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if value is Array:
		for item: Variant in (value as Array):
			result.append(StringName(item))
	elif value is PackedStringArray:
		for item: Variant in (value as PackedStringArray):
			result.append(StringName(item))
	return result