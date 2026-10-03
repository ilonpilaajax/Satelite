extends MenuPanel
## Parts shop. Opened from the access bar; the game keeps running behind it
## because this screen is not in [code]MenuController.PAUSING_MENUS[/code]. Close
## returns to the game.
##
## Rows are built from [code]SatelliteController.part_catalogue[/code] rather than
## from a list written out here, so a part added to [SatelliteParts.parts] shows up
## with its price and its rules already applied. The row never decides whether a
## purchase is allowed: [SatelliteParts] does, and this only reports the reason it
## was handed back.
##
## [b]Nothing rebuilds on every stat change[/b]. Distance accrues each frame while
## the game runs, so [code]stats_changed[/code] fires far too often to rebuild a
## row on. What rows actually depend on is the price, the fitted count and whether
## the button is live, so the catalogue is reduced to a short signature and the
## rows are only rebuilt when that changes. The wallet label is the one thing
## refreshed outright, because credits are the thing that moved.

## Shown when the satellite has no parts catalogue at all.
@export var empty_message: String = "No parts are available for this satellite yet."

## Rows past this are left out, so a large catalogue cannot turn the shop into a
## wall. The shop is meant to be browsable with the game running behind it.
@export_range(1, 32) var max_visible_rows: int = 10

## Rows are rebuilt rather than diffed, so only the cheap parts are cached between
## rebuilds: the signature they are keyed on, and one style shared by every row.
var _signature: String = ""
var _row_style: StyleBoxFlat = null

@onready var _list_box: VBoxContainer = get_node_or_null("%List")
@onready var _wallet_label: Label = get_node_or_null("%Wallet")
@onready var _placeholder: Label = get_node_or_null("%ContentPlaceholder")
@onready var _status_label: Label = get_node_or_null("%Status")


func _ready() -> void:
	super()
	if _placeholder and not empty_message.is_empty():
		_placeholder.text = empty_message
	_row_style = _make_row_style()
	SatelliteController.parts_changed.connect(_on_catalogue_changed)
	SatelliteController.stats_changed.connect(_on_stats_changed)
	_rebuild()


func _on_open() -> void:
	_set_status("")
	_rebuild()


func _on_close() -> void:
	_set_status("")


# --- Rows -------------------------------------------------------------------

func _rebuild(force: bool = false) -> void:
	if _list_box == null:
		return
	var catalogue := SatelliteController.part_catalogue()
	_refresh_wallet(catalogue)
	var signature := _signature_of(catalogue)
	# Compared rather than assumed: an empty catalogue signs to "", so a sentinel
	# would collide with a real one and silently skip the rebuild that clears the
	# screen. Callers that know something moved pass force.
	if not force and signature == _signature:
		return
	_signature = signature
	_detach_rows()

	var shown := 0
	for row: Dictionary in catalogue:
		if shown >= max_visible_rows:
			break
		_list_box.add_child(_build_row(row))
		shown += 1

	# One empty-state label for the whole menu, the same one every other menu uses.
	if _placeholder:
		_placeholder.visible = catalogue.is_empty()


## Shared by every row, so fitting ten parts does not build ten identical styles.
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


