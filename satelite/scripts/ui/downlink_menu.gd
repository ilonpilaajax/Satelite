extends MenuPanel
## Downlink: the list of data the satellite can send back to Earth.
##
## One [b]SEND[/b] button and a list. A row is picked, then sent, rather than each
## row carrying its own button, because the list is what you read while deciding and
## the button is the one commitment at the end.
##
## Rows are built from [code]SatelliteController.downlink_catalogue[/code] rather
## than from a list written out here, so a packet added to
## [member SatelliteDownlink.packets] shows up already sized and already resolved.
## This script never decides whether a send is allowed: [SatelliteDownlink] does, and
## the row only reports the reason it handed back.
##
## Opened from the access bar; the game keeps running behind it because this screen
## is not in [code]MenuController.PAUSING_MENUS[/code]. That is deliberate - the
## distance keeps accruing while you decide what is worth spending it on.
##
## [b]The catalogue ships empty[/b], because nothing collects data yet, so the empty
## state is the normal state and the send button is dead until something is listed.
## That is not a placeholder here: drop a [DataPacketDefinition] into the satellite
## and the row appears, no change to this script.

## Shown when the satellite has no packets listed at all.
@export var empty_message: String = "Nothing to send yet. Nothing has been collected, and no signal has been accepted."

## Shown when the satellite has packets but the one picked has already gone down.
@export var nothing_selected_message: String = "Pick something from the list to send it."

## Rows past this are left out, so a large catalogue cannot turn the screen into a
## wall. The menu is meant to be browsed with the game running behind it.
@export_range(1, 32) var max_visible_rows: int = 8

## Colour of the border on the picked row. Only the selection is coloured; the rest
## of the row uses the same style every time.
const SELECTION_COLOR := Color(0.478431, 0.741176, 0.968627, 1)

## Which packet the SEND button would send. Empty means nothing is picked.
var _selected_id: StringName = &""
## Rows are kept between selection changes so picking one does not rebuild the list:
## a rebuild frees the button that was just pressed and takes the keyboard focus with
## it, which would drop a keyboard user back at the top of the screen every press.
var _row_panels: Dictionary = {}
var _row_hits: Dictionary = {}
## Rows are rebuilt rather than diffed, so only the two styles are cached between
## rebuilds.
var _row_style: StyleBoxFlat = null
var _selected_style: StyleBoxFlat = null

@onready var _list_box: VBoxContainer = get_node_or_null("%List")
@onready var _placeholder: Label = get_node_or_null("%ContentPlaceholder")
@onready var _totals_label: Label = get_node_or_null("%Totals")
@onready var _status_label: Label = get_node_or_null("%Status")
@onready var _send_button: Button = get_node_or_null("%SendButton")


func _ready() -> void:
	super()
	if _placeholder and not empty_message.is_empty():
		_placeholder.text = empty_message
	_row_style = _make_row_style(Color(0.176471, 0.196078, 0.278431, 1))
	_selected_style = _make_row_style(SELECTION_COLOR)
	SatelliteController.downlink_changed.connect(_on_downlink_changed)
	SatelliteController.active_changed.connect(_on_active_changed)
	if _send_button:
		_send_button.pressed.connect(_on_send_pressed)
	_rebuild()


func _on_open() -> void:
	_set_status("")
	# The pick is not remembered between visits: what was worth sending and what is
	# now may not be the same thing, and a stale highlight on a list the player has
	# not looked at yet is worse than no highlight.
	_selected_id = &""
	_rebuild()


# --- Rows -------------------------------------------------------------------

## Rebuilds the list from the catalogue as it stands. Unconditional: the catalogue is
## a handful of rows and every thing that can change one says so, so there is no
## signature worth checking and nothing to save by skipping. Picking a row does
## [b]not[/b] come through here, only a send, a new catalogue or a new satellite.
func _rebuild() -> void:
	if _list_box == null:
		return
	_refresh_totals()
	_detach_rows()

	var catalogue := SatelliteController.downlink_catalogue()
	var shown := 0
	for row: Dictionary in catalogue:
		if shown >= max_visible_rows:
			break
		var panel := _build_row(row)
		_list_box.add_child(panel)
		_row_panels[StringName(row.get("id", &""))] = panel
		shown += 1

	# A pick that the new catalogue no longer contains cannot be sent, so it is
	# dropped rather than left selecting nothing.
	if not _row_panels.has(_selected_id):
		_selected_id = &""
	_apply_selection_styles()
	if _placeholder:
		_placeholder.visible = catalogue.is_empty()
	_sync_send_button()
	_restore_focus()


