class_name Hunt
extends RefCounted
## A generated map's monsters (the map's counterpart to Waves): Tuning.MAP_MONSTERS of them,
## asleep in their glades from the moment Bloob arrives. They stroll about where they lie until
## he comes close (or hits one), then that monster and its pack wake and fight. Nothing seals:
## you choose which glade to walk into. When all of them have fallen the map is cleared and
## the gate opens.
##
## Toughness: a monster takes about Tuning.COMBOS_TO_KILL full combos of the weapon in hand
## when it wakes (the weapon's combo damage at the job's base damage; levels, techs and
## passives still make you stronger than that). Champions take half as much again.

const CHAMPION_COMBOS := 1.5


## Put the room's monsters down where they sleep.
static func populate(world: World) -> void:
	var C := float(Tuning.CELL)
	for m in world.room.monsters:
		var at := world.free_spot(Vector2((m.cell.x + 0.5) * C, (m.cell.y + 0.5) * C))
		var e := Director.spawn_enemy(world, m.kind, at, float(world.map.ground_at(at.x, at.y)))
		if e == null:
			continue
		if m.champ:
			Waves.make_champion(world, e)
		e.dormant = true
		e.home = at
		e.timer = world.rng.pick(120)


## One tick: wake anything Bloob has come close to.
static func tick(world: World) -> void:
	var p := world.player
	if p.dead or world.phase != World.Phase.ENTERED:
		return
	for e: Enemy in world.enemies:
		if e.alive and e.dormant and e.position.distance_to(p.position) < Tuning.WAKE_DIST and absf(e.z - p.z) < 70.0:
			wake(world, e)


## Wake a monster (and every sleeping one near it): it sizes itself up against the weapon in
## hand and comes for Bloob.
static func wake(world: World, e: Enemy) -> void:
	if not e.dormant or not e.alive:
		return
	e.dormant = false
	var hp := toughness(e.champ) * world.rng.rangef(0.92, 1.08)
	e.hp = hp
	e.max_hp = hp
	e.state = Enemy.St.APPROACH
	e.timer = 0
	e.cd = maxi(e.cd, 30)
	e.vel = Vector2.ZERO
	Events.push(Ev.ENGAGE, e.position.x, e.position.y, 1, 0, e.z)
	for o: Enemy in world.enemies:
		if o.dormant and o.position.distance_to(e.position) < Tuning.PACK_DIST:
			wake(world, o)


## hit points for a monster woken now: COMBOS_TO_KILL full combos of the weapon in hand
static func toughness(champ: bool) -> float:
	var per_combo := GameState.weapon_data().combo_damage() * GameState.job_data().dmg_mul
	return Tuning.COMBOS_TO_KILL * per_combo * (CHAMPION_COMBOS if champ else 1.0)


## how many are awake and still standing
static func awake(world: World) -> int:
	var n := 0
	for e: Enemy in world.enemies:
		if e.alive and not e.dormant:
			n += 1
	return n
