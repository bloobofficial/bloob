class_name SwingData
extends Resource
## One swing of a weapon combo (prototype: content/combat.ts `Swing`).
## Timings are in ticks (60 per second), distances in world units, angles in radians.

enum Shape { ARC, THRUST, SMASH, RING }

@export var name := ""
@export var windup := 3          ## anticipation before the hit lands
@export var active := 3          ## ticks the hitbox is live (lunge happens here)
@export var recover := 10        ## follow-through; dodge can cancel it
@export var chain_from := 4      ## recover tick from which a buffered next swing may start
@export var range := 46.0        ## reach from Bloob's center
@export var arc := 1.0           ## half-angle of the swing
@export var damage := 1.5
@export var knock := 3.6         ## knockback impulse (units/tick, decays ~18%/tick)
@export var stagger := 10        ## ticks the enemy reels
@export var lunge := 2.4         ## Bloob steps forward (units/tick during active)
@export var freeze_enemy := 3    ## local hitstop on struck enemies
@export var freeze_self := 2     ## local hitstop on Bloob when the swing connects
@export var hitstop := 0         ## global freeze on connect (paid from the hitstop budget)
@export var knock_up := 0.0      ## upward pop (units/tick)
@export var brute_knock_mul := 0.15
@export var breaks_poise := false
@export var width := 0.0         ## > 0: thrust lane this wide
@export var impact := 0.0        ## > 0: smash circle this big at the far end
@export var heavy := false       ## finisher: bigger slash, more shake
@export var pose := -1           ## Bloob swing drawing 0..2 (-1 = step - 1)
@export var has_vis := false
@export var vis_from := 0.0      ## blade angle (relative to aim) at the end of the windup
@export var vis_to := 0.0        ## blade angle at the end of the active frames
@export var vis_lift := 0.0      ## 0 = blade along the ground, 1 = raised straight up
@export var vis_thrust := 0.0    ## weapon pushes forward this far during the active frames
@export var bolt_damage := 0.0   ## > 0: the swing also throws a bolt (costs the weapon's mana_cost)
@export var bolt_speed := 9.0
@export var bolt_shots := 1
@export var bolt_spread := 0.0


func shape() -> Shape:
	if width > 0.0:
		return Shape.THRUST
	if impact > 0.0:
		return Shape.SMASH
	if has_vis and absf(vis_to - vis_from) >= TAU - 0.01:
		return Shape.RING
	return Shape.ARC


static func _ease(u: float) -> float:
	var c := clampf(u, 0.0, 1.0)
	return 1.0 - (1.0 - c) * (1.0 - c)


## Blade angle (relative to the aim) after k of the swing's active ticks.
func sweep_at(k: float) -> float:
	var from := vis_from if has_vis else -arc
	var to := vis_to if has_vis else arc
	return from + (to - from) * _ease(k / maxf(1.0, active))


## How far the tip reaches after k active ticks (thrusts push out; everything else = range).
func tip_at(k: float) -> float:
	if width <= 0.0 or vis_thrust == 0.0:
		return range
	return range - vis_thrust * (1.0 - _ease(k / maxf(1.0, active)))


func total_ticks() -> int:
	return windup + active + recover


## A copy with Bloob's modifiers applied: faster wind-ups / follow-throughs, longer reach.
## The active frames keep their length so the hitbox still traces the drawn sweep.
func scaled(speed: float, reach: float) -> SwingData:
	if speed == 1.0 and reach == 1.0:
		return self
	var s := duplicate() as SwingData
	s.windup = maxi(1, roundi(windup / speed))
	s.recover = maxi(2, roundi(recover / speed))
	s.chain_from = chain_from if chain_from >= 99 else maxi(1, roundi(chain_from / speed))
	s.range = range * reach
	s.impact = impact * reach
	s.vis_thrust = vis_thrust * reach
	return s