## Moves the highlight. Called on every pick, so it has to work from the row map
## rather than from a rebuild.
func _apply_selection_styles() -> void:
	for key: Variant in _row_panels:
		var panel: Variant = _row_panels[key]
		if panel is PanelContainer:
			(panel as PanelContainer).add_theme_stylebox_override(
				&"panel", _selected_style if StringName(key) == _selected_id else _row_style)


## Puts the keyboard focus back on the row that had it. [method _detach_rows] frees
## the focused node, and Godot hands focus to nothing rather than to a neighbour, so a
## rebuild triggered by a send would otherwise dump a keyboard user out of the list.
func _restore_focus() -> void:
	if not is_open or _selected_id.is_empty():
		return
	var hit: Variant = _row_hits.get(_selected_id)
	if hit is Button and (hit as Button).has_focus():
		return
	# Only reclaim focus when it would otherwise be lost, so pressing SEND keeps the
	# focus on the button the player just used.
	if get_viewport().gui_get_focus_owner() == null and hit is Button:
		(hit as Button).grab_focus()


func _build_row(row: Dictionary) -> Control:
	var packet_id := StringName(row.get("id", &""))

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", _row_style)

	# Added first so it sits *behind* the labels, which are all mouse-transparent.
	# That is what makes the whole row clickable rather than just its title, and it
	# keeps the row reachable by keyboard because this is a real focusable button.
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_ALL
	hit.tooltip_text = _tooltip_for(row)
	hit.pressed.connect(_on_row_pressed.bind(packet_id))
	_row_hits[packet_id] = hit
	panel.add_child(hit)

	var columns := HBoxContainer.new()
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_theme_constant_override(&"separation", 8)

	var info := VBoxContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override(&"separation", 2)

	var title := HBoxContainer.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_constant_override(&"separation", 6)

	var icon: Variant = row.get("icon")
	if icon is Texture2D:
		var picture := TextureRect.new()
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.texture = icon
		picture.custom_minimum_size = Vector2(28, 28)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		title.add_child(picture)

	var name_label := Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = str(row.get("display_name", "Data"))
	title.add_child(name_label)

	var category := StringName(row.get("category", &""))
	if category != &"":
		title.add_child(_tag(str(category).to_upper()))

	info.add_child(title)

	var description := str(row.get("description", ""))
	if not description.is_empty():
		var detail := Label.new()
		detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		detail.text = description
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.add_theme_color_override(&"font_color", Color(0.560784, 0.607843, 0.717647, 1))
		info.add_child(detail)

	var reason := _reason_text(row)
	if not reason.is_empty():
		var note := Label.new()
		note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		note.text = reason
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_color_override(&"font_color", Color(0.85098, 0.552941, 0.396078, 1))
		info.add_child(note)

	columns.add_child(info)

	var figures := VBoxContainer.new()
	figures.mouse_filter = Control.MOUSE_FILTER_IGNORE
	figures.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	figures.add_theme_constant_override(&"separation", 2)
	figures.add_child(_figure(str(row.get("size", 0)), str(row.get("unit", ""))))
	var sent_label := str(row.get("sent_label", ""))
	if not sent_label.is_empty():
		figures.add_child(_tag(sent_label))
	columns.add_child(figures)

	panel.add_child(columns)
	return panel


## Shared by every row, so fitting eight packets does not build eight identical
## styles. The selection differs only in border colour, which is what keeps the list
## readable when one row is picked.
func _make_row_style(border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.117647, 0.129412, 0.172549, 0.858824)
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10.0
	style.content_margin_top = 8.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 8.0
	return style


## Detach before freeing: [method Node.queue_free] only takes the node out of the
## tree at the end of the frame, which would leave the old rows on screen under the
## new ones for a frame.
func _detach_rows() -> void:
	_row_panels.clear()
	_row_hits.clear()
	for child: Node in _list_box.get_children():
		_list_box.remove_child(child)
		child.queue_free()


