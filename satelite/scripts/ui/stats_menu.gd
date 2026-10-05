extends MenuPanel
## Stats menu. Opened from the access bar; the game keeps running behind it
## because this screen is not in [code]MenuController.PAUSING_MENUS[/code]. Close
## returns to the game.
##
## The detail the top bar has no room for, one submenu per subject: the bar carries the
## handful of numbers worth seeing without opening anything, and this screen lists
## everything else, grouped by the [code]tab[/code] a stat names in its
## [code]stat_meta[/code].
##
## Which is which is decided by the satellite, not here. A stat whose [code]stat_meta[/code]
## asks for the hud goes on the bar; everything else lands here, under a tab named by the
## same metadata. The two readouts therefore split the set rather than each keeping a list
## of their own, so a stat cannot end up shown twice or not at all, and adding a stat to a
## satellite puts it somewhere sensible without touching either screen.
##
## Tabs are local to this scene rather than separate [code]MenuController[/code] menus,
## because the controller keeps one menu on screen at a time and these would push each
## other off it.

const CAPTION_COLOR := Color(0.478431, 0.529412, 0.639216, 1)
const VALUE_COLOR := Color(0.85098, 0.890196, 1, 1)
const VALUE_FONT_SIZE := 18

## Tab for a stat whose [code]stat_meta[/code] names no [code]tab[/code], so a stat added
## with nothing but a caption is still listed rather than dropped.
@export var default_tab: String = "STATS"

## Which submenu is listed. Kept between visits: re-picking a tab every time the menu
## opens is busywork when you came back to the same one.
var _selected_tab: StringName = &""
## Tab buttons by caption, used to restore the pressed state.
var _tabs: Dictionary = {}
var _group: ButtonGroup = null
## The groups from the last build, so switching tabs does not have to go back to the
## satellite for them.
var _groups_cache: Array[Dictionary] = []
## What is on screen, as text, so a rebuild only happens when it actually differs. Stats
## change every frame, and rebuilding frees every row, which would stutter continuously.
var _current_signature: String = ""
## The value label per stat id, so a ticking stat rewrites text instead of rebuilding.
var _value_labels: Dictionary = {}
## Rows are rebuilt rather than diffed, so only the one style is cached.
var _row_style: StyleBoxFlat = null

@onready var _tabs_box: HBoxContainer = get_node_or_null("%Tabs")
@onready var _list_box: VBoxContainer = get_node_or_null("%List")
@onready var _placeholder: Label = get_node_or_null("%ContentPlaceholder")


func _ready() -> void:
	super()
	_row_style = _make_row_style()
	SatelliteController.active_changed.connect(_on_active_changed)
	SatelliteController.stats_changed.connect(_on_stats_changed)
	_refresh(SatelliteController.stat_descriptors())


func _on_open() -> void:
	_apply_tab_state()
	_refresh(SatelliteController.stat_descriptors())


func _on_active_changed(_satellite: Node) -> void:
	# A different satellite tracks different stats, so the previous build describes
	# nothing that is still on screen. Dropped rather than refreshed, so the next build
	# compares against nothing and definitely happens.
	_current_signature = ""
	_value_labels.clear()
	_refresh(SatelliteController.stat_descriptors())


func _on_stats_changed(_snapshot: Dictionary) -> void:
	_refresh(SatelliteController.stat_descriptors())


# --- Stats ------------------------------------------------------------------

## Brings the screen up to date, rebuilding only when what it would show has changed.
func _refresh(descriptors: Array) -> void:
	var groups := _groups(descriptors)
	var signature := _signature(groups)
	if signature != _current_signature:
		_current_signature = signature
		_rebuild(groups)
	_refresh_values(descriptors)


## The stats this screen is responsible for, grouped into submenus in the order the
## satellite first lists them.
##
## Anything asking for the hud is skipped: that is the top bar's, and listing it here too
## would show the same number in two places at once.
func _groups(descriptors: Array) -> Array[Dictionary]:
	var order: Array[String] = []
	var rows: Dictionary = {}
	for entry: Variant in descriptors:
		if not (entry is Dictionary):
			continue
		var data: Dictionary = entry
		if bool(data.get("hud", false)):
			continue
		var caption := _caption_for_tab(data)
		if not rows.has(caption):
			rows[caption] = []
			order.append(caption)
		(rows[caption] as Array).append(data)

	var groups: Array[Dictionary] = []
	for caption: String in order:
		groups.append({"caption": caption, "rows": rows[caption]})
	return groups


## The submenu a stat belongs to: the [code]tab[/code] its [code]stat_meta[/code] names,
## or [member default_tab] when it names none.
func _caption_for_tab(descriptor: Dictionary) -> String:
	var named := str(descriptor.get("tab", ""))
	return named if not named.is_empty() else default_tab


