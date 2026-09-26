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
	test_run_plan()
	await test_run_rooms_load()
	await test_run_combat()
	await test_run_pickups_and_altars()
	await test_run_shop_and_safe()
	await test_archetypes_and_boss()
	await test_ui()
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
	var melee := Content.weapons.filter(func(w): return w.combo.all(func(s): return s.bolt_damage == 0.0))
	dmg = melee.map(func(w): return w.combo_damage())
	check("weapons: five melee weapons, one full combo deals about the same (6-7.5)", melee.size() == 5 and dmg.all(func(x): return x >= 6.0 and x <= 7.5), str(dmg))
	var staff: WeaponData = Content.weapons[Content.weapon_index("staff")]
	check("weapons: the staff throws bolts and costs mana", staff.mana_cost > 0.0 and staff.combo.all(func(s): return s.bolt_damage > 0.0))


func test_ui() -> void:
	if world:
		world.queue_free()
		world = null
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	check("ui: main scene boots with the start card", main.start_card.visible and not main.world.running)
	main.begin()
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("ui: Wake up starts the run", main.world.running and not main.start_card.visible)
	check("ui: HUD shows the area, HP and Essence", main.hud._room_name.text == main.world.room.name and main.world.in_run() and main.hud._hp_text.text.begins_with("100") and main.hud._res.text.begins_with("Essence"))
	main._open_menu()
	var ok: bool = get_tree().paused and main.menu.visible
	for i in PauseMenu.TABS.size():
		main.menu.show_tab(i)
		await get_tree().process_frame
		ok = ok and main.menu._page.get_child_count() > 0
	check("ui: the pause menu pauses the game and renders all six tabs", ok)
	main._close_menu()
	check("ui: closing the menu resumes", not get_tree().paused)
	main.shrine.open()
	await get_tree().process_frame
	check("ui: the Shrine lists jobs and techs", main.shrine._content.get_child_count() >= 4)
	main.shrine.close()
	main.board.open()
	await get_tree().process_frame
	check("ui: the notice board shows the tally", main.board._content.text.contains("Defeated"))
	main.board.close()
	main.dev.run("give all 50")
	main.dev.run("spawn charger 2")
	check("ui: the dev console gives resources and spawns", GameState.res[0] == 50 and main.world.enemies.size() == 2)
	main.restart("hollow")
	await get_tree().physics_frame
	check("ui: room keys / restart start a new run in that room", main.world.room.id == "hollow" and GameState.res[0] == 0)
	var hit: bool = main.world.player.hurt(9999, Vector2.ZERO)
	await get_tree().process_frame
	await get_tree().process_frame
	check("ui: death shows the Overrun card", main.death_card.visible, "hit=%s dead=%s god=%s inv=%d started=%s" % [hit, main.world.player.dead, main.world.player.god, main.world.player.invuln, main.started])
	var stats: String = (main.death_card.body.get_node("Stats") as RichTextLabel).text
	check("ui: the death card tallies the run", ["Enemies defeated", "Rooms cleared", "Essence collected", "Skills", "Weapon", "Run time"].all(func(k): return stats.contains(k)), stats)
	main.world.start_run(5)
	GameState.add_essence(30)
	(main.death_card.body.get_node("Restart") as Button).pressed.emit()
	await get_tree().process_frame
	check("ui: Restart run starts a fresh run", not main.death_card.visible and main.world.in_run() and GameState.essence == 0 and not main.world.player.dead and main.world.room_idx == 0)
	main.world.run_won.emit()
	await get_tree().process_frame
	check("ui: beating the boss shows the Victory card", main.death_card.visible and main.death_card.title_label.text == "Victory")
	main.queue_free()
	await get_tree().process_frame


# ---------------- the run loop ----------------

func fresh_run(seed_value := 777) -> World:
	if world:
		world.queue_free()
		await get_tree().process_frame
	world = WORLD.instantiate()
	add_child(world)
	world.start_run(seed_value)
	await get_tree().physics_frame
	events.clear()
	return world


func _kinds(plan: RunPlan) -> Array:
	return plan.rooms.map(func(r): return r.kind)


