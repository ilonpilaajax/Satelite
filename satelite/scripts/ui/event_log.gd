extends CanvasLayer
## In-game event log: a running feed of things worth knowing about, in the bottom
## corner.
##
## [b]Read-only by construction.[/b] There is no line edit, no text entry and nothing
## here takes keyboard input, so the player cannot write to it - the only way a line
## appears is [method post], called from something that happened. That is the whole
## point: it is a log, not a chat.
##
## It subscribes to the events worth reporting on its own, so most of it needs no wiring
## anywhere:
##
## [codeblock]
## # A new signal was heard on a channel
## control_panel.signal_found(channel, signal, count)
##
## # The player did something
## SatelliteController.part_purchased / upgrade_purchased / action_performed
## SatelliteController.data_transmitted
##
## # Which satellite is in focus, so the right control panel gets listened to
## SatelliteController.active_changed
##
## # Anything else, from anywhere
## get_node("Main/EventLog").post("Antenna deployed.")
## [/codeblock]
##
## Lines are trimmed to [member max_lines] and the view follows the newest, so it reads
## like a terminal rather than growing without bound.
##
## It has two states, toggled by the button under it and named by [member expanded]. By
## default it shows only the most recent line, bare on the screen background, which is
## the read for something you glance at. Expanded, it is the full feed in a panel, for
## when you want to read back what happened.
##
## Neither state throws anything away: the latest-only state hides the older lines rather
## than deleting them, so hiding the log or opening the full log afterwards finds the
## whole history still there.
##
## A line about something that has a screen of its own - a signal detection - is also a
## link. It is green as it appears, greys under the pointer, and opens that signal's
## channel in the signals menu on a click, so a detection can be looked at properly
## without hunting for it again.
##
## Nothing here knows what a signal or a part is. Every line arrives as finished text
## from whatever produced it, so this file survives new event sources without changing.

## Lines past this are dropped from the top. Bounded so a long session cannot grow the
## feed, and because nothing here is scrollable back through anyway. Only counts in
## the full-log state; see [member expanded].
@export_range(1, 64) var max_lines: int = 12

## Which of the two states the log is in.
##
## [b]Off - latest only.[/b] Just the newest line, on the screen background: no panel,
## no border, no scroll. Shrinks to the height of that one line, so it stays out of the
## way over a long session.
##
## [b]On - full log.[/b] The feed as it normally reads: every line up to [member
## max_lines], inside the panel, following the newest.
##
## Switching either way keeps what is on screen and discards the rest, so the states are
## views of the same live feed rather than two logs. Toggle it with [method
## toggle_expanded], which is what the button in the scene is wired to.
@export var expanded: bool = false

## Show a clock on each line. Off gives a cleaner read; on makes gaps in the feed
## explainable.
@export var show_timestamps: bool = true

## Seconds between two identical lines being merged into one with a count, so a signal
## heard every few seconds does not push everything else off the feed.
@export_range(0.0, 30.0, 0.5) var repeat_merge_window: float = 6.0

## Tint per kind, so a detection reads differently from a purchase. A kind with no entry
## here is drawn in the default colour.
const KIND_COLORS := {
	&"signal": Color(0.478, 0.89, 0.61),
	&"buy": Color(0.98, 0.82, 0.44),
	&"action": Color(0.62, 0.76, 0.97),
	&"downlink": Color(0.73, 0.58, 0.97),
	&"alert": Color(0.94, 0.5, 0.42),
}
const DEFAULT_COLOR := Color(0.85, 0.89, 1.0)
const STAMP_COLOR := Color(0.4, 0.45, 0.56)
## A line the player has read. Deliberately duller than the green a signal starts as, so a
## line you have been over reads as spent and stops competing with one you have not. This
## is the colour a signal takes on for good once the pointer has been over one of its lines.
const SPENT_COLOR := Color(0.5, 0.53, 0.6)

## How many times the latest-only state re-measures itself before giving up. A line
## settles into its real height a frame or two after it appears, and the panel has to
## catch up with it; bounded so a label that never gets laid out cannot spin the queue.
const FIT_PASSES := 3