## Which stats are on which tab, as text. Values are left out on purpose: they change every
## frame, and comparing them would mean rebuilding the screen every frame.
func _signature(groups: Array[Dictionary]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for group: Dictionary in groups:
		var ids: PackedStringArray = PackedStringArray()
		for row: Dictionary in group.get("rows", []):
			ids.append(str(row.get("id", "")))
		parts.append("%s:%s" % [str(group.get("caption", "")), ",".join(ids)])
	return "|".join(parts)


## The stats under one tab, or nothing when that tab is not among the groups.
func _rows_for(groups: Array[Dictionary], tab: StringName) -> Array:
	for group: Dictionary in groups:
		if StringName(group.get("caption", "")) == tab:
			return group.get("rows", [])
	return []


## Rewrites the values on screen. The only thing that happens when a stat ticks, so it
## allocates nothing and touches no nodes beyond the label texts.
func _refresh_values(descriptors: Array) -> void:
	for entry: Variant in descriptors:
		if not (entry is Dictionary):
			continue
		var data: Dictionary = entry
		var label: Variant = _value_labels.get(data.get("id"))
		if label is Label:
			(label as Label).text = SatelliteStats.format_value(data)


# --- Tabs -------------------------------------------------------------------

func _rebuild(groups: Array[Dictionary]) -> void:
	_groups_cache = groups
	if _placeholder != null:
		_placeholder.visible = groups.is_empty()
	if _tabs_box == null:
		return
	if groups.is_empty():
		_tabs.clear()
		_group = null
		_rebuild_rows([])
		return

	_rebuild_tabs(groups)
	# A tab that has gone - a different satellite, or a stat_meta change - cannot stay
	# selected, so the pick falls back to the first one listed.
	if not _tabs.has(_selected_tab):
		_selected_tab = StringName((groups[0] as Dictionary).get("caption", ""))
		_apply_tab_state()
	_rebuild_rows(_rows_for(groups, _selected_tab))


func _rebuild_tabs(groups: Array[Dictionary]) -> void:
	_detach(_tabs_box)
	_tabs.clear()
	# A group rather than per-button state: it keeps exactly one tab pressed for free,
	# including when a tab is selected from somewhere other than a click.
	_group = ButtonGroup.new()
	for group: Dictionary in groups:
		var caption := StringName(group.get("caption", ""))
		var tab := Button.new()
		tab.toggle_mode = true
		tab.button_group = _group
		tab.text = str(group.get("caption", ""))
		tab.tooltip_text = "%s, %d tracked" % [tab.text, _rows_for(groups, caption).size()]
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(_on_tab_pressed.bind(caption))
		_tabs_box.add_child(tab)
		_tabs[caption] = tab
	_apply_tab_state()


func _apply_tab_state() -> void:
	for key: Variant in _tabs:
		var tab: Variant = _tabs[key]
		if tab is Button:
			(tab as Button).set_pressed_no_signal(StringName(key) == _selected_tab)


func _on_tab_pressed(caption: StringName) -> void:
	if caption.is_empty() or caption == _selected_tab:
		return
	_selected_tab = caption
	_rebuild_rows(_rows_for(_groups_cache, caption))


# --- Rows -------------------------------------------------------------------

func _rebuild_rows(rows: Array) -> void:
	if _list_box == null:
		return
	_detach(_list_box)
	_value_labels.clear()
	for entry: Variant in rows:
		if entry is Dictionary:
			_list_box.add_child(_build_row(entry as Dictionary))


## One stat: its caption on the left, its reading on the right. Both in a row rather than
## stacked like the bar's cells, because a submenu lists a handful of things to compare
## rather than a glance at everything at once.
func _build_row(descriptor: Dictionary) -> Control:
	var panel := PanelContainer.new()
	if _row_style != null:
		panel.add_theme_stylebox_override(&"panel", _row_style)

	var columns := HBoxContainer.new()
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_theme_constant_override(&"separation", 10)

	var caption := Label.new()
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.text = str(descriptor.get("caption", ""))
	caption.add_theme_color_override(&"font_color", CAPTION_COLOR)
	columns.add_child(caption)

	var value := Label.new()
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# The same formatter the top bar uses, so a number cannot read differently in the two
	# places it appears. See [method SatelliteStats.format_value].
	value.text = SatelliteStats.format_value(descriptor)
	value.add_theme_font_size_override(&"font_size", VALUE_FONT_SIZE)
	value.add_theme_color_override(&"font_color", VALUE_COLOR)
	columns.add_child(value)

	panel.add_child(columns)
	_value_labels[descriptor.get("id")] = value
	return panel


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
	if box == null:
		return
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()