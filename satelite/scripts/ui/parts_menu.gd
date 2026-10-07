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
##
## [b]Buying and mounting are two buttons[/b]. BUY spends credits on another copy of the
## part and places nothing, so copies can be bought one after another. FIT or MOVE opens the
## slot picker and places a copy the player already owns; the mount the player picks is what
## decides the spot on the body the part appears in. Fitting into a mount that already holds
## something replaces it, so the hardware can be changed at any time.
##
## [b]Copies are tracked apart[/b]. A part bought more than once is one row here, so the row
## says both how many copies are on the satellite and how many are still in store. What is
## mounted is per copy, so two radio antennas sit in two different mounts and each one is
## moved on its own.

## Shown when the satellite has no parts catalogue at all.
@export var empty_message: String = "No parts are available for this satellite yet."

## Rows past this are left out, so a large catalogue cannot turn the shop into a
## wall. The shop is meant to be browsable with the game running behind it.
@export_range(1, 32) var max_visible_rows: int = 10

## Rows are rebuilt rather than diffed, so only the cheap parts are cached between
## rebuilds: the signature they are keyed on, and one style shared by every row.
var _signature: String = ""
var _row_style: StyleBoxFlat = null

## The part the open slot picker is placing, or an empty id when it is closed. The picker is
## a mode on top of the shop rather than a screen of its own, so the rows behind it stay
## visible and the player can see what they are moving.
var _picking: StringName = &""

## One entry per copy chip on screen, so [method _process] can repaint the countdowns without
## rebuilding the rows they live in.
var _chips: Array[Dictionary] = []
## Seconds since the chips were last repainted. Half a second, so the countdown reads as
## whole seconds without repainting on every frame.
var _since_tick: float = 0.0

@onready var _list_box: VBoxContainer = get_node_or_null("%List")
@onready var _wallet_label: Label = get_node_or_null("%Wallet")
@onready var _placeholder: Label = get_node_or_null("%ContentPlaceholder")
@onready var _status_label: Label = get_node_or_null("%Status")
@onready var _picker: PanelContainer = get_node_or_null("%SlotPicker")
@onready var _picker_title: Label = get_node_or_null("%Title")
@onready var _picker_slots: HBoxContainer = get_node_or_null("%Slots")
@onready var _picker_cancel: Button = get_node_or_null("%SlotPickerCancel")


func _ready() -> void:
	super()
	if _placeholder and not empty_message.is_empty():
		_placeholder.text = empty_message
	_row_style = _make_row_style()
	SatelliteController.parts_changed.connect(_on_catalogue_changed)
	SatelliteController.stats_changed.connect(_on_stats_changed)
	# A mount changing under the open picker means what it said about itself is stale, so
	# it is rebuilt rather than left offering a spot that is already taken.
	SatelliteController.slots_changed.connect(_on_slots_changed)
	if _picker_cancel != null:
		_picker_cancel.pressed.connect(_close_picker)
	_rebuild()


func _on_open() -> void:
	_set_status("")
	_close_picker()
	_rebuild()


func _on_close() -> void:
	_set_status("")
	_close_picker()


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
		var part_id := StringName(row.get("id", &""))
		# Which mounts it is in and how many copies are waiting to be mounted, so fitting
		# a second copy rebuilds the row rather than leaving it claiming it is in the store.
		var mounts := PackedStringArray()
		for slot: Variant in SatelliteController.slots_of_part(part_id):
			mounts.append(str(slot))
		parts.append("%s|%s|%d|%d|%d|%s|%s" % [
			row.get("id", &""),
			row.get("reason", &""),
			int(row.get("price", 0)),
			int(row.get("owned", 0)),
			SatelliteController.fitted_count_of_part(part_id),
			row.get("fitted_label", ""),
			",".join(mounts),
		])
	return ";".join(parts)


## Detach before freeing: [method Node.queue_free] only takes the node out of the
## tree at the end of the frame, which would leave the old rows on screen under
## the new ones for a frame.
func _detach_rows() -> void:
	_detach(_list_box)
	# The chips are children of the rows just freed, so the bookkeeping that repaints their
	# countdowns goes with them.
	_chips.clear()


