extends MenuPanel
## Signals menu: what the satellite's antennas have picked up.
##
## One tab per channel, and under it the list of signals actually found on that
## channel. The tab row is the submenu: picking a tab swaps the list below it, which
## keeps the whole thing on one screen.
##
## [b]Deliberately not separate [code]MenuController[/code] menus.[/b] The controller
## keeps one menu on screen at a time, because [method MenuController.open_menu] hides
## whichever was showing before it opens the next. Making these screens that push each
## other would mean turning that into a stack. Tabs stay local to this scene and cost
## nothing.
##
## Nothing here is hardcoded. The channels come from the control panel's own
## [code]channels[/code] list and the rows come from its [method
## SatelliteControlPanel.findings_for], so the menu keeps up with the satellite without
## knowing what a radio is. A signal that is never detected never appears, because the
## panel is the only thing that decides what has been found.
##
## A row shows the signal's icon, its name, its type, and the signal's own readings -
## frequency, bandwidth, dose rate, whatever that particular signal carries - plus the
## strength it came in at. Every hearing is a row of its own, and each row carries an
## ACCEPT button that hands that one hearing to the downlink, where it can be sent for
## the points the signal is worth.

## Shown when there is no satellite to read.
@export var empty_message: String = "No satellite is selected."

## Shown on a channel that has detected nothing yet. Says so per channel, because an
## empty tab next to a full one is normal while the satellite is still listening.
@export var nothing_found_message: String = "Nothing detected on this channel yet."

## Rows past this are left out, so a chatty channel cannot turn the screen into a wall.
@export_range(1, 32) var max_visible_rows: int = 12

## Which channel's signals are listed. Kept between visits: re-picking a tab every time
## the menu opens is busywork when you came back to the same channel.
var _selected_id: StringName = &""
## The signal to bring into view on the next rebuild, set by [method select_signal] and
## cleared as soon as it has been applied. Not kept: a later rebuild - a new detection, a
## satellite swap - would otherwise drag the list back to a row the player has already
## moved away from.
var _target_signal_id: StringName = &""
## The stylebox for the signal the player arrived from, so it is obvious which row the
## list scrolled to. Built from the plain row style rather than written out separately, so
## the two cannot drift apart.
var _marked_style: StyleBoxFlat = null
## The channel the rows on screen belong to, so a rebuild that has swapped the channel's
## rows underneath the list knows the scroll offset now points at the wrong row.
var _built_id: StringName = &""
## Tab buttons by channel id, used to restore the pressed state and the found count.
var _tabs: Dictionary = {}
var _group: ButtonGroup = null
## Rows are rebuilt rather than diffed, so only the one style is cached.
var _row_style: StyleBoxFlat = null
## The panel currently connected to, so its signals can be unsubscribed when the
## active satellite changes.
var _panel: Node = null

@onready var _tabs_box: HBoxContainer = get_node_or_null("%Tabs")
@onready var _list_box: VBoxContainer = get_node_or_null("%List")
## By path rather than by unique name, because this is the editor's scene and adding a
## unique name to it would mean every save of the scene could conflict with the change.
@onready var _scroll: ScrollContainer = get_node_or_null(^"Panel/Margin/Layout/Scroll")
@onready var _placeholder: Label = get_node_or_null("%ContentPlaceholder")
@onready var _status_label: Label = get_node_or_null("%Status")


func _ready() -> void:
	super()
	if _placeholder and not empty_message.is_empty():
		_placeholder.text = empty_message
	_row_style = _make_row_style()
	SatelliteController.active_changed.connect(_on_active_changed)
	_bind_panel()
	_rebuild()


func _on_open() -> void:
	_set_status("")
	_apply_tab_state()
	_rebuild()


## Picks the tab [param channel] belongs to and scrolls [param signal_id] into view, so
## a signal picked from the event log lands on its own row rather than on the top of the
## tab. Both are optional; an unknown or empty id is left to the rebuild to correct, which
## falls back to the first tab listed.
##
## Public because the event log steers this from a line the player clicked, and it calls
## this before opening the menu, so the opening rebuild lands on the right tab with the
## right row in view.
func select_signal(channel: StringName, signal_id: StringName = &"") -> void:
	_selected_id = channel
	_target_signal_id = signal_id


