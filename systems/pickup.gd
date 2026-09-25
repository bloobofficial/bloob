class_name Pickup
extends Node2D
## A loot orb (prototype: sim/pickups.ts): resource orbs and health orbs. They spray out,
## bounce, then fly to Bloob when he gets close (magnet radius from the profile).
## Position = ground point; `z` = height.

var world: World
var type := 0             ## resource index, or Tuning.PICKUP_HEAL
var amount := 0
var z := 0.0
var vel := Vector2.ZERO
var vz := 0.0
var life := Tuning.PICKUP_LIFE
var magnet := false
var _bob_seed := 0.0


func setup(w: World, at: Vector2, pz: float, t: int, amt: int) -> void:
	world = w
	position = at
	z = pz
	type = t
	amount = amt
	var rng := w.rng
	var a := rng.rangef(0, TAU)
	vel = Vector2.from_angle(a) * rng.rangef(0.6, 2.4)
	vz = rng.rangef(3.0, 5.5)
	_bob_seed = rng.rangef(0, 100)
	reset_physics_interpolation()


## returns false when the pickup is gone
func tick() -> bool:
	var s := world.time.world_scale
	if s == 0.0:
		return true
	life -= 1
	if life <= 0:
		return false
	var p := world.player
	var d := p.position - position
	var d2 := d.length_squared()
	if not p.dead and not magnet and d2 < GameState.magnet * GameState.magnet and life < Tuning.PICKUP_LIFE - 20 and absf(p.z - z) < 60.0:
		magnet = true
	if magnet:
		# fly to Bloob, faster the closer it gets
		var dl := maxf(sqrt(d2), 1.0)
		var sp := minf(11.0, 3.0 + 400.0 / (dl + 30.0))
		vel += (d / dl * sp - vel) * 0.35
		z += (p.z + 10.0 - z) * 0.25
		vz = 0.0
		if dl < Tuning.PICKUP_COLLECT + 4.0:
			_collect()
			return false
	var before := position
	position += vel * s
	if not magnet:
		# bounce off trees, water, walls and props so loot never lands out of reach
		var c := world.map.cell_of(position.x, position.y)
		if c >= 0 and world.map.wall[c]:
			position = before
			vel *= -0.5
		var g := world.map.ground_at(position.x, position.y)
		vz -= 0.45 * s
		z += vz * s
		if g != Tuning.VOID_H and z <= g + 3:
			# bounce, settle
			z = g + 3
			vz = -vz * 0.45 if absf(vz) > 1.2 else 0.0
			vel *= 0.8
		elif g == Tuning.VOID_H and z < -200.0:
			# fell off the island: bank it rather than lose it
			if type != Tuning.PICKUP_HEAL:
				GameState.add_res(type, amount)
			return false
	queue_redraw()
	return true


func _collect() -> void:
	var p := world.player
	if type == Tuning.PICKUP_HEAL:
		p.hp = minf(p.max_hp, p.hp + Tuning.HEAL_ORB)
	else:
		GameState.add_res(type, amount)
	Events.push(Ev.PICKUP, position.x, position.y, type, amount, z)


func _draw() -> void:
	var c := Tuning.res_color(type)
	var fade := 0.3 if life < 180 and (life >> 2) & 1 else 1.0
	var bob := 0.0 if magnet else sin(world.tick_n * 0.12 + _bob_seed) * 2.0 + 3.0
	var big := 5.0 if type == 3 else (4.5 if type == 4 else 3.2 + minf(2.0, amount * 0.3))
	var g := world.map.ground_at(position.x, position.y)
	if g != Tuning.VOID_H and not magnet:
		Draw25.ground_circle(self, Vector2(0, View.lift(g)), big * 0.9, Color(0, 0, 0, 0.3))
	var at := Vector2(0, View.lift(z + bob))
	Draw25.upright_circle(self, at, big * 2.0, Color(c, 0.12 * fade))
	if type == 3:
		draw_set_transform(at, PI / 4.0, Vector2(1.0, View.upright()))
		draw_rect(Rect2(-big * 0.7, -big * 0.7, big * 1.4, big * 1.4), Color(c, fade))
		draw_set_transform(Vector2.ZERO)
	else:
		Draw25.upright_circle(self, at, big, Color(c, fade))