func _signature(plan: RunPlan) -> String:
	var parts := []
	for r in plan.rooms:
		parts.append("%s:%s:%s:%s:%d" % [r.kind, r.name, str(r.waves), str(r.doors.keys()), r.drop_weapon])
	return "|".join(parts)


## index of the first room of a kind in the current run (-1 if this run has none)
func _room_of(kind: String) -> int:
	for i in world.rooms.size():
		if world.rooms[i].kind == kind:
			return i
	return -1


## a seed whose run has a room of this kind in its branch
func _seed_with(kind: String) -> int:
	for s in range(1, 200):
		if _kinds(RunPlan.build(s)).has(kind):
			return s
	return 1


## walk out through passage `id` of the current room
func _walk_out(id: String) -> void:
	var d := world.map.door_info(id)
	place(Vector2(d.in_x, d.in_y))
	var dir := Vector2(d.cx - d.in_x, d.cy - d.in_y).normalized()
	dir = Vector2(signf(roundf(dir.x)), signf(roundf(dir.y)))
	steps(100, dir)


func test_run_plan() -> void:
	var plan := RunPlan.build(42)
	var kinds := _kinds(plan)
	check("run: Start -> Combat -> branch -> Combat -> Safe -> Elite -> Boss",
		plan.rooms.size() == 9 and kinds[0] == "start" and kinds[1] == "combat" and kinds[5] == "combat" and kinds[6] == "safe" and kinds[7] == "elite" and kinds[8] == "boss", str(kinds))
	var branch: Array = kinds.slice(2, 5)
	check("run: the branch offers a fight, somewhere to spend and somewhere to grow",
		branch.has("combat") and (branch.has("shop") or branch.has("event")) and (branch.has("altar") or branch.has("weapon")), str(branch))
	check("run: the first fight's room has three ways on", plan.rooms[1].doors.size() == 3)
	var bad := []
	for r in plan.rooms:
		var text := "".join(r.layout)
		for id in r.doors:
			var link: Array = r.doors[id]
			var to := plan.rooms[plan.index_of(link[0])]
			if not text.contains(id) or not "".join(to.layout).contains(link[1]) or to.entrance != link[1]:
				bad.append("%s.%s" % [r.id, id])
		for id in "ABCD":
			if text.contains(id) and id != r.entrance and not r.doors.has(id):
				bad.append("%s: stray passage %s" % [r.id, id])
	check("run: every exit exists and leads to the next room's entrance; other passages are grown over", bad.is_empty(), str(bad))
	var reach := {plan.rooms[0].id: true}
	var queue := [plan.rooms[0]]
	while not queue.is_empty():
		var r: RoomData = queue.pop_front()
		for link in r.doors.values():
			if not reach.has(link[0]):
				reach[link[0]] = true
				queue.append(plan.rooms[plan.index_of(link[0])])
	check("run: every room can be reached and the boss is the end", reach.size() == plan.rooms.size() and plan.rooms[8].doors.is_empty())
	var fights := plan.rooms.filter(func(r): return r.kind == "combat")
	check("run: normal fights are 2-4 enemies per wave", fights.all(func(r): return r.waves.all(func(w): return w.size() >= 2 and w.size() <= 4)), str(fights.map(func(r): return r.waves)))
	check("run: the elite fight has champions, the boss room holds the Barrow King",
		plan.rooms[7].champions > 0 and plan.rooms[8].waves == [[Content.enemy_index("king")]])
	check("run: same seed, same run", _signature(RunPlan.build(42)) == _signature(plan))
	var sigs := {}
	for s in [1, 2, 3, 4, 5, 6]:
		sigs[_signature(RunPlan.build(s))] = true
	check("run: different seeds, different runs", sigs.size() >= 5, "%d distinct of 6" % sigs.size())
	# every module can grow a passage on every side
	var carve_ok := true
	for id in RunPlan.COMBAT_MODULES + ["forge", "lounge", "wayshrine", "overlook", "sanctum", "barrow", "arena", "yard"]:
		for side in "ABCD":
			var rows := []
			var w := 0
			for row in Content.module(id).layout:
				w = maxi(w, row.length())
			for row in Content.module(id).layout:
				rows.append(row.rpad(w))
			if not "".join(rows).contains(side) and not RunPlan._carve(rows, side):
				carve_ok = false
				print("      can't carve %s in %s" % [side, id])
	check("run: every module can open a passage on any side", carve_ok)


