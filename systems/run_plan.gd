class_name RunPlan
extends RefCounted
## One run: a few generated maps, then the Barrow King.
##
##   Map 1 -> Map 2 -> Map 3 -> Boss
##
## Each map is one connected island of areas built fresh by MapGen (personal pathing: walk
## anywhere, no loading between areas): a start clearing, monster glades, a shop, an altar,
## a lounge to rest in, hidden groves with loot, and a gate out. Four monsters sleep in the
## glades; the gate opens once all four have fallen. The boss waits in its own arena, built
## from a hand-made room module with its passages rewired (entrance carved, the rest grown over).
## Everything random (layouts, monsters, stock, loot, altar choices) comes from the seed, so a
## seed replays the same run.

const MAPS := 3
const MAP_THEMES := ["moss", "thorn", "mire", "overlook", "way"]
const THEME_NAMES := {moss = "Mosswood", thorn = "Thornwood", mire = "The Mire", overlook = "Overlook", way = "Wayside"}
## the monsters each map draws its four from
const MONSTER_POOLS := [
	["chaser", "chaser", "spitter", "rammer"],
	["chaser", "spitter", "rammer", "rammer", "spitter"],
	["chaser", "spitter", "rammer", "brute"],
]
const MAP_TIERS := [1, 2, 2]
const MAP_CHAMPS := [0, 0, 1]
const CLEAR_ESSENCE := Vector2i(10, 16)
const LOOT_ESSENCE := Vector2i(14, 22)
const MODULES := {boss = "arena"}
const KIND_NAMES := {
	start = "Burrow", combat = "Combat", shop = "Shop", event = "Hidden Cache", altar = "Altar",
	weapon = "Weapon Room", safe = "Safe Room", elite = "Elite", boss = "Boss", wilds = "Map",
}
## markers each kind of room keeps (the rest become floor)
const KEEP := {start = "", combat = "R", shop = "W", event = "X", altar = "S", weapon = "RX", safe = "H", elite = "R", boss = ""}
const MARKERS := "SHWPLXR"
const REWARD_NAMES := {essence = "Essence", weapon = "Weapon", heal = "Healing"}
const PRICES := {weapon = 20, skill = 25, heal = 15}
const HEAL_OFFER := 0.3
const FLOOR := ".,*@"
const CROSS := "Tt#~ .,*@"
const KEEPERS := {
	shop = ["Tallow the Trader", Color(0.95, 0.8, 0.55), [
		"Essence buys anything here. Well. Anything on the table.",
		"Four of them roam every wood. Put them down and the gate lets you on.",
		"The overgrown trails? Somebody hid something at the end of every one."]],
	lounge = ["Keeper Moss", Color(0.72, 0.95, 0.7), [
		"Sit a while. The well mends you, once.",
		"The map in the corner fills in as you walk. Wheel or , and . to zoom.",
		"The King waits past the last gate. Don't go in hurt."]],
}

var seed_value := 0
var rooms: Array[RoomData] = []
var start_weapon := -1            ## lying next to you when the run begins
var _rng: Rng
var _used_weapons := {}


static func build(seed_value_in: int) -> RunPlan:
	var plan := RunPlan.new()
	plan.seed_value = seed_value_in
	plan._rng = Rng.new(seed_value_in)
	plan._generate()
	return plan


func index_of(id: String) -> int:
	for i in rooms.size():
		if rooms[i].id == id:
			return i
	return -1


# ---------------- generation ----------------

func _generate() -> void:
	start_weapon = _roll_weapon()
	var themes := MAP_THEMES.duplicate()
	_shuffle(themes)
	var maps: Array[RoomData] = []
	for m in MAPS:
		maps.append(_map(m, themes[m]))
	var boss := _node("boss", MODULES.boss, MAPS, 1)
	_link(boss, [])
	for m in MAPS:
		var next: RoomData = maps[m + 1] if m + 1 < MAPS else boss
		maps[m].doors = {"A": [next.id, next.entrance]}