## The control panel this log is listening to, so it can unsubscribe when the active
## satellite changes.
var _panel: Node = null
## Signal ids the player has read, kept for the whole session. A signal is only worth
## noticing the first time it is heard, and a live feed redetects the same handful of
## carriers over and over, so without this the log would be green from top to bottom within
## seconds and green would stop meaning anything.
var _read_signals: Dictionary = {}
## The line currently in the feed, so a repeat can merge into it.
var _last_text: String = ""
var _last_kind: StringName = &""
var _last_stamp: String = ""
var _last_count: int = 1
## When the line in the feed was posted, so a repeat only merges into it while the merge
## window is still open.
var _last_msec: int = 0
## The panel's own stylebox, read once so the latest-only state can swap in an empty one
## and the full-log state can put the original back without the scene owning both.
var _frame_background: StyleBox = null
## The panel's top edge as the scene laid it out, which is the full-log state's height.
## Held here because the latest-only state moves it.
var _expanded_top: float = 0.0
## Set by the hide button, so the latest-only line stays out of the way until something
## new actually happens. Cleared by the next new line, or by asking for it back.
var _dismissed: bool = false

@onready var _frame: PanelContainer = get_node_or_null("Frame")
@onready var _lines_box: VBoxContainer = get_node_or_null("%Lines")
@onready var _scroll: ScrollContainer = get_node_or_null("%Scroll")
@onready var _toggle: Button = get_node_or_null("%Toggle")
@onready var _dismiss: Button = get_node_or_null("%Dismiss")


func _ready() -> void:
	SatelliteController.part_purchased.connect(_on_part_purchased)
	SatelliteController.upgrade_purchased.connect(_on_upgrade_purchased)
	SatelliteController.action_performed.connect(_on_action_performed)
	SatelliteController.data_transmitted.connect(_on_data_transmitted)
	SatelliteController.active_changed.connect(_on_active_changed)
	if _frame != null:
		_frame_background = _frame.get_theme_stylebox(&"panel")
		_expanded_top = _frame.offset_top
	if _toggle != null:
		_toggle.pressed.connect(toggle_expanded)
	if _dismiss != null:
		_dismiss.pressed.connect(toggle_dismissed)
	_apply_mode()
	bind_control_panel()
	post("Systems nominal.", &"")


## Swaps between the two states. Safe to call from anywhere; the button in the scene and
## anything else that wants the other state call this rather than setting [member
## expanded] directly, so the panel, the height and the button label all follow.
##
## Opening the full log also undoes a dismissal: asking to see the log is not something a
## hidden line can refuse.
func toggle_expanded() -> void:
	expanded = not expanded
	_dismissed = false
	_apply_mode()


## Hides the latest-only line, or brings it back if it is already hidden. Wired to the
## button under the log, and a two-way control on purpose.
##
## It has to be two-way. Hiding the button along with the line left no way to get the
## log back but a new line, and repeats merge into the line that is already there rather
## than counting as new - so a log hidden while one signal was being heard repeatedly
## stayed hidden with nothing on screen to click. The button stays either way.
##
## Only does anything in the latest-only state, where there is one line to get out of the
## way; the full log is a window the player opened on purpose, so it stays.
##
## Deliberately not automatic and not on a timer. The line does not fade or clear itself
## after a while, because a log that vanishes on its own is a log you cannot rely on
## having shown you something.
func toggle_dismissed() -> void:
	if expanded:
		return
	_dismissed = not _dismissed
	_apply_mode()


## Puts the screen into whichever state [member expanded] says: the panel background on
## or off, the button labels naming the state they would switch to, the feed trimmed to
## that state's length, and the panel resized to fit.
func _apply_mode() -> void:
	if _frame != null:
		# An empty stylebox is what takes the background and the border away. It also
		# drops the panel's content margins to zero, which is why the latest-only line
		# sits flush instead of inset.
		_frame.add_theme_stylebox_override(&"panel", _frame_background if expanded else StyleBoxEmpty.new())
		_frame.visible = not _dismissed
	if _toggle != null:
		# Named for where the button goes, not where it is, so the label reads as what it
		# will do.
		_toggle.text = "LATEST" if expanded else "FULL LOG"
		_toggle.tooltip_text = ("Show only the most recent line." if expanded
			else "Show the whole log.")
	if _dismiss != null:
		# Always on screen while collapsed, hidden or not, so a dismissed log is never a
		# dead end. Only the latest-only state has a line to hide at all.
		_dismiss.visible = not expanded
		# Named for what it will do, so a button reading "Hide" is never a puzzle and a
		# button reading "Show" is never mistaken for the thing it just hid.
		_dismiss.text = "Show" if _dismissed else "Hide"
		_dismiss.tooltip_text = ("Bring the log back." if _dismissed
			else "Hide the log until the next line.")
	_refresh_rows()
	_trim()
	_fit()


