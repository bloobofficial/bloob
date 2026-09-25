extends Node
## Headless gameplay tests, modelled on the prototype's tests/sim.test.ts.
## Run:  godot --headless res://tests/run_tests.tscn   (exit code 0 = all passed)
## Each check drives the real World scene with scripted input, tick by tick.

const WORLD := preload("res://world/world.tscn")
const C := 32.0

var passed := 0
var failed := 0
var world: World
var events := {}


func _ready() -> void:
	_run.call_deferred()


func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
		print("  ok   ", name)
	else:
		failed += 1
		print("  FAIL ", name, "  ", detail)


func _on_event(type: int, _x: float, _y: float, _a: float, _b: float, _z: float) -> void:
	events[type] = events.get(type, 0) + 1


func count(type: int) -> int:
	return events.get(type, 0)


func fresh(room_id: String = "sanctum") -> World:
	if world:
		world.queue_free()
		await get_tree().process_frame
	world = WORLD.instantiate()
	add_child(world)
	world.reset_run(room_id, 1234)
	world.spawning = false
	await get_tree().physics_frame
	events.clear()
	return world


func cell(cx: float, cy: float) -> Vector2:
	return Vector2((cx + 0.5) * C, (cy + 0.5) * C)


func place(at: Vector2) -> void:
	world.player.place(at, world.map.ground_at(at.x, at.y))


## a monster for tests: no attack pattern unless given, lots of HP
func dummy(kind: int, at: Vector2, hp := 500.0, atk_id := "") -> Enemy:
	var e := Director.spawn_enemy(world, kind, at, world.map.ground_at(at.x, at.y), true)
	e.hp = hp
	e.max_hp = hp
	e.atk = null
	e.affix = 0
	e.champ = false
	e.knock_mul = 1.0
	e.cd = 0
	if atk_id != "":
		e.atk = load("res://data/attacks/%s.tres" % atk_id)
	return e


func frame(move := Vector2.ZERO, extra := {}) -> InputFrame:
	var f := InputFrame.new()
	f.move = move
	f.aim = extra.aim if extra.has("aim") else world.player.position + Vector2(100, 0)
	for k in extra:
		if k != "aim":
			f.set(k, extra[k])
	return f


## step n ticks with the same input (edge presses only on the first tick)
func steps(n: int, move := Vector2.ZERO, extra := {}) -> void:
	for i in n:
		world.step(frame(move, extra if i == 0 else _held(extra)))


func _held(extra: Dictionary) -> Dictionary:
	var h := {}
	for k in ["fire", "atk", "aim"]:
		if extra.has(k):
			h[k] = extra[k]
	return h


func _station(kind: int):
	for s in world.stations:
		if s.kind == kind:
			return s
	return null


func _run() -> void:
	print("== The Bloob: gameplay tests ==")
	Events.game_event.connect(_on_event)
	await test_smoke()
	await test_rooms()
	await test_height()
	await test_jump()
	await test_combat()
	await test_air_and_dive()
	await test_loot_and_progression()
	await test_skills()
	await test_enemy_attacks()
	await test_stations()
	test_world_graph()
	print("== %d passed, %d failed ==" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)


func test_smoke() -> void:
	await fresh()
	check("boot: world loads the Sanctum", world.room.id == "sanctum")
	var p0 := world.player.position
	steps(60, Vector2.LEFT)
	var dx := p0.x - world.player.position.x
	check("move: 60 ticks = 198 units (3.3/tick)", absf(dx - 198.0) < 3.0, "dx=%.1f" % dx)
	steps(40, Vector2.RIGHT)
	check("collision: the Well (a solid station) stops Bloob", world.player.position.x < 26 * C - 10, "x=%.1f" % world.player.position.x)


