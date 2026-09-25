class_name World
extends Node2D
## The playable world: the current room and everything in it (prototype: sim/sim.ts).
##
## One physics tick = one prototype tick, run here in the prototype's order:
##   time -> director -> player -> interact -> doors -> squads -> AI think -> AI move
##   -> totems / sprayers -> projectiles -> hazards -> pickups -> room cleared?
## Actors own their logic (Player, Enemy, Pickup, ...); this node only sequences it, so the
## update order that the combat timing depends on stays exactly the prototype's.
##
## Coordinates: node positions are ground-plane world units; heights are each actor's `z`.

signal room_loaded(index: int)
signal station_opened(kind: int)          ## 1 Shrine, 2 notice board
signal talk(npc_index: int, line: String, at: Vector3)

enum StationKind { SHRINE = 1, WELL, RACK, NPC, BOARD, CACHE, REWARD }

const ENEMY_SCENE := preload("res://actors/enemies/enemy.tscn")
const PICKUP_SCENE := preload("res://systems/pickup.tscn")
const HAZARD_SCENE := preload("res://systems/hazard.tscn")
const TOTEM_SCENE := preload("res://systems/totem.tscn")
const STATION_SCENE := preload("res://world/rooms/station.tscn")

## Developer overrides (prototype: sim/dev.ts DevState)
class DevState:
	var director := true
	var spawn_mul := 1.0
	var max_alive := -1
	var champ_chance := -1.0
	var patterns := -1
	var enemy_speed := 1.0
	var enemy_damage := 1.0
	var enemy_hp := 1.0
	var freeze_ai := false
	var passive := false
	var no_cooldowns := false
	var infinite_flask := false
	var player_damage := 1.0
	var budget := -1
	var god := false

var map := RoomMap.new()
var nav := NavGrid.new()
var rng := Rng.new(0)
var time := TimeController.new()
var dev := DevState.new()
var enemies: Array[Enemy] = []
var squads: Array[Dictionary] = []
var squad_total_members := 0
var pickups: Array[Pickup] = []
var hazards: Array[Hazard] = []
var totems: Array[Totem] = []
## [{kind, pos: Vector2, z, ref, slot, active, node}]
var stations: Array[Dictionary] = []

var room: RoomData
var room_idx := 0
var encounter: EncounterData
var mode: ModeData
var diff: TierData
var threat := 1                   ## monster level in this room
var mix := PackedFloat32Array([1, 1, 1, 1, 1, 1])
var tick_n := 0
var room_tick := 0
var spawned := 0
var doors_open := true
var _door_armed := false
var exit_t := 0
var exit_door := ""
var exit_dir := Vector2.ZERO
var enter_t := 0
var enter_dir := Vector2.ZERO
var running := false               ## ticking (false before "Wake up" and while paused)
var spawning := true               ## tests can switch the director off
var god_override := false
var debug_hitboxes := false        ## H: hitbox overlay
var debug_states := false          ## dev: AI state rings
var _field_goals := PackedInt32Array([-1, -1, -1, -1, -1])
var _grid := {}

@onready var terrain: TerrainView = $Terrain
@onready var collision: RoomCollision = $Collision
@onready var ground: Node2D = $Ground
@onready var actors: Node2D = $Actors
@onready var player: Player = $Actors/Player
@onready var projectiles: Projectiles = $Projectiles
@onready var fx: FxLayer = $Fx


func _ready() -> void:
	player.setup(self)
	projectiles.world = self
	fx.world = self


# ---------------- runs & rooms ----------------

## Fresh run: new seed, every room forgotten, start in room_id.
func reset_run(room_id: String = Content.START_ROOM, seed_value: int = -1) -> void:
	rng = Rng.new(seed_value if seed_value >= 0 else randi())
	GameState.reset()
	time.reset()
	dev = DevState.new()
	god_override = false
	tick_n = 0
	player.reset_state()
	load_room(Content.room_index(room_id), "")


