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
## This is the calculation seam and it is intentionally left for you. It has to
## return a distance in whatever unit the distance stat is tracked in, since the
## result is added to the stat verbatim. The live stats are reachable through
## [member _stats], so the inputs are already there, e.g.
## [code]_stats.speed[/code] for the current speed.
##
## Runs on the render frame, not the physics frame. Move it to
## [method _physics_process] instead if you want it tied to the simulation.
func distance_for_delta(_delta: float) -> float:
	return 0.0
