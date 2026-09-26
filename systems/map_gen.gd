class_name MapGen
extends RefCounted
## One map of a run (Patch 1, "personal pathing"): a single floating island of connected
## areas, walked end to end with no loading in between.
##
## Areas sit on a coarse grid of slots. A main path climbs from the start clearing (south,
## nearest the camera) to the gate (north edge); the places you choose to visit hang off it:
## a shop, an altar, a lounge, and hidden groves with loot at the ends of overgrown trails.
## Monster glades lie on the main path, so the gate is earned. Areas are organic clearings
## (or built rooms, for the shop and lounge) joined by winding dirt paths, rimmed with forest,
## rocks and open cliff edges. Everything comes from the run's Rng, so a seed replays a map.
##
## Output (written onto a RoomData): the ASCII layout RoomMap reads (see its legend), plus
## per-cell zones (which area a cell belongs to) and floor styles, the area list the minimap
## and HUD use, where the monsters sleep, and decor (torches).

const SLOT := Vector2i(26, 21)     ## cells per grid slot
const COLS := 4
const ROWS := 4
const PAD := 4                     ## void kept around the island
const ATTEMPTS := 12
## [rx, ry] half-sizes in cells
const SIZES := {
	start = [7, 5], exit = [7, 5], combat = [10, 7], cross = [5, 4], shop = [8, 6],
	altar = [7, 6], lounge = [8, 6], loot = [5, 4],
}
const BUILT := ["shop", "lounge"]
const NAMES := {
	start = "Clearing", exit = "The Gate", cross = "Crossroads", shop = "Shop", altar = "Altar",
	lounge = "Lounge", loot = "Hidden Grove",
}
const GLADE_NAMES := ["Glade", "Hollow", "Thicket", "Dell", "Brake", "Coppice"]
## chars RoomMap treats as walkable ground
const GROUND := ".,*@R1abc"

var rng: Rng
var w := COLS * SLOT.x + PAD * 2
var h := ROWS * SLOT.y + PAD * 2
var ch := PackedByteArray()        ## layout char codes
var flo := PackedByteArray()       ## 1 = ground carved (area or trail)
var core := PackedByteArray()      ## 1 = dirt path
var zone := PackedByteArray()      ## area index + 1 (0 = none)
var sty := PackedByteArray()       ## style char codes
var areas: Array = []              ## [{kind, name, slot, cell, rx, ry, idx}]
var edges: Array = []              ## [[a, b, hidden], ...]
var monsters: Array = []
var decor: Array = []
var gate_x := 0
var noise_seed := 0


## Build a map onto `r`: `kinds` are the monsters' enemy kind indices (Tuning.MAP_MONSTERS of
## them), `champs` how many of them come as champions.
static func generate(r: RoomData, rng_in: Rng, kinds: Array, champs: int) -> void:
	var g: MapGen
	for attempt in ATTEMPTS:
		g = MapGen.new()
		g.rng = rng_in
		g._build(kinds, champs)
		if g._connected():
			break
		if attempt == ATTEMPTS - 1:
			push_warning("MapGen: kept a map that failed its reachability check")
	g._write(r)


# ---------------- the graph ----------------

func _build(kinds: Array, champs: int) -> void:
	var n := w * h
	ch.resize(n)
	ch.fill(32)
	flo.resize(n)
	core.resize(n)
	zone.resize(n)
	sty.resize(n)
	sty.fill(46)
	noise_seed = rng.pick(100000)
	_plan()
	for a in areas:
		_carve_area(a)
	for e in edges:
		_carve_trail(areas[e[0]], areas[e[1]], e[2])
	# the path stops at the door of built rooms (their floor is planks or flagstones)
	for c in w * h:
		if core[c] and (sty[c] == 119 or sty[c] == 115):
			core[c] = 0
	_carve_gate()
	_rim()
	for a in areas:
		_furnish(a)
	_place_monsters(kinds, champs)
	for c in w * h:
		if core[c] and ch[c] == 46:
			ch[c] = 44   # ',': dirt path


func _slot_free(taken: Dictionary, s: Vector2i) -> bool:
	return s.x >= 0 and s.y >= 0 and s.x < COLS and s.y < ROWS and not taken.has(s)