# --- Panel ------------------------------------------------------------------

## The active satellite's control panel, or null when there is no satellite or it has
## none. Looked up by path rather than through the hub because the control panel is not
## part of [Satellite]'s outward contract - it declares no [code]class_name[/code] and
## the aggregate does not republish it. That also means nothing here needs to change if
## the panel is later given a class of its own.
func _control_panel() -> Node:
	var satellite := SatelliteController.get_active()
	if satellite == null:
		return null
	return satellite.get_node_or_null(^"Control-Panel")


## Subscribes to the panel's findings. Re-subscribing rather than connecting per
## rebuild, so switching satellites does not leave the old panel talking to a menu that
## no longer belongs to it.
func _bind_panel() -> void:
	if _panel != null and _panel.has_signal(&"signal_found"):
		if _panel.is_connected(&"signal_found", _on_signal_found):
			_panel.disconnect(&"signal_found", _on_signal_found)
		if _panel.is_connected(&"signals_changed", _on_signals_changed):
			_panel.disconnect(&"signals_changed", _on_signals_changed)
	_panel = _control_panel()
	if _panel != null and _panel.has_signal(&"signal_found"):
		_panel.connect(&"signal_found", _on_signal_found)
		_panel.connect(&"signals_changed", _on_signals_changed)


# --- Tabs -------------------------------------------------------------------

func _rebuild_tabs(tabs: Array) -> void:
	if _tabs_box == null:
		return
	_detach(_tabs_box)
	_tabs.clear()
	# A group rather than per-button state: it keeps exactly one tab pressed for free,
	# including when a channel is selected from somewhere other than a click.
	_group = ButtonGroup.new()
	for entry: Dictionary in tabs:
		var id := StringName(entry.get("id", &""))
		var tab := Button.new()
		tab.toggle_mode = true
		tab.button_group = _group
		tab.text = _tab_label(entry)
		tab.tooltip_text = str(entry.get("caption", ""))
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(_on_tab_pressed.bind(id))
		_tabs_box.add_child(tab)
		_tabs[id] = tab
	_apply_tab_state()


## Found count on the tab, so a channel with something on it is obvious without opening
## it. Hidden when nothing has been found, rather than showing a zero on every tab.
func _tab_label(entry: Dictionary) -> String:
	var label := str(entry.get("label", ""))
	var found := int(entry.get("found", 0))
	var total := int(entry.get("total", 0))
	if found <= 0:
		return label
	if total > 0 and found >= total:
		return "%s  %d/%d" % [label, found, total]
	return "%s  %d" % [label, found]


func _apply_tab_state() -> void:
	for key: Variant in _tabs:
		var tab: Variant = _tabs[key]
		if tab is Button:
			(tab as Button).set_pressed_no_signal(StringName(key) == _selected_id)


func _on_tab_pressed(id: StringName) -> void:
	if id.is_empty() or id == _selected_id:
		return
	_selected_id = id
	_set_status("")
	_rebuild()


# --- Findings ---------------------------------------------------------------

