class_name Hazard
extends Node2D
## A telegraphed blast (prototype: sim/hazards.ts): a ring appears on the ground, then goes
## off when its fuse runs out. Owner 0 = enemy (volatile deaths, hurts Bloob),
## owner 1 = Bloob (the Blink decoy, hurts enemies).

var world: World
var z := 0.0
var radius := 50.0
var timer := 30
var total := 30
var dmg := 10.0
var owner_side := 0


func setup(w: World, at: Vector2, pz: float, r: float, fuse: int, damage: float, who: int) -> void:
	world = w
	position = at
	z = pz
	radius = r
	timer = fuse
	total = fuse
	dmg = damage
	owner_side = who
	Events.push(Ev.HAZARD_ARM, at.x, at.y, r, fuse, pz)


## returns false once it has gone off
func tick() -> bool:
	if world.time.frozen():
		return true
	timer -= 1
	queue_redraw()
	if timer > 0:
		return true
	Events.push(Ev.BLAST, position.x, position.y, radius, owner_side, z)
	var p := world.player
	if owner_side == 0:
		if position.distance_to(p.position) < radius + Player.R and absf(p.z - z) < 30.0:
			if p.in_perfect_window():
				p.perfect(null)
			else:
				p.hurt(dmg, position)
	else:
		CombatRules.aoe_hit(world, position, z, {
			radius = radius, damage = dmg * p.out_mul(), knock = 7.0, knock_up = 4.0, stagger = 30, freeze = 4, breaks_poise = false, step = 5,
		})
	return false


func _draw() -> void:
	var t := 1.0 - float(timer) / maxf(1.0, total)
	var c := Color(1, 0.3, 0.22) if owner_side == 0 else Color(1, 0.85, 0.5)
	var at := Vector2(0, View.lift(z))
	Draw25.ground_circle(self, at, radius, Color(c, 0.12 + t * 0.28))
	Draw25.ground_ring(self, at, radius, Color(c, 0.5 + t * 0.5), 2.5)
	Draw25.ground_ring(self, at, radius * t, Color(c, 0.6), 2.0)
