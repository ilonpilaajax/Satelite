class_name SatelliteAppearance
extends Node
## How the satellite looks, as data rather than code.
##
## Values are grouped into named states, so a visual preset is one dictionary and
## the "which one is active" question is a single [method set_state] call. Targets
## are optional: assign [member tint_targets] / [member scale_targets] and the
## component drives them, or leave them empty and it just tracks state for whoever
## wants to read it. Keys it does not know are still stored, so effects from
## upgrades and other systems can pass anything through.

signal appearance_changed(snapshot: Dictionary)

## Named visual presets, e.g. {&"idle": {"tint": Color.WHITE, "scale": 1.0, "visible": true}}.
@export var states: Dictionary = {
	&"idle": {"tint": Color.WHITE, "scale": 1.0, "visible": true},
}

## State applied on ready.
@export var default_state: StringName = &"idle"

## Optional. [Node2D] or [Control] nodes driven by the current state's
## "tint", "scale" and "visible" keys.
@export var tint_targets: Array[NodePath] = []
@export var scale_targets: Array[NodePath] = []

var _visuals: Dictionary = {}


func _ready() -> void:
	if not states.is_empty():
		set_state(default_state)


## Switches to a named preset from [member states]. Unknown keys are ignored.
func set_state(key: StringName) -> void:
	var state: Variant = states.get(key)
	if not (state is Dictionary):
		push_warning("SatelliteAppearance: no state called '%s'." % key)
		return
	_visuals = (state as Dictionary).duplicate()
	_apply()
	appearance_changed.emit(snapshot())


## Sets one visual key, e.g. [code]set_visual(&"tint", Color.RED)[/code].
func set_visual(key: StringName, value: Variant) -> void:
	_visuals[key] = value
	_apply()
	appearance_changed.emit(snapshot())


## Bulk version of [method set_visual], used by upgrade appearance effects.
func set_visuals(values: Dictionary) -> void:
	for key: Variant in values:
		_visuals[StringName(key)] = values[key]
	_apply()
	appearance_changed.emit(snapshot())


## Replaces the tracked visuals with [param values] instead of merging into them,
## so a key the save no longer mentions really goes away. That is what restoring a
## save needs; [method set_visuals] is the one that layers changes on top.
func restore(values: Dictionary) -> void:
	_visuals = values.duplicate(true)
	_apply()
	appearance_changed.emit(snapshot())


func get_visual(key: StringName, fallback: Variant = null) -> Variant:
	return _visuals.get(key, fallback)


## Current visuals, safe to send over the satellite's outward contract.
func snapshot() -> Dictionary:
	return _visuals.duplicate()


func _apply() -> void:
	var tint: Variant = _visuals.get(&"tint")
	var scale_value: Variant = _visuals.get(&"scale")
	var visible_value: Variant = _visuals.get(&"visible")
	var has_scale := scale_value is float or scale_value is int

	for path: NodePath in tint_targets:
		var target := get_node_or_null(path)
		if not (target is CanvasItem):
			continue
		if tint is Color:
			(target as CanvasItem).modulate = tint
		if visible_value is bool:
			(target as CanvasItem).visible = visible_value

	for path: NodePath in scale_targets:
		var target := get_node_or_null(path)
		if not (target is CanvasItem):
			continue
		if target is Node2D and has_scale:
			(target as Node2D).scale = Vector2.ONE * float(scale_value)
		elif target is Control and has_scale:
			(target as Control).pivot_offset = (target as Control).size * 0.5
			(target as Control).scale = Vector2.ONE * float(scale_value)
		if visible_value is bool:
			(target as CanvasItem).visible = visible_value