## Enter a room, arriving through door `via_door` (or at its start marker).
func load_room(idx: int, via_door: String) -> void:
	var def := Content.rooms[idx]
	room_idx = idx
	room = def
	map.load_room(def)
	nav.build(map)
	collision.build(map)
	for e: Enemy in enemies:
		e.queue_free()
	enemies.clear()
	for n in pickups:
		n.queue_free()
	for n in hazards:
		n.queue_free()
	for n in totems:
		n.queue_free()
	pickups.clear()
	hazards.clear()
	totems.clear()
	projectiles.clear()
	squads.clear()
	squad_total_members = 0
	room_tick = 0
	spawned = 0
	exit_t = 0
	enter_t = 0
	exit_door = ""
	_door_armed = false
	time.slowmo = 0
	var st: Dictionary = GameState.room_states[idx]
	st.visited = true
	encounter = def.encounter
	mode = def.encounter.preset if def.encounter else Content.mode("calm")
	# a cleared room stays cleared: no encounter on the way back through
	var active: bool = def.encounter != null and not st.cleared
	if not active:
		encounter = null
	doors_open = not active or budget() == 0
	threat = mini(20, def.encounter.tier + GameState.rooms_cleared / 2) if def.encounter else 1
	diff = Content.tier_of(def.encounter.tier if def.encounter else 1)
	# each visit re-weights the spawn mix, so the same room plays differently
	var base_mix: PackedFloat32Array = def.encounter.mix if def.encounter and def.encounter.mix.size() == 6 else mode.mix
	mix = PackedFloat32Array()
	for wgt in base_mix:
		mix.append(wgt * rng.rangef(0.5, 1.5) if wgt > 0 else 0.0)
	_build_stations(def, st)
	# the Sanctum restores you: full health, flask refilled (elsewhere, find a well)
	if def.restore:
		GameState.flask = GameState.flask_max
		player.max_hp = GameState.max_hp
		player.hp = player.max_hp
		player.max_mana = GameState.mana_max
		player.mana = player.max_mana
		player.heal_left = 0.0
	# arrival point
	var arrive := Vector2(map.start.x, map.start.y)
	if via_door != "":
		var d := map.door_info(via_door)
		if not d.is_empty():
			arrive = Vector2(d.in_x, d.in_y)
	player.place(arrive, map.ground_at(arrive.x, arrive.y))
	player.god = mode.god_mode or god_override or dev.god
	# stress-test sprayers (proto-towers)
	var n_em := mini(mode.emitters, 16) if encounter else 0
	for i in n_em:
		var a := float(i) / n_em * TAU
		projectiles.emitters.append({
			pos = Vector2(map.px_w / 2 + cos(a) * map.px_w * 0.28, map.px_h / 2 + sin(a) * map.px_h * 0.32),
			angle = a, spin = (1.0 if i % 2 == 0 else -1.0) * 0.045,
		})
	terrain.build(map, def.theme, actors)
	RenderingServer.set_default_clear_color(def.theme.fog)
	_update_field_goals()
	GameState.changed.emit()
	Events.push(Ev.ROOM_ENTER, arrive.x, arrive.y, idx, 0, player.z)
	if active and not doors_open:
		Events.push(Ev.DOORS_SEALED, arrive.x, arrive.y, 0, 0, player.z)
	room_loaded.emit(idx)


func room_state() -> Dictionary:
	return GameState.room_states[room_idx]