## Same reasoning for any rebuilt container, the slot buttons among them.
func _detach(box: Node) -> void:
	if box == null:
		return
	for child: Node in box.get_children():
		box.remove_child(child)
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

	info.add_child(title)

	var chips := HBoxContainer.new()
	chips.add_theme_constant_override(&"separation", 4)
	# One chip per copy bought, so the row says what the player actually has instead of
	# cramming a count into a tag: each chip is one piece of hardware and names the mount it
	# is in, or says it is still in store.
	for index: int in int(row.get("owned", 0)):
		chips.add_child(_build_chip(part_id, index))
	info.add_child(chips)

	if not reason.is_empty():
		var note := Label.new()
		note.text = reason
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_color_override(&"font_color", Color(0.851, 0.553, 0.396))
		info.add_child(note)

	# Two buttons because buying and mounting are two decisions. FIT or MOVE places a copy
	# that is already owned, and stays dead on a part nothing is owned of yet; BUY spends
	# credits on another copy and never places it, so a player can buy several copies and
	# then decide where each one goes.
	var mount_button := Button.new()
	mount_button.custom_minimum_size = Vector2(96, 36)
	mount_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mount_button.text = _mount_button_text(part_id)
	mount_button.tooltip_text = _mount_button_hint(part_id)
	mount_button.disabled = not _is_mountable(part_id)
	mount_button.pressed.connect(_on_mount_pressed.bind(part_id))

	var buy_button := Button.new()
	buy_button.custom_minimum_size = Vector2(96, 36)
	buy_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# A part the player cannot buy any more of shows no price: the catalogue reports a
	# price of zero there, and "BUY 0" would read as free hardware.
	var maxed := StringName(row.get("reason", &"")) == &"maxed"
	buy_button.text = "MAXED" if maxed else "BUY  %d" % int(row.get("price", 0))
	buy_button.tooltip_text = _buy_hint(row)
	buy_button.disabled = not bool(row.get("can_purchase", false))
	buy_button.pressed.connect(_on_buy_pressed.bind(part_id))

	columns.add_child(info)
	columns.add_child(mount_button)
	columns.add_child(buy_button)
	panel.add_child(columns)
	return panel