# --- Figures ----------------------------------------------------------------

func _tag(text: String) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.add_theme_color_override(&"font_color", Color(0.478431, 0.529412, 0.639216, 1))
	return label


## Size on the right, in the unit [SatelliteDownlink] counts it in.
func _figure(value: Variant, unit: String) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.text = "%s %s" % [value, unit] if not unit.is_empty() else str(value)
	return label


## How much has gone down so far. Hidden entirely when the satellite has no downlink
## module, rather than showing a row of zeroes.
func _refresh_totals() -> void:
	if _totals_label == null:
		return
	var totals := SatelliteController.downlink_totals()
	if totals.is_empty():
		_totals_label.text = ""
		return
	var transmissions := int(totals.get("transmissions", 0))
	_totals_label.text = "SENT  %d   %d %s" % [
		transmissions,
		int(totals.get("volume", 0)),
		str(totals.get("unit", "")),
	]


## Why a row's send is refused, phrased for a player rather than as a constant.
func _reason_text(row: Dictionary) -> String:
	match StringName(row.get("reason", &"")):
		&"exhausted", &"sent":
			return "Already sent. There is no more of this."
		&"sending":
			return "Transmission in progress. The points arrive when it lands."
	return ""


func _tooltip_for(row: Dictionary) -> String:
	if StringName(row.get("kind", &"packet")) == &"signal":
		if bool(row.get("can_send", false)):
			return "Send this signal. %d points arrive when it lands." % int(row.get("size", 0))
		return _reason_text(row)
	var sent := str(row.get("sent_label", ""))
	if sent.is_empty():
		return "Pick this to send it."
	return "%s - %s" % [sent, "pick this to send it again" if bool(row.get("can_send", false)) else _reason_text(row).to_lower()]


func _set_status(text: String) -> void:
	if _status_label:
		_status_label.text = text


# --- Input ------------------------------------------------------------------

func _on_row_pressed(packet_id: StringName) -> void:
	if packet_id.is_empty():
		return
	# Pressing the picked row again puts it down, which is the usual way out of a
	# selection without reaching for the keyboard.
	_selected_id = packet_id if packet_id != _selected_id else &""
	_set_status("")
	# Restyled rather than rebuilt: rebuilding would free the very button that was
	# just pressed, and with it the keyboard focus.
	_apply_selection_styles()
	_sync_send_button()


func _on_send_pressed() -> void:
	if _selected_id.is_empty():
		_set_status(nothing_selected_message)
		return
	var row := _row_of(_selected_id)
	if row.is_empty():
		_set_status(nothing_selected_message)
		return
	if not bool(row.get("can_send", false)):
		_set_status(_reason_text(row))
		return
	if SatelliteController.transmit_data(_selected_id):
		if StringName(row.get("kind", &"packet")) == &"signal":
			# A signal's send takes time, so what the player did was start
			# it; the points turn up when the transmission lands.
			_set_status("Sending %s. The points arrive when it lands." % str(row.get("display_name", "signal")))
		else:
			_set_status("Sent %s." % str(row.get("display_name", "data")))
	else:
		_set_status("Could not send that.")


## The catalogue row for the current pick, or an empty dictionary when the pick no
## longer exists - a packet removed from the scene while it was selected.
func _row_of(packet_id: StringName) -> Dictionary:
	for row: Dictionary in SatelliteController.downlink_catalogue():
		if StringName(row.get("id", &"")) == packet_id:
			return row
	return {}


## The send button is live only for a picked row that may actually go down, which is
## what makes it visibly dead while the list is empty.
func _sync_send_button() -> void:
	if _send_button == null:
		return
	_send_button.disabled = _selected_id.is_empty() or not bool(_row_of(_selected_id).get("can_send", false))


# --- Signals ----------------------------------------------------------------

## A packet went down or the catalogue changed. [code]downlink_changed[/code] fires
## for both, so this is the only refresh this menu needs: it reports the outcome of a
## send, and it clears the list when the catalogue empties.
func _on_downlink_changed() -> void:
	_rebuild()


func _on_active_changed(_satellite: Node) -> void:
	# A different satellite has a different catalogue, so a pick from the old one is
	# meaningless now.
	_selected_id = &""
	_rebuild()