func test_rooms() -> void:
	await fresh()
	world.spawning = true
	# walk into the Sanctum's north passage (A, cols 20-23)
	place(cell(21.5, 3))
	steps(90, Vector2.UP)
	check("door: Sanctum north door leads to the Hollow", world.room.id == "hollow", world.room.id)
	check("door: Hollow seals while its encounter runs", not world.doors_open and world.remaining() > 0, "remaining=%d" % world.remaining())
	check("door: you arrive inside the room, not on the doorway", world.map.door_at(world.player.position.x, world.player.position.y) == 0)
	world.player.god = true
	steps(200)
	check("director: monsters spawn in a combat room, within the cap", world.enemies.size() > 0 and world.enemies.size() <= Director.alive_cap(world), "alive=%d cap=%d" % [world.enemies.size(), Director.alive_cap(world)])
	# spend the budget: everything spawned and killed
	world.spawning = false
	world.spawned = world.budget()
	events.clear()
	for e in world.enemies.duplicate():
		CombatRules.kill_enemy(world, e, false)
	steps(2)
	check("clear: doors open when the budget is spent and the room is empty", world.doors_open and world.room_state().cleared and count(Ev.ROOM_CLEARED) == 1)
	check("clear: drops a chest of loot", world.pickups.size() > 5 and count(Ev.LOOT) >= 1, "pickups=%d" % world.pickups.size())
	var reward = _station(World.StationKind.REWARD)
	check("reward: the Hollow's sword appears once it's cleared", reward != null and reward.active and count(Ev.ITEM_APPEAR) == 1)
	place(reward.pos)
	steps(1, Vector2.ZERO, {use = true})
	check("reward: taking it owns and equips it", GameState.weapon == Content.weapon_index("sword") and GameState.weapons[1] == 1 and not reward.active)
	# back south to the Sanctum and north again
	var d := world.map.door_info("C")
	place(Vector2(d.in_x, d.in_y))
	steps(90, Vector2.DOWN)
	check("door: back to the Sanctum", world.room.id == "sanctum", world.room.id)
	place(cell(21.5, 3))
	steps(90, Vector2.UP)
	check("persistence: the Hollow remembers it was cleared", world.room.id == "hollow" and world.doors_open and world.enemies.is_empty())
	var rw2 = _station(World.StationKind.REWARD)
	check("reward: it's gone when you come back", rw2 != null and not rw2.active)


func test_height() -> void:
	await fresh()
	# stairs: below the Sanctum's shrine plateau (stairs a/b/c at cols 20-23, rows 12-14)
	place(cell(21.5, 15.5))
	steps(80, Vector2.UP)
	check("stairs: Bloob climbs onto the plateau", world.player.z == 48.0, "z=%.1f" % world.player.z)
	# cliff: the plateau's face at col 17 can't be walked up
	place(cell(17.5, 12.4))
	steps(40, Vector2.UP)
	check("cliff: Bloob can't walk up a cliff face", world.player.z == 0.0 and world.player.position.y > 12 * C, "y=%.1f z=%.1f" % [world.player.position.y, world.player.z])
	# ledge: on the Ridge, a monster knocked off the high plateau lands hard on the floor
	await fresh("ridge")
	world.dev.freeze_ai = true
	place(cell(30, 16))
	var e := dummy(1, cell(10, 9.2))
	check("ledge: enemy starts on the high plateau", e.z == 96.0, "z=%.1f" % e.z)
	e.knock = Vector2(0, 7)
	steps(60)
	check("ledge: knocked off, heavy landing on the floor", is_instance_valid(e) and e.z == 0.0 and count(Ev.LAND) == 1, "z=%.1f lands=%d" % [e.z if is_instance_valid(e) else -1.0, count(Ev.LAND)])
	# void: the Hollow's sinkholes
	await fresh("hollow")
	world.dev.freeze_ai = true
	place(cell(30, 26))
	var k0 := GameState.kills
	var v := dummy(1, cell(9.2, 15))
	v.knock = Vector2(9, 0)
	steps(90)
	check("void: knocked into a pit = ring-out", count(Ev.RING_OUT) == 1 and not v.alive and GameState.kills == k0 + 1)
	world.dev.freeze_ai = false
	place(cell(21, 15))
	var w := dummy(1, cell(9.2, 15))
	steps(120)
	check("void: enemies don't walk off the edge by themselves", is_instance_valid(w) and w.z == 0.0)
	# collision: diagonal into a wall slides along it (the Forge's west wall)
	await fresh("forge")
	place(cell(5, 12))
	var y0 := world.player.position.y
	steps(40, Vector2(-1, 1))
	check("collision: diagonal into a wall slides along it", world.player.position.y > y0 + 40 and world.player.position.x > 4 * C, "x=%.1f dy=%.1f" % [world.player.position.x, world.player.position.y - y0])