func test_run_rooms_load() -> void:
	await fresh_run(42)
	var ok := true
	var why := ""
	for i in world.rooms.size():
		var r := world.rooms[i]
		world.load_room(i, r.entrance)
		var p := world.player.position
		if world.map.door_at(p.x, p.y) != 0 or not world.map.walkable(p.x, p.y):
			ok = false
			why += " %s: arrives on a door / in a wall" % r.id
		for id in r.doors:
			if world.map.door_info(id).is_empty():
				ok = false
				why += " %s: no passage %s" % [r.id, id]
		if r.encounter and world.phase != World.Phase.ENTERED:
			ok = false
			why += " %s: fight didn't wait" % r.id
		if not r.encounter and not world.doors_open:
			ok = false
			why += " %s: safe room sealed" % r.id
	check("run: every room loads, you arrive inside, safe rooms are open, fights wait for you", ok, why)


func test_run_combat() -> void:
	await fresh_run(42)
	world.spawning = true
	world.load_room(1, "C")
	check("room state: entering a combat room = Entered, exits shut, nothing spawned yet",
		world.phase == World.Phase.ENTERED and not world.doors_open and world.enemies.is_empty() and world.pending.is_empty())
	steps(10)
	check("room state: the fight hasn't started a moment after arriving", world.phase == World.Phase.ENTERED)
	world.player.god = true
	steps(60, Vector2.UP)
	check("room state: stepping in starts the fight (Combat Active), exits sealed",
		world.phase == World.Phase.COMBAT and not world.doors_open and count(Ev.DOORS_SEALED) == 1 and count(Ev.ENGAGE) == 1)
	check("encounter: spawns are telegraphed before anything appears", world.pending.size() == world.room.waves[0].size() and world.enemies.is_empty())
	steps(120)
	var first: Array = world.room.waves[0]
	check("encounter: the first wave arrives after its telegraph", world.enemies.size() == first.size() and count(Ev.SPAWN_TELL) >= first.size(),
		"alive=%d wave=%d" % [world.enemies.size(), first.size()])
	check("encounter: every enemy fights with a telegraphed attack, never by touch",
		world.enemies.all(func(e): return e.atk != null) and not world.mode.contact)
	check("encounter: spawns keep their distance from Bloob", world.enemies.all(func(e): return e.position.distance_to(world.player.position) > 120.0))
	var guard := 0
	var ess0 := GameState.essence_total
	while not world.doors_open and guard < 60:
		for e in world.enemies.duplicate():
			CombatRules.kill_enemy(world, e, false)
		steps(30)
		guard += 1
	check("room state: all waves down = Cleared, exits open", world.doors_open and world.phase == World.Phase.CLEARED and world.room_state().cleared and count(Ev.ROOM_CLEARED) == 1,
		"guard=%d spawned=%d budget=%d" % [guard, world.spawned, world.budget()])
	check("encounter: exactly the rolled enemies came out", world.spawned == world.budget())
	steps(200)
	check("currency: kills and the clear spill Essence", GameState.essence_total > ess0, "essence=%d" % GameState.essence_total)
	if world.room.reward_kind == "weapon":
		var drop = null
		for s in world.stations:
			if s.kind == World.StationKind.DROP and s.active:
				drop = s
		check("reward: this room's weapon lies waiting once it's cleared", drop != null and drop.ref == world.room.drop_weapon)
	else:
		check("reward: this room rewarded %s" % world.room.reward_kind, world.room.reward_kind in ["essence", "heal"])
	# onward: through an exit to the room it names
	var exit_id: String = world.room.doors.keys()[0]
	var target: String = world.room.doors[exit_id][0]
	_walk_out(exit_id)
	check("passages: walking out of an exit takes you to the room it leads to", world.room.id == target, "%s -> %s" % [world.room.id, target])
	var before := world.room.id
	world.load_room(world.room_idx, "C")
	_walk_out("C")
	check("passages: the way you came in stays shut (runs go forward)", world.room.id == before)
	world.load_room(1, "C")
	check("room state: a cleared room stays cleared", world.phase == World.Phase.CLEARED and world.doors_open and world.enemies.is_empty())