func _rebuild() -> void:
	if _list_box == null:
		return
	_bind_panel()
	_detach(_list_box)
	if _placeholder:
		_placeholder.visible = _panel == null
	if _panel == null:
		return

	var tabs: Array = _panel.call(&"channel_tabs")
	_rebuild_tabs(tabs)
	# A channel that has gone - a satellite swap, or a channel removed from the panel -
	# cannot stay selected, so the pick falls back to the first one listed.
	if not _tabs.has(_selected_id):
		_selected_id = StringName((tabs[0] as Dictionary).get("id", &"")) if not tabs.is_empty() else &""
		_apply_tab_state()

	var findings: Array = _panel.call(&"findings_for", _selected_id)
	# The cap decides how many rows exist at all, so a signal past its end would not merely
	# be off screen - it would not be there to scroll to. The window is centred on the
	# wanted signal rather than starting on it, so there is context on both sides and the
	# scroll below has room to put it in the middle without running off the end.
	var first: int = 0
	if not _target_signal_id.is_empty():
		var wanted: int = _index_of(findings, _target_signal_id)
		first = clampi(wanted - max_visible_rows / 2, 0, maxi(findings.size() - max_visible_rows, 0))

	# Different rows are on screen now, so an offset carried over from the last channel
	# would leave the list scrolled past rows that are no longer there. A pending target
	# sets its own offset at the end of this, and a rebuild that only adds to the same
	# channel keeps the offset so a new detection does not yank the view.
	if _selected_id != _built_id:
		if _scroll != null:
			_scroll.scroll_vertical = 0
		_built_id = _selected_id

	var shown := 0
	for index: int in range(first, findings.size()):
		if shown >= max_visible_rows:
			break
		_list_box.add_child(_build_row(findings[index]))
		shown += 1

	if findings.is_empty():
		_add_nothing_found()
	elif first + shown < findings.size():
		_add_more(int(findings.size()) - first - shown)

	_apply_target()


## Brings the signal the player arrived from into view, then forgets it so the next rebuild
## leaves the list where they left it. A no-op on an ordinary rebuild.
func _apply_target() -> void:
	if _target_signal_id.is_empty():
		return
	var wanted := _target_signal_id
	_target_signal_id = &""
	var row: Control = _row_for(wanted)
	if row == null:
		return
	row.add_theme_stylebox_override(&"panel", _make_marked_row_style())
	_scroll_to(row)


## Position of the finding with this id in the rows as the panel lists them, or -1.
func _index_of(findings: Array, signal_id: StringName) -> int:
	for index: int in findings.size():
		var row: Dictionary = findings[index]
		if StringName(row.get("id", &"")) == signal_id:
			return index
	return -1


## The row on screen for this signal, or null when it is not one of the rows built.
func _row_for(signal_id: StringName) -> Control:
	if _list_box == null:
		return null
	for child in _list_box.get_children():
		if child is Control and StringName(child.get_meta(&"signal_id", &"")) == signal_id:
			return child
	return null


## Scrolls so [param row] sits in the middle of the list, deferred, because the container
## has not been laid out since the rebuild and asking for a position now would use the one
## the rows had before they existed.
func _scroll_to(row: Control) -> void:
	if _scroll == null or row == null:
		return
	_scroll_later.call_deferred(row)


func _scroll_later(row: Control) -> void:
	await get_tree().process_frame
	if _scroll == null or not is_inside_tree() or not is_instance_valid(row):
		return
	# Centred rather than aligned to the top, so the rows around it give some context
	# about where in the channel this signal sits.
	var target: float = row.position.y + row.size.y * 0.5 - _scroll.size.y * 0.5
	_scroll.scroll_vertical = int(maxf(target, 0.0))


## The row style for the signal the player came from. Derived from the plain row style so
## the two always match apart from the highlight.
func _make_marked_row_style() -> StyleBoxFlat:
	if _marked_style == null:
		_marked_style = _make_row_style()
		_marked_style.bg_color = _marked_style.bg_color.lightened(0.14)
		_marked_style.border_color = Color(0.478431, 0.533333, 0.701961, 0.784314)
	return _marked_style