## a generated map: its island, its four monsters, its shop stock and altar choices
func _map(m: int, theme_id: String) -> RoomData:
	var r := RoomData.new()
	r.id = "wilds_%d" % m
	r.kind = "wilds"
	r.map_no = m
	r.layer = m
	r.map_pos = Vector2i(0, MAPS - m)
	r.name = THEME_NAMES.get(theme_id, "The Wilds")
	r.blurb = "Map %d of %d. Four monsters roam these woods; the gate opens when they fall." % [m + 1, MAPS]
	r.theme = load("res://data/themes/%s.tres" % theme_id)
	var pool: Array = MONSTER_POOLS[mini(m, MONSTER_POOLS.size() - 1)]
	var kinds := []
	var brutes := 0
	while kinds.size() < Tuning.MAP_MONSTERS:
		var id: String = pool[_rng.pick(pool.size())]
		if id == "brute":
			if brutes > 0:
				continue
			brutes += 1
		kinds.append(Content.enemy_index(id))
	MapGen.generate(r, _rng, kinds, MAP_CHAMPS[mini(m, MAP_CHAMPS.size() - 1)])
	r.champions = MAP_CHAMPS[mini(m, MAP_CHAMPS.size() - 1)]
	var enc := EncounterData.new()
	enc.preset = Content.mode("arena")
	enc.tier = MAP_TIERS[mini(m, MAP_TIERS.size() - 1)]
	enc.start_alive = 0
	enc.budget = r.monsters.size()
	r.encounter = enc
	r.reward_kind = "essence"
	r.essence = CLEAR_ESSENCE
	r.choices = _roll_passives(3)
	r.offers = [
		{type = "weapon", ref = _roll_weapon(), price = PRICES.weapon, sold = false},
		{type = "skill", ref = _roll_passives(1)[0], price = PRICES.skill, sold = false},
		{type = "heal", ref = HEAL_OFFER, price = PRICES.heal, sold = false},
	]
	# the locals, in the order their markers read (row by row)
	var npcs: Array[NpcData] = []
	for y in r.layout.size():
		var row: String = r.layout[y]
		for x in row.length():
			if row[x] != "P":
				continue
			var zi := r.zones[y][x]
			var kind := "lounge"
			if zi != " ":
				kind = r.areas[zi.unicode_at(0) - 48].kind
			var k: Array = KEEPERS.get(kind, KEEPERS.lounge)
			var npc := NpcData.new()
			npc.name = k[0]
			npc.tint = k[1]
			npc.lines = PackedStringArray(k[2])
			npcs.append(npc)
	r.npcs = npcs
	rooms.append(r)
	return r


## the boss arena, built from its hand-made module with the King's fight rolled
func _node(kind: String, module_id: String, layer: int, x: int) -> RoomData:
	var src := Content.module(module_id)
	var r := RoomData.new()
	r.id = "%s_%d_%d" % [kind, layer, rooms.size()]
	r.kind = kind
	r.name = src.name
	r.blurb = src.blurb
	r.theme = src.theme
	r.layout = src.layout.duplicate()
	r.map_pos = Vector2i(x, 0)
	r.layer = layer
	_strip_markers(r, kind)
	_roll_fight(r, kind, 3)
	rooms.append(r)
	return r


func _roll_fight(r: RoomData, kind: String, tier: int) -> void:
	var pool := Content.encounters.filter(func(e: EncounterDef): return e.kind == kind and (kind != "combat" or e.tier == tier))
	var def: EncounterDef = pool[_rng.pick(pool.size())]
	var waves: Array = []
	for w in def.waves:
		var wave: Array[int] = []
		for id in w:
			wave.append(Content.enemy_index(id))
		waves.append(wave)
	var extra := floori(_rng.rangef(0, def.extra + 0.999)) if def.extra_pool.size() > 0 else 0
	for k in extra:
		waves[0].append(Content.enemy_index(def.extra_pool[_rng.pick(def.extra_pool.size())]))
	r.waves = waves
	r.champions = def.champions
	r.essence = def.essence
	var enc := EncounterData.new()
	enc.preset = Content.mode("arena")
	enc.tier = tier
	enc.start_alive = 0
	enc.budget = 0
	for w in waves:
		enc.budget += w.size()
	r.encounter = enc


## a weapon other than Goo Paws, spreading the run's finds across the armoury
func _roll_weapon() -> int:
	var pool := []
	for i in range(1, Content.weapons.size()):
		if not _used_weapons.has(i):
			pool.append(i)
	if pool.is_empty():
		_used_weapons.clear()
		pool = range(1, Content.weapons.size())
	var w: int = pool[_rng.pick(pool.size())]
	_used_weapons[w] = true
	return w


