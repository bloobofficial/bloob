class_name RunPlan
extends RefCounted
## One run's map: a short chain of rooms with a branch, built from reusable room modules.
##
##   Start -> Combat -> ( Combat | Shop or Cache | Altar or Weapon ) -> Combat -> Safe -> Elite -> Boss
##
## Each node is a runtime copy of a hand-made room (RoomData) with its passages rewired: you
## arrive through `entrance`, each exit leads on to the next step, and every other passage is
## grown over. A module that lacks a passage gets one carved from the room's edge to the
## nearest floor. Runs are forward-only: the way you came in stays shut behind you.
## Everything random (modules, branch order, fights, rewards, altar and shop stock) comes from
## the seed, so a seed replays the same run.

const COMBAT_MODULES := ["hollow", "mire", "ridge", "thornwood"]
const MODULES := {
	start = "yard", shop = "forge", event = "lounge", altar = "wayshrine", weapon = "overlook",
	safe = "sanctum", elite = "barrow", boss = "arena",
}
const KIND_NAMES := {
	start = "Burrow", combat = "Combat", shop = "Shop", event = "Hidden Cache", altar = "Altar",
	weapon = "Weapon Room", safe = "Safe Room", elite = "Elite", boss = "Boss",
}
## markers each kind of room keeps (the rest become floor)
const KEEP := {start = "", combat = "R", shop = "W", event = "X", altar = "S", weapon = "RX", safe = "H", elite = "R", boss = ""}
const MARKERS := "SHWPLXR"
const REWARD_NAMES := {essence = "Essence", weapon = "Weapon", heal = "Healing"}
const PRICES := {weapon = 20, skill = 25, heal = 15}
const HEAL_OFFER := 0.3
const DOOR_X := {A = 1, D = 0, B = 2, C = 1}
const LAYERS := 7
const FLOOR := ".,*@"
const CROSS := "Tt#~ .,*@"

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
	var combat := COMBAT_MODULES.duplicate()
	_shuffle(combat)
	start_weapon = _roll_weapon()
	var start := _node("start", MODULES.start, 0, 1)
	var first := _node("combat", combat[0], 1, 1)
	# the branch: one more fight, a place to spend, a place to grow
	var options := ["combat", "shop" if _rng.chance(0.75) else "event", "altar" if _rng.chance(0.7) else "weapon"]
	_shuffle(options)
	var branch: Array[RoomData] = []
	for k in options.size():
		var kind: String = options[k]
		branch.append(_node(kind, combat[1] if kind == "combat" else MODULES[kind], 2, 0))
	var third := _node("combat", combat[2], 3, 1)
	var safe := _node("safe", MODULES.safe, 4, 1)
	var elite := _node("elite", MODULES.elite, 5, 1)
	var boss := _node("boss", MODULES.boss, 6, 1)
	_link(start, [first])
	_link(first, branch)
	for b in branch:
		_link(b, [third])
	_link(third, [safe])
	_link(safe, [elite])
	_link(elite, [boss])
	_link(boss, [])


## a room of this kind built from `module_id`, with its fight / stock rolled
func _node(kind: String, module_id: String, layer: int, x: int) -> RoomData:
	var src := Content.module(module_id)
	var r := RoomData.new()
	r.id = "%s_%d_%d" % [kind, layer, rooms.size()]
	r.kind = kind
	r.name = src.name.trim_prefix("The ") if kind == "combat" else (KIND_NAMES[kind] if kind != "boss" else src.name)
	if kind == "elite":
		r.name = "Elite · " + src.name.trim_prefix("The ")
	r.blurb = src.blurb
	r.theme = src.theme
	r.layout = src.layout.duplicate()
	r.map_pos = Vector2i(x, LAYERS - 1 - layer)
	r.layer = layer
	_strip_markers(r, kind)
	match kind:
		"combat", "elite", "boss":
			var tier := 1 if layer <= 2 else (2 if kind == "combat" else 3)
			_roll_fight(r, kind, tier)
			if kind == "combat":
				r.reward_kind = ["essence", "weapon", "heal"][_rng.weighted([5, 3, 2])]
				if layer == 1:
					r.reward_kind = "essence" if _rng.chance(0.5) else "weapon"
			elif kind == "elite":
				r.reward_kind = "essence"
				r.choices = _roll_passives(3)   # an altar rises when the elites fall
			if r.reward_kind == "weapon":
				r.drop_weapon = _roll_weapon()
		"weapon":
			r.drop_weapon = _roll_weapon()
		"altar":
			r.choices = _roll_passives(3)
		"shop":
			r.offers = [
				{type = "weapon", ref = _roll_weapon(), price = PRICES.weapon, sold = false},
				{type = "skill", ref = _roll_passives(1)[0], price = PRICES.skill, sold = false},
				{type = "heal", ref = HEAL_OFFER, price = PRICES.heal, sold = false},
			]
		"event":
			r.essence = Vector2i(14, 22)
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
	# a branch lays its choices out the way their passages face
	if next.size() > 1:
		for k in next.size():
			next[k].map_pos.x = DOOR_X[exits[k]]
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