## Shows the lines the current state is for and hides the rest, without removing any of
## them. This is what makes closing the log loseless: the latest-only state hides the
## older lines instead of deleting them, so opening the full log again finds the whole
## history still there.
##
## Nothing is thrown away in either state, so the bound is [member max_lines] throughout.
func _refresh_rows() -> void:
	if _lines_box == null:
		return
	var count: int = _lines_box.get_child_count()
	for index: int in count:
		_lines_box.get_child(index).visible = expanded or index == count - 1


## Adds one line. This is the only way text gets in.
##
## [param kind] is optional and only picks a colour, so callers do not have to know
## which kinds exist - a line with an unrecognised kind just renders in the default
## colour.
##
## [param count] is for an event that already knows how many times it has happened, such
## as a signal the panel has been tracking. Given, it is the number shown rather than the
## count of merges, so the line states the real total instead of how many identical posts
## happened back to back. Left at 0 for an event that has no running total of its own,
## which is counted by merging like any other.
##
## [param channel] and [param signal_id] are what a click on the line goes to: the channel
## tab, and the row within it, so the menu opens on the signal rather than on the top of
## the list. Only given for a line that has somewhere to go, which today means a signal
## detection, and a line without one is inert - there is nothing behind it to look at.
func post(text: String, kind: StringName = &"", count: int = 0, channel: StringName = &"",
		signal_id: StringName = &"") -> void:
	if text.strip_edges().is_empty():
		return
	# Same thing twice in a row becomes one line with a count, so a signal heard every
	# few seconds cannot push everything else off the feed.
	if _same_as_last(text, kind):
		# A merge is the line updating itself, not something new happening, so it leaves a
		# dismissed log dismissed. Bringing it back here would make the line flicker
		# straight back in on the next repeat, which is not what hiding it was for.
		_last_count = count if count > 0 else _last_count + 1
		_replace_last(_with_count(text, _last_count))
		return
	# A new line is what brings a dismissed log back. Checked here rather than inside
	# _add_line, so the undismiss happens on the same path as any other new line.
	if _dismissed:
		_dismissed = false
		_apply_mode()
	# Recorded before the line is built, because the line takes the timestamp from
	# _last_stamp and a line built first would show whatever the previous one did.
	_last_text = text
	_last_kind = kind
	_last_stamp = _stamp()
	_last_msec = Time.get_ticks_msec()
	_last_count = maxi(count, 1)
	_add_line(text, kind, _last_count, channel, signal_id)


## Subscribes to the active satellite's control panel, so new detections arrive without
## anything having to forward them. Re-subscribing rather than connecting once, so a
## satellite swap does not leave the old panel talking to a log that has moved on.
func bind_control_panel() -> void:
	if _panel != null and _panel.has_signal(&"signal_found"):
		if _panel.is_connected(&"signal_found", _on_signal_found):
			_panel.disconnect(&"signal_found", _on_signal_found)
	_panel = _control_panel()
	if _panel != null and _panel.has_signal(&"signal_found"):
		_panel.connect(&"signal_found", _on_signal_found)


## The active satellite's control panel, or null. Looked up by path for the same reason
## the signals menu does it: the control panel is not part of [Satellite]'s outward
## contract, so there is no hub method to ask.
func _control_panel() -> Node:
	var satellite := SatelliteController.get_active()
	if satellite == null:
		return null
	return satellite.get_node_or_null(^"Control-Panel")


# --- Lines ------------------------------------------------------------------

func _stamp() -> String:
	if not show_timestamps:
		return ""
	return Time.get_time_string_from_system()


