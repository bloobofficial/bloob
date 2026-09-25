class_name TimeController
extends RefCounted
## Impact time (prototype: core/time.ts). Gameplay reads world_scale / player_scale instead of
## assuming 1.0:
##  - global hitstop: everything frozen for N ticks (scale 0), paid from a refilling budget
##  - slow-mo: the world runs slow, Bloob at full speed (the perfect-dodge punish window)
## Local hitstop lives on each enemy (freeze) and on Bloob (self_freeze).

var hitstop := 0
var hitstop_prio := 0
var slowmo := 0
var slowmo_scale := 1.0
var budget := Tuning.HITSTOP_BUDGET_MAX
var denied := 0
var world_scale := 1.0
var player_scale := 1.0


func reset() -> void:
	hitstop = 0
	hitstop_prio = 0
	slowmo = 0
	slowmo_scale = 1.0
	budget = Tuning.HITSTOP_BUDGET_MAX
	denied = 0
	world_scale = 1.0
	player_scale = 1.0


## once at the start of every tick
func advance() -> void:
	budget = minf(Tuning.HITSTOP_BUDGET_MAX, budget + Tuning.HITSTOP_BUDGET_REFILL)
	if hitstop > 0:
		hitstop -= 1
		world_scale = 0.0
		player_scale = 0.0
		if hitstop == 0:
			hitstop_prio = 0
		return
	if slowmo > 0:
		slowmo -= 1
		world_scale = slowmo_scale
		player_scale = 1.0
		return
	world_scale = 1.0
	player_scale = 1.0


## ask for a global freeze; returns true if granted
func request_hitstop(ticks: int, prio: int) -> bool:
	if hitstop > 0 and prio < hitstop_prio:
		denied += 1
		return false
	if budget < ticks and prio < Tuning.Prio.BOSS:
		denied += 1
		return false
	budget = maxf(0.0, budget - ticks)
	hitstop = maxi(hitstop, ticks)
	hitstop_prio = maxi(hitstop_prio, prio)
	return true


func request_slowmo(ticks: int, scale: float) -> void:
	slowmo = maxi(slowmo, ticks)
	slowmo_scale = scale


func frozen() -> bool:
	return world_scale == 0.0
