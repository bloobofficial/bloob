class_name AttackData
extends Resource
## An enemy attack pattern (prototype: content/attacks.ts). All attacks share one flow:
## approach -> windup (tell; aim locks at AIM_LOCK) -> active -> recover -> reposition.

enum Kind { DASH, SHOOT, SLAM, LEAP, STRIKE }

@export var id := ""
@export var name := ""
@export var kind: Kind = Kind.DASH
@export var range := 100.0        ## starts when Bloob is within this distance
@export var windup := 20          ## ticks of telegraph
@export var active := 10          ## ticks of the attack itself
@export var recover := 30         ## ticks of vulnerability afterwards
@export var cooldown := Vector2i(120, 200)
@export var damage := 8.0
@export var speed := 0.0          ## dash or projectile speed (units/tick)
@export var radius := 0.0         ## blast radius (slam / leap)
@export var shots := 0
@export var spread := 0.0         ## radians between shots
@export var heavy := false        ## heavy tells get a micro-freeze
@export var arc := 0.8            ## strike: half-angle of the wedge


## where an attacker stands while its attack recharges
func spacing() -> float:
	return maxf(84.0, minf(190.0, range * 0.6))