func test_jump() -> void:
	await fresh()
	place(cell(8, 16))
	var max_z := 0.0
	steps(1, Vector2.ZERO, {jump = true})
	for i in 60:
		steps(1)
		max_z = maxf(max_z, world.player.z)
	check("jump: apex clears one level, not two", max_z > 48.0 and max_z < 96.0, "apex=%.1f" % max_z)
	check("jump: lands back on the ground", world.player.z == 0.0 and world.player.jumps == 1)
	# jump onto the plateau without the stairs (its south face at row 11)
	place(cell(18.5, 12.5))
	steps(1, Vector2.UP, {jump = true})
	steps(40, Vector2.UP)
	check("jump: lands on the plateau without stairs", world.player.z == 48.0, "z=%.1f" % world.player.z)
	# a two-level cliff can't be jumped (the Ridge's high plateau over its floor)
	await fresh("ridge")
	place(cell(10, 10.4))
	steps(1, Vector2.UP, {jump = true})
	steps(50, Vector2.UP)
	check("jump: can't jump straight up a two-level cliff", world.player.z == 0.0, "z=%.1f" % world.player.z)
	# a press just before landing still jumps (buffer)
	await fresh()
	place(cell(8, 16))
	steps(1, Vector2.ZERO, {jump = true})
	var pressed := false
	for i in 60:
		var soon := world.player.vz < 0.0 and world.player.z < 8.0 and not pressed
		steps(1, Vector2.ZERO, {jump = soon})
		if soon:
			pressed = true
	check("jump: buffered press right before landing still jumps", world.player.jumps == 2, "jumps=%d" % world.player.jumps)


func test_combat() -> void:
	await fresh("proving")
	world.dev.freeze_ai = true
	world.player.god = true
	place(Vector2(30 * C, 26 * C))
	var e := dummy(0, world.player.position + Vector2(40, 0))
	var seen := []
	var knocks := []
	for i in 90:
		world.step(frame(Vector2.ZERO, {atk = true, aim = e.position}))
		var m := world.player.melee
		if m.swinging() and (seen.is_empty() or seen[-1] != m.atk_step):
			seen.append(m.atk_step)
		if e.knock.length() > 0.5 and knocks.size() < seen.size():
			knocks.append(e.knock.length())
		# keep the dummy in reach, knockback measured fresh every swing
		e.position = world.player.position + Vector2(40, 0)
		e.knock = Vector2.ZERO
		e.vz = 0.0
		e.z = 0.0
		if seen.size() >= 3 and not m.swinging():
			break
	check("combo: chains 1 -> 2 -> 3", seen.slice(0, 3) == [1, 2, 3], str(seen))
	check("combo: finisher knocks furthest", knocks.size() >= 3 and knocks[2] > knocks[0] * 2 and knocks[0] > 3, str(knocks))
	check("combat: Bloob damages monsters", e.hp < e.max_hp, "hp=%.1f" % e.hp)
	var k0 := GameState.kills
	var weak := dummy(0, world.player.position + Vector2(40, 0), 1.0)
	for i in 40:
		var at := weak.position if weak.alive else world.player.position + Vector2(40, 0)
		world.step(frame(Vector2.ZERO, {atk = true, aim = at}))
	check("combat: monsters die", not weak.alive and GameState.kills == k0 + 1)
	# wall splat: knock a monster into a pillar (Proving Ground pillar at cols 39-40, rows 15-16)
	for x in world.enemies.duplicate():
		CombatRules.kill_enemy(world, x, true)
	events.clear()
	place(Vector2(34 * C, 16 * C))
	var s := dummy(0, Vector2(37.6 * C, 16 * C))
	s.knock = Vector2(12, 0)
	steps(10)
	check("wall splat: knocked into a pillar", count(Ev.WALL_SPLAT) == 1)
	check("collision: fast knockback can't tunnel through a wall", s.position.x < 39 * C, "x=%.1f" % s.position.x)
	# monsters hurt Bloob (horde presets keep contact damage); Bloob can die
	world.player.god = false
	world.dev.freeze_ai = false
	world.mode = Content.mode("zombie")
	place(Vector2(30 * C, 26 * C))
	var hp0 := world.player.hp
	var c := dummy(0, world.player.position + Vector2(8, 0))
	c.state = Enemy.St.COMMIT
	c.timer = 999
	steps(5)
	check("contact: a committed monster hurts Bloob on contact", world.player.hp < hp0, "hp=%.1f" % world.player.hp)
	world.player.hp = 1.0
	world.player.invuln = 0
	c.atk_cd = 0
	c.state = Enemy.St.COMMIT
	c.position = world.player.position + Vector2(8, 0)
	events.clear()
	steps(60)
	check("death: Bloob dies at 0 HP", world.player.dead and count(Ev.PLAYER_DEATH) == 1)