## Everything the rows actually render. Two catalogues that produce the same
## signature produce the same rows, which is what makes skipping the rebuild safe.
func _signature_of(catalogue: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for row: Dictionary in catalogue:
		parts.append("%s|%s|%d|%d|%s" % [
			row.get("id", &""),
			row.get("reason", &""),
			int(row.get("price", 0)),
			int(row.get("owned", 0)),
			row.get("fitted_label", ""),
		])
	return ";".join(parts)


## Detach before freeing: [method Node.queue_free] only takes the node out of the
## tree at the end of the frame, which would leave the old rows on screen under
## the new ones for a frame.
func _detach_rows() -> void:
	for child: Node in _list_box.get_children():
		_list_box.remove_child(child)
		child.queue_free()


func _build_row(row: Dictionary) -> Control:
	var part_id := StringName(row.get("id", &""))
	var reason := _reason_text(row)

	var panel := PanelContainer.new()
	if _row_style != null:
		panel.add_theme_stylebox_override(&"panel", _row_style)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 12)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override(&"separation", 2)

	var title := HBoxContainer.new()
	title.add_theme_constant_override(&"separation", 6)

	var icon: Variant = row.get("icon")
	if icon is Texture2D:
		var picture := TextureRect.new()
		picture.texture = icon
		picture.custom_minimum_size = Vector2(32, 32)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		title.add_child(picture)

	var name_label := Label.new()
	name_label.text = str(row.get("display_name", "Part"))
	title.add_child(name_label)

	var category := StringName(row.get("category", &""))
	if category != &"":
		title.add_child(_tag(str(category).to_upper()))

	var fitted := str(row.get("fitted_label", ""))
	if not fitted.is_empty():
		title.add_child(_tag("FITTED %s" % fitted))

	info.add_child(title)

	var description := Label.new()
	description.text = str(row.get("description", ""))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override(&"font_color", Color(0.561, 0.608, 0.718))
	info.add_child(description)

	if not reason.is_empty():
		var note := Label.new()
		note.text = reason
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_color_override(&"font_color", Color(0.851, 0.553, 0.396))
		info.add_child(note)

	var buy := Button.new()
	buy.custom_minimum_size = Vector2(104, 36)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.text = _button_text(row)
	buy.disabled = not bool(row.get("can_purchase", false))
	buy.tooltip_text = reason if buy.disabled else "Fit this part"
	buy.pressed.connect(_on_buy_pressed.bind(part_id))

	columns.add_child(info)
	columns.add_child(buy)
	panel.add_child(columns)
	return panel


## Small dim label used for the category and the fitted count.
func _tag(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override(&"font_color", Color(0.478, 0.529, 0.639))
	return label


func _button_text(row: Dictionary) -> String:
	if StringName(row.get("reason", &"")) == &"maxed":
		return "FITTED"
	return "BUY  %d" % int(row.get("price", 0))


## Why a row's button is dead, phrased for a player rather than as a constant.
func _reason_text(row: Dictionary) -> String:
	match StringName(row.get("reason", &"")):
		&"maxed":
			return "Already fully fitted."
		&"locked":
			return "Needs another part fitted first."
		&"cannot_afford":
			return "Not enough credits."
		&"unknown_part":
			return "This part is no longer installed."
	return ""


## Hidden entirely when the satellite tracks no credits, rather than showing a
## balance that is never spent.
func _refresh_wallet(catalogue: Array) -> void:
	if _wallet_label == null:
		return
	if catalogue.is_empty() or not _has_prices(catalogue):
		_wallet_label.text = ""
		return
	_wallet_label.text = "CREDITS  %d" % int(SatelliteController.stat(&"credits", 0.0))


## True when at least one part asks for money, which is what makes a wallet worth
## showing.
func _has_prices(catalogue: Array) -> bool:
	for row: Dictionary in catalogue:
		if int(row.get("price", 0)) > 0:
			return true
	return false


func _set_status(text: String) -> void:
	if _status_label:
		_status_label.text = text


# --- Input ------------------------------------------------------------------

func _on_buy_pressed(part_id: StringName) -> void:
	if part_id == &"":
		return
	if SatelliteController.purchase_part(part_id):
		_set_status("Fitted %s." % _display_name_of(part_id))
	else:
		_set_status("Could not fit that part.")


func _display_name_of(part_id: StringName) -> String:
	for row: Dictionary in SatelliteController.part_catalogue():
		if StringName(row.get("id", &"")) == part_id:
			return str(row.get("display_name", "part"))
	return "part"


# --- Signals ----------------------------------------------------------------

## A part changed somewhere, so nothing cached here can be trusted any more. Forced
## rather than left to the signature, because a catalogue emptied out signs to the
## same value as one that was never filled.
func _on_catalogue_changed() -> void:
	_rebuild(true)


## Credits moving is what most often flips a row between buyable and not. The
## guard inside [method _rebuild] is what keeps this cheap.
func _on_stats_changed(_snapshot: Dictionary) -> void:
	_rebuild()
