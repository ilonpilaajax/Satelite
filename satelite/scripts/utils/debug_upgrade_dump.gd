extends Node
## Debug key: press [code]I[/code] to print every upgrade on the active satellite with the
## level it is at, its ceiling and the price of the next level.
##
## Nothing else: no menu, no state, no wiring into the game. It is an autoload only because
## that is the one place a key press can be caught without editing a scene, so removing it is
## deleting this file and its one line in [code]project.godot[/code].

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.keycode == KEY_I:
		_dump_upgrades()


func _dump_upgrades() -> void:
	for entry: Variant in SatelliteController.upgrade_catalogue():
		var upgrade: UpgradeDefinition = entry
		if upgrade == null:
			continue
		print("%s  %d/%d  next %d" % [
			upgrade.id,
			SatelliteController.level_of(upgrade.id),
			upgrade.max_level,
			SatelliteController.cost_of(upgrade.id),
		])