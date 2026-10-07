class_name SatelliteMotion
extends Node
## Accumulates distance from Earth for as long as the game is running.
##
## [method _process] ticks every frame and adds whatever [method distance_for_delta]
## returns to the distance stat. It follows the tree's process mode, so a paused
## game stops accruing distance - that is the point of pausing.
##
## [method distance_for_delta] is the only place the physics belongs. It is
## deliberately empty: implement it and everything else keeps working unchanged.

## Turn accrual off without removing the component. Handy while the satellite is
## docked or the game is showing a cutscene.
@export var accrual_enabled: bool = true

## Multiplier on [member SatelliteStats.SPEED] when accruing distance. One by
## default, because the two stats already agree: speed is tracked in km/s and the
## distance in km, so one second at [code]speed[/code] km/s covers
## [code]speed[/code] km. Raise it to make the satellite cover ground faster than
## it is genuinely travelling, e.g. while a warp drive is engaged.
@export_range(0.0, 100.0, 0.1) var distance_scale: float = 1.0

## Part whose fitted copies scale the speed, and the upgrade whose level
## divides that scale. Both are sold under the same id, one as hardware
## and one as levels of the array.
const SOLAR_PANEL_PART := &"solar_panels"
const SOLAR_PANEL_UPGRADE := &"solar_panels"

## The speed scale one fitted solar panel adds on its own. Halved
## from a third, so a full array of panels hurries the satellite
## along without leaving the thrusters far behind.
const SOLAR_SCALE_PER_PANEL := 0.15
## What one level of the solar panel upgrade adds to every panel's
## share: a tenth of a panel's own share, so a level barely nudges
## the speed no matter how many are bought.
const SOLAR_SCALE_PER_LEVEL := SOLAR_SCALE_PER_PANEL / 10.0

## Set by [Satellite] so the calculation can read the live stats.
var _stats: SatelliteStats = null
## Set by [Satellite] so the solar panel count can be read off the mounts.
var _slots: SatelliteSlots = null
## Set by [Satellite] so the solar panel upgrade level can be read.
var _upgrades: SatelliteUpgrades = null


## Connects the modules this component reads. [Satellite] does this for you.
func bind(stats: SatelliteStats, slots: SatelliteSlots = null, upgrades: SatelliteUpgrades = null) -> void:
	_stats = stats
	_slots = slots
	_upgrades = upgrades


func _process(delta: float) -> void:
	if not accrual_enabled or _stats == null:
		return
	var step := distance_for_delta(delta)
	if not is_zero_approx(step):
		_stats.add_stat(SatelliteStats.DISTANCE_FROM_EARTH, step)


## How much distance to add for one frame of [param delta] seconds.
##
## The default is speed times the frame time, which is what makes the readout move
## on its own: every upgrade or part that raises speed raises the rate the distance
## grows at, and the HUD follows without being told.
##
## The speed is scaled by the solar array first, through
## [method solar_scale], which is what makes the panels on the hull
## matter to how fast the satellite actually travels.
##
## Everything else about the motion belongs here - drag, gravity, course changes,
## whatever the game decides a satellite in this world obeys. [method _process]
## adds whatever this returns to [constant SatelliteStats.DISTANCE_FROM_EARTH]
## verbatim, so the unit is whatever that stat is tracked in.
##
## The live stats are reachable through [member _stats], so the inputs are already
## there.
##
## Runs on the render frame, not the physics frame. Move it to
## [method _physics_process] instead if you want it tied to the simulation.
func distance_for_delta(delta: float) -> float:
	if _stats == null:
		return 0.0
	return _stats.speed * distance_scale * solar_scale() * delta


## How much the fitted solar panels scale the speed: every panel on the hull
## adds [constant SOLAR_SCALE_PER_PANEL], and every level of the solar panel
## upgrade adds [constant SOLAR_SCALE_PER_LEVEL] per panel - a panel adds its
## share even before the first level is bought - so the scale reads as
## [code]1 + panels * (0.15 + 0.015 * level)[/code]. More panels and
## more levels both make the satellite faster, with a level doing a
## tenth as much as a panel.
##
## A hull with no panel on it leaves the speed alone, so the satellite
## still moves on its own.
##
## Public because [Satellite] scales the speed readout with it, so the
## numbers on screen show the speed the satellite actually travels at
## rather than the raw sum its thrusters add up to.
func solar_scale() -> float:
	var amount := _slots.fitted_count_of(SOLAR_PANEL_PART) if _slots != null else 0
	var level := _upgrades.level_of(SOLAR_PANEL_UPGRADE) if _upgrades != null else 0
	return 1.0 + amount * (SOLAR_SCALE_PER_PANEL + SOLAR_SCALE_PER_LEVEL * level)
