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

## Set by [Satellite] so the calculation can read the live stats.
var _stats: SatelliteStats = null


## Connects the stat block this component writes to. [Satellite] does this for you.
func bind(stats: SatelliteStats) -> void:
	_stats = stats


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
	return _stats.speed * distance_scale * delta