func test_run_pickups_and_altars() -> void:
	await fresh_run(42)
	var drop = null
	for s in world.stations:
		if s.kind == World.StationKind.DROP:
			drop = s
	check("weapons: a weapon lies in the first room", drop != null and drop.active and drop.ref == world.run.start_weapon)
	place(drop.pos)
	steps(1, Vector2.ZERO, {use = true})
	check("pickup: T takes it; bare paws aren't left behind", GameState.weapon == world.run.start_weapon and not drop.active)
	var other := 1 if GameState.weapon != 1 else 2
	var s2 := world.add_station(World.StationKind.DROP, world.free_spot(world.player.position + Vector2(40, 0)), other)
	var held := GameState.weapon
	place(s2.pos)
	steps(12)
	steps(1, Vector2.ZERO, {use = true})
	check("pickup: taking a weapon drops the one in hand where it lay", GameState.weapon == other and s2.active and s2.ref == held)
	check("pickup: the run remembers every weapon used", GameState.weapons_used.size() >= 3)
	# skills: each passive changes a real stat
	var p := world.player
	var hp0 := p.max_hp
	world.take_passive("thick_goo")
	world.take_passive("heavy_hand")
	world.take_passive("quick_step")
	world.take_passive("swift_swing")
	world.take_passive("long_reach")
	check("skills: Thick Goo raises max HP (and fills it)", p.max_hp == hp0 + 25 and GameState.max_hp == p.max_hp)
	check("skills: Heavy Hand / Quick Step change the numbers", is_equal_approx(GameState.melee_mul, 1.15) and is_equal_approx(GameState.dodge_cd_mul, 0.8))
	var sw: SwingData = GameState.weapon_data().combo[0]
	var scaled := sw.scaled(GameState.weapon_data().attack_speed * GameState.atk_speed, GameState.reach_mul)
	check("skills: Swift Swing and Long Reach reshape the swing (faster, longer hitbox)",
		scaled.windup <= sw.windup and scaled.recover < sw.recover and scaled.range > sw.range)
	p.melee.cancel()
	steps(20)
	var e := dummy(0, p.position + Vector2(40, 0))
	var hp_before := e.hp
	steps(12, Vector2.ZERO, {atk = true, aim = e.position})
	var dealt := hp_before - e.hp
	check("skills: melee hits land harder with Heavy Hand", dealt >= sw.damage * 1.15 * GameState.dmg_mul * 0.99, "dealt=%.2f" % dealt)
	CombatRules.kill_enemy(world, e, true)
	steps(30)
	steps(1, Vector2.DOWN, {dodge = true})
	check("skills: Quick Step shortens the dodge cooldown", p.dodge_cd == roundi(Tuning.DODGE_CD * 0.8), "cd=%d" % p.dodge_cd)
	check("skills: they're kept for the Skills tab", GameState.passives.size() == 5)
	# altar: three choices, pick one, the altar goes dark
	steps(30)
	world.room.choices = PackedStringArray(["mana_flow", "iron_hide", "greed"])
	var alt := world.add_station(World.StationKind.ALTAR, world.free_spot(p.position + Vector2(0, 60)), -1)
	place(alt.pos + Vector2(0, -30))
	var opened := [false]
	world.station_opened.connect(func(k): opened[0] = k == 3, CONNECT_ONE_SHOT)
	steps(1, Vector2.ZERO, {use = true})
	check("altar: T opens it", opened[0])
	check("altar: taking a skill applies it and puts the altar out", world.choose_at_altar(1) and GameState.passives.has("iron_hide") and is_equal_approx(GameState.dmg_taken_mul, 0.88) and not alt.active)
	check("altar: a dark altar gives nothing more", not world.choose_at_altar(0))
	var hp1 := p.hp
	p.invuln = 0
	p.hurt(10.0, p.position + Vector2(10, 0))
	check("skills: Iron Hide takes the edge off hits", is_equal_approx(hp1 - p.hp, 8.8), "took %.2f" % (hp1 - p.hp))
	# elites raise an altar when they fall
	await fresh_run(42)
	world.load_room(_room_of("elite"), "C")
	world.player.god = true
	Waves.engage(world)
	var guard := 0
	while not world.doors_open and guard < 60:
		steps(30)
		for en in world.enemies.duplicate():
			CombatRules.kill_enemy(world, en, false)
		guard += 1
	var altars := world.stations.filter(func(s): return s.kind == World.StationKind.ALTAR and s.active)
	check("elite: champions among them, and clearing it raises an altar with three skills", world.doors_open and altars.size() == 1 and world.altar_choices().size() == 3 and count(Ev.CHAMPION) >= 1)