## Small dim label used for the category and the copy count.
func _tag(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override(&"font_color", Color(0.478, 0.529, 0.639))
	return label


## One chip per copy bought, so each piece of hardware is shown on its own rather than as a
## count in a tag. A chip says which mount its copy is in, or that it is still in store, and
## counts down the setup while the copy is being installed.
##
## A button because pressing it is the same choice the FIT button offers: put this copy in a
## mount, or move it to another one.
func _build_chip(part_id: StringName, copy: int) -> Button:
	var slot := _mount_of_copy(part_id, copy)
	var chip := Button.new()
	chip.custom_minimum_size = Vector2(76, 30)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.focus_mode = Control.FOCUS_NONE
	chip.pressed.connect(_on_mount_pressed.bind(part_id))
	_chip_of(part_id, copy, slot, chip)
	return chip


## Which mount [param copy] of [param part_id] is in, or -1 when that copy is in store. Copies
## are told apart by mount order, so the first copy is the lowest-numbered mount holding the
## part and a copy with no mount of its own is waiting to be fitted.
func _mount_of_copy(part_id: StringName, copy: int) -> int:
	var mounts := SatelliteController.slots_of_part(part_id)
	return int(mounts[copy]) if copy < mounts.size() else -1


## Puts [param chip] into the bookkeeping [method _refresh_chips] uses, and gives it the text
## it should start with.
func _chip_of(part_id: StringName, copy: int, slot: int, chip: Button) -> void:
	_chips.append({"part_id": part_id, "copy": copy, "slot": slot, "button": chip})
	_refresh_chip(chip, slot)


## What a chip says. A copy in store says so; a fitted copy names its mount and, while it is
## being set up, how long that has left.
func _refresh_chip(chip: Button, slot: int) -> void:
	if slot < 0:
		chip.text = "STORE"
		chip.tooltip_text = "Bought, not fitted. FIT puts it in a mount."
		chip.add_theme_color_override(&"font_color", Color(0.561, 0.608, 0.718))
		return
	var remaining := SatelliteController.install_remaining(slot)
	if remaining > 0.0:
		chip.text = "S%d  %s" % [slot + 1, _countdown(remaining)]
		chip.tooltip_text = "Being set up in slot %d. %s left, then it starts working." \
			% [slot + 1, _countdown(remaining)]
		# Amber while it is still being installed, so a mount that is not yet contributing
		# does not read the same as one that is.
		chip.add_theme_color_override(&"font_color", Color(0.98, 0.82, 0.44))
		return
	chip.text = "SLOT %d" % (slot + 1)
	chip.tooltip_text = "Working in slot %d." % (slot + 1)
	chip.add_theme_color_override(&"font_color", Color(0.62, 0.78, 0.62))


## Seconds as [code]m:ss[/code], so a countdown reads as time rather than as a number.
func _countdown(seconds: float) -> String:
	var whole := int(ceil(seconds))
	return "%d:%02d" % [whole / 60, whole % 60]


## Refreshes the chips on a timer rather than rebuilding the rows: a countdown changes every
## second, and rebuilding every row that often to redraw one number would cost far more than
## writing the text. Off-screen the menu does nothing at all.
func _process(delta: float) -> void:
	if not visible or _chips.is_empty():
		return
	_since_tick += delta
	if _since_tick < 0.5:
		return
	_since_tick = 0.0
	for chip: Dictionary in _chips:
		var button: Variant = chip.get("button")
		if not is_instance_valid(button):
			continue
		_refresh_chip(button as Button, int(chip.get("slot", -1)))


## What the button will do: mount a copy, move a copy, or buy one and then mount it.
func _mount_button_text(part_id: StringName) -> String:
	if _is_move(part_id):
		return "MOVE"
	if SatelliteController.can_fit_part(part_id):
		return "FIT"
	return "FITTED"


## Whether this part can be moved to a different mount rather than bought, which is what
## keeps the button live on a part whose copies are all mounted.
func _is_move(part_id: StringName) -> bool:
	return part_id != &"" and SatelliteController.fitted_count_of_part(part_id) > 0 \
		and not SatelliteController.can_fit_part(part_id)


## Whether the mount button does anything: it places a copy the player already owns, so it
## is dead for a part nothing is owned of, and with no mounts at all there is nowhere to
## place even a copy that is owned.
func _is_mountable(part_id: StringName) -> bool:
	if part_id.is_empty() or not SatelliteController.owns_part(part_id):
		return false
	return SatelliteController.available_slots() > 0


## What the mount button will do, said plainly.
func _mount_button_hint(part_id: StringName) -> String:
	if SatelliteController.available_slots() <= 0:
		return "This satellite has no mounts"
	if _is_move(part_id):
		return "Move a fitted copy to another slot"
	return "Choose a slot for the copy in store"


## Why the buy button is dead, or what it buys. Buying is never blocked by the mounts: a
## copy can be bought and mounted later, which is the point of keeping the two apart.
func _buy_hint(row: Dictionary) -> String:
	if not bool(row.get("can_purchase", false)):
		return _reason_text(row)
	return "Buy another copy, then fit it" if int(row.get("owned", 0)) > 0 else "Buy one"


## Why a row's button is dead, phrased for a player rather than as a constant.
func _reason_text(row: Dictionary) -> String:
	match StringName(row.get("reason", &"")):
		&"maxed":
			return "You own as many of these as you can."
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

## Buying a copy spends credits and stops there. It deliberately does not open the slot
## picker: buying several copies in a row and then deciding where each one goes is a normal
## thing to want, and a purchase that also picked a mount could only ever do one copy at a
## time.
func _on_buy_pressed(part_id: StringName) -> void:
	if part_id.is_empty():
		return
	if not SatelliteController.purchase_part(part_id):
		_set_status("Could not buy %s." % _display_name_of(part_id))
		return
	var name := _display_name_of(part_id)
	if SatelliteController.available_slots() > 0:
		_set_status("Bought %s. Use FIT to mount a copy." % name)
	else:
		_set_status("Bought %s, but this satellite has no mounts to fit it in." % name)


## A row's mount button does not buy anything on its own: it asks where the part is going
## first, because the mount is what decides where it appears on the body.
func _on_mount_pressed(part_id: StringName) -> void:
	if part_id.is_empty():
		return
	if SatelliteController.available_slots() <= 0:
		_set_status("This satellite has no mounts to fit anything in.")
		return
	_open_picker(part_id)


# --- Slot picker ------------------------------------------------------------

## Opens the picker for [param part_id]. A part whose copies are all mounted is being moved,
## which is the same choice with a different consequence, so it reuses this rather than being
## a second screen.
func _open_picker(part_id: StringName) -> void:
	_picking = part_id
	if _picker == null:
		return
	_picker.visible = true
	if _picker_title != null:
		_picker_title.text = "%s %s — choose a slot" % [_verb(part_id), _display_name_of(part_id)]
	_build_picker_slots()
	_set_status("")


## What picking a slot will be called: a copy in store is being fitted, a part whose copies
## are all mounted is being moved.
func _verb(part_id: StringName) -> String:
	return "Move" if _is_move(part_id) else "Fit"


func _close_picker() -> void:
	_picking = &""
	if _picker != null:
		_picker.visible = false
	_detach(_picker_slots)


## One button per mount. An occupied mount says what is in it and says plainly that picking
## it replaces that part, because the alternative - silently refusing - would look like the
## picker had lost the mount.
##
## Built rather than kept, so a mount that filled up while the picker was open is described
## accurately. Five of them, so this is not worth diffing.
func _build_picker_slots() -> void:
	if _picker_slots == null or _picking.is_empty():
		return
	_detach(_picker_slots)
	var states := SatelliteController.slot_states()
	if states.is_empty():
		return

	for entry: Dictionary in states:
		var slot := int(entry.get("index", 0))
		var occupied := bool(entry.get("occupied", false))
		var holding := str(entry.get("display_name", ""))
		var remaining := float(entry.get("install_remaining", 0.0))

		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 56)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		# Three lines when something is being set up there, so the mount says it is not
		# working yet rather than looking like an ordinary occupied mount.
		button.text = "SLOT %d\n%s" % [slot + 1, holding if occupied else "empty"]
		if remaining > 0.0:
			button.text += "\nsetting up  %s" % _countdown(remaining)
			button.tooltip_text = "%s is being set up in slot %d, %s left." \
				% [holding, slot + 1, _countdown(remaining)]
		else:
			button.tooltip_text = "Replace %s" % holding if occupied else "Fit here"
		if occupied:
			button.add_theme_color_override(&"font_color", Color(0.98, 0.82, 0.44))
		button.pressed.connect(_on_slot_pressed.bind(slot))
		_picker_slots.add_child(button)


