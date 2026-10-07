extends MenuPanel
## Upgrade menu. Opened from the access bar; the game keeps running behind it
## because this screen is not in [code]MenuController.PAUSING_MENUS[/code]. Close
## returns to the game.
##
## Rows are built from [code]SatelliteController.upgrade_catalogue[/code] rather than from a
## list written out here, so an upgrade added to [SatelliteUpgrades.upgrades] shows up with
## its price, its level and its ceiling already applied. The row never decides whether a
## purchase is allowed: [SatelliteUpgrades] does, and this only reports the reason it was
## handed back.
##
## A row reads as "level owned of the ceiling", because that is the only number that decides
## whether another level can be bought: [member UpgradeDefinition.max_level] is how many
## times the upgrade can be bought in total, not how strong one level is.
##
## [b]Nothing rebuilds on every stat change[/b]. Credits move when the game runs, so
## [code]upgrades_changed[/code] is the signal to rebuild on and the wallet label is refreshed
## on its own.

## Rows past this are left out, so a large catalogue cannot turn the menu into a scroll.
@export var max_visible_rows: int = 8

## Shown when the satellite has no upgrades at all.
@export var empty_message: String = "No upgrades are available for this satellite yet."

@onready var _list_box: VBoxContainer = %List
@onready var _placeholder: Label = %ContentPlaceholder
@onready var _wallet_label: Label = %Wallet
@onready var _status_label: Label = %Status

var _signature: String = ""


func _ready() -> void:
	super()
	SatelliteController.upgrades_changed.connect(_on_upgrades_changed)
	SatelliteController.upgrade_purchased.connect(_on_upgrade_purchased)
	SatelliteController.upgrade_purchase_rejected.connect(_on_purchase_rejected)
	SatelliteController.stats_changed.connect(_on_stats_changed)
	SatelliteController.active_changed.connect(_on_active_changed)
	_rebuild()


func _on_open() -> void:
	_rebuild(true)


func _on_close() -> void:
	pass


## The rows are not rebuilt unless something they show has actually changed: the catalogue,
## the level of an upgrade, or whether its button is live. Credits are refreshed outright,
## because that is the thing that moves.
func _on_upgrades_changed() -> void:
	_rebuild()


func _on_upgrade_purchased(_upgrade: Resource, level: int) -> void:
	_rebuild()


func _on_purchase_rejected(upgrade: Resource, reason: StringName) -> void:
	_set_status("%s: %s" % [upgrade.display_name if upgrade != null else "Upgrade",
		_reason_text(reason)])


func _on_stats_changed(_snapshot: Dictionary) -> void:
	# Credits are the only thing here a stat change can move.
	_refresh_wallet()


func _on_active_changed(_satellite: Node) -> void:
	_rebuild(true)


func _rebuild(force: bool = false) -> void:
	var catalogue := SatelliteController.upgrade_catalogue()
	var signature := _signature_of(catalogue)
	_refresh_wallet()
	if not force and signature == _signature:
		return
	_signature = signature

	if _list_box == null:
		return
	_detach(_list_box)

	var shown := 0
	for upgrade: UpgradeDefinition in catalogue:
		if upgrade == null:
			continue
		if shown >= max_visible_rows:
			break
		_list_box.add_child(_build_row(upgrade))
		shown += 1

	if _placeholder != null:
		_placeholder.visible = shown == 0
		_placeholder.text = empty_message


## Everything the rows actually render. Two catalogues that produce the same signature
## produce the same rows, which is what makes skipping the rebuild safe.
func _signature_of(catalogue: Array) -> String:
	var parts := PackedStringArray()
	for upgrade: UpgradeDefinition in catalogue:
		if upgrade == null:
			continue
		parts.append("%s|%d|%d|%s" % [
			upgrade.id,
			upgrade.max_level,
			SatelliteController.level_of(upgrade.id),
			SatelliteController.can_purchase(upgrade.id),
		])
	return ";".join(parts)


func _build_row(upgrade: UpgradeDefinition) -> Control:
	var panel := PanelContainer.new()
	var level := SatelliteController.level_of(upgrade.id)
	var cost := SatelliteController.cost_of(upgrade.id)
	var reason := _reason_text(SatelliteController.upgrade_purchase_reason(upgrade.id))

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 12)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override(&"separation", 2)

	var title := HBoxContainer.new()
	title.add_theme_constant_override(&"separation", 6)

	var icon: Texture2D = upgrade.icon
	if icon != null:
		var picture := TextureRect.new()
		picture.texture = icon
		picture.custom_minimum_size = Vector2(32, 32)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		title.add_child(picture)

	var name_label := Label.new()
	name_label.text = upgrade.display_name
	title.add_child(name_label)

	# The ceiling is the number that decides whether another level exists at all, so it is
	# on the row: "LEVEL 3 / 11" rather than a max hidden in the tooltip.
	title.add_child(_tag("LEVEL %d / %d" % [level, upgrade.max_level]))
	info.add_child(title)

	if not reason.is_empty():
		var note := Label.new()
		note.text = reason
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_color_override(&"font_color", Color(0.851, 0.553, 0.396))
		info.add_child(note)

	var buy := Button.new()
	buy.custom_minimum_size = Vector2(112, 36)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# A maxed upgrade has no next level and so no price, and "BUY 0" would read as free.
	if upgrade.is_maxed_at(level):
		buy.text = "MAXED"
	else:
		buy.text = "BUY  %d" % cost
	buy.disabled = not SatelliteController.can_purchase(upgrade.id)
	buy.tooltip_text = reason if buy.disabled else "Buy level %d" % (level + 1)
	buy.pressed.connect(_on_buy_pressed.bind(upgrade.id))

	columns.add_child(info)
	columns.add_child(buy)
	panel.add_child(columns)
	return panel


## Small dim label used for the level counter.
func _tag(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override(&"font_color", Color(0.478, 0.529, 0.639))
	return label


## Why an upgrade's button is dead, phrased for a player rather than as a constant.
func _reason_text(reason: StringName) -> String:
	match reason:
		&"maxed":
			return "Fully upgraded."
		&"cannot_afford":
			return "Not enough credits."
		&"unknown_upgrade":
			return "This upgrade is no longer installed."
	return ""


## Hidden entirely when the satellite tracks no credits, rather than showing a
## balance that is never spent.
func _refresh_wallet() -> void:
	if _wallet_label == null:
		return
	if SatelliteController.upgrade_catalogue().is_empty():
		_wallet_label.text = ""
		return
	_wallet_label.text = "CREDITS  %d" % int(SatelliteController.stat(&"credits", 0.0))


func _detach(box: Node) -> void:
	if box == null:
		return
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _on_buy_pressed(upgrade_id: StringName) -> void:
	if upgrade_id.is_empty():
		return
	if not SatelliteController.purchase_upgrade(upgrade_id):
		_set_status("Could not buy that upgrade.")
		return
	var level := SatelliteController.level_of(upgrade_id)
	_set_status("Upgraded to level %d." % level)
	_rebuild()


func _set_status(text: String) -> void:
	if _status_label:
		_status_label.text = text