func _add_area(kind: String, slot: Vector2i, taken: Dictionary) -> int:
	var size: Array = SIZES[kind]
	var rx: int = size[0]
	var ry: int = size[1]
	if kind == "combat":
		rx += rng.pick(3) - 1
		ry += rng.pick(3) - 1
	var jx := rng.pick(5) - 2
	var jy := rng.pick(3) - 1
	var cell := Vector2i(PAD + slot.x * SLOT.x + SLOT.x / 2 + jx, PAD + slot.y * SLOT.y + SLOT.y / 2 + jy)
	var a := {kind = kind, name = NAMES.get(kind, ""), slot = slot, cell = cell, rx = rx, ry = ry, idx = areas.size(),
		p1 = rng.rangef(0, TAU), p2 = rng.rangef(0, TAU)}
	areas.append(a)
	taken[slot] = a.idx
	return a.idx


func _connect(a: int, b: int, hidden := false) -> void:
	edges.append([a, b, hidden])


func _plan() -> void:
	var taken := {}
	# the main path: start (bottom row) climbing to the gate (top row), wandering sideways
	var cur := Vector2i(rng.pick(COLS), ROWS - 1)
	var path: Array[Vector2i] = [cur]
	while cur.y > 0:
		var side := rng.pick(3) - 1
		if side != 0 and rng.chance(0.55) and cur.x + side >= 0 and cur.x + side < COLS:
			cur = Vector2i(cur.x + side, cur.y)
			path.append(cur)
		cur = Vector2i(cur.x, cur.y - 1)
		path.append(cur)
	if rng.chance(0.5):
		var side := rng.sgn()
		if cur.x + side >= 0 and cur.x + side < COLS:
			cur = Vector2i(cur.x + side, 0)
			path.append(cur)
	# what the main path holds: fights in between, the odd crossroads
	var mid := path.size() - 2
	var fights := 3 if mid >= 4 else 2
	var fight_at := {}
	# spread the fights out along the way
	for k in fights:
		fight_at[1 + roundi(float(k) * (mid - 1) / maxf(1.0, fights - 1.0))] = true
	var main: Array[int] = []
	for i in path.size():
		var kind := "cross"
		if i == 0:
			kind = "start"
		elif i == path.size() - 1:
			kind = "exit"
		elif fight_at.has(i):
			kind = "combat"
		main.append(_add_area(kind, path[i], taken))
		if i > 0:
			_connect(main[i - 1], main[i])
	# name the glades
	var names := GLADE_NAMES.duplicate()
	_shuffle(names)
	var gi := 0
	for a in areas:
		if a.kind == "combat":
			a.name = names[gi % names.size()]
			gi += 1
	# side places, off the main path: the non-monster areas and the hidden groves
	var side_kinds := ["shop", "altar", "lounge"]
	_shuffle(side_kinds)
	side_kinds.append("loot")
	if rng.chance(0.6):
		side_kinds.append("loot")
	for kind in side_kinds:
		var hosts: Array = []
		for a in areas:
			if a.kind == "exit" or a.kind == "loot":
				continue
			if kind != "loot" and not main.has(a.idx):
				continue   # shops, altars and lounges hang straight off the main path
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.UP]:
				var s: Vector2i = a.slot + d
				if _slot_free(taken, s) and not (kind != "loot" and s.y == 0 and d == Vector2i.UP):
					hosts.append([a.idx, s])
		if hosts.is_empty():
			continue
		var pick: Array = hosts[rng.pick(hosts.size())]
		var b := _add_area(kind, pick[1], taken)
		_connect(pick[0], b, kind == "loot")
	# now and then a second way round between neighbouring areas
	if rng.chance(0.5):
		var pairs := []
		for a in areas:
			if a.kind == "loot" or a.kind == "exit":
				continue
			for d in [Vector2i.RIGHT, Vector2i.DOWN]:
				var s: Vector2i = a.slot + d
				if not taken.has(s):
					continue
				var b: Dictionary = areas[taken[s]]
				if b.kind == "loot" or b.kind == "exit" or _linked(a.idx, b.idx):
					continue
				pairs.append([a.idx, b.idx])
		if not pairs.is_empty():
			var pr: Array = pairs[rng.pick(pairs.size())]
			_connect(pr[0], pr[1])