func _roll_passives(n: int) -> PackedStringArray:
	var ids := []
	for p in Content.passives:
		ids.append(p.id)
	_shuffle(ids)
	return PackedStringArray(ids.slice(0, n))


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := _rng.pick(i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


# ---------------- passages ----------------

## Wire a room to the rooms after it. Exits go to existing passages first (north, west, east),
## missing ones are carved; you arrive from the south. Unused passages are grown over.
func _link(r: RoomData, next: Array) -> void:
	var rows := _rows(r.layout)
	var have := _door_letters(rows)
	var entrance := ""
	if r.kind != "start":
		entrance = "C"
		if not have.has("C"):
			_carve(rows, "C")
	var exits: Array[String] = []
	for id in ["A", "D", "B"]:
		if exits.size() < next.size() and have.has(id):
			exits.append(id)
	for id in ["A", "D", "B"]:
		if exits.size() < next.size() and not exits.has(id):
			if not _carve(rows, id):
				push_error("RunPlan: can't carve passage %s in %s" % [id, r.id])
			exits.append(id)
	for id in "ABCD":
		if id != entrance and not exits.has(id):
			_seal(rows, id)
	r.entrance = entrance
	r.doors = {}
	for k in next.size():
		r.doors[exits[k]] = [next[k].id, "C"]
	r.layout = PackedStringArray(rows)


func _rows(layout: PackedStringArray) -> Array:
	var w := 0
	for row in layout:
		w = maxi(w, row.length())
	var rows := []
	for row in layout:
		rows.append(row.rpad(w))
	return rows


func _door_letters(rows: Array) -> Dictionary:
	var out := {}
	for row: String in rows:
		for id in "ABCD":
			if row.contains(id):
				out[id] = true
	return out


func _strip_markers(r: RoomData, kind: String) -> void:
	var keep: String = KEEP[kind]
	var racks := 0
	var rows := []
	for row: String in r.layout:
		var out := ""
		for ch in row:
			if MARKERS.contains(ch) and not keep.contains(ch):
				ch = "."
			elif ch == "W":
				racks += 1
				if racks > 3:
					ch = "."   # a shop shows three wares
			out += ch
		rows.append(out)
	r.layout = PackedStringArray(rows)


static func _put(rows: Array, x: int, y: int, ch: String) -> void:
	var row: String = rows[y]
	rows[y] = row.substr(0, x) + ch + row.substr(x + 1)


static func _seal(rows: Array, id: String) -> void:
	for y in rows.size():
		if rows[y].contains(id):
			rows[y] = rows[y].replace(id, "T")


## the cell `k` steps in from side `id`, `i` across a 4-wide passage starting at `p`
static func _side_cell(rows: Array, id: String, p: int, k: int, i: int) -> Vector2i:
	var h := rows.size()
	var w: int = rows[0].length()
	match id:
		"A": return Vector2i(p + i, k)
		"C": return Vector2i(p + i, h - 1 - k)
		"D": return Vector2i(k, p + i)
	return Vector2i(w - 1 - k, p + i)


## the ground level a cell stands on for passage purposes: "," floor, "1" plateau,
## "2" high plateau, "" = not somewhere a passage can end
static func _level(ch: String) -> String:
	if FLOOR.contains(ch):
		return ","
	if ch == "1" or ch == "&":
		return "1"
	if ch == "2" or ch == "%":
		return "2"
	return ""


## How deep a passage at `p` must be cut to reach open ground, and what to fill it with
## (a path, or a causeway at plateau height on floating islands). [] = it would cut through
## stairs, stations or another passage.
static func _carve_depth(rows: Array, id: String, p: int) -> Array:
	var deep: int = (rows.size() if id == "A" or id == "C" else rows[0].length()) / 2
	for k in deep:
		var level := ""
		var same := true
		for i in 4:
			var c := _side_cell(rows, id, p, k, i)
			var ch: String = rows[c.y][c.x]
			var lv := _level(ch)
			if lv != "" and (level == "" or level == lv) and (i == 0 or level != ""):
				level = lv
				continue
			same = false
			if not CROSS.contains(ch):
				return []
		if same and k >= 2:
			return [k, level]
	return []


## Cut a 4-wide passage `id` (A north, B east, C south, D west) from the edge to the nearest
## ground, as close to the middle of that side as it can.
static func _carve(rows: Array, id: String) -> bool:
	var along: int = rows[0].length() if id == "A" or id == "C" else rows.size()
	var best := -1
	var best_cut := []
	var best_score := INF
	for p in range(2, along - 6):
		var cut := _carve_depth(rows, id, p)
		if cut.is_empty():
			continue
		var score: float = cut[0] * 3.0 + absf(p + 2.0 - along / 2.0) + (0.0 if cut[1] == "," else 20.0)
		if score < best_score:
			best_score = score
			best = p
			best_cut = cut
	if best < 0:
		return false
	for k in best_cut[0]:
		for i in 4:
			var c := _side_cell(rows, id, best, k, i)
			_put(rows, c.x, c.y, id if k == 0 else best_cut[1])
	return true


# ---------------- descriptions ----------------

## what a passage promises: "Combat · Weapon", "Shop", "Altar · choose a skill"
static func describe(r: RoomData) -> String:
	match r.kind:
		"wilds":
			return "Map %d · %s" % [r.map_no + 1, r.name]
		"combat":
			return "Combat · " + REWARD_NAMES.get(r.reward_kind, "Essence")
		"elite":
			return "Elite · champions guard a skill"
		"shop":
			return "Shop · spend Essence"
		"event":
			return "Hidden Cache · Essence, no fight"
		"altar":
			return "Altar · choose a skill"
		"weapon":
			return "Weapon Room · " + Content.weapons[r.drop_weapon].name
		"safe":
			return "Safe Room · rest"
		"boss":
			return "Boss · " + r.name
	return KIND_NAMES.get(r.kind, r.name)
