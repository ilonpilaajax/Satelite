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
## Shows only the stats whose [code]stat_meta[/code] asks to be on the hud. The stats
## menu lists the rest, and the two split the set between them rather than each keeping
## a list, so a stat cannot turn up in both or in neither. That is what keeps this bar
## to the handful of numbers worth seeing without opening a menu.
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

## Cells per row. The bar reads as one line of numbers along the top, so this is set to
## the number of stats that fit there and lowered only when a satellite tracks enough to
## make the captions squeeze - at which point the bar grows downwards instead.
@export_range(1, 4) var columns: int = 3

@onready var _top_bar: PanelContainer = $TopBar
@onready var _grid: GridContainer = $TopBar/Grid

var _value_labels: Dictionary = {}
var _current_ids: Array = []


func _ready() -> void:
	_top_bar.visible = false
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
	# Filtered first, so the "did the set change" test below compares like with like: a
	# satellite that only moves stats between the bar and the menu rebuilds exactly once.
	var shown := _bar_descriptors(descriptors)
	var ids: Array = []
	for descriptor: Variant in shown:
		if descriptor is Dictionary:
			ids.append((descriptor as Dictionary).get("id"))

	if ids != _current_ids:
		_rebuild(shown)
		_current_ids = ids

	for descriptor: Variant in shown:
		if not (descriptor is Dictionary):
			continue
		var data: Dictionary = descriptor
		var label: Variant = _value_labels.get(data.get("id"))
		if label is Label:
			(label as Label).text = SatelliteStats.format_value(data)

	_top_bar.visible = not _current_ids.is_empty()


## The descriptors this bar is responsible for: the ones whose [code]stat_meta[/code]
## asks for the hud. Everything else is the stats menu's, which is what stops a stat
## being listed twice.
func _bar_descriptors(descriptors: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for descriptor: Variant in descriptors:
		if descriptor is Dictionary and bool((descriptor as Dictionary).get("hud", false)):
			result.append(descriptor as Dictionary)
	return result


## Cells are detached before being freed. [method Node.queue_free] would leave
## them in the container until the end of the frame, and the bar sizes itself from
## its content, so it would briefly measure the old and new cells together.
func _rebuild(descriptors: Array) -> void:
	# Never more columns than there are cells: a grid left at three columns with two
	# numbers in it leaves a hole at the end of the row, so the bar reads as padded out
	# rather than as the numbers it has.
	_grid.columns = maxi(mini(columns, descriptors.size()), 1)

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
	# The same formatter the stats menu uses, so a number cannot read differently in the
	# two places it appears. See [method SatelliteStats.format_value].
	value.text = SatelliteStats.format_value(descriptor)
	value.add_theme_font_size_override(&"font_size", VALUE_FONT_SIZE)
	value.add_theme_color_override(&"font_color", VALUE_COLOR)

	cell.add_child(caption)
	cell.add_child(value)
	_grid.add_child(cell)
	_value_labels[descriptor.get("id")] = value