func _linked(a: int, b: int) -> bool:
	for e in edges:
		if (e[0] == a and e[1] == b) or (e[0] == b and e[1] == a):
			return true
	return false


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.pick(i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


# ---------------- carving ----------------

func _i(x: int, y: int) -> int:
	return y * w + x


func _in(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


func _ch(x: int, y: int) -> String:
	return String.chr(ch[_i(x, y)]) if _in(x, y) else " "


func _put(x: int, y: int, c: String) -> void:
	if _in(x, y):
		ch[_i(x, y)] = c.unicode_at(0)


func _ground(x: int, y: int, path: bool) -> void:
	if not _in(x, y) or x < 1 or y < 0 or x >= w - 1 or y >= h - 1:
		return
	var c := _i(x, y)
	flo[c] = 1
	if ch[c] == 32:
		ch[c] = 46   # '.'
	if path:
		core[c] = 1


## is (x, y) inside area a's shape? (an organic blob, or a squarish built room)
func _inside(a: Dictionary, x: int, y: int) -> bool:
	var dx: float = (x - a.cell.x) / float(a.rx)
	var dy: float = (y - a.cell.y) / float(a.ry)
	if BUILT.has(a.kind):
		return pow(absf(dx), 4.0) + pow(absf(dy), 4.0) < 1.0
	var ang := atan2(dy, dx)
	var edge := 1.0 + 0.16 * sin(3.0 * ang + a.p1) + 0.1 * sin(5.0 * ang + a.p2)
	return dx * dx + dy * dy < edge * edge


func _carve_area(a: Dictionary) -> void:
	var c: Vector2i = a.cell
	for y in range(c.y - a.ry - 2, c.y + a.ry + 3):
		for x in range(c.x - a.rx - 2, c.x + a.rx + 3):
			if _in(x, y) and _inside(a, x, y):
				_ground(x, y, false)
				zone[_i(x, y)] = a.idx + 1
	# built rooms and the altar get their floor
	var style := ""
	match a.kind:
		"shop", "lounge": style = "w"
		"altar": style = "s"
	if style != "":
		for y in range(c.y - a.ry + 1, c.y + a.ry):
			for x in range(c.x - a.rx + 1, c.x + a.rx):
				if _in(x, y) and zone[_i(x, y)] == a.idx + 1 and (a.kind != "altar" or Vector2(x - c.x, (y - c.y) * 1.2).length() < a.rx - 1.5):
					sty[_i(x, y)] = style.unicode_at(0)


## a winding trail between two areas: a dirt path with grass verges (hidden trails: narrow,
## no dirt, just trodden grass)
func _carve_trail(a: Dictionary, b: Dictionary, hidden: bool) -> void:
	var p0 := Vector2(a.cell)
	var p3 := Vector2(b.cell)
	var d := p3 - p0
	var perp := Vector2(-d.y, d.x).normalized()
	var p1 := p0 + d / 3.0 + perp * rng.rangef(-3.0, 3.0)
	var p2 := p0 + d * 2.0 / 3.0 + perp * rng.rangef(-3.0, 3.0)
	var pts := [p0, p1, p2, p3]
	var half := 1.4 if hidden else 2.3
	var core_r := 0.0 if hidden else 0.95
	for k in 3:
		var s: Vector2 = pts[k]
		var e: Vector2 = pts[k + 1]
		var steps := ceili(s.distance_to(e) / 0.35)
		for i in steps + 1:
			var q := s.lerp(e, float(i) / steps)
			for oy in range(-3, 4):
				for ox in range(-3, 4):
					var x := roundi(q.x) + ox
					var y := roundi(q.y) + oy
					var dist := Vector2(x, y).distance_to(q)
					if dist <= half:
						_ground(x, y, dist <= core_r)
						if hidden and _in(x, y) and zone[_i(x, y)] == 0:
							sty[_i(x, y)] = 104   # 'h': a trodden trail


## the gate: a 4-wide passage from the exit clearing north off the edge of the island
func _carve_gate() -> void:
	var ex: Dictionary = areas.filter(func(a): return a.kind == "exit")[0]
	gate_x = ex.cell.x - 2
	for y in range(0, ex.cell.y + 1):
		for x in range(gate_x - 1, gate_x + 5):
			_ground(x, y, x >= gate_x and x < gate_x + 4)
	for x in range(gate_x, gate_x + 4):
		_put(x, 0, "A")
	# pillars either side, a torch on each
	for y in [2, 3]:
		_put(gate_x - 2, y, "#")
		_put(gate_x + 5, y, "#")
	decor.append({type = "torch", cell = Vector2i(gate_x - 2, 5)})
	decor.append({type = "torch", cell = Vector2i(gate_x + 5, 5)})


## around the carved ground: forest at the back and sides, bushes and rocks, and open cliff
## edges toward the camera (south) where the island falls away
func _rim() -> void:
	var out := ch.duplicate()
	for y in h:
		for x in w:
			var c := _i(x, y)
			if flo[c] or ch[c] != 32:
				continue   # ground, or already built on (the gate's pillars)
			# where is the nearest ground? (within 2 cells)
			var near := 99
			var south_of_ground := false   # ground lies to the north: we're on a south edge
			for oy in range(-2, 3):
				for ox in range(-2, 3):
					var nx := x + ox
					var ny := y + oy
					if not _in(nx, ny) or not flo[_i(nx, ny)]:
						continue
					var dd := maxi(absi(ox), absi(oy))
					if dd < near:
						near = dd
					if oy < 0 and ox == 0:
						south_of_ground = true
			if near > 2:
				continue
			var n := _noise(x, y)
			var r := RoomMap.hash2(x * 7 + 3, y * 13 + 5)
			var t := "T"
			if y <= 1:
				t = "T"   # the top edge is always forest (the gate cuts through it)
			elif south_of_ground:
				# the near edge: mostly open drops, some shrubs and rocks framing the view
				if near == 1:
					t = "t" if n > 0.6 else ("o" if r < 0.1 else ("T" if n > 0.5 else " "))
				else:
					t = "T" if n > 0.68 else " "
			elif near == 1:
				# the back and sides: a wall of forest with brush and boulders at its foot
				t = "T" if n > 0.3 else ("o" if r < 0.3 else "t")
			out[c] = t.unicode_at(0)
	ch = out


## smooth value noise, 0..1 (clumps of trees rather than salt and pepper)
func _noise(x: int, y: int) -> float:
	var s := 3.0
	var fx := x / s
	var fy := y / s
	var ix := floori(fx)
	var iy := floori(fy)
	var tx := fx - ix
	var ty := fy - iy
	var seed := noise_seed
	var a := RoomMap.hash2(ix + seed, iy)
	var b := RoomMap.hash2(ix + 1 + seed, iy)
	var c := RoomMap.hash2(ix + seed, iy + 1)
	var d := RoomMap.hash2(ix + 1 + seed, iy + 1)
	var u := tx * tx * (3.0 - 2.0 * tx)
	var v := ty * ty * (3.0 - 2.0 * ty)
	return lerpf(lerpf(a, b, u), lerpf(c, d, u), v)


# ---------------- furnishing ----------------

func _free(x: int, y: int) -> bool:
	return _in(x, y) and flo[_i(x, y)] == 1 and _ch(x, y) == "."


## a free floor cell of area `a` near (x, y), avoiding the dirt path; (-1, -1) if none
func _spot(a: Dictionary, x: int, y: int, avoid_path := true) -> Vector2i:
	for ring in range(0, 4):
		for oy in range(-ring, ring + 1):
			for ox in range(-ring, ring + 1):
				if maxi(absi(ox), absi(oy)) != ring:
					continue
				var px := x + ox
				var py := y + oy
				if _free(px, py) and zone[_i(px, py)] == a.idx + 1 and not (avoid_path and core[_i(px, py)]):
					return Vector2i(px, py)
	return Vector2i(-1, -1)


func _mark(a: Dictionary, x: int, y: int, c: String) -> Vector2i:
	var s := _spot(a, x, y)
	if s.x >= 0:
		_put(s.x, s.y, c)
	return s


## a back wall across a built room, broken wherever a path comes through
func _back_wall(a: Dictionary, y: int) -> void:
	for x in range(a.cell.x - a.rx + 2, a.cell.x + a.rx - 1):
		if _free(x, y) and not core[_i(x, y)] and not core[_i(x, y + 1)] and not core[_i(x, y - 1)]:
			_put(x, y, "#")


func _furnish(a: Dictionary) -> void:
	var c: Vector2i = a.cell
	match a.kind:
		"start":
			_put(c.x, c.y, "@")
			_torch(a, c.x - 4, c.y - 2)
			_torch(a, c.x + 4, c.y - 2)
		"exit":
			_torch(a, c.x - 5, c.y)
			_torch(a, c.x + 4, c.y)
		"cross":
			_torch(a, c.x + 3, c.y - 2)
			_scatter(a, "t", 2, 1)
		"shop":
			_back_wall(a, c.y - 4)
			_mark(a, c.x, c.y - 3, "P")
			for k in 3:
				_mark(a, c.x - 3 + k * 3, c.y - 1, "W")
			_torch(a, c.x - 6, c.y - 3)
			_torch(a, c.x + 6, c.y - 3)
		"lounge":
			_back_wall(a, c.y - 4)
			_mark(a, c.x - 4, c.y - 2, "H")
			_mark(a, c.x, c.y - 3, "P")
			_mark(a, c.x + 4, c.y - 2, "L")
			for y in range(c.y, c.y + 3):
				for x in range(c.x - 3, c.x + 4):
					if _in(x, y) and zone[_i(x, y)] == a.idx + 1 and sty[_i(x, y)] == 119:
						sty[_i(x, y)] = 114   # 'r': the rug
			_torch(a, c.x - 6, c.y - 3)
			_torch(a, c.x + 6, c.y - 3)
		"altar":
			_mark(a, c.x, c.y - 1, "S")
			for p in [Vector2i(-3, -3), Vector2i(3, -3), Vector2i(-3, 2), Vector2i(3, 2)]:
				var q: Vector2i = c + p
				if _free(q.x, q.y) and not core[_i(q.x, q.y)]:
					_put(q.x, q.y, "#")
			decor.append({type = "brazier", cell = c + Vector2i(-2, -3)})
			decor.append({type = "brazier", cell = c + Vector2i(2, -3)})
		"loot":
			_mark(a, c.x, c.y - 1, "X")
			_scatter(a, "t", 4, 1)
		"combat":
			_glade(a)


func _torch(a: Dictionary, x: int, y: int) -> void:
	var s := _spot(a, x, y)
	if s.x >= 0:
		decor.append({type = "torch", cell = s})


## `n` little clumps of char `c` about the area (never on the path, never near its middle)
func _scatter(a: Dictionary, c: String, n: int, size: int) -> void:
	var tries := 0
	var placed := 0
	while placed < n and tries < 60:
		tries += 1
		var x: int = a.cell.x + rng.pick(a.rx * 2 - 1) - a.rx + 1
		var y: int = a.cell.y + rng.pick(a.ry * 2 - 1) - a.ry + 1
		if Vector2i(x, y).distance_to(a.cell) < 3.0:
			continue
		var ok := true
		for oy in range(-1, size + 1):
			for ox in range(-1, size + 1):
				if not _free(x + ox, y + oy) or core[_i(x + ox, y + oy)] or zone[_i(x + ox, y + oy)] != a.idx + 1:
					ok = false
		if not ok:
			continue
		for oy in size:
			for ox in size:
				_put(x + ox, y + oy, c)
		placed += 1


## a monster glade: rocks, brush, sometimes a pond or a raised ledge with steps
func _glade(a: Dictionary) -> void:
	var c: Vector2i = a.cell
	# a ledge across the back of the glade, climbed by a short stair
	if rng.chance(0.5):
		var lw := 5 + rng.pick(3)
		var x0 := c.x - lw / 2 + rng.pick(3) - 1
		var y0: int = c.y - a.ry + 2
		var ok := true
		for y in range(y0 - 1, y0 + 6):
			for x in range(x0 - 1, x0 + lw + 1):
				if not _free(x, y) or core[_i(x, y)] or zone[_i(x, y)] != a.idx + 1:
					ok = false
		if ok:
			for y in range(y0, y0 + 2):
				for x in range(x0, x0 + lw):
					_put(x, y, "1")
			var sx := x0 + lw / 2 - 1
			for k in 3:
				for x in range(sx, sx + 3):
					_put(x, y0 + 2 + k, "cba"[k])
	if rng.chance(0.4):
		# a pond
		var px: int = c.x + (rng.pick(2) * 2 - 1) * (a.rx / 2)
		var py := c.y + rng.pick(3) - 1
		var pr := 1.4 + rng.rangef(0, 0.9)
		var cells := []
		var ok := true
		for y in range(py - 3, py + 4):
			for x in range(px - 3, px + 4):
				if Vector2(x - px, (y - py) * 1.3).length() <= pr:
					if not _free(x, y) or core[_i(x, y)]:
						ok = false
					cells.append(Vector2i(x, y))
		if ok:
			for q in cells:
				_put(q.x, q.y, "~")
	_scatter(a, "o", 2 + rng.pick(3), 1)
	_scatter(a, "t", 2 + rng.pick(3), 1)


func _place_monsters(kinds: Array, champs: int) -> void:
	var glades := areas.filter(func(a): return a.kind == "combat")
	if glades.is_empty():
		return
	var k := 0
	var gi := 0
	var used: Array[Vector2i] = []
	while k < kinds.size():
		var a: Dictionary = glades[gi % glades.size()]
		gi += 1
		var spot := Vector2i(-1, -1)
		for t in 40:
			var ang := rng.rangef(0, TAU)
			var rad := rng.rangef(0.3, 0.75)
			var x: int = a.cell.x + roundi(cos(ang) * a.rx * rad)
			var y: int = a.cell.y + roundi(sin(ang) * a.ry * rad)
			if not _free(x, y) or zone[_i(x, y)] != a.idx + 1:
				continue
			var clear := true
			for u in used:
				if u.distance_to(Vector2i(x, y)) < 3.0:
					clear = false
			if clear:
				spot = Vector2i(x, y)
				break
		if spot.x < 0:
			spot = _spot(a, a.cell.x + 2, a.cell.y, false)
		used.append(spot)
		monsters.append({kind = kinds[k], cell = spot, champ = k < champs})
		k += 1


# ---------------- checks & output ----------------

func _height(c: String) -> int:
	return RoomMap.HEIGHTS.get(c, 0)


func _walkable(x: int, y: int) -> bool:
	return _in(x, y) and (GROUND.contains(_ch(x, y)) or _ch(x, y) == "A")


## every area, marker, monster and the gate can be reached from the start on foot
func _connected() -> bool:
	var start: Dictionary = areas[0]
	var seen := PackedByteArray()
	seen.resize(w * h)
	var queue: Array[Vector2i] = [start.cell]
	seen[_i(start.cell.x, start.cell.y)] = 1
	while not queue.is_empty():
		var p: Vector2i = queue.pop_back()
		var hp := _height(_ch(p.x, p.y))
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var q: Vector2i = p + d
			if not _walkable(q.x, q.y) or seen[_i(q.x, q.y)]:
				continue
			if _height(_ch(q.x, q.y)) - hp > Tuning.STEP_UP:
				continue
			seen[_i(q.x, q.y)] = 1
			queue.append(q)
	var reach := func(x: int, y: int) -> bool:
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				if _in(x + ox, y + oy) and seen[_i(x + ox, y + oy)]:
					return true
		return false
	for a in areas:
		var s := _spot(a, a.cell.x, a.cell.y, false)
		if s.x < 0 or not seen[_i(s.x, s.y)]:
			return false
	for y in h:
		for x in w:
			var c := _ch(x, y)
			if RoomMap.MARKERS.contains(c) and not reach.call(x, y):
				return false
			if c == "A" and not seen[_i(x, y)]:
				return false
	for m in monsters:
		if m.cell.x < 0 or not seen[_i(m.cell.x, m.cell.y)]:
			return false
	return true


## crop to the island and write the layout, zones, styles and areas onto the room
func _write(r: RoomData) -> void:
	var x0 := w
	var x1 := 0
	var y1 := 0
	for y in h:
		for x in w:
			if ch[_i(x, y)] != 32:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	x0 = maxi(0, x0 - 2)
	x1 = mini(w - 1, x1 + 2)
	var y_end := mini(h - 1, y1 + 3)
	var off := Vector2i(x0, 0)
	var layout := PackedStringArray()
	var zones := PackedStringArray()
	var styles := PackedStringArray()
	for y in range(0, y_end + 1):
		var row := ""
		var zr := ""
		var sr := ""
		for x in range(x0, x1 + 1):
			var c := _i(x, y)
			row += String.chr(ch[c])
			zr += String.chr(47 + zone[c]) if zone[c] > 0 else " "
			sr += String.chr(sty[c])
		layout.append(row)
		zones.append(zr)
		styles.append(sr)
	r.layout = layout
	r.zones = zones
	r.styles = styles
	r.areas = []
	for a in areas:
		var cell: Vector2i = a.cell - off
		r.areas.append({kind = a.kind, name = a.name, cell = cell, idx = a.idx,
			rect = Rect2i(cell.x - a.rx, cell.y - a.ry, a.rx * 2 + 1, a.ry * 2 + 1)})
	r.monsters = []
	for m in monsters:
		r.monsters.append({kind = m.kind, cell = m.cell - off, champ = m.champ})
	r.decor = []
	for d in decor:
		r.decor.append({type = d.type, cell = d.cell - off})