func test_air_and_dive() -> void:
	await fresh("proving")
	world.dev.freeze_ai = true
	place(Vector2(30 * C, 26 * C))
	var e := dummy(0, world.player.position + Vector2(36, 0))
	var hits0 := world.player.melee.melee_hits
	steps(1, Vector2.ZERO, {jump = true})
	steps(6)
	var saw_air := false
	for i in 40:
		world.step(frame(Vector2.ZERO, {atk = true, aim = e.position}))
		if world.player.melee.atk_step == Tuning.AIR_STEP:
			saw_air = true
		e.position = world.player.position + Vector2(36, 0)
	check("air swipe: attacking in the air uses the air swipe and connects", saw_air and world.player.melee.melee_hits > hits0)
	check("air swipe: max 3 per jump", world.player.air_swings <= 3)
	steps(60)
	events.clear()
	var e2 := dummy(0, world.player.position + Vector2(30, 0))
	var hp0 := e2.hp
	steps(1, Vector2.ZERO, {jump = true})
	steps(12)
	steps(1, Vector2.ZERO, {dodge = true})
	steps(40)
	check("dive slam: dodge in the air plunges and slams", count(Ev.DIVE_SLAM) == 1 and e2.hp < hp0, "hp=%.1f" % e2.hp)


func test_loot_and_progression() -> void:
	await fresh("hollow")
	world.dev.freeze_ai = true
	place(cell(25, 20))
	var e := dummy(0, world.player.position + Vector2(24, 0), 0.5)
	var ichor0: int = GameState.res[0]
	CombatRules.damage_enemy(world, e, 5)
	check("loot: a kill drops pickups", world.pickups.size() > 0, "pickups=%d" % world.pickups.size())
	check("xp: the kill gave XP", GameState.xp > 0 or GameState.level > 1)
	steps(150)
	check("loot: pickups fly to Bloob and bank as resources", GameState.res[0] > ichor0 and world.pickups.is_empty(), "ichor=%d left=%d" % [GameState.res[0], world.pickups.size()])
	var p := world.player
	p.hp = 30.0
	var c0 := GameState.flask
	steps(1, Vector2.ZERO, {heal = true})
	steps(40)
	check("flask: drinking uses a charge and heals over time", GameState.flask == c0 - 1 and p.hp > 30.0 + p.max_hp * 0.3 - 1.0, "hp=%.1f" % p.hp)
	p.hp = p.max_hp
	steps(1, Vector2.ZERO, {heal = true})
	check("flask: won't waste a charge at full health", GameState.flask == c0 - 1)
	p.hp = 50.0
	world.spawn_pickup(p.position + Vector2(20, 0), p.z + 8.0, Tuning.PICKUP_HEAL, 0)
	steps(80)
	check("health orb heals", p.hp > 50.0, "hp=%.1f" % p.hp)
	await fresh()
	var hp0 := world.player.max_hp
	CombatRules.grant_xp(world, Tuning.xp_to_next(1))
	check("levels: XP past the threshold levels up", GameState.level == 2 and count(Ev.LEVEL_UP) == 1)
	check("levels: level up raises max HP", world.player.max_hp == hp0 + 6, "maxHp=%d" % world.player.max_hp)
	await fresh()
	GameState.res = PackedInt32Array([500, 100, 100, 10])
	var hp1 := world.player.max_hp
	world.buy_tech(Content.tech_index("vigor2"))
	check("techs: prerequisites are enforced", not GameState.has("vigor2"))
	world.buy_tech(Content.tech_index("vigor1"))
	check("techs: Thick Goo adds 20 max HP and spends ichor", GameState.has("vigor1") and world.player.max_hp == hp1 + 20 and GameState.res[0] == 470)
	world.switch_job(1)
	check("jobs: Warden is locked until its tech", GameState.job == 0)
	world.buy_tech(Content.tech_index("warden"))
	world.switch_job(1)
	check("jobs: Warden unlocks and switches (x1.25 HP)", GameState.job == 1 and world.player.max_hp == roundi(120 * 1.25), "maxHp=%d" % world.player.max_hp)
	await fresh("hollow")
	GameState.res = PackedInt32Array([500, 100, 100, 10])
	world.buy_tech(0)
	check("techs: can only be bought in safe areas", not GameState.has("vigor1"))
	world.threat = 1
	var threat0 := mini(20, 1 + GameState.rooms_cleared / 2)
	GameState.rooms_cleared = 6
	world.load_room(Content.room_index("mire"), "")
	check("threat: monster level rises as you clear rooms", world.threat > threat0, "threat %d" % world.threat)


