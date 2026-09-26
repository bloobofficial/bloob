class_name Projectiles
extends Node2D
## Every projectile in the room (prototype: sim/bullets.ts): Bloob's goo spit, enemy shots,
## Warden totem shots and the stress-test sprayers. Pooled data + one draw call per frame:
## the stress preset puts thousands in the air, far too many for one node each.
## Owners: 0 Bloob, 1 sprayer, 2 enemy (hits Bloob), 3 totem.

const OWNER_PLAYER := 0
const OWNER_EMITTER := 1
const OWNER_ENEMY := 2
const OWNER_TOTEM := 3
const OWNER_BOLT := 4      ## Bloob's staff bolts
const EMIT_PER_TICK := 14
const EMIT_SPEED := 5.5
const EMIT_LIFE := 62

var world: World
var pos := PackedVector2Array()
var z := PackedFloat32Array()
var vel := PackedVector2Array()
var life := PackedFloat32Array()
var dmg := PackedFloat32Array()
var who_of := PackedByteArray()   ## owner per projectile
var dropped := 0
## stress-test sprayers: [{pos, angle, spin}]
var emitters: Array[Dictionary] = []


func clear() -> void:
	pos.clear(); z.clear(); vel.clear(); life.clear(); dmg.clear(); who_of.clear()
	emitters.clear()
	queue_redraw()


func count() -> int:
	return pos.size()


func spawn(at: Vector2, at_z: float, v: Vector2, lifetime: float, damage: float, who: int) -> void:
	if pos.size() >= Tuning.MAX_BULLETS:
		dropped += 1
		return   # cap: drop quietly
	pos.append(at); z.append(at_z); vel.append(v); life.append(lifetime); dmg.append(damage); who_of.append(who)


func _remove(i: int) -> void:
	var last := pos.size() - 1
	pos[i] = pos[last]; z[i] = z[last]; vel[i] = vel[last]; life[i] = life[last]; dmg[i] = dmg[last]; who_of[i] = who_of[last]
	pos.resize(last); z.resize(last); vel.resize(last); life.resize(last); dmg.resize(last); who_of.resize(last)


func update_emitters() -> void:
	var s := world.time.world_scale
	if emitters.is_empty() or s == 0.0:
		return
	var step := TAU / EMIT_PER_TICK
	for em in emitters:
		em.angle += em.spin * s
		var gz := float(world.map.ground_at(em.pos.x, em.pos.y)) + 16.0
		for n in EMIT_PER_TICK:
			var d := Vector2.from_angle(em.angle + n * step)
			spawn(em.pos + d * 14.0, gz, d * EMIT_SPEED, EMIT_LIFE, 1.0, OWNER_EMITTER)


func update() -> void:
	var map := world.map
	var ps := world.time.player_scale
	var ws := world.time.world_scale
	var p := world.player
	var i := 0
	while i < pos.size():
		var who := who_of[i]
		var s := ps if who == OWNER_PLAYER or who == OWNER_BOLT else ws   # Bloob's shots keep full speed in slow-mo
		if s == 0.0:
			i += 1
			continue
		var at := pos[i] + vel[i] * s
		pos[i] = at
		life[i] -= s
		var bz := z[i]
		if life[i] <= 0.0 or at.x < 0 or at.y < 0 or at.x >= map.px_w or at.y >= map.px_h or map.blocks_shot(at.x, at.y, bz):
			_remove(i)
			continue
		if who == OWNER_ENEMY:
			# enemy shots hit Bloob
			if p.dead or absf(p.z + 12.0 - bz) > 26.0:
				i += 1
				continue
			var d2 := at.distance_squared_to(p.position)
			if p.in_perfect_window() and d2 < pow(Player.R + 14.0, 2):
				p.perfect(null)
				_remove(i)
				continue
			if d2 < pow(Player.R + 4.0, 2):
				p.hurt(dmg[i], at - vel[i])
				_remove(i)
				continue
			i += 1
			continue
		var hit: Enemy = null
		if not world.enemies.is_empty():
			var gcx := floori(at.x / Tuning.CELL)
			var gcy := floori(at.y / Tuning.CELL)
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					for e: Enemy in world.grid_at(gcx + ox, gcy + oy):
						if not e.alive or absf(e.z + 12.0 - bz) > 26.0:
							continue
						var rr := e.radius + 3.0
						if at.distance_squared_to(e.position) < rr * rr:
							hit = e
							break
					if hit:
						break
				if hit:
					break
		if hit == null:
			i += 1
			continue
		var n := vel[i].normalized()
		hit.flash = 5
		var kn := (0.35 if hit.is_brute() else (4.0 if who == OWNER_BOLT else 2.2)) * hit.knock_mul
		hit.knock += n * kn
		if who != OWNER_EMITTER and hit.freeze == 0:
			hit.freeze = 2   # local hitstop: only the struck enemy stalls
		Events.push(Ev.HIT, at.x, at.y, n.x, n.y, bz)
		var damage := dmg[i]
		_remove(i)
		CombatRules.damage_enemy(world, hit, damage)
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	var map := world.map
	# shadows under enemy shots lie on the ground
	for i in pos.size():
		if who_of[i] == OWNER_ENEMY:
			var g := map.ground_at(pos[i].x, pos[i].y)
			if g != Tuning.VOID_H:
				Draw25.dot(self, View.to_world(pos[i], g), 4.0, Color(0, 0, 0, 0.3))
	# the glows stand upright: one counter-scaled transform for all of them
	var k := View.ground_k
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, View.upright()))
	for i in pos.size():
		var w := View.to_world(pos[i], z[i])
		var at := Vector2(w.x, w.y * k)
		match who_of[i]:
			OWNER_PLAYER:
				Draw25.dot(self, at, 3.4, Color(0.8, 1, 0.55))
			OWNER_ENEMY:
				Draw25.dot(self, at, 9.0, Color(1, 0.3, 0.6, 0.18))
				Draw25.dot(self, at, 4.5, Color(1, 0.3, 0.6))
			OWNER_TOTEM:
				Draw25.dot(self, at, 3.0, Color(1, 0.85, 0.45))
			OWNER_BOLT:
				Draw25.dot(self, at, 10.0, Color(0.55, 0.65, 1, 0.22))
				Draw25.dot(self, at, 4.6, Color(0.75, 0.85, 1))
			_:
				# stress-test sprayer shots: many of them, so a cheap square
				draw_rect(Rect2(at.x - 2.2, at.y - 2.2, 4.4, 4.4), Color(0.3, 0.75, 0.8, 0.8))
	draw_set_transform(Vector2.ZERO)