func _add_line(text: String, kind: StringName, count: int, channel: StringName,
		signal_id: StringName) -> void:
	if _lines_box == null:
		return
	_lines_box.add_child(_build_line(text, kind, count, channel, signal_id))
	_refresh_rows()
	_trim()
	_fit()
	_follow()


## Drops the oldest lines once the feed is past [member max_lines]. The cap does not
## change between states: the latest-only state hides what it is not showing rather than
## deleting it, so this is the only thing that ever removes a line, and what it removes is
## the history rather than the state.
##
## Floored at one because a feed holding no lines cannot show a line: every row posted
## would be trimmed straight back off, and the screen would read as broken rather than as
## empty.
func _trim() -> void:
	if _lines_box == null:
		return
	while _lines_box.get_child_count() > maxi(max_lines, 1):
		var oldest: Node = _lines_box.get_child(0)
		_lines_box.remove_child(oldest)
		oldest.queue_free()


## Resizes the panel around the feed. The full-log state is the fixed-height window the
## scene laid out, so that edge goes back where it started; the latest-only state shrinks
## to the one line, whose height depends on whether it wrapped.
func _fit() -> void:
	if _frame == null:
		return
	if expanded:
		_frame.offset_top = _expanded_top
		return
	_fit_later.call_deferred()


func _fit_later(passes_left: int = FIT_PASSES) -> void:
	if _frame == null or expanded or _lines_box == null or not is_inside_tree():
		return
	var message: Label = _newest_message()
	if message == null:
		return
	# A wrapped label works its minimum height out from the width it currently has, and a
	# row that has only just been added can still be a pixel wide for a frame. Measured
	# then, a single line comes back as tall as one word per line - over 800px - and the
	# panel is dragged off the top of the screen with the line on it. A width that has not
	# been laid out yet is treated as no measurement at all, and asked for again next
	# frame, once the container has handed the label its real width.
	if message.size.x <= 1.0:
		if passes_left > 0:
			_fit_later.call_deferred(passes_left - 1)
		return
	# Measured off the lines rather than the frame. A ScrollContainer reports a minimum
	# size of zero precisely so its content is allowed to overflow, so the frame's own
	# minimum says nothing about how tall a line is.
	var height: float = _lines_box.get_combined_minimum_size().y
	if height <= 0.0:
		return
	var bottom: float = _frame.offset_bottom
	if is_equal_approx(_frame.offset_top, bottom - height):
		return
	_frame.offset_top = bottom - height
	# Asked once more afterwards. The line settles into its real height a frame after it
	# appears, and without this second pass the panel keeps whatever height the first,
	# unlaid-out measurement gave it - which is a panel hanging off the top of the screen
	# with the line somewhere above the viewport. Stops as soon as two measurements agree.
	if passes_left > 0:
		_fit_later.call_deferred(passes_left - 1)


## The message label of the newest row, or null. The line being shown, as opposed to the
## timestamp beside it.
func _newest_message() -> Label:
	if _lines_box == null or _lines_box.get_child_count() == 0:
		return null
	var row: Node = _lines_box.get_child(_lines_box.get_child_count() - 1)
	var labels: Array = row.find_children("*", "Label", true, false)
	return labels[labels.size() - 1] as Label if not labels.is_empty() else null


## The last line, rewritten in place. Cheaper than removing and re-adding, and it keeps
## the feed from flickering every time a repeat merges.
func _replace_last(text: String) -> void:
	if _lines_box == null or _lines_box.get_child_count() == 0:
		return
	var row: Node = _lines_box.get_child(_lines_box.get_child_count() - 1)
	var labels: Array[Node] = row.find_children("*", "Label", true, false)
	# The message is the last Label in the row. Indexed rather than named, so a merge
	# still lands on the message with timestamps turned off and the row holding only
	# that one label.
	if not labels.is_empty():
		(labels[labels.size() - 1] as Label).text = text
	_fit()
	_follow()