func test_skills() -> void:
	await fresh("proving")
	world.dev.freeze_ai = true
	place(Vector2(30 * C, 26 * C))
	var p := world.player
	var a := dummy(0, p.position + Vector2(50, 0), 50)
	var b := dummy(0, p.position + Vector2(-50, 0), 50)
	steps(1, Vector2.ZERO, {sk1 = true})
	check("skill Quake: hits enemies all around", a.hp < 50 and b.hp < 50)
	var casts := p.casts
	steps(20)
	steps(1, Vector2.ZERO, {sk1 = true})
	check("skill: cooldown blocks recasting", p.casts == casts and p.skill_cd[0] > 0)
	check("mana: skills cost mana", p.mana < p.max_mana)
	await fresh("proving")
	world.dev.freeze_ai = true
	place(Vector2(30 * C, 26 * C))
	GameState.job = 1
	GameState.recompute()
	p = world.player
	var t := dummy(0, p.position + Vector2(150, 0), 100)
	steps(1, Vector2.ZERO, {sk1 = true, aim = t.position})
	steps(60)
	check("skill Totem: plants a totem that shoots enemies", world.totems.size() == 1 and t.hp < 100, "hp=%.1f" % t.hp)
	var g := dummy(0, p.position + Vector2(40, 0), 100)
	steps(1, Vector2.ZERO, {sk2 = true})
	check("skill Bulwark: stuns enemies close by", g.state == Enemy.St.STAGGER and p.guard_t > 0)
	await fresh("proving")
	world.dev.freeze_ai = true
	place(Vector2(30 * C, 26 * C))
	GameState.job = 2
	GameState.recompute()
	p = world.player
	var victim := dummy(0, p.position + Vector2(10, 30), 100)
	var start := p.position
	steps(1, Vector2.ZERO, {sk1 = true, aim = p.position + Vector2(-300, 0)})
	steps(40)
	check("skill Blink: teleports and the old spot explodes", p.position.distance_to(start) > 100 and count(Ev.BLAST) >= 1 and victim.hp < 100)
	var hx := dummy(0, p.position + Vector2(100, 0), 100)
	steps(1, Vector2.ZERO, {sk2 = true, aim = hx.position})
	check("skill Hex: curses enemies near the aim", hx.hex_t > 0)


