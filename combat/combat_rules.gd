class_name CombatRules
extends RefCounted
## Shared combat rules (prototype: sim/combat.ts): damage to enemies (hex), kills (XP, loot,
## volatile blasts, squad bookkeeping), level ups and area hits (dive slam, Quake, blasts).


## Apply damage to an enemy. Returns true if it died.
static func damage_enemy(world: World, e: Enemy, amount: float, heavy := false) -> bool:
	if not e.alive:
		return false
	if e.dormant:
		Hunt.wake(world, e)   # a sleeping monster wakes when struck (sizing itself up first)
	var d := amount
	if e.hex_t > 0:
		d *= Content.skills[SkillData.Id.HEX].p("dmg_taken", 1.5)
	e.hp -= d
	Events.push(Ev.DAMAGE, e.position.x, e.position.y, d, 1 if heavy else 0, e.z)
	if e.data.boss and not e.enraged and e.hp > 0.0 and e.hp < e.max_hp * 0.5:
		# phase two: faster tells, shorter breathers (the slam's long recovery stays)
		e.enraged = true
		e.speed *= 1.2
		Events.push(Ev.BOSS_PHASE, e.position.x, e.position.y, 0, 0, e.z)
	if e.hp <= 0.0:
		kill_enemy(world, e, false)
		return true
	return false


## Kill an enemy: XP, loot, volatile blast, bookkeeping. ring_out = fell off the island.
static func kill_enemy(world: World, e: Enemy, ring_out: bool) -> void:
	if not e.alive:
		return
	e.alive = false
	var pos := e.position
	var z := e.z
	var kd := e.data
	if not ring_out:
		Events.push(Ev.KILL, pos.x, pos.y, e.kind, e.radius, z)
		world.death_ghost(e)
	world.note_defeat()
	if e.is_brute():
		world.time.request_hitstop(6, Tuning.Prio.ELITE_KILL)
	# XP
	var xp := kd.kill_xp * (3 if e.champ else 1) * (1.0 + (e.level - 1) * Tuning.ENEMY_XP_PER_LVL)
	grant_xp(world, maxi(1, roundi(xp)))
	# passives that feed on kills
	var pl := world.player
	if GameState.kill_mana > 0.0:
		pl.gain_mana(GameState.kill_mana)
	if GameState.kill_haste > 0:
		GameState.haste_t = maxi(GameState.haste_t, GameState.kill_haste)
	if kd.boss:
		world.time.request_hitstop(18, Tuning.Prio.BOSS)
	# runs: Essence (champions and bosses more) and sometimes a health orb
	if world.run:
		var ess := kd.essence * (3 if e.champ else 1)
		if ring_out:
			GameState.add_essence(ess)
		else:
			world.spill_essence(pos, z + 8.0, ess)
			if world.rng.chance(Tuning.CHAMPION_HEAL_CHANCE if e.champ else kd.loot_heal_chance):
				world.spawn_pickup(pos, z + 8.0, Tuning.PICKUP_HEAL, 0)
	# loot (not in the stress test)
	elif world.mode.loot:
		var rng := world.rng
		var mul := Tuning.CHAMPION_LOOT_MUL if e.champ else 1
		var ichor := roundi(rng.rangef(kd.loot_ichor.x, kd.loot_ichor.y + 0.999) - 0.499) * mul
		var drops := [[Tuning.Res.ICHOR, maxi(1, ichor)]]
		if rng.chance(minf(1.0, kd.loot_extra_chance * mul)):
			drops.append([kd.loot_extra, 3 if e.champ else 1])
		if rng.chance(Tuning.CHAMPION_SHARD_CHANCE if e.champ else kd.loot_shard_chance):
			drops.append([Tuning.Res.SHARD, 1])
		var heal := rng.chance(Tuning.CHAMPION_HEAL_CHANCE if e.champ else kd.loot_heal_chance)
		if ring_out:
			# knocked off the island: the bounty goes straight into your pockets
			for dr in drops:
				GameState.add_res(dr[0], dr[1])
			var p := world.player
			Events.push(Ev.PICKUP, p.position.x, p.position.y, drops[0][0], drops[0][1], p.z)
		else:
			for dr in drops:
				var n: int = dr[1]
				# split ichor into a few orbs so it sprays nicely
				var pieces := mini(n, 4) if dr[0] == Tuning.Res.ICHOR else 1
				for k in pieces:
					var amt := n / pieces + (1 if k < n % pieces else 0)
					if amt > 0:
						world.spawn_pickup(pos, z + 8.0, dr[0], amt)
			if heal:
				world.spawn_pickup(pos, z + 8.0, Tuning.PICKUP_HEAL, 0)
	if not ring_out and (e.affix & Tuning.Affix.VOLATILE):
		world.arm_hazard(pos, z, Tuning.VOLATILE_RADIUS, Tuning.VOLATILE_FUSE, Tuning.VOLATILE_DAMAGE * e.dmg_mul, 0)
	Squads.member_died(world, e)
	world.remove_enemy(e)


static func grant_xp(world: World, amount: int) -> void:
	var before := GameState.max_hp
	var gained := GameState.add_xp(amount)
	if gained > 0:
		var p := world.player
		p.max_hp = GameState.max_hp
		p.hp = minf(p.max_hp, p.hp + (GameState.max_hp - before) + p.max_hp * Tuning.LEVEL_HEAL)
		p.max_mana = GameState.mana_max
		p.mana = minf(p.max_mana, p.mana + p.max_mana * Tuning.LEVEL_MANA)
		Events.push(Ev.LEVEL_UP, p.position.x, p.position.y, GameState.level, 0, p.z)


## Hit every enemy in a circle around `at` at height z. Returns hits.
## spec: radius, damage, knock, knock_up, stagger, freeze, breaks_poise, step
static func aoe_hit(world: World, at: Vector2, z: float, spec: Dictionary) -> int:
	var hits := 0
	for e: Enemy in world.enemies.duplicate():
		if not e.alive or absf(e.z - z) > 36.0:
			continue
		var dv := e.position - at
		var d := maxf(dv.length(), 0.001)
		if d > spec.radius + e.radius:
			continue
		hits += 1
		var brute := e.is_brute()
		var n := dv / d
		e.flash = 6
		e.freeze = maxi(e.freeze, int(spec.freeze))
		var falloff := 1.0 - minf(1.0, d / (spec.radius + e.radius)) * 0.5
		var km := e.knock_mul * (0.3 if brute else 1.0)
		e.knock = n * spec.knock * falloff * km
		e.vel *= 0.2
		if not brute:
			if spec.knock_up > 0.0:
				e.vz = maxf(e.vz, spec.knock_up * e.knock_mul)
			if spec.stagger > 0 and e.state != Enemy.St.LUNGE:
				e.state = Enemy.St.STAGGER
				e.timer = maxi(e.timer, int(spec.stagger))
		elif spec.breaks_poise and e.state == Enemy.St.WINDUP:
			e.state = Enemy.St.STAGGER
			e.timer = 45
			e.cd = 60
		Events.push(Ev.MELEE_HIT, e.position.x, e.position.y, n.angle(), spec.step, e.z)
		damage_enemy(world, e, spec.damage)
	return hits