func test_run_shop_and_safe() -> void:
	await fresh_run(_seed_with("shop"))
	world.load_room(_room_of("shop"), "C")
	var offers := world.stations.filter(func(s): return s.kind == World.StationKind.OFFER)
	check("shop: a walkable room with three wares (weapon, skill, healing)", offers.size() == 3 and world.doors_open
		and world.room.offers.map(func(o): return o.type) == ["weapon", "skill", "heal"])
	check("shop: prices 20 / 25 / 15 Essence", world.room.offers.map(func(o): return o.price) == [20, 25, 15])
	var p := world.player
	p.hp = 40.0
	place(offers[2].pos + Vector2(0, 36))
	steps(1, Vector2.ZERO, {use = true})
	check("shop: can't buy without the Essence", p.hp == 40.0 and not world.room.offers[2].sold and count(Ev.DENIED) == 1)
	GameState.add_essence(100)
	steps(12)
	steps(1, Vector2.ZERO, {use = true})
	check("shop: healing restores 30% HP for 15", world.room.offers[2].sold and absf(p.hp - (40.0 + p.max_hp * 0.3)) < 1.0 and GameState.essence == 85, "hp=%.1f ess=%d" % [p.hp, GameState.essence])
	place(offers[1].pos + Vector2(0, 36))
	steps(12)
	steps(1, Vector2.ZERO, {use = true})
	check("shop: a skill for 25 joins your skills", GameState.passives.size() == 1 and GameState.essence == 60)
	world.equip(Content.weapon_index("sword") if world.room.offers[0].ref != Content.weapon_index("sword") else Content.weapon_index("spear"))
	var held := GameState.weapon
	place(offers[0].pos + Vector2(0, 36))
	steps(12)
	steps(1, Vector2.ZERO, {use = true})
	var dropped := world.stations.filter(func(s): return s.kind == World.StationKind.DROP and s.active and s.ref == held)
	check("shop: buying a weapon equips it and drops the old one", GameState.weapon == world.room.offers[0].ref and dropped.size() == 1 and GameState.essence == 40)
	# safe room: a well that mends once
	world.load_room(_room_of("safe"), "C")
	var well = _station(World.StationKind.WELL)
	check("safe room: no enemies, exits open, a well", world.encounter == null and world.doors_open and well != null)
	p.hp = 20.0
	p.mana = 0.0
	place(well.pos + Vector2(0, 36))
	steps(1, Vector2.ZERO, {use = true})
	check("safe room: the well restores HP and mana", p.hp == p.max_hp and p.mana == p.max_mana)
	check("safe room: it mends you only once", not well.active)
	# a hidden cache: Essence, no fight
	await fresh_run(_seed_with("event"))
	world.load_room(_room_of("event"), "C")
	var cache = _station(World.StationKind.CACHE)
	var e0 := GameState.essence_total
	place(cache.pos + Vector2(0, 36))
	steps(1, Vector2.ZERO, {use = true})
	steps(240)
	check("cache: opening it spills Essence", not cache.active and GameState.essence_total > e0)