func _build_stations(def: RoomData, st: Dictionary) -> void:
	for s in stations:
		if is_instance_valid(s.node):
			s.node.queue_free()
	stations.clear()
	var rack := 0
	var npc := 0
	for slot in map.markers.size():
		var m: Dictionary = map.markers[slot]
		var kind: int
		var ref := -1
		var active := true
		var taken: bool = (int(st.taken) & (1 << slot)) != 0
		match m.ch:
			"S": kind = StationKind.SHRINE
			"H": kind = StationKind.WELL
			"W":
				kind = StationKind.RACK
				ref = maxi(0, Content.weapon_index(def.stands[rack] if rack < def.stands.size() else "paws"))
				rack += 1
			"P":
				kind = StationKind.NPC
				ref = npc
				npc += 1
			"L": kind = StationKind.BOARD
			"X":
				kind = StationKind.CACHE
				active = not taken
			_:
				kind = StationKind.REWARD
				ref = Content.weapon_index(def.reward) if def.reward != "" else -1
				active = ref >= 0 and not taken and (def.encounter == null or st.cleared)
		var s := {kind = kind, pos = Vector2(m.x, m.y), z = float(m.z), ref = ref, slot = slot, active = active}
		var node: Station = STATION_SCENE.instantiate()
		actors.add_child(node)
		node.setup(self, s)
		s.node = node
		stations.append(s)


## nearest usable station to a point, or -1
func nearest_station(p: Vector2) -> int:
	var best := -1
	var bd := 1e9
	for k in stations.size():
		var s: Dictionary = stations[k]
		if not s.active:
			continue
		var d := p.distance_to(s.pos)
		var rng_r := Tuning.REWARD_RANGE if s.kind == StationKind.REWARD else Tuning.USE_RANGE
		if d <= rng_r and d < bd:
			bd = d
			best = k
	return best


## T: use whatever is next to Bloob.
func interact() -> void:
	var p := player
	if p.dead or p.busy() or p.melee.swinging():
		return
	var k := nearest_station(p.position)
	if k < 0:
		return
	var s: Dictionary = stations[k]
	var st := room_state()
	var sx: float = s.pos.x
	var sy: float = s.pos.y
	match s.kind:
		StationKind.SHRINE:
			Events.push(Ev.STATION_OPEN, sx, sy, 1, 0, s.z)
			station_opened.emit(1)
		StationKind.BOARD:
			Events.push(Ev.STATION_OPEN, sx, sy, 2, 0, s.z)
			station_opened.emit(2)
		StationKind.WELL:
			p.hp = p.max_hp
			p.max_mana = GameState.mana_max
			p.mana = p.max_mana
			p.heal_left = 0.0
			GameState.flask = GameState.flask_max
			GameState.changed.emit()
			Events.push(Ev.WELL_USED, sx, sy, 0, 0, s.z)
		StationKind.NPC:
			var npc_def: NpcData = room.npcs[s.ref] if s.ref < room.npcs.size() else null
			Events.push(Ev.TALK, sx, sy, s.ref, GameState.talks, s.z)
			if npc_def:
				talk.emit(s.ref, npc_def.lines[GameState.talks % npc_def.lines.size()], Vector3(sx, sy, s.z))
			GameState.talks += 1
		StationKind.RACK:
			var w: int = s.ref
			if GameState.weapon == w:
				Events.push(Ev.DENIED, sx, sy, 2, w, s.z)
				return
			if not GameState.weapons[w]:
				var cost := Content.weapons[w].cost
				if not GameState.can_afford(cost):
					Events.push(Ev.DENIED, sx, sy, 1, w, s.z)
					return
				GameState.spend(cost)
				GameState.weapons[w] = 1
				Events.push(Ev.WEAPON_FOUND, sx, sy, w, 1, s.z)
			equip(w)
		StationKind.CACHE:
			s.active = false
			st.taken = int(st.taken) | (1 << s.slot)
			for r in Tuning.RES_COUNT:
				var lim: Vector2i = Tuning.CACHE_LOOT[r]
				var n := floori(rng.rangef(lim.x, lim.y + 0.999))
				for q in mini(n, 4):
					spawn_pickup(s.pos + Vector2(0, 20), s.z + 10.0, r, maxi(1, roundi(float(n) / mini(n, 4))))
			Events.push(Ev.LOOT, sx, sy, 1, 0, s.z)
		StationKind.REWARD:
			var w: int = s.ref
			s.active = false
			st.taken = int(st.taken) | (1 << s.slot)
			if GameState.weapons[w]:
				# already bought it: the spare breaks down into Relic Shards
				for q in Tuning.DUPLICATE_SHARDS:
					spawn_pickup(s.pos, s.z + 12.0, Tuning.Res.SHARD, 1)
				Events.push(Ev.WEAPON_FOUND, sx, sy, w, 2, s.z)
			else:
				GameState.weapons[w] = 1
				Events.push(Ev.WEAPON_FOUND, sx, sy, w, 0, s.z)
			equip(w)
	if is_instance_valid(s.node):
		s.node.refresh()


