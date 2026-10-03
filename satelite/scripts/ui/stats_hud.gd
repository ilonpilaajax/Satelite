extends CanvasLayer
## Top-of-screen readout, built from whatever the active satellite actually
## tracks.
##
## Nothing here is hardcoded. The satellite's [SatelliteStats] hands over one
## descriptor per stat - id, caption, unit, precision, value, and an optional second
## unit already converted - and the bar builds a cell for each. Adding a stat to a
## satellite makes it appear here with no change to this script; captions, units and
## the conversion between them come from the satellite's [code]stat_meta[/code], so the
## formatting lives next to the definition rather than in the UI.
##
## The only thing this script knows about the satellite layer is one method on
## the hub and two signals, so the readout keeps working for any satellite.
##
## Sits on layer 10: above the default canvas, below [code]MenuController[/code].

const CAPTION_COLOR := Color(0.478431, 0.529412, 0.639216, 1)
const VALUE_COLOR := Color(0.85098, 0.890196, 1, 1)
const CAPTION_FONT_SIZE := 10
const VALUE_FONT_SIZE := 16

## Reads from [code]SatelliteController[/code] instead of being fed by hand.
@export var follow_active_satellite: bool = true

## Cells per row. Lower it when a satellite tracks many stats so the bar grows
## downwards instead of squeezing every caption.
@export_range(1, 4) var columns: int = 2

@onready var _top_bar: PanelContainer = $TopBar
@onready var _grid: GridContainer = $TopBar/Grid

var _value_labels: Dictionary = {}
var _current_ids: Array = []


func _ready() -> void:
	_top_bar.visible = false
	_grid.columns = columns
	if follow_active_satellite:
		SatelliteController.active_changed.connect(_on_active_changed)
		SatelliteController.stats_changed.connect(_on_stats_changed)
		_refresh(SatelliteController.stat_descriptors())


## Pushes an explicit list of descriptors, bypassing the hub. For tooling and tests.
func set_descriptors(descriptors: Array) -> void:
	_refresh(descriptors)


func _on_active_changed(_satellite: Node) -> void:
	_refresh(SatelliteController.stat_descriptors())


func _on_stats_changed(_snapshot: Dictionary) -> void:
	_refresh(SatelliteController.stat_descriptors())


## Rebuilds the cells only when the set of stats changed; otherwise this just
## rewrites text, so a value ticking every frame allocates nothing.
func _refresh(descriptors: Array) -> void:
	var ids: Array = []
	for descriptor: Variant in descriptors:
		if descriptor is Dictionary:
			ids.append((descriptor as Dictionary).get("id"))

	if ids != _current_ids:
		_rebuild(descriptors)
		_current_ids = ids

	for descriptor: Variant in descriptors:
		if not (descriptor is Dictionary):
			continue
		var data: Dictionary = descriptor
		var label: Variant = _value_labels.get(data.get("id"))
		if label is Label:
			(label as Label).text = _format(data)

	_top_bar.visible = not _current_ids.is_empty()


## Cells are detached before being freed. [method Node.queue_free] would leave
## them in the container until the end of the frame, and the bar sizes itself from
## its content, so it would briefly measure the old and new cells together.
func _rebuild(descriptors: Array) -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_value_labels.clear()

	for descriptor: Variant in descriptors:
		if descriptor is Dictionary:
			_add_cell(descriptor as Dictionary)


func _add_cell(descriptor: Dictionary) -> void:
	var cell := VBoxContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var caption := Label.new()
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.text = str(descriptor.get("caption", ""))
	caption.add_theme_font_size_override(&"font_size", CAPTION_FONT_SIZE)
	caption.add_theme_color_override(&"font_color", CAPTION_COLOR)

	var value := Label.new()
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value.clip_text = true
	value.text = _format(descriptor)
	value.add_theme_font_size_override(&"font_size", VALUE_FONT_SIZE)
	value.add_theme_color_override(&"font_color", VALUE_COLOR)

	cell.add_child(caption)
	cell.add_child(value)
	_grid.add_child(cell)
	_value_labels[descriptor.get("id")] = value


## Renders a stat as its secondary unit first, then its own: "0.00000006 AU / 9 km".
## The secondary unit comes first because that is the order the readout was asked for,
## and because a stat with a secondary unit is being read at two scales at once, coarse
## to fine.
##
## The secondary block is derived from the same tracked value the primary one shows,
## computed by [SatelliteStats], so the two can never disagree. A readout with no
## secondary unit is unchanged and shows only its own.
func _format(descriptor: Dictionary) -> String:
	var primary := _format_in(descriptor.get("value"), str(descriptor.get("unit", "")), int(descriptor.get("decimals", 1)))
	var secondary: Variant = descriptor.get("secondary")
	if not (secondary is Dictionary):
		return primary
	var alt: Dictionary = secondary
	var alt_unit := str(alt.get("unit", ""))
	if alt_unit.is_empty():
		return primary
	return "%s / %s" % [_format_in(alt.get("value"), alt_unit, int(alt.get("decimals", 1))), primary]


func _format_in(value: Variant, unit: String, decimals: int) -> String:
	var text: String
	if value is float:
		text = String.num(float(value), decimals)
	elif value is int:
		text = str(value)
	else:
		text = str(value)
	return "%s %s" % [text, unit] if not unit.is_empty() else text