func test_archetypes_and_boss() -> void:
	await fresh_run(42)
	world.load_room(1, "C")
	world.phase = World.Phase.COMBAT
	world.doors_open = false
	var p := world.player
	place(world.free_spot(Vector2(world.map.px_w / 2.0, world.map.px_h / 2.0)))
	var c := p.position
	# Chaser: approaches, telegraphs a bite, bites, recovers
	var ch := Director.spawn_enemy(world, Content.enemy_index("chaser"), world.free_spot(c + Vector2(160, 0)), p.z, true)
	ch.cd = 0
	var saw := {}
	for t in 300:
		world.step(frame())
		if not is_instance_valid(ch) or not ch.alive:
			break
		saw[ch.state] = true
		if saw.has(Enemy.St.RECOVER):
			break
	check("chaser: approaches, telegraphs, strikes, recovers", saw.has(Enemy.St.APPROACH) and saw.has(Enemy.St.WINDUP) and saw.has(Enemy.St.LUNGE) and saw.has(Enemy.St.RECOVER), str(saw.keys()))
	if is_instance_valid(ch) and ch.alive:
		CombatRules.kill_enemy(world, ch, true)
	# Charger: telegraphs a direction, dashes fast, then stands open
	p.god = true
	var rm := Director.spawn_enemy(world, Content.enemy_index("rammer"), world.free_spot(c + Vector2(180, 0)), p.z, true)
	rm.cd = 0
	var dash_speed := 0.0
	var aim_locked := Vector2.ZERO
	var recovered := 0
	for t in 400:
		world.step(frame())
		if not rm.alive:
			break
		if rm.state == Enemy.St.WINDUP and rm.timer < rm.wtot * Tuning.AIM_LOCK:
			aim_locked = rm.lunge_dir
		if rm.state == Enemy.St.LUNGE:
			dash_speed = maxf(dash_speed, rm.vel.length())
		if rm.state == Enemy.St.RECOVER:
			recovered += 1
		if recovered > 0 and rm.state != Enemy.St.RECOVER:
			break
	check("charger: telegraphs its direction, charges fast, then a long recovery", aim_locked != Vector2.ZERO and dash_speed > 5.0 and recovered >= 50,
		"speed=%.1f recover=%d" % [dash_speed, recovered])
	if rm.alive:
		CombatRules.kill_enemy(world, rm, true)
	# Ranged: keeps its distance, backs off when rushed, shoots
	var sp := Director.spawn_enemy(world, Content.enemy_index("spitter"), world.free_spot(c + Vector2(70, 0)), p.z, true)
	sp.cd = 400
	var d0 := sp.position.distance_to(p.position)
	steps(90)
	var d1 := sp.position.distance_to(p.position)
	check("ranged: backs away when Bloob is close", d1 > d0 + 60.0, "%.0f -> %.0f" % [d0, d1])
	sp.cd = 0
	events.clear()
	steps(150)
	check("ranged: fires projectiles from range", count(Ev.ENEMY_SHOT) >= 1)
	if sp.alive:
		CombatRules.kill_enemy(world, sp, true)
	# the boss: a fixed cycle, a phase two, and the run is won when it falls
	await fresh_run(42)
	world.load_room(_room_of("boss"), "C")
	world.phase = World.Phase.COMBAT
	world.doors_open = false
	p = world.player
	p.god = true
	var boss := Director.spawn_enemy(world, Content.enemy_index("king"), world.free_spot(p.position + Vector2(0, -80)), p.z)
	check("boss: a single, heavy, poised enemy", boss.data.boss and boss.is_brute() and boss.max_hp >= 100.0)
	var order := []
	var last := -1
	for t in 2400:
		if boss.state == Enemy.St.WINDUP and boss.pattern_i != last:
			last = boss.pattern_i
			order.append(boss.atk.id)
		world.step(frame())
		if order.size() >= 4:
			break
	check("boss: swing -> charge -> slam, then again", order.size() >= 4 and order.slice(0, 4) == ["king_swing", "king_charge", "king_slam", "king_swing"], str(order))
	check("boss: every attack is telegraphed (windups of half a second or more)", boss.data.attacks.all(func(a): return a.windup >= 30))
	check("boss: the slam leaves a long punish window", boss.data.attacks[2].recover >= 100)
	events.clear()
	CombatRules.damage_enemy(world, boss, boss.hp - boss.max_hp * 0.45)
	check("boss: below half health it enrages", boss.enraged and count(Ev.BOSS_PHASE) == 1)
	var won := [false]
	world.run_won.connect(func(): won[0] = true, CONNECT_ONE_SHOT)
	world.spawned = world.budget()
	CombatRules.damage_enemy(world, boss, 99999.0)
	steps(2)
	check("boss: when it falls, the run is won", won[0] and world.run_over and world.doors_open)
