class_name Waves
extends RefCounted
## A run room's fight (the run's counterpart to the Director): the room's rolled waves come
## out one after another, each spawn telegraphed on the ground first so nothing appears on
## top of Bloob unannounced. The next wave comes once the last one is down.

const TELL_TICKS := 50        ## spawn telegraph
const WAVE_GAP := 45          ## breather between waves
const MIN_DIST := 170.0       ## spawns keep at least this far from Bloob


## The fight begins: seal the exits and call the first wave.
static func engage(world: World) -> void:
	world.phase = World.Phase.COMBAT
	world.doors_open = false
	world.wave = 0
	var p := world.player
	Events.push(Ev.ENGAGE, p.position.x, p.position.y, 0, 0, p.z)
	Events.push(Ev.DOORS_SEALED, p.position.x, p.position.y, 0, 0, p.z)
	call_wave(world, 0, 20)


## Telegraph wave `n` (0-based); its enemies arrive after `delay` + the tell.
static func call_wave(world: World, n: int, delay: int) -> void:
	var waves: Array = world.room.waves
	if n >= waves.size():
		return
	world.wave = n
	var list: Array = waves[n]
	var champs := world.room.champions if n == 0 else 0
	var spots := _spots(world, list.size())
	for k in list.size():
		var at: Vector3 = spots[k]
		world.pending.append({kind = list[k], pos = Vector2(at.x, at.y), z = at.z, t = delay + TELL_TICKS + k * 6, champ = k < champs})
	var p := world.player
	if waves.size() > 1:
		Events.push(Ev.WAVE, p.position.x, p.position.y, n + 1, waves.size(), p.z)


## One tick: count down the telegraphs, bring enemies in, call the next wave when it's quiet.
static func tick(world: World) -> void:
	if world.phase != World.Phase.COMBAT or world.time.frozen():
		return
	for s in world.pending.duplicate():
		s.t -= 1
		if s.t == TELL_TICKS:
			Events.push(Ev.SPAWN_TELL, s.pos.x, s.pos.y, s.kind, TELL_TICKS, s.z)
		if s.t > 0:
			continue
		world.pending.erase(s)
		var e := Director.spawn_enemy(world, s.kind, s.pos, s.z)
		if e == null:
			continue
		if s.champ:
			make_champion(world, e)
	if world.pending.is_empty() and world.enemies.is_empty() and world.wave + 1 < world.room.waves.size():
		call_wave(world, world.wave + 1, WAVE_GAP)


## An elite: a champion with one or two affixes, tougher and harder-hitting.
static func make_champion(world: World, e: Enemy) -> void:
	if e.champ or e.data.boss:
		return
	var rng := world.rng
	var affix: int = Tuning.AFFIX_BITS[rng.pick(Tuning.AFFIX_BITS.size())]
	if rng.chance(0.5):
		affix |= Tuning.AFFIX_BITS[rng.pick(Tuning.AFFIX_BITS.size())]
	e.champ = true
	e.affix = affix
	e.hp *= Tuning.CHAMPION_HP_MUL
	e.max_hp = e.hp
	e.dmg_mul *= 1.25
	e.size *= 1.12
	if affix & Tuning.Affix.SWIFT:
		e.speed *= 1.35
	if affix & Tuning.Affix.ARMORED:
		e.hp *= 1.8
		e.max_hp = e.hp
		e.knock_mul *= 0.5
	if affix & Tuning.Affix.GIANT:
		e.hp *= 2.0
		e.max_hp = e.hp
		e.knock_mul *= 0.6
		e.size *= 1.4
		e.radius = minf(28.0, e.radius * 1.4)
		e.apply_radius()
	Events.push(Ev.CHAMPION, e.position.x, e.position.y, affix, 0, e.z)


## `n` spawn points away from Bloob: the room's spawn markers first, then open floor.
static func _spots(world: World, n: int) -> Array:
	var map := world.map
	var rng := world.rng
	var p := world.player.position
	var out := []
	var marks: Array[Vector3] = map.spawns.duplicate()
	for i in range(marks.size() - 1, 0, -1):
		var j := rng.pick(i + 1)
		var t := marks[i]
		marks[i] = marks[j]
		marks[j] = t
	for m in marks:
		if out.size() >= n:
			break
		if Vector2(m.x, m.y).distance_to(p) >= MIN_DIST:
			out.append(Vector3(m.x + rng.rangef(-10, 10), m.y + rng.rangef(-10, 10), m.z))
	var tries := 0
	while out.size() < n and tries < 200:
		tries += 1
		var c := Vector2(rng.rangef(64, map.px_w - 64), rng.rangef(64, map.px_h - 64))
		if not map.walkable(c.x, c.y) or map.door_at(c.x, c.y) != 0:
			continue
		if c.distance_to(p) < MIN_DIST and tries < 150:
			continue
		var g := float(map.ground_at(c.x, c.y))
		if not map.can_stand(c.x, c.y, 12.0, g, false):
			continue
		out.append(Vector3(c.x, c.y, g))
	while out.size() < n:
		out.append(Vector3(p.x, p.y - 120.0, world.player.z))
	return out