## One row: a timestamp and the message, side by side. Built in code rather than as a
## scene, so a line is a Label and nothing else can end up in the log.
##
## A row with somewhere to go behind it - [param channel], which today means a signal -
## takes the mouse and opens that channel's menu on a click. One without is inert.
func _build_line(text: String, kind: StringName, count: int, channel: StringName,
		signal_id: StringName) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.focus_mode = Control.FOCUS_NONE
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 6)

	if show_timestamps:
		var stamp := Label.new()
		stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stamp.text = _last_stamp
		stamp.add_theme_color_override(&"font_color", STAMP_COLOR)
		row.add_child(stamp)

	var base := _color_for(kind, signal_id)
	var message := Label.new()
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	message.text = _with_count(text, count)
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_color_override(&"font_color", base)
	row.add_child(message)

	if not channel.is_empty():
		_make_clickable(row, message, channel, signal_id, base)
	return row


## Turns a row into something the mouse can use, and nothing more. It still cannot be
## typed into and still takes no focus; all a click does is open the menu behind it.
##
## Green as it appears, and grey for good from the moment the pointer has been over it, so
## green is left only to the signals the player has not been near. The state is held on the
## row and in the read set rather than baked into the label, so a merge rewriting the text
## cannot knock them out of step with the pointer.
func _make_clickable(row: HBoxContainer, message: Label, channel: StringName,
		signal_id: StringName, base: Color) -> void:
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.set_meta(&"message", message)
	row.set_meta(&"channel", channel)
	row.set_meta(&"signal_id", signal_id)
	row.set_meta(&"base_color", base)
	row.set_meta(&"hovered", false)
	row.mouse_entered.connect(_on_row_hovered.bind(row, true))
	row.mouse_exited.connect(_on_row_hovered.bind(row, false))
	row.gui_input.connect(_on_row_input.bind(row))


func _on_row_hovered(row: Node, hovered: bool) -> void:
	row.set_meta(&"hovered", hovered)
	if hovered:
		# Being over a line is how a line gets read, so that is what marks it. Committing
		# here rather than on a click, because reading is not a decision the player makes
		# and asking them to click to say so would leave the feed green while they read it.
		_mark_read(row.get_meta(&"signal_id"))
	_paint(row)


## Marks a signal read for the session, then repaints every line for it - the one just
## hovered and any older line for the same signal still on screen. Green is left only to
## signals the player has not been over, which is what makes it worth scanning for.
func _mark_read(signal_id: Variant) -> void:
	var id := StringName(signal_id)
	if id.is_empty() or _read_signals.has(id):
		return
	_read_signals[id] = true
	# Every line for that signal, not just the newest: the same carrier heard twice is one
	# signal, and greying only one of the two would leave the feed half read.
	if _lines_box == null:
		return
	for child in _lines_box.get_children():
		if child is Control and StringName(child.get_meta(&"signal_id", &"")) == id:
			_paint(child)


## The colour for a row's message: grey if the signal behind it has been read, or while the
## pointer is on it, otherwise the line's own colour.
##
## One place decides this, so a line that has been read cannot go back to green the moment
## the pointer leaves it.
func _paint(row: Node) -> void:
	var message: Variant = row.get_meta(&"message")
	var base: Variant = row.get_meta(&"base_color")
	if not (message is Label) or not (base is Color):
		return
	var spent: bool = bool(row.get_meta(&"hovered", false)) \
		or _read_signals.has(StringName(row.get_meta(&"signal_id", &"")))
	# Applied to the message only: the timestamp is not part of what is being read.
	(message as Label).add_theme_color_override(&"font_color",
		SPENT_COLOR if spent else base)


func _on_row_input(event: InputEvent, row: Node) -> void:
	# Only a left click opens anything. A right click or a drag has no meaning here, and
	# acting on every button would open the menu by accident.
	var press := event as InputEventMouseButton
	if press == null or not press.pressed:
		return
	if press.button_index != MOUSE_BUTTON_LEFT:
		return
	# Nothing to mark: hovering a line already read it, and a click can only land on a line
	# the pointer has been on.
	_open_signal(row.get_meta(&"channel"), row.get_meta(&"signal_id"))


## Opens the signals menu on [param channel], scrolled to [param signal_id] within it, so
## the row that was clicked is the row in view rather than one somewhere down the list.
func _open_signal(channel: StringName, signal_id: StringName) -> void:
	if channel.is_empty():
		return
	var menu: Control = MenuController.get_menu(MenuController.Id.SIGNALS)
	if menu == null:
		return
	if menu.has_method(&"select_signal"):
		menu.call(&"select_signal", channel, signal_id)
	MenuController.open_menu(MenuController.Id.SIGNALS)


