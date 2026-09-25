class_name Director
extends RefCounted
## Decides what spawns, where and when for the current room's encounter
## (prototype: sim/director.ts). The room sets the budget; the preset (ModeData) sets the dials.

const SQUAD_LAYOUT := [[5, Enemy.Role.LEAD], [4, Enemy.Role.PIN], [4, Enemy.Role.PIN], [2, Enemy.Role.FLANK], [2, Enemy.Role.FLANK]]
## small squads for capped rooms: a pinner and two flankers, or a brute leading two
const SQUAD_SMALL := [[4, Enemy.Role.PIN], [2, Enemy.Role.FLANK], [2, Enemy.Role.FLANK]]
const SQUAD_SMALL_ELITE := [[5, Enemy.Role.LEAD], [2, Enemy.Role.FLANK], [2, Enemy.Role.FLANK]]


## a spawn marker away from the player (null if none this time)
static func spawn_point(world: World):
	var spawns := world.map.spawns
	if spawns.is_empty():
		return null
	var rng := world.rng
	var p := world.player.position
	for t in 6:
		var m: Vector3 = spawns[rng.pick(spawns.size())]
		if Vector2(m.x, m.y).distance_squared_to(p) < Tuning.MIN_SPAWN_DIST * Tuning.MIN_SPAWN_DIST:
			continue
		return Vector3(m.x + rng.rangef(-12, 12), m.y + rng.rangef(-12, 12), m.z)
	return null   # degrade: skip this spawn rather than drop one on the player


## counts toward the room's budget unless `free` (dev spawns)
static func spawn_enemy(world: World, kind: int, at: Vector2, z: float, free := false) -> Enemy:
	if world.enemies.size() >= Tuning.MAX_ENEMIES:
		return null   # hard cap: quietly drop
	var rng := world.rng
	var pers := Content.enemies[kind]
	var e := world.add_enemy(kind, at, z)
	e.hp = pers.hp
	e.radius = pers.radius
	e.speed = pers.speed * rng.rangef(0.85, 1.15)
	e.phase = rng.rangef(0, TAU)
	e.weave_amp = pers.weave_amp * rng.rangef(0.7, 1.2)
	e.weave_freq = pers.weave_freq * rng.rangef(0.7, 1.3)
	e.orbit_dir = rng.sgn()
	e.route = rng.weighted(pers.routes)
	e.anchor = -1
	e.state = Enemy.St.APPROACH
	e.timer = 0
	e.cd = 60 if kind == 5 else 0
	e.squad = -1
	e.role = Enemy.Role.NONE
	_roll_attributes(world, e)
	if not free:
		world.spawned += 1
	return e


## Randomize this enemy: level, size / hp variation, attack pattern, champion affixes.
static func _roll_attributes(world: World, e: Enemy) -> void:
	var rng := world.rng
	var kind := e.kind
	var pers := e.data
	var lvl := maxi(1, world.threat)
	var sz := rng.rangef(Tuning.ROLL_SIZE.x, Tuning.ROLL_SIZE.y)
	var tier := world.diff
	# durability = kind base x level x map tier x run setting x dev multiplier
	var hp_mul := rng.rangef(Tuning.ROLL_HP.x, Tuning.ROLL_HP.y) * (1.0 + Tuning.ENEMY_HP_PER_LVL * (lvl - 1)) * tier.hp_mul * Tuning.RUN_HP_MUL * world.dev.enemy_hp
	var dmg_mul := (1.0 + Tuning.ENEMY_DMG_PER_LVL * (lvl - 1)) * tier.dmg_mul * Tuning.RUN_DMG_MUL
	e.speed *= tier.speed_mul * Tuning.RUN_SPEED_MUL
	var knock_mul := 1.0
	var vis := sz
	var affix := 0
	var champ := false
	var atk: AttackData = null
	var patterns: bool = world.mode.patterns if world.dev.patterns < 0 else world.dev.patterns == 1
	if patterns:
		atk = pers.attacks[rng.weighted(pers.attack_weights)] if pers.attacks.size() > 0 else null
		# champions: the map tier sets the base odds, monster level adds a little
		var chance: float
		if world.dev.champ_chance >= 0.0:
			chance = world.dev.champ_chance
		elif world.encounter != null:
			chance = minf(Tuning.ELITE_MAX, tier.elite_chance + Tuning.ELITE_PER_LEVEL * (lvl - 1))
		else:
			chance = minf(Tuning.CHAMPION_MAX_CHANCE, Tuning.CHAMPION_BASE_CHANCE + Tuning.CHAMPION_PER_LVL * (lvl - 1))
		if kind != 5 and rng.chance(chance):
			champ = true
			var n := 2 if rng.chance(tier.two_affix_chance) else 1
			for k in n:
				affix |= Tuning.AFFIX_BITS[rng.pick(Tuning.AFFIX_BITS.size())]
			hp_mul *= Tuning.CHAMPION_HP_MUL
			dmg_mul *= 1.25
			vis *= 1.12
	if affix & Tuning.Affix.SWIFT:
		e.speed *= 1.35
	if affix & Tuning.Affix.ARMORED:
		hp_mul *= 1.8
		knock_mul *= 0.5
	if affix & Tuning.Affix.GIANT:
		hp_mul *= 2.0
		knock_mul *= 0.6
		vis *= 1.4
	var r := pers.radius * sz * (1.4 if affix & Tuning.Affix.GIANT else 1.0)
	e.radius = minf(28.0, r)
	e.hp = pers.hp * hp_mul
	e.max_hp = e.hp
	e.level = lvl
	e.affix = affix
	e.champ = champ
	e.atk = atk
	e.aspd = 0.0
	e.wtot = 1
	e.dmg_mul = dmg_mul
	e.knock_mul = knock_mul
	e.hex_t = 0
	e.age = 0
	e.size = vis
	e.leap = false
	e.cd = floori(rng.rangef(40, 140))   # don't all attack at once on spawn
	e.apply_radius()
	if champ:
		Events.push(Ev.CHAMPION, e.position.x, e.position.y, affix, 0, e.z)