func test_enemy_attacks() -> void:
	await fresh("barrow")
	place(cell(22, 22))
	var p := world.player
	var spit := dummy(1, p.position + Vector2(160, 0), 500, "spit")
	var hp0 := p.hp
	for i in 200:
		steps(1)
		if p.hp < hp0:
			break
	check("attack Spit: telegraphs, fires, and the shot hurts", count(Ev.TELL) >= 1 and count(Ev.ENEMY_SHOT) >= 1 and p.hp < hp0, "hp=%.1f" % p.hp)
	await fresh("barrow")
	place(cell(22, 22))
	p = world.player
	var brute := dummy(5, p.position + Vector2(60, 0), 500, "quake")
	hp0 = p.hp
	var wound := false
	for i in 200:
		steps(1)
		if brute.state == Enemy.St.WINDUP:
			wound = true
		if p.hp < hp0:
			break
	check("attack Ground Slam: winds up, then blasts around the brute", wound and p.hp < hp0 and count(Ev.BLAST) >= 1)
	await fresh("barrow")
	place(cell(22, 22))
	p = world.player
	var st := dummy(4, p.position + Vector2(180, 0), 500, "pounce")
	hp0 = p.hp
	var airborne := false
	for i in 300:
		steps(1)
		if st.leap and st.z > 5.0:
			airborne = true
		if p.hp < hp0:
			break
	check("attack Pounce: leaps in and lands a blast", airborne and p.hp < hp0, "hp=%.1f" % p.hp)
	await fresh("barrow")
	place(cell(22, 22))
	p = world.player
	var striker := dummy(2, p.position + Vector2(40, 0), 500, "slash")
	hp0 = p.hp
	for i in 200:
		steps(1)
		if p.hp < hp0:
			break
	check("attack Strike: a telegraphed melee swipe hurts", p.hp < hp0, "hp=%.1f" % p.hp)
	# a perfect dodge through a shot: no damage, freeze + slow-mo
	await fresh("barrow")
	place(cell(22, 22))
	p = world.player
	var shooter := dummy(1, p.position + Vector2(120, 0), 500, "spit")
	hp0 = p.hp
	var dodged := false
	for i in 200:
		var near := false
		for k in world.projectiles.count():
			if world.projectiles.pos[k].distance_to(p.position) < 30.0:
				near = true
		steps(1, Vector2.ZERO, {dodge = near and not dodged, aim = p.position + Vector2(0, 50)})
		if near:
			dodged = true
		if count(Ev.PERFECT_DODGE) > 0:
			break
	check("perfect dodge: freeze + slow-mo, no damage", count(Ev.PERFECT_DODGE) == 1 and p.hp == hp0 and (world.time.slowmo > 0 or world.time.hitstop > 0), "perfects=%d hp=%.1f" % [count(Ev.PERFECT_DODGE), p.hp])
	await fresh("barrow")
	world.dev.freeze_ai = true
	place(cell(22, 22))
	p = world.player
	var vol := dummy(0, p.position + Vector2(20, 0), 1)
	vol.affix = Tuning.Affix.VOLATILE
	CombatRules.damage_enemy(world, vol, 5)
	check("volatile: death arms a blast", world.hazards.size() == 1)
	hp0 = p.hp
	steps(40)
	check("volatile: the blast hurts if you stay close", p.hp < hp0, "hp=%.1f" % p.hp)
	var e := dummy(0, p.position + Vector2(200, 0))
	world.dev.freeze_ai = false
	e.knock = Vector2(3, 0)
	world.time.request_hitstop(5, Tuning.Prio.BOSS)
	var x0 := e.position.x
	steps(3)
	check("global hitstop: nothing moves", e.position.x == x0)
	# champions and variation
	await fresh("barrow")
	world.dev.champ_chance = 1.0
	var champs := 0
	for i in 10:
		var ce := Director.spawn_enemy(world, 0, cell(20, 20), 0.0, true)
		if ce.champ and ce.affix != 0:
			champs += 1
	check("champions: forced champion chance makes champions with affixes", champs == 10, "champs=%d" % champs)