func _with_count(text: String, count: int) -> String:
	return text if count <= 1 else "%s  x%d" % [text, count]


## The colour a line is drawn in, grey if the player has already been over a line for that
## signal. A redetection is a new line but not news, and drawing it green again would put a
## signal the player has read back into the feed every few seconds.
func _color_for(kind: StringName, signal_id: StringName = &"") -> Color:
	if not signal_id.is_empty() and _read_signals.has(signal_id):
		return SPENT_COLOR
	return KIND_COLORS.get(kind, DEFAULT_COLOR)


## Scrolls to the newest line. Deferred, because the container has not been laid out
## until after this frame, so asking for its height now would clamp to the old one.
func _follow() -> void:
	if _scroll == null:
		return
	_follow_later.call_deferred()


func _follow_later() -> void:
	if _scroll == null or not is_inside_tree():
		return
	# A second frame, not just a deferred call: a deferred call still lands in the same
	# layout pass as the add, where the feed's height is the one it had before the line.
	await get_tree().process_frame
	if _scroll == null or not is_inside_tree():
		return
	var bar: VScrollBar = _scroll.get_v_scroll_bar()
	if bar:
		_scroll.scroll_vertical = int(bar.max_value)


func _same_as_last(text: String, kind: StringName) -> bool:
	if repeat_merge_window <= 0.0 or text != _last_text or kind != _last_kind:
		return false
	# Only merges into the line while its window is open. Past that the repeat is a
	# separate event and gets a line of its own, so the count never implies "since
	# the start of the session".
	return Time.get_ticks_msec() - _last_msec < int(repeat_merge_window * 1000.0)


# --- Subscribed events -----------------------------------------------------

func _on_signal_found(channel: StringName, found: Resource, count: int) -> void:
	var signal_name := _resource_text(found, "display_name", "a signal")
	# The same words every time this signal is heard. Phrasing it by count - "new" on the
	# first hearing - gave one signal two different strings, and since a merge matches on
	# the text a signal could then never merge with itself at all. The count on the line
	# carries that information instead, and it is the panel's own running total, which is
	# the true one.
	#
	# signal_type is a tag on the signal (carrier, burst, beacon) rather than one of this
	# log's kinds, so it reads as part of the line and the kind stays &"signal".
	var tag := _resource_text(found, "signal_type", "")
	var line := "Signal: %s" % signal_name
	if not tag.is_empty():
		line = "%s (%s)" % [line, tag]
	# The id is what a click on the line scrolls the signals menu to, so it travels with
	# the line rather than being looked up again when the menu is already open.
	var signal_id := StringName(str(found.get(&"id"))) if found != null else &""
	post("%s." % line, &"signal", count, channel, signal_id)


func _on_part_purchased(part: Resource, _owned: int) -> void:
	post("Fitted %s." % _resource_text(part, "display_name", "a part"), &"buy")


func _on_upgrade_purchased(upgrade: Resource, level: int) -> void:
	post("%s is now level %d." % [_resource_text(upgrade, "display_name", "An upgrade"), level], &"buy")


func _on_action_performed(action: Resource) -> void:
	post("Ran %s." % _resource_text(action, "display_name", "an action"), &"action")


func _on_data_transmitted(packet: Resource, _count: int) -> void:
	var line := "Downlinked %s." % _resource_text(packet, "display_name", "data")
	# A signal carries the points it pays out, which a data packet does
	# not, so the line says what arrived as well as what went down.
	var points := int(packet.get(&"points")) if packet != null else 0
	if points > 0:
		line = "%s  (+%d points)" % [line, points]
	post(line, &"downlink")


func _on_active_changed(_satellite: Node) -> void:
	bind_control_panel()
	post("Satellite changed.", &"")


## Best-effort field read off a resource, so this file needs no knowledge of what a
## [SignalDefinition] or a [PartDefinition] is.
func _resource_text(resource: Resource, field: String, fallback: String) -> String:
	if resource == null:
		return fallback
	var value: Variant = resource.get(field)
	if value == null or value is StringName or value is String:
		var text := str(value)
		return text if not text.is_empty() else fallback
	return fallback