## switch Bloob's weapon (drops any swing in progress)
func equip(w: int) -> void:
	if w < 0 or w >= Content.weapons.size():
		return
	GameState.weapon = w
	player.melee.cancel()
	player.melee.combo_cd = 0
	GameState.changed.emit()
	Events.push(Ev.WEAPON_EQUIP, player.position.x, player.position.y, w, 0, player.z)


## this visit's budget (dev override wins): 0 = endless
func budget() -> int:
	if encounter == null:
		return 0
	return dev.budget if dev.budget >= 0 else encounter.budget


## enemies still to defeat before the doors open (-1 = endless / none)
func remaining() -> int:
	if encounter == null or budget() == 0:
		return -1
	return maxi(0, budget() - spawned) + enemies.size()


## one of the four anchor points around Bloob (E, S, W, N), kept inside the room
func anchor_point(k: int) -> Vector2:
	var a := k * (PI / 2.0)
	var p := player.position + Vector2(cos(a), sin(a)) * Tuning.ANCHOR_R
	return Vector2(clampf(p.x, 48, map.px_w - 48), clampf(p.y, 48, map.px_h - 48))


func _update_field_goals() -> void:
	_field_goals[0] = nav.goal_cell(player.position)
	for k in 4:
		_field_goals[k + 1] = nav.goal_cell(anchor_point(k))


## which way to walk toward field f's goal (0 = Bloob, 1..4 = anchors E,S,W,N); ZERO = none
func flow(f: int, from: Vector2, cache: Dictionary) -> Vector2:
	return nav.flow_dir(from, _field_goals[f], cache, tick_n)


func squad_count() -> int:
	var n := 0
	for sq in squads:
		if sq.alive:
			n += 1
	return n


# ---------------- spatial grid (separation + projectile hits) ----------------

func _build_grid() -> void:
	_grid.clear()
	for e: Enemy in enemies:
		var key := Vector2i(floori(e.position.x / Tuning.CELL), floori(e.position.y / Tuning.CELL))
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(e)


## enemies in the 3x3 cells around a point
func neighbours(p: Vector2) -> Array:
	var out := []
	var cx := floori(p.x / Tuning.CELL)
	var cy := floori(p.y / Tuning.CELL)
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var list = _grid.get(Vector2i(cx + ox, cy + oy))
			if list:
				out.append_array(list)
	return out


# ---------------- spawning helpers ----------------

func add_enemy(kind: int, at: Vector2, z: float) -> Enemy:
	var e: Enemy = ENEMY_SCENE.instantiate()
	actors.add_child(e)
	e.setup(self, kind, at, z)
	enemies.append(e)
	return e


func remove_enemy(e: Enemy) -> void:
	enemies.erase(e)
	e.queue_free()


func note_defeat() -> void:
	GameState.kills += 1
	room_state().defeated += 1


func spawn_pickup(at: Vector2, z: float, type: int, amount: int) -> void:
	if pickups.size() >= Tuning.MAX_PICKUPS:
		# cap reached: bank it directly so loot is never lost
		if type != Tuning.PICKUP_HEAL:
			GameState.add_res(type, amount)
		return
	var pk: Pickup = PICKUP_SCENE.instantiate()
	actors.add_child(pk)
	pk.setup(self, at, z, type, amount)
	pickups.append(pk)


