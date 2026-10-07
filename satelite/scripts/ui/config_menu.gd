extends MenuPanel
## Config menu. Opened by clicking a satellite, and describes the satellite in
## focus: clicking one makes it active the moment the menu opens, and the hub
## is what keeps the two in step, so a screen already open when the focus
## changes reads the new satellite's values rather than stale ones.
##
## A readout, not an editor: it names the satellite being configured, its
## type, and what it carries - where it is, how much memory it has, and
## each antenna's type, count, strength and range. Everything is read
## through the hub, so what is shown is what the satellite has, and what
## the control panel keeps is what is shown.

const CAPTION_COLOR := Color(0.478431, 0.529412, 0.639216, 1)
const VALUE_COLOR := Color(0.85098, 0.890196, 1, 1)
const VALUE_FONT_SIZE := 18

@onready var _list_box: VBoxContainer = get_node_or_null("%List")
@onready var _placeholder: Label = get_node_or_null("%ContentPlaceholder")
@onready var _type_label: Label = get_node_or_null("%Type")

## The fitted-count labels by channel, rewritten on every refresh because
## fitting an antenna changes them.
var _count_labels: Dictionary = {}
var _row_style: StyleBoxFlat = null


func _ready() -> void:
	super()
	_row_style = _make_row_style()
	SatelliteController.active_changed.connect(_on_active_changed)


func _on_open() -> void:
	_refresh()


func _on_active_changed(_satellite: Node) -> void:
	# The satellite in focus is what this screen describes, so a swap while it
	# is open is a new set of values rather than stale ones.
	if is_open:
		_refresh()


# --- Readout -----------------------------------------------------------------

## The whole list, rebuilt on every refresh: the antenna sections are built
## from the active satellite's configuration, so a satellite with another
## set of antennas shows another set of rows. Refreshes happen when the
## menu opens and when the focus moves, never while it is being read.
func _refresh() -> void:
	var satellite := SatelliteController.get_active()
	var config := SatelliteController.config_snapshot()
	var antennas := SatelliteController.antenna_configs()
	if _subtitle_label != null:
		var raw: Variant = satellite.get(&"display_name") if satellite != null else null
		_subtitle_label.text = str(raw) if raw != null else ""
	if _type_label != null:
		_type_label.text = "TYPE: %s" % str(config.get("type", ""))
	if _list_box != null:
		_detach(_list_box)
		_count_labels.clear()
		_add_info("POSITION", _position_text(config.get("position")))
		_add_info("MEMORY", "%d MB" % int(config.get("memory", 0)))
		_build_antenna_rows(antennas)
	for channel: Variant in antennas:
		var entry: Dictionary = antennas[channel]
		var id := StringName(channel)
		var count: Variant = _count_labels.get(id)
		if count is Label:
			(count as Label).text = "x%d" % int(entry.get("count", 0))
	if _placeholder != null:
		_placeholder.visible = satellite == null


## One line of the readout: what it is on the left, what it is on the
## right. A label rather than a spin box, because this screen reports the
## satellite rather than edits it.
func _add_info(caption: String, value: String) -> void:
	var panel := PanelContainer.new()
	if _row_style != null:
		panel.add_theme_stylebox_override(&"panel", _row_style)

	var columns := HBoxContainer.new()
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_theme_constant_override(&"separation", 10)

	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = caption
	label.add_theme_color_override(&"font_color", CAPTION_COLOR)
	columns.add_child(label)

	var value_label := Label.new()
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override(&"font_size", VALUE_FONT_SIZE)
	value_label.add_theme_color_override(&"font_color", VALUE_COLOR)
	value_label.text = value
	columns.add_child(value_label)

	panel.add_child(columns)
	_list_box.add_child(panel)


## One section per antenna: a heading naming its type and how many are
## fitted, then the strength and range that belong to that antenna alone.
## A satellite with no antennas shows nothing here, rather than a section
## of zeros it does not have.
func _build_antenna_rows(antennas: Dictionary) -> void:
	if antennas.is_empty():
		return
	_add_caption("ANTENNAS")
	for channel: Variant in antennas:
		var id := StringName(channel)
		var entry: Dictionary = antennas[channel]
		_add_caption("%s ANTENNA" % str(entry.get("type", id)).to_upper(), id)
		_add_info("STRENGTH", "%d" % int(entry.get("strength", 0)))
		_add_info("RANGE", _number_text(float(entry.get("range", 0.0))))


## A heading on its own, carrying how many antennas are fitted when
## [param channel] is given. The count is a label rather than a value to
## set: it follows the mounts, so it is read here, not chosen here.
func _add_caption(caption: String, channel: StringName = &"") -> void:
	var panel := PanelContainer.new()
	if _row_style != null:
		panel.add_theme_stylebox_override(&"panel", _row_style)

	var columns := HBoxContainer.new()
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_theme_constant_override(&"separation", 10)

	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = caption
	label.add_theme_color_override(&"font_color", CAPTION_COLOR)
	columns.add_child(label)

	if not channel.is_empty():
		var count := Label.new()
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.add_theme_font_size_override(&"font_size", VALUE_FONT_SIZE)
		count.add_theme_color_override(&"font_color", VALUE_COLOR)
		columns.add_child(count)
		_count_labels[channel] = count

	panel.add_child(columns)
	_list_box.add_child(panel)


## Where the satellite is, as the pair the world measures it in.
func _position_text(position: Variant) -> String:
	if not position is Vector2:
		return "-"
	return "(%d, %d)" % [int(position.x), int(position.y)]


## A number as whole when it is one, so a range reads as 4 rather than 4.0.
func _number_text(value: float) -> String:
	if is_equal_approx(value, float(int(value))):
		return "%d" % int(value)
	return String.num(value, 2)


func _make_row_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.117647, 0.129412, 0.172549, 0.858824)
	style.border_color = Color(0.176471, 0.196078, 0.278431, 1)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10.0
	style.content_margin_top = 8.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 8.0
	return style


## Detach before freeing: [method Node.queue_free] only takes the node out of
## the tree at the end of the frame, which would leave the old rows on
## screen under the new ones.
func _detach(box: Node) -> void:
	if box == null:
		return
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()