func _build_row(row: Dictionary) -> Control:
	var panel := PanelContainer.new()
	if _row_style != null:
		panel.add_theme_stylebox_override(&"panel", _row_style)
	# So the row a signal arrived on can be found again and scrolled to, without this file
	# having to match rows up against the list order.
	panel.set_meta(&"signal_id", StringName(row.get("id", &"")))

	var columns := HBoxContainer.new()
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_theme_constant_override(&"separation", 10)

	# Optional, and laid out without it: a signal works before any art exists, and the
	# catalogue entry carries the slot so a texture can be dropped in later.
	var icon: Variant = row.get("icon")
	if icon is Texture2D:
		var picture := TextureRect.new()
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.texture = icon
		picture.custom_minimum_size = Vector2(32, 32)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		columns.add_child(picture)

	var info := VBoxContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override(&"separation", 2)

	var title := HBoxContainer.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_constant_override(&"separation", 6)

	var name_label := Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = str(row.get("display_name", "Signal"))
	title.add_child(name_label)

	var signal_type := StringName(row.get("signal_type", &""))
	if signal_type != &"":
		title.add_child(_tag(str(signal_type).to_upper()))

	info.add_child(title)

	var details := _details_text(row.get("details", {}))
	if not details.is_empty():
		var readings := Label.new()
		readings.mouse_filter = Control.MOUSE_FILTER_IGNORE
		readings.text = details
		readings.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		readings.add_theme_color_override(&"font_color", Color(0.560784, 0.607843, 0.717647, 1))
		info.add_child(readings)

	var description := str(row.get("description", ""))
	if not description.is_empty():
		var detail := Label.new()
		detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		detail.text = description
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.add_theme_color_override(&"font_color", Color(0.478431, 0.529412, 0.639216, 1))
		info.add_child(detail)

	columns.add_child(info)

	var accept := _accept_button(row)
	if accept != null:
		columns.add_child(accept)

	panel.add_child(columns)
	return panel


## The button that hands this hearing to the downlink. One
## per row rather than one per list, because a hearing is
## accepted where it is listed. Disabled once accepted: a
## hearing is accepted once, and the downlink is where it
## goes from there.
func _accept_button(row: Dictionary) -> Button:
	var key := StringName(row.get("key", &""))
	if key.is_empty():
		return null
	var accepted := bool(row.get("accepted", false))
	var button := Button.new()
	button.text = "ACCEPTED" if accepted else "ACCEPT"
	button.disabled = accepted
	button.tooltip_text = "Already handed to the downlink." if accepted \
		else "Hand this signal to the downlink, where it can be sent for points."
	button.pressed.connect(_on_accept_pressed.bind(key, _selected_id))
	return button


## The signal's own readings, in the order the definition declared them, so a carrier
## reads frequency then bandwidth rather than alphabetically.
func _details_text(details: Variant) -> String:
	if not (details is Dictionary):
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for key: Variant in details:
		parts.append("%s %s" % [str(key), str(details[key])])
	return "  ·  ".join(parts)


func _tag(text: String) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.add_theme_color_override(&"font_color", Color(0.478431, 0.529412, 0.639216, 1))
	return label


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


## Detach before freeing: [method Node.queue_free] only takes the node out of the tree
## at the end of the frame, which would leave the old rows on screen under the new ones.
func _detach(box: Node) -> void:
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _add_nothing_found() -> void:
	if _list_box == null or nothing_found_message.is_empty():
		return
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = nothing_found_message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override(&"font_color", Color(0.560784, 0.607843, 0.717647, 1))
	_list_box.add_child(label)


## Rows past [member max_visible_rows], said plainly rather than silently dropped.
func _add_more(hidden: int) -> void:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = "and %d more" % hidden
	label.add_theme_color_override(&"font_color", Color(0.478431, 0.529412, 0.639216, 1))
	_list_box.add_child(label)


func _set_status(text: String) -> void:
	if _status_label:
		_status_label.text = text


## Accepting a hearing asks the panel, which owns the
## findings. The panel announces it through
## [code]signals_changed[/code], so the list rebuilds
## with the row showing ACCEPTED and the downlink has
## the signal without this menu knowing anything about it.
func _on_accept_pressed(key: StringName, channel: StringName) -> void:
	if _panel == null or key.is_empty() or channel.is_empty():
		return
	var accepted: Variant = _panel.call(&"accept_finding", channel, key)
	_set_status("Accepted. It has gone to the downlink." if accepted \
		else "That one is already accepted.")


# --- Signals ----------------------------------------------------------------

func _on_signal_found(_channel: StringName, _found: Resource, _count: int) -> void:
	_rebuild()


func _on_signals_changed() -> void:
	_rebuild()


func _on_active_changed(_satellite: Node) -> void:
	# A different satellite has a different panel and a different catalogue, so a pick
	# from the old one is meaningless now.
	_selected_id = &""
	_built_id = &""
	_bind_panel()
	_rebuild()