func arm_hazard(at: Vector2, z: float, r: float, fuse: int, dmg: float, who: int) -> void:
	var hz: Hazard = HAZARD_SCENE.instantiate()
	ground.add_child(hz)
	hz.setup(self, at, z, r, fuse, dmg, who)
	hazards.append(hz)


func plant_totem(at: Vector2, z: float, facing: float, life: int, max_count: int) -> void:
	if totems.size() >= max_count:
		# replace the oldest (lowest life)
		var oldest := totems[0]
		for t in totems:
			if t.life < oldest.life:
				oldest = t
		totems.erase(oldest)
		oldest.queue_free()
	var t: Totem = TOTEM_SCENE.instantiate()
	actors.add_child(t)
	t.setup(self, at, z, facing, life)
	totems.append(t)


func death_ghost(e: Enemy) -> void:
	fx.ghost(e)


## a room's first clear: a chest's worth of loot bursts out at Bloob's feet
func drop_chest() -> void:
	var p := player
	var parts := [[Tuning.Res.ICHOR, Tuning.CLEAR_CHEST_ICHOR], [Tuning.Res.BONE, Tuning.CLEAR_CHEST_BONE],
		[Tuning.Res.WISP, Tuning.CLEAR_CHEST_WISP], [Tuning.Res.SHARD, Tuning.CLEAR_CHEST_SHARD]]
	var count := 0
	for part in parts:
		var lim: Vector2i = part[1]
		var n := floori(rng.rangef(lim.x, lim.y + 0.999))
		var pieces := mini(n, 8 if part[0] == Tuning.Res.ICHOR else 3)
		for k in pieces:
			var amt := n / pieces + (1 if k < n % pieces else 0)
			if amt > 0:
				spawn_pickup(p.position, p.z + 10.0, part[0], amt)
				count += 1
	Events.push(Ev.LOOT, p.position.x, p.position.y, count, 0, p.z)


# ---------------- the tick ----------------

func _physics_process(_delta: float) -> void:
	if running:
		step()


func step(inp: InputFrame = null) -> void:
	time.advance()                                   # 1. time / impact
	if spawning:
		Director.run(self)                           # 2. spawning
	var walking := exit_t > 0 or enter_t > 0
	var f := inp if inp != null else player.read_input(walking)
	if inp != null and walking:
		f = InputFrame.new()
		f.move = auto_walk_dir()
		f.aim = inp.aim
	player.tick(f)                                   # 3. player
	if f.use and not walking:
		interact()                                   # 3a. T: stations, racks, rewards, locals
	_check_doors()                                   # 3b. walking into an open passage
	_update_field_goals()                            # 4. path goals
	Squads.update(self)                              # 5. squad brains
	_build_grid()
	if not time.frozen() and not dev.freeze_ai:      # 6. decisions
		for e: Enemy in enemies.duplicate():
			if e.alive:
				e.think()
	var s := time.world_scale
	for e: Enemy in enemies.duplicate():                    # 7. steering, height, contact
		if e.alive:
			e.move(s)
	_build_grid()
	for t: Totem in totems.duplicate():                     # 8. Warden totems
		if not t.tick():
			totems.erase(t)
			t.queue_free()
	projectiles.update_emitters()                    #    stress sprayers
	projectiles.update()                             # 9. projectiles + hits + kills
	for hz: Hazard in hazards.duplicate():                   #    telegraphed blasts
		if not hz.tick():
			hazards.erase(hz)
			hz.queue_free()
	for pk: Pickup in pickups.duplicate():                   #    loot
		if not pk.tick():
			pickups.erase(pk)
			pk.queue_free()
	_check_cleared()                                 # 10. encounter done?
	tick_n += 1
	GameState.run_ticks += 1
	if not time.frozen():
		room_tick += 1
	if enter_t > 0:
		enter_t -= 1
	if exit_t > 0:
		exit_t -= 1
		if exit_t == 0:
			_take_door(exit_door)