## The player has picked a mount. Nothing is bought here: the mount button only opens for a
## part the player already owns a copy of, so this places that copy rather than spending
## credits, and a copy bought and left unmounted is mounted through here later.
func _on_slot_pressed(slot: int) -> void:
	var part_id := _picking
	if part_id.is_empty():
		return
	# Captured before the fit, because fitting is what empties the mount and with it the
	# name of what was replaced.
	var replaced := _name_in_slot(slot)

	if not SatelliteController.fit_part(part_id, slot):
		_set_status("Could not fit that part there.")
		return

	_close_picker()
	var name := _display_name_of(part_id)
	if replaced.is_empty():
		_set_status("Fitted %s to slot %d." % [name, slot + 1])
	elif replaced == name:
		_set_status("Moved %s to slot %d." % [name, slot + 1])
	else:
		_set_status("Fitted %s to slot %d, replacing %s." % [name, slot + 1, replaced])
	_rebuild()


## Name of whatever is fitted to [param slot], or empty. Kept separate from the catalogue
## because the answer is about a mount rather than about a part that exists.
func _name_in_slot(slot: int) -> String:
	for entry: Dictionary in SatelliteController.slot_states():
		if int(entry.get("index", -1)) == slot:
			return str(entry.get("display_name", "")) if bool(entry.get("occupied", false)) else ""
	return ""


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
## A mount changed, which is what a fit, a move and a finished setup all report. The chips
## name their mounts, so they have to be matched to the mounts again; the picker, if it is
## open, has to be told too.
func _on_slots_changed(_slot: int) -> void:
	_rebuild(true)
	if not _picking.is_empty():
		_build_picker_slots()


func _on_stats_changed(_snapshot: Dictionary) -> void:
	_rebuild()