static func squad_layout(world: World) -> Array:
	if not world.mode.cap_all:
		return SQUAD_LAYOUT
	var tier := world.encounter.tier if world.encounter else 1
	return SQUAD_SMALL_ELITE if tier >= 3 else SQUAD_SMALL


## this room's concurrency cap: dev override, else the room, else the map tier
static func alive_cap(world: World) -> int:
	if world.dev.max_alive >= 0:
		return world.dev.max_alive
	var enc := world.encounter
	if enc == null:
		return 0
	return enc.max_alive if enc.max_alive > 0 else world.diff.max_alive


static func spawn_squad(world: World) -> void:
	var s := -1
	for k in world.squads.size():
		if not world.squads[k].alive:
			s = k
			break
	if s < 0:
		world.squads.append(Squads.new_squad())
		s = world.squads.size() - 1
	var pt = spawn_point(world)
	if pt == null:
		return
	var n := 0
	var flank_side := 1
	var rng := world.rng
	for entry in squad_layout(world):
		var at := Vector2(pt.x + rng.rangef(-30, 30), pt.y + rng.rangef(-30, 30))
		if not world.map.can_stand(at.x, at.y, 16, pt.z, false) or absf(world.map.ground_at(at.x, at.y) - pt.z) > 1.0:
			at = Vector2(pt.x, pt.y)
		var e := spawn_enemy(world, entry[0], at, pt.z)
		if e == null:
			continue
		e.squad = s
		e.role = entry[1]
		e.route = EnemyKindData.Route.DIRECT
		if e.role == Enemy.Role.FLANK:
			e.orbit_dir = flank_side
			flank_side = -flank_side
		n += 1
	if n == 0:
		return
	var sq: Dictionary = world.squads[s]
	sq.alive = true
	sq.state = Squads.GATHER
	sq.timer = 0
	sq.members = n
	sq.front = (Vector2(pt.x, pt.y) - world.player.position).angle()
	world.squad_total_members += n


static func run(world: World) -> void:
	var enc := world.encounter
	var dev := world.dev
	if enc == null or world.time.frozen() or not dev.director:
		return
	var m := world.mode
	var t := world.room_tick / 60.0
	var budget := world.budget()
	var budget_left := (budget - world.spawned) if budget > 0 else 1 << 30
	if budget_left <= 0:
		return
	var cap := alive_cap(world)
	var squad_size := squad_layout(world).size()
	# squads only where the map tier allows coordinated behaviour
	var squads_on := enc.squads > 0 and m.squad_every > 0 and (not m.cap_all or world.diff.squads)
	# capped rooms: squads first, so the horde never fills the slots they need
	if m.cap_all:
		budget_left = _try_squads(world, squads_on, squad_size, cap, budget_left)
	var every := maxi(1, roundi(m.spawn_every / dev.spawn_mul))
	if m.spawn_every > 0 and world.room_tick % every == 0 and budget_left > 0:
		var target := mini(cap, floori(enc.start_alive + enc.ramp_per_sec * dev.spawn_mul * t))
		var counted := world.enemies.size() if m.cap_all else world.enemies.size() - world.squad_total_members
		var n := mini(mini(ceili(m.spawn_burst * maxf(1.0, dev.spawn_mul / 2.0)), target - counted), budget_left)
		for k in n:
			var pt = spawn_point(world)
			if pt == null:
				continue
			spawn_enemy(world, world.rng.weighted(world.mix), Vector2(pt.x, pt.y), pt.z)
	if not m.cap_all:
		_try_squads(world, squads_on, squad_size, cap, budget_left)


static func _try_squads(world: World, squads_on: bool, squad_size: int, cap: int, budget_left: int) -> int:
	var m := world.mode
	var enc := world.encounter
	if not squads_on or world.room_tick % 30 != 0 or budget_left < squad_size:
		return budget_left
	if m.cap_all and world.enemies.size() + squad_size > cap:
		return budget_left
	var desired := mini(enc.squads, m.squads_start + floori(world.room_tick * world.dev.spawn_mul / m.squad_every))
	if world.squad_count() < desired:
		var before := world.spawned
		spawn_squad(world)
		budget_left -= world.spawned - before
	return budget_left