func test_stations() -> void:
	await fresh("forge")
	var sword := Content.weapon_index("sword")
	var rack
	var paws_rack
	for s in world.stations:
		if s.kind == World.StationKind.RACK and s.ref == sword:
			rack = s
		if s.kind == World.StationKind.RACK and s.ref == 0:
			paws_rack = s
	check("forge: a rack for every weapon", world.stations.filter(func(s): return s.kind == World.StationKind.RACK).size() == 5)
	place(rack.pos + Vector2(0, 40))
	steps(1, Vector2.ZERO, {use = true})
	check("forge: can't buy without the resources", GameState.weapon == 0 and not GameState.weapons[sword])
	GameState.res = PackedInt32Array([100, 10, 0, 0])
	steps(1, Vector2.ZERO, {use = true})
	check("forge: buying the Thorn Sword equips it and spends the price", GameState.weapon == sword and GameState.weapons[sword] == 1 and GameState.res[0] == 60 and GameState.res[1] == 6)
	place(paws_rack.pos + Vector2(0, 40))
	steps(1, Vector2.ZERO, {use = true})
	place(rack.pos + Vector2(0, 40))
	steps(1, Vector2.ZERO, {use = true})
	check("forge: owned weapons swap back for free", GameState.weapon == sword and GameState.res[0] == 60)
	steps(30, Vector2.UP)
	check("stations are solid: Bloob can't walk through a rack", world.player.position.y > rack.pos.y + 12, "dy=%.1f" % (world.player.position.y - rack.pos.y))
	await fresh("overlook")
	var rw = _station(World.StationKind.REWARD)
	check("reward: the Overlook's spear lies there waiting", rw != null and rw.active and rw.ref == Content.weapon_index("spear"))
	await fresh("wayshrine")
	var p := world.player
	p.hp = 20.0
	GameState.flask = 0
	var well = _station(World.StationKind.WELL)
	place(well.pos + Vector2(0, 40))
	steps(1, Vector2.ZERO, {use = true})
	check("well: full heal and flasks refilled", p.hp == p.max_hp and GameState.flask == GameState.flask_max)
	var talks := []
	world.talk.connect(func(_i, line, _at): talks.append(line))
	var npc = _station(World.StationKind.NPC)
	place(npc.pos + Vector2(0, 40))
	steps(1, Vector2.ZERO, {use = true})
	steps(1)
	steps(1, Vector2.ZERO, {use = true})
	check("locals: talking cycles their lines", talks.size() == 2 and talks[0] != talks[1])
	var opened := []
	world.station_opened.connect(func(k): opened.append(k))
	var shrine = _station(World.StationKind.SHRINE)
	place(shrine.pos + Vector2(0, 40))
	steps(1, Vector2.ZERO, {use = true})
	check("shrine: T opens the Shrine", opened == [1])
	GameState.res = PackedInt32Array([500, 0, 0, 0])
	check("shrine: techs can be bought at the Wayshrine too (any safe area)", world.buy_tech(0) and GameState.has("vigor1"))
	await fresh("lounge")
	var opened2 := []
	world.station_opened.connect(func(k): opened2.append(k))
	var board = _station(World.StationKind.BOARD)
	place(board.pos + Vector2(0, 40))
	steps(1, Vector2.ZERO, {use = true})
	check("board: T opens the notice board", opened2 == [2])
	var cache = _station(World.StationKind.CACHE)
	place(cache.pos + Vector2(0, 40))
	steps(1, Vector2.ZERO, {use = true})
	check("cache: opens once per run", world.pickups.size() > 0 and not cache.active)
	await fresh("hollow")
	world.player.hp = 20.0
	var d := world.map.door_info("C")
	world.doors_open = true
	place(Vector2(d.in_x, d.in_y))
	steps(90, Vector2.DOWN)
	check("sanctum: entering fully restores Bloob", world.room.id == "sanctum" and world.player.hp == world.player.max_hp)


func test_world_graph() -> void:
	var bad := []
	var dirs := {A = Vector2i(0, -1), B = Vector2i(1, 0), C = Vector2i(0, 1), D = Vector2i(-1, 0)}
	var adjacency_ok := true
	for r in Content.rooms:
		for id in r.doors:
			var link: Array = r.doors[id]
			var other := Content.rooms[Content.room_index(link[0])]
			if link[1] != "" and (not other.doors.has(link[1]) or other.doors[link[1]][0] != r.id):
				bad.append("%s.%s" % [r.id, id])
			if r.on_map and other.on_map and link[1] != "" and other.map_pos - r.map_pos != dirs[id]:
				adjacency_ok = false
	check("world: every passage links both ways", bad.is_empty(), str(bad))
	check("world: passages point the way the map shows (A north, B east, C south, D west)", adjacency_ok)
	var seen := {"sanctum": true}
	var queue := ["sanctum"]
	while not queue.is_empty():
		var id: String = queue.pop_front()
		for d in Content.rooms[Content.room_index(id)].doors.values():
			if not seen.has(d[0]):
				seen[d[0]] = true
				queue.append(d[0])
	var mapped := Content.rooms.filter(func(r): return r.on_map)
	check("world: every area on the map can be walked to from the Sanctum", mapped.all(func(r): return seen.has(r.id)), "%d reachable" % seen.size())
	var kinds := {}
	for r in Content.rooms:
		kinds[r.kind] = true
	check("world: combat and safe areas", ["combat", "elite", "hub", "shop", "social", "rest", "explore"].all(func(k): return kinds.has(k)))
	var dmg := Content.weapons.map(func(w): return w.combo_damage())
	check("weapons: five, one full combo deals about the same (6-7.5)", Content.weapons.size() == 5 and dmg.all(func(x): return x >= 6.0 and x <= 7.5), str(dmg))