## during a passage walk-out / walk-in Bloob just walks
func auto_walk_dir() -> Vector2:
	var d := exit_dir if exit_t > 0 else enter_dir
	return Vector2(signf(roundf(d.x)), signf(roundf(d.y)))


## where the mouse points on the ground (plane at Bloob's height + 10, like the prototype)
func aim_ground(z: float) -> Vector2:
	var joy := Input.get_vector(&"aim_left", &"aim_right", &"aim_up", &"aim_down")
	if joy.length() > 0.3:
		return player.position + joy.normalized() * 140.0
	return View.to_ground(get_global_mouse_position(), z + 10.0)


func _check_doors() -> void:
	var p := player
	if exit_t > 0:
		return
	var on := map.door_at(p.position.x, p.position.y)
	if on == 0:
		_door_armed = true   # must step off the doorway you arrived through first
		return
	if not _door_armed or not doors_open or p.dead:
		return
	var id := String.chr(on)
	var d := map.door_info(id)
	if d.is_empty():
		return
	# walk out through the passage; the room changes when the walk ends
	exit_door = id
	exit_t = Tuning.EXIT_TICKS
	exit_dir = (Vector2(d.cx, d.cy) - Vector2(d.in_x, d.in_y)).normalized()
	Events.push(Ev.ROOM_EXIT, p.position.x, p.position.y, 0, 0, p.z)


func _take_door(id: String) -> void:
	var link = room.doors.get(id)
	exit_door = ""
	if link == null:
		return
	load_room(Content.room_index(link[0]), link[1])
	var d := map.door_info(link[1])
	if not d.is_empty():
		# keep walking in from the passage for a moment
		enter_dir = (Vector2(d.in_x, d.in_y) - Vector2(d.cx, d.cy)).normalized()
		enter_t = Tuning.ENTER_TICKS


func _check_cleared() -> void:
	var b := budget()
	if encounter == null or b == 0 or doors_open:
		return
	if spawned >= b and enemies.is_empty():
		doors_open = true
		room_state().cleared = true
		GameState.rooms_cleared += 1
		var p := player
		p.hp = minf(p.max_hp, p.hp + p.max_hp * Tuning.CLEAR_HEAL)
		if mode.loot:
			drop_chest()
		Events.push(Ev.ROOM_CLEARED, p.position.x, p.position.y, 0, 0, p.z)
		# Encounter -> Reward: the room's weapon appears at its reward spot
		for s in stations:
			if s.kind == StationKind.REWARD and s.ref >= 0 and not (int(room_state().taken) & (1 << s.slot)):
				s.active = true
				s.node.refresh()
				Events.push(Ev.ITEM_APPEAR, s.pos.x, s.pos.y, s.ref, 0, s.z)
		GameState.changed.emit()


## Shrine and menu commands (safe areas only): buy tech, switch job, equip an owned weapon.
func buy_tech(i: int) -> bool:
	if room.encounter != null or i < 0 or i >= Content.techs.size():
		return false
	var before := GameState.max_hp
	if not GameState.buy(i):
		return false
	player.max_hp = GameState.max_hp
	player.hp = minf(player.max_hp, player.hp + maxf(0.0, GameState.max_hp - before))
	Events.push(Ev.TECH_BOUGHT, player.position.x, player.position.y, i, 0, player.z)
	return true


func switch_job(j: int) -> bool:
	if room.encounter != null or not GameState.job_unlocked(j) or GameState.job == j:
		return false
	GameState.job = j
	GameState.recompute()
	player.max_hp = GameState.max_hp
	player.hp = player.max_hp   # switching jobs at the altar is a fresh start
	player.skill_cd = [0, 0]
	GameState.changed.emit()
	Events.push(Ev.JOB_CHANGED, player.position.x, player.position.y, j, 0, player.z)
	return true


func menu_equip(w: int) -> bool:
	if room.encounter != null or w < 0 or w >= Content.weapons.size() or not GameState.weapons[w] or GameState.weapon == w:
		return false
	equip(w)
